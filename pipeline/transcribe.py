import os
import tempfile
from pathlib import Path

import assemblyai as aai

from .identify import refine_diarization
from .vad import trim_silence


def _vad_enabled() -> bool:
    # Default on; flip via Render env var if VAD ever breaks diarization in
    # production. Keeping the kill switch is cheap and lets us roll back
    # without a redeploy.
    return os.environ.get("VAD_TRIM_ENABLED", "true").strip().lower() not in (
        "false", "0", "no", "off",
    )


def transcribe_with_speakers(audio_path: Path, speakers_expected: int | None = None) -> aai.Transcript:
    aai.settings.api_key = os.environ["ASSEMBLYAI_API_KEY"]

    # Silero VAD pass — strips silent stretches before they hit AssemblyAI's
    # billable second counter. Open houses are mostly dead air; in practice
    # this trims 50–80% of duration. trim_silence is fail-safe: on any
    # decode/inference error it copies the original audio to upload_path and
    # returns trimmed=False, so we never lose a recording over a VAD bug.
    upload_path = audio_path
    tmp_fd: int | None = None
    tmp_wav: Path | None = None
    if _vad_enabled():
        tmp_fd, tmp_path = tempfile.mkstemp(prefix="vad_", suffix=".wav")
        os.close(tmp_fd)
        tmp_wav = Path(tmp_path)
        try:
            result = trim_silence(audio_path, tmp_wav)
            saved_pct = (
                100.0 * (1.0 - result.trimmed_seconds / result.original_seconds)
                if result.original_seconds > 0 else 0.0
            )
            print(
                f"[vad] {audio_path.name}: {result.original_seconds:.1f}s → "
                f"{result.trimmed_seconds:.1f}s ({saved_pct:.0f}% saved, "
                f"{result.segments} segments, trimmed={result.trimmed})",
                flush=True,
            )
            if result.trimmed:
                upload_path = tmp_wav
        except Exception as e:
            print(f"[vad] trim failed, using original audio: {e}", flush=True)

    # AssemblyAI moved from `speech_model` (singular) to `speech_models`
    # (plural list) and renamed their model identifiers. The current valid
    # production models are "universal-3-pro" and "universal-2"; we use
    # universal-2 because it's the cheaper of the two and still excellent
    # at diarization on noisy multi-speaker audio like open-house chatter.
    #
    # speakers_expected is a strong hint to the diarizer. Without it, voices
    # that share acoustic features (e.g. one person doing impressions) get
    # collapsed into a single speaker; passing the known count forces the
    # model to find that many distinct clusters.
    try:
        config = aai.TranscriptionConfig(
            speaker_labels=True,
            speech_models=["universal-2"],
            speakers_expected=speakers_expected,
        )
        transcriber = aai.Transcriber(config=config)
        transcript = transcriber.transcribe(str(upload_path))
        if transcript.error:
            raise RuntimeError(f"AssemblyAI error: {transcript.error}")
        # Claude post-correction: fix speaker swaps on rapid back-and-forth
        # and split merged turns ("what's your name? I'm Alex. Hi Alex." in
        # one utterance). Non-fatal — if Claude returns malformed JSON or
        # invents speaker labels, the original AAI utterances are kept.
        # Disable via DIARIZATION_REFINE_ENABLED=false on Render.
        try:
            transcript = refine_diarization(transcript)
        except Exception as e:
            print(f"[diarization-refine] failed, keeping raw AAI output: {e}", flush=True)
        return transcript
    finally:
        if tmp_wav is not None:
            try:
                tmp_wav.unlink(missing_ok=True)
            except OSError:
                pass
