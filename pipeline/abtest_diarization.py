"""A/B harness — run a single audio file through AssemblyAI, Deepgram, and
Speechmatics in parallel and print their diarized transcripts side by side.

Why: AssemblyAI's diarization is merging turns on single-mic iPhone audio
(two close-mic'd speakers cluster as one). Before committing to a provider
swap, we want concrete evidence on a real failing recording.

Usage:
    export ASSEMBLYAI_API_KEY=...
    export DEEPGRAM_API_KEY=...
    export SPEECHMATICS_API_KEY=...
    .venv/bin/python -m pipeline.abtest_diarization /path/to/recording.m4a

Each provider returns a list of utterances (speaker label, start time, text);
the script prints them as three columns so misalignments are visible at a
glance. Also writes a side-by-side JSON dump for closer inspection.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path

import requests


@dataclass
class Utterance:
    speaker: str
    start_ms: int
    text: str


@dataclass
class ProviderResult:
    provider: str
    elapsed_s: float
    speaker_count: int
    utterances: list[Utterance]
    error: str | None = None


# ---------------------------------------------------------------------------
# AssemblyAI
# ---------------------------------------------------------------------------

def run_assemblyai(audio_path: Path, api_key: str) -> ProviderResult:
    import assemblyai as aai
    t0 = time.time()
    try:
        aai.settings.api_key = api_key
        # universal-2 is what production uses (see pipeline/transcribe.py).
        config = aai.TranscriptionConfig(
            speaker_labels=True,
            speech_models=["universal-2"],
        )
        transcriber = aai.Transcriber(config=config)
        transcript = transcriber.transcribe(str(audio_path))
        if transcript.error:
            return ProviderResult("assemblyai", time.time() - t0, 0, [], transcript.error)
        utterances = [
            Utterance(
                speaker=u.speaker,
                start_ms=int(getattr(u, "start", 0) or 0),
                text=u.text,
            )
            for u in (transcript.utterances or [])
        ]
        speakers = {u.speaker for u in utterances}
        return ProviderResult("assemblyai", time.time() - t0, len(speakers), utterances)
    except Exception as e:
        return ProviderResult("assemblyai", time.time() - t0, 0, [], str(e))


def run_assemblyai_refined(audio_path: Path, api_key: str) -> ProviderResult:
    """Run AssemblyAI, then post-process through the Claude refinement pass
    that production uses (pipeline/identify.refine_diarization). Shows what
    the agent's session actually sees after the post-correction step that
    fixes lumped turns ('What's your name? Ethan. Ethan, Alex.' → 3 turns).
    """
    t0 = time.time()
    base = run_assemblyai(audio_path, api_key)
    if base.error:
        return ProviderResult("assemblyai_refined", time.time() - t0, 0, [], base.error)
    try:
        from pipeline.identify import _claude_refine_utterances
        valid_speakers = sorted({u.speaker for u in base.utterances})
        # The refine helper expects end_ms; AAI dropped it on the way through
        # the abtest dataclass. We approximate end_ms = next utt's start (or
        # +5s on the last one) — only used as a budget for monotonic splits.
        starts = [u.start_ms for u in base.utterances]
        payload = []
        for i, u in enumerate(base.utterances):
            end_ms = starts[i + 1] if i + 1 < len(starts) else u.start_ms + 5000
            payload.append({
                "speaker": u.speaker,
                "start_ms": u.start_ms,
                "end_ms": end_ms,
                "text": u.text,
            })
        cleaned = _claude_refine_utterances(payload, valid_speakers)
        if not cleaned:
            # Refine failed — surface raw AAI under the refined label so the
            # UI shows something, with an error hint via the speaker count.
            return ProviderResult(
                "assemblyai_refined", time.time() - t0,
                len({u.speaker for u in base.utterances}),
                base.utterances,
                "refine pass returned no usable output — showing raw AAI",
            )
        refined_utts = [
            Utterance(
                speaker=item["speaker"],
                start_ms=item["start_ms"],
                text=item["text"],
            )
            for item in cleaned
        ]
        return ProviderResult(
            "assemblyai_refined", time.time() - t0,
            len({u.speaker for u in refined_utts}),
            refined_utts,
        )
    except Exception as e:
        return ProviderResult("assemblyai_refined", time.time() - t0, 0, [], str(e))


# ---------------------------------------------------------------------------
# Deepgram (HTTPS POST raw audio body to /v1/listen)
# ---------------------------------------------------------------------------

def run_deepgram(audio_path: Path, api_key: str) -> ProviderResult:
    t0 = time.time()
    try:
        # nova-3 collapsed every word to speaker_0 on a real iPhone open-house
        # recording during the A/B bake-off — diarization quality regressed
        # vs nova-2 on noisy single-mic audio. Stick with nova-2 here until
        # Deepgram's own benchmarks change. multichannel=false is explicit so
        # the diarizer doesn't try to treat mono iPhone audio as multi-track.
        params = {
            "model": "nova-2",
            "diarize": "true",
            "punctuate": "true",
            "smart_format": "true",
            "utterances": "true",
            "multichannel": "false",
            "language": "en",
        }
        with audio_path.open("rb") as f:
            resp = requests.post(
                "https://api.deepgram.com/v1/listen",
                params=params,
                headers={
                    "Authorization": f"Token {api_key}",
                    "Content-Type": _guess_mime(audio_path),
                },
                data=f.read(),
                timeout=180,
            )
        if resp.status_code != 200:
            return ProviderResult(
                "deepgram", time.time() - t0, 0, [],
                f"HTTP {resp.status_code}: {resp.text[:300]}",
            )
        body = resp.json()
        # Prefer the top-level utterances array (when ?utterances=true), which
        # already groups consecutive words by speaker; falls back to walking
        # the words array if the response shape is different.
        utterances: list[Utterance] = []
        utts = body.get("results", {}).get("utterances")
        if utts:
            for u in utts:
                utterances.append(Utterance(
                    speaker=f"speaker_{u.get('speaker')}",
                    start_ms=int(float(u.get("start", 0)) * 1000),
                    text=u.get("transcript", "").strip(),
                ))
        else:
            # Group word-by-word by speaker boundaries.
            channels = body.get("results", {}).get("channels", [])
            words = (channels[0].get("alternatives", [{}])[0].get("words", [])
                     if channels else [])
            cur_speaker = None
            cur_start = 0
            cur_text: list[str] = []
            for w in words:
                spk = f"speaker_{w.get('speaker', 0)}"
                if spk != cur_speaker and cur_text:
                    utterances.append(Utterance(
                        speaker=cur_speaker or "speaker_0",
                        start_ms=cur_start,
                        text=" ".join(cur_text),
                    ))
                    cur_text = []
                if not cur_text:
                    cur_start = int(float(w.get("start", 0)) * 1000)
                cur_speaker = spk
                cur_text.append(w.get("punctuated_word") or w.get("word", ""))
            if cur_text:
                utterances.append(Utterance(
                    speaker=cur_speaker or "speaker_0",
                    start_ms=cur_start,
                    text=" ".join(cur_text),
                ))
        speakers = {u.speaker for u in utterances}
        return ProviderResult("deepgram", time.time() - t0, len(speakers), utterances)
    except Exception as e:
        return ProviderResult("deepgram", time.time() - t0, 0, [], str(e))


# ---------------------------------------------------------------------------
# Speechmatics (create job → poll → fetch transcript)
# ---------------------------------------------------------------------------

SPEECHMATICS_BASE = "https://asr.api.speechmatics.com/v2"


def run_speechmatics(audio_path: Path, api_key: str) -> ProviderResult:
    t0 = time.time()
    try:
        headers = {"Authorization": f"Bearer {api_key}"}
        # transcription_config schema is strict — enable_partials lives on the
        # realtime websocket config, NOT the batch /jobs config, so passing it
        # here gets the whole job rejected with HTTP 400. Removed.
        config = {
            "type": "transcription",
            "transcription_config": {
                "language": "en",
                "operating_point": "enhanced",
                "diarization": "speaker",
            },
        }
        with audio_path.open("rb") as f:
            create = requests.post(
                f"{SPEECHMATICS_BASE}/jobs",
                headers=headers,
                files={
                    "data_file": (audio_path.name, f, _guess_mime(audio_path)),
                    "config": (None, json.dumps(config), "application/json"),
                },
                timeout=180,
            )
        if create.status_code not in (200, 201):
            return ProviderResult(
                "speechmatics", time.time() - t0, 0, [],
                f"create HTTP {create.status_code}: {create.text[:300]}",
            )
        job_id = create.json().get("id")
        if not job_id:
            return ProviderResult(
                "speechmatics", time.time() - t0, 0, [],
                f"no job id in response: {create.text[:300]}",
            )

        # Poll for completion. Speechmatics is slower than AAI/Deepgram —
        # typical latency for a 30-60s clip is 10-30s; cap at 5 minutes.
        deadline = time.time() + 300
        status = ""
        while time.time() < deadline:
            time.sleep(2)
            poll = requests.get(
                f"{SPEECHMATICS_BASE}/jobs/{job_id}",
                headers=headers, timeout=30,
            )
            if poll.status_code != 200:
                continue
            status = poll.json().get("job", {}).get("status", "")
            if status in ("done", "rejected"):
                break
        if status != "done":
            return ProviderResult(
                "speechmatics", time.time() - t0, 0, [],
                f"job ended with status={status}",
            )

        result = requests.get(
            f"{SPEECHMATICS_BASE}/jobs/{job_id}/transcript",
            params={"format": "json-v2"},
            headers=headers, timeout=60,
        )
        if result.status_code != 200:
            return ProviderResult(
                "speechmatics", time.time() - t0, 0, [],
                f"transcript HTTP {result.status_code}: {result.text[:300]}",
            )
        body = result.json()
        # Speechmatics returns word-level with speaker labels in
        # results[].alternatives[0].speaker. Group consecutive same-speaker
        # words into utterances.
        utterances: list[Utterance] = []
        cur_speaker: str | None = None
        cur_start = 0
        cur_text: list[str] = []
        for entry in body.get("results", []):
            if entry.get("type") != "word" and entry.get("type") != "punctuation":
                continue
            alts = entry.get("alternatives") or []
            if not alts:
                continue
            alt = alts[0]
            spk = alt.get("speaker") or "S?"
            content = alt.get("content", "")
            start_s = float(entry.get("start_time", 0))
            if spk != cur_speaker and cur_text:
                utterances.append(Utterance(
                    speaker=cur_speaker or "S?",
                    start_ms=cur_start,
                    text=_join_speechmatics_tokens(cur_text),
                ))
                cur_text = []
            if not cur_text:
                cur_start = int(start_s * 1000)
            cur_speaker = spk
            cur_text.append((entry.get("type"), content))
        if cur_text:
            utterances.append(Utterance(
                speaker=cur_speaker or "S?",
                start_ms=cur_start,
                text=_join_speechmatics_tokens(cur_text),
            ))
        speakers = {u.speaker for u in utterances}
        return ProviderResult("speechmatics", time.time() - t0, len(speakers), utterances)
    except Exception as e:
        return ProviderResult("speechmatics", time.time() - t0, 0, [], str(e))


def _join_speechmatics_tokens(tokens: list[tuple[str, str]]) -> str:
    # Speechmatics returns words and punctuation as separate entries; rejoin
    # with no space before punctuation so we get natural sentences instead of
    # "hi , how are you ?".
    out = ""
    for kind, content in tokens:
        if kind == "punctuation":
            out += content
        else:
            out += (" " if out and not out.endswith(" ") else "") + content
    return out.strip()


# ---------------------------------------------------------------------------
# Common helpers
# ---------------------------------------------------------------------------

def _guess_mime(audio_path: Path) -> str:
    return {
        ".m4a": "audio/mp4",
        ".mp4": "audio/mp4",
        ".wav": "audio/wav",
        ".mp3": "audio/mpeg",
        ".aac": "audio/aac",
        ".flac": "audio/flac",
    }.get(audio_path.suffix.lower(), "application/octet-stream")


def _fmt_time(ms: int) -> str:
    s = ms // 1000
    return f"{s // 60}:{s % 60:02d}"


def print_side_by_side(results: list[ProviderResult]) -> None:
    print()
    print("=" * 110)
    for r in results:
        if r.error:
            print(f"  {r.provider:>12}: ERROR — {r.error}")
        else:
            print(f"  {r.provider:>12}: {len(r.utterances)} turns, "
                  f"{r.speaker_count} distinct speakers, "
                  f"{r.elapsed_s:.1f}s wall time")
    print("=" * 110)
    print()
    for r in results:
        print(f"\n── {r.provider} ──────────────────────────────────────────────")
        if r.error:
            print(f"  ERROR: {r.error}")
            continue
        for u in r.utterances:
            print(f"  [{_fmt_time(u.start_ms)}] {u.speaker:>10}  {u.text}")
    print()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("audio", type=Path, help="Path to audio file (.m4a/.wav/.mp3)")
    ap.add_argument("--out", type=Path, default=None,
                    help="Optional path to dump full JSON of all 3 results")
    args = ap.parse_args()

    if not args.audio.exists():
        print(f"audio not found: {args.audio}", file=sys.stderr)
        return 2

    keys = {
        "assemblyai": os.environ.get("ASSEMBLYAI_API_KEY"),
        "deepgram": os.environ.get("DEEPGRAM_API_KEY"),
        "speechmatics": os.environ.get("SPEECHMATICS_API_KEY"),
    }
    missing = [k for k, v in keys.items() if not v]
    if missing:
        print(f"Missing env vars: {', '.join(k.upper() + '_API_KEY' for k in missing)}",
              file=sys.stderr)
        return 2

    print(f"Running 3 providers on {args.audio} ({args.audio.stat().st_size // 1024} KB)...")
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as ex:
        futures = {
            ex.submit(run_assemblyai, args.audio, keys["assemblyai"]): "assemblyai",
            ex.submit(run_deepgram, args.audio, keys["deepgram"]): "deepgram",
            ex.submit(run_speechmatics, args.audio, keys["speechmatics"]): "speechmatics",
        }
        results: list[ProviderResult] = []
        for fut in concurrent.futures.as_completed(futures):
            results.append(fut.result())
    # Stable order for printing: AAI first (the baseline), then Deepgram, then Speechmatics.
    order = {"assemblyai": 0, "deepgram": 1, "speechmatics": 2}
    results.sort(key=lambda r: order.get(r.provider, 99))

    print_side_by_side(results)
    if args.out:
        args.out.write_text(json.dumps([asdict(r) for r in results], indent=2))
        print(f"Full JSON written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
