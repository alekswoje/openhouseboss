import os
from pathlib import Path

import assemblyai as aai


def transcribe_with_speakers(audio_path: Path, speakers_expected: int | None = None) -> aai.Transcript:
    aai.settings.api_key = os.environ["ASSEMBLYAI_API_KEY"]
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
    config = aai.TranscriptionConfig(
        speaker_labels=True,
        speech_models=["universal-2"],
        speakers_expected=speakers_expected,
    )
    transcriber = aai.Transcriber(config=config)
    transcript = transcriber.transcribe(str(audio_path))
    if transcript.error:
        raise RuntimeError(f"AssemblyAI error: {transcript.error}")
    return transcript
