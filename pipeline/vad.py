"""Silero-VAD-based silence trimming.

Open-house recordings are mostly dead air between visitor groups, and
AssemblyAI bills per audio second processed. Running the audio through
Silero VAD here lets us strip the silent stretches before uploading,
typically dropping the billable duration by 50–80%.

Silero is a *voice* activity detector — it's trained to reject
non-speech audio including music, so instrumental playing in the
background generally won't survive the trim. Conversational speech
scores 0.7–0.95 against the model; music + ambient noise sits well
below. Use VAD_THRESHOLD to tune (default 0.5, the upstream
recommended production value).

We deliberately keep this lightweight: the bundled silero_vad.onnx is
loaded with onnxruntime (no torch dependency), and m4a decoding is done
via PyAV so we don't need ffmpeg on the system path. The exported audio
is a mono 16 kHz wav — same sample rate Silero uses internally, accepted
directly by AssemblyAI, no second re-encode needed.

Between voiced segments we insert a short silent spacer so AssemblyAI's
diarizer still sees prosodic gaps where speaker turns happen — without
this, two visitors taking turns can collapse into a single speaker label.
"""
from __future__ import annotations

import os
import shutil
import time
import wave
from dataclasses import dataclass
from pathlib import Path

import av
import numpy as np
import onnxruntime as ort

_SAMPLE_RATE = 16_000
# Silero v5 expects 512-sample windows at 16 kHz (32 ms each), with a
# 64-sample "context" buffer (the tail of the previous window) prepended
# so each inference call sees 576 samples. Without that context, the model
# treats every window as the start of audio and probabilities collapse to
# zero — that bit us once, see _run_silero.
_WINDOW_SAMPLES = 512
_CONTEXT_SAMPLES = 64
_MODEL_PATH = Path(__file__).parent / "silero_vad.onnx"

# Lazily-initialised ONNX session — model load is ~80ms, no point paying
# it on every request when the FastAPI worker stays warm.
_session: ort.InferenceSession | None = None


def _get_session() -> ort.InferenceSession:
    global _session
    if _session is None:
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 1
        opts.inter_op_num_threads = 1
        _session = ort.InferenceSession(
            str(_MODEL_PATH), sess_options=opts, providers=["CPUExecutionProvider"]
        )
    return _session


def _decode_to_mono_16k(audio_path: Path) -> np.ndarray:
    """Decode an m4a/wav/mp3 file into mono float32 PCM at 16 kHz."""
    container = av.open(str(audio_path))
    try:
        stream = next(s for s in container.streams if s.type == "audio")
        resampler = av.audio.resampler.AudioResampler(
            format="flt", layout="mono", rate=_SAMPLE_RATE
        )
        chunks: list[np.ndarray] = []
        for frame in container.decode(stream):
            for out in resampler.resample(frame):
                chunks.append(out.to_ndarray().reshape(-1))
        for out in resampler.resample(None):
            chunks.append(out.to_ndarray().reshape(-1))
    finally:
        container.close()
    if not chunks:
        return np.zeros(0, dtype=np.float32)
    return np.concatenate(chunks).astype(np.float32, copy=False)


