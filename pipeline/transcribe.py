import os
from pathlib import Path

import assemblyai as aai


def transcribe_with_speakers(audio_path: Path) -> aai.Transcript:
    aai.settings.api_key = os.environ["ASSEMBLYAI_API_KEY"]
    config = aai.TranscriptionConfig(
        speaker_labels=True,
        speech_model=aai.SpeechModel.best,
    )
    transcriber = aai.Transcriber(config=config)
    transcript = transcriber.transcribe(str(audio_path))
    if transcript.error:
        raise RuntimeError(f"AssemblyAI error: {transcript.error}")
    return transcript
