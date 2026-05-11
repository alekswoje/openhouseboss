"""Mock AssemblyAI transcript loader for testing without real audio."""
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class MockUtterance:
    speaker: str
    text: str
    start: int  # ms
    end: int    # ms


@dataclass
class MockTranscript:
    text: str
    utterances: list[MockUtterance]
    error: Optional[str] = None


def load_mock_transcript(path: Path) -> MockTranscript:
    data = json.loads(path.read_text())
    utterances = [MockUtterance(**u) for u in data["utterances"]]
    full_text = data.get("text") or " ".join(u.text for u in utterances)
    return MockTranscript(text=full_text, utterances=utterances)