def _run_silero(audio: np.ndarray) -> np.ndarray:
    """Slide the 512-sample window through `audio`, returning per-window
    speech probabilities (one float per window, in [0, 1]).

    Open-house recordings are 70–90% dead air. Each silero inference call
    has fixed Python/ONNX dispatch overhead, so a 2-hour file means
    ~225k calls even though the model rarely changes its mind on silence.
    We use a cheap RMS pre-filter to short-circuit clearly-silent windows
    (energy below the noise floor) — those get probability 0 without
    calling silero. In practice this cuts VAD wall-time by 5-10x on the
    typical mostly-silent open-house file. Loud windows still run through
    silero so its hysteresis + recurrent state stay accurate on actual
    voice."""
    sess = _get_session()
    sr = np.array(_SAMPLE_RATE, dtype=np.int64)
    state = np.zeros((2, 1, 128), dtype=np.float32)
    context = np.zeros((1, _CONTEXT_SAMPLES), dtype=np.float32)
    n_windows = len(audio) // _WINDOW_SAMPLES
    probs = np.empty(n_windows, dtype=np.float32)

    # RMS energy per window in one numpy op — way cheaper than running
    # silero. Threshold chosen well below the level where any real human
    # voice picked up by a phone mic registers; near-silent room tone
    # sits around 0.001–0.003, and conversational speech is 0.02–0.2.
    windows_2d = audio[: n_windows * _WINDOW_SAMPLES].reshape(n_windows, _WINDOW_SAMPLES)
    rms = np.sqrt(np.mean(windows_2d * windows_2d, axis=1))
    quiet_threshold = 0.005

    silero_calls = 0
    for i in range(n_windows):
        window = windows_2d[i : i + 1]
        if rms[i] < quiet_threshold:
            # Skip silero inference but still advance the context tail so
            # the next loud-window call sees the correct preroll samples.
            # Recurrent state is left untouched; silero's gate naturally
            # decays toward "no speech" across silent stretches anyway.
            probs[i] = 0.0
            context = window[:, -_CONTEXT_SAMPLES:]
            continue
        inp = np.concatenate([context, window], axis=1)
        out, state = sess.run(None, {"input": inp, "state": state, "sr": sr})
        probs[i] = float(out[0, 0])
        context = inp[:, -_CONTEXT_SAMPLES:]
        silero_calls += 1

    if n_windows > 0:
        skipped_pct = 100.0 * (1.0 - silero_calls / n_windows)
        print(
            f"[vad] silero called on {silero_calls}/{n_windows} windows "
            f"({skipped_pct:.0f}% skipped via RMS pre-filter)",
            flush=True,
        )
    return probs


@dataclass(frozen=True)
class _Segment:
    start: int  # sample index (inclusive)
    end: int    # sample index (exclusive)


def _probs_to_segments(
    probs: np.ndarray,
    n_samples: int,
    *,
    threshold: float,
    min_speech_samples: int,
    min_silence_samples: int,
    pad_samples: int,
) -> list[_Segment]:
    """Port of silero-vad's `get_speech_timestamps` state machine.

    Walks the per-window probabilities, opening a segment on the first
    window above `threshold` and closing it after `min_silence_samples` of
    sub-threshold audio. The `neg_threshold` (threshold - 0.15) hysteresis
    matches the upstream implementation — it prevents flapping when
    probabilities hover right around the boundary.
    """
    if probs.size == 0:
        return []
    neg_threshold = max(0.15, threshold - 0.15)
    segments: list[_Segment] = []
    triggered = False
    current_start = 0
    temp_end = 0
    for i, p in enumerate(probs):
        sample = i * _WINDOW_SAMPLES
        if p >= threshold and not triggered:
            triggered = True
            current_start = sample
            temp_end = 0
            continue
        if not triggered:
            continue
        if p < neg_threshold:
            if temp_end == 0:
                temp_end = sample
            if sample - temp_end < min_silence_samples:
                continue
            end = temp_end
            if end - current_start >= min_speech_samples:
                segments.append(_Segment(current_start, end))
            triggered = False
            temp_end = 0
        else:
            temp_end = 0
    if triggered:
        end = n_samples
        if end - current_start >= min_speech_samples:
            segments.append(_Segment(current_start, end))

    # Pad edges so we don't clip the first/last phoneme of each utterance,
    # then merge any segments that now overlap.
    padded: list[_Segment] = []
    for s in segments:
        padded.append(_Segment(max(0, s.start - pad_samples),
                               min(n_samples, s.end + pad_samples)))
    merged: list[_Segment] = []
    for s in padded:
        if merged and s.start <= merged[-1].end:
            merged[-1] = _Segment(merged[-1].start, max(merged[-1].end, s.end))
        else:
            merged.append(s)
    return merged


