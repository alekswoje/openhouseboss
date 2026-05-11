import os
from pathlib import Path

import assemblyai as aai


def transcribe_with_speakers(audio_path: Path) -> aai.Transcript:
    aai.settings.api_key = os.environ["ASSEMBLYAI_API_KEY"]
    # The explicit speech_model arg was deprecated server-side
    # ("speech_model is deprecated. Use 'speech_models' instead"). Dropping
    # the arg lets the SDK send the new request shape; we still get
    # Universal-2 / best by default.
    config = aai.TranscriptionConfig(speaker_labels=True)
    transcriber = aai.Transcriber(config=config)
    transcript = transcriber.transcribe(str(audio_path))
    if transcript.error:
        raise RuntimeError(f"AssemblyAI error: {transcript.error}")
    return transcript
