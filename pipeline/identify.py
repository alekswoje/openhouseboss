import csv
import json
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Optional

import assemblyai as aai
from anthropic import Anthropic
from pydantic import BaseModel

MODEL = "claude-sonnet-4-6"


class Visitor(BaseModel):
    name: str
    email: str
    phone: str
    signed_in_at: Optional[datetime] = None
    speaker: Optional[str] = None
    first_name: Optional[str] = None


class IdentificationResult(BaseModel):
    agent_speaker: str
    matched_visitors: list[Visitor]
    unmatched_speakers: list[str]


def load_visitors(csv_path: Path) -> list[Visitor]:
    visitors: list[Visitor] = []
    with csv_path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            signed_in: Optional[datetime] = None
            if row.get("signed_in_at"):
                try:
                    signed_in = datetime.fromisoformat(row["signed_in_at"])
                except ValueError:
                    pass
            visitors.append(
                Visitor(
                    name=row["name"],
                    email=row.get("email", ""),
                    phone=row.get("phone", ""),
                    signed_in_at=signed_in,
                    first_name=row["name"].split()[0].lower(),
                )
            )
    return visitors


def detect_agent_speaker(transcript: aai.Transcript) -> str:
    durations: Counter[str] = Counter()
    for utt in transcript.utterances or []:
        durations[utt.speaker] += utt.end - utt.start
    if not durations:
        raise RuntimeError("No utterances found in transcript")
    return durations.most_common(1)[0][0]


def _strip_code_fence(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        if text.endswith("```"):
            text = text.rsplit("\n```", 1)[0]
        if text.lower().startswith("json\n"):
            text = text[5:]
    return text


def _extract_json(text: str) -> str:
    """Pull just the first balanced JSON object or array out of an LLM
    response. Models occasionally return JSON followed by trailing prose
    ("{...}\n\nNote: ...") which trips json.loads with the confusing
    "Extra data: line 3 column 1 (char 18)" error. We scan for the first
    '{' or '[' and walk forward tracking depth + string state until we
    find the matching close, then return just that slice."""
    text = _strip_code_fence(text)
    # Find the first top-level opener.
    start = -1
    for i, ch in enumerate(text):
        if ch in "{[":
            start = i
            break
    if start == -1:
        return text  # fall through; json.loads will raise on its own
    depth = 0
    in_str = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]  # unbalanced; let the caller raise


def extract_speaker_names(transcript: aai.Transcript, agent_speaker: str) -> dict[str, str]:
    utterances_text = "\n".join(
        f"[{u.speaker}] {u.text}" for u in (transcript.utterances or [])
    )

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=1024,
        system=(
            f"You analyze diarized open-house transcripts. Speaker {agent_speaker} is "
            "the real-estate agent. Every other speaker is a visitor. Extract each "
            "visitor's first name from the conversation — visitors typically introduce "
            "themselves when the agent asks their name. Return JSON only, no prose, "
            'format: {"B": "sarah", "C": "mike"}. Use lowercase first names. Omit any '
            "speaker whose name is not mentioned in the transcript."
        ),
        messages=[{"role": "user", "content": utterances_text}],
    )
    text = _extract_json(response.content[0].text)
    return json.loads(text)


def identify_agent_and_visitors(
    transcript: aai.Transcript, visitors_csv: Optional[Path] = None
) -> IdentificationResult:
    agent = detect_agent_speaker(transcript)
    speaker_names = extract_speaker_names(transcript, agent)

    # iOS path: no kiosk CSV. Each non-agent speaker becomes a visitor —
    # we use their extracted first name when we got one, "Visitor B/C/D" otherwise.
    if visitors_csv is None:
        synthetic: list[Visitor] = []
        all_speakers = {
            u.speaker for u in (transcript.utterances or []) if u.speaker != agent
        }
        for speaker in sorted(all_speakers):
            first = speaker_names.get(speaker)
            name = first.title() if first else f"Visitor {speaker}"
            synthetic.append(Visitor(
                name=name,
                email="",
                phone="",
                speaker=speaker,
                first_name=(first or "").lower() or None,
            ))
        return IdentificationResult(
            agent_speaker=agent,
            matched_visitors=synthetic,
            unmatched_speakers=[],
        )

    visitors = load_visitors(visitors_csv)
    matched: list[Visitor] = []
    unmatched: list[str] = []

    for speaker, first_name in speaker_names.items():
        candidates = [
            v for v in visitors
            if v.first_name == first_name.lower() and v.speaker is None
        ]
        if not candidates:
            unmatched.append(speaker)
            continue
        candidates[0].speaker = speaker
        matched.append(candidates[0])

    return IdentificationResult(
        agent_speaker=agent,
        matched_visitors=matched,
        unmatched_speakers=unmatched,
    )