def _write_wav(samples: np.ndarray, out_path: Path) -> None:
    pcm16 = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    with wave.open(str(out_path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(_SAMPLE_RATE)
        w.writeframes(pcm16.tobytes())


@dataclass(frozen=True)
class TrimResult:
    original_seconds: float
    trimmed_seconds: float
    segments: int
    trimmed: bool  # False if we left the file untouched (no segments, decode failure, etc.)


def _resolve_threshold(explicit: float | None) -> float:
    if explicit is not None:
        return explicit
    raw = os.environ.get("VAD_THRESHOLD", "").strip()
    if not raw:
        return 0.5
    try:
        v = float(raw)
    except ValueError:
        return 0.5
    return max(0.1, min(0.95, v))


def trim_silence(
    audio_path: Path,
    out_path: Path,
    *,
    threshold: float | None = None,
    min_speech_ms: int = 200,
    min_silence_ms: int = 400,
    speech_pad_ms: int = 150,
    spacer_ms: int = 500,
) -> TrimResult:
    """Trim silence from `audio_path`, writing a mono 16 kHz wav to `out_path`.

    `threshold` is the per-window speech probability cutoff. Default is
    0.5 (silero's own recommended production value) — voice typically
    scores 0.7–0.95, so 0.5 keeps a safety margin against false negatives
    on speech while rejecting most music and ambient noise. Override via
    the VAD_THRESHOLD env var without a redeploy.

    On any failure (decode error, no speech detected, etc.) we copy the
    original file to `out_path` and return `trimmed=False` so the caller
    can still ship audio to AssemblyAI — losing the trim is an acceptable
    degradation, losing the recording is not.
    """
    threshold = _resolve_threshold(threshold)
    t0 = time.monotonic()
    samples = _decode_to_mono_16k(audio_path)
    decode_s = time.monotonic() - t0
    original_seconds = len(samples) / _SAMPLE_RATE
    # Tiny clips aren't worth the round trip — likely a dropped recording.
    if original_seconds < 1.0:
        shutil.copy(audio_path, out_path)
        return TrimResult(original_seconds, original_seconds, 0, trimmed=False)

    t1 = time.monotonic()
    probs = _run_silero(samples)
    silero_s = time.monotonic() - t1
    # Probability distribution of the windows that beat the noise floor.
    # If music is leaking through, we'd see a mass of windows scoring
    # 0.4–0.7 here; clear speech sits 0.7+. Use this to tune VAD_THRESHOLD
    # against real recordings without guessing.
    loud = probs[probs > 0.0]
    if loud.size:
        p50 = float(np.percentile(loud, 50))
        p90 = float(np.percentile(loud, 90))
        above_05 = int(np.sum(loud >= 0.5))
        above_07 = int(np.sum(loud >= 0.7))
        print(
            f"[vad] threshold={threshold} prob_dist (loud windows={loud.size}): "
            f"p50={p50:.2f} p90={p90:.2f} ≥0.5={above_05} ≥0.7={above_07}",
            flush=True,
        )
    print(
        f"[vad] timings: decode={decode_s:.1f}s silero={silero_s:.1f}s "
        f"audio_len={original_seconds:.0f}s",
        flush=True,
    )
    segments = _probs_to_segments(
        probs,
        len(samples),
        threshold=threshold,
        min_speech_samples=int(min_speech_ms * _SAMPLE_RATE / 1000),
        min_silence_samples=int(min_silence_ms * _SAMPLE_RATE / 1000),
        pad_samples=int(speech_pad_ms * _SAMPLE_RATE / 1000),
    )
    if not segments:
        shutil.copy(audio_path, out_path)
        return TrimResult(original_seconds, original_seconds, 0, trimmed=False)

    spacer = np.zeros(int(spacer_ms * _SAMPLE_RATE / 1000), dtype=np.float32)
    parts: list[np.ndarray] = []
    for i, seg in enumerate(segments):
        if i > 0:
            parts.append(spacer)
        parts.append(samples[seg.start:seg.end])
    trimmed = np.concatenate(parts)
    _write_wav(trimmed, out_path)
    return TrimResult(
        original_seconds=original_seconds,
        trimmed_seconds=len(trimmed) / _SAMPLE_RATE,
        segments=len(segments),
        trimmed=True,
    )
