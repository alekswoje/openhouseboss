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
    # Claude's estimate of true speaker count (including the agent). When
    # this exceeds the diarizer's count, the caller should re-transcribe
    # with `speakers_expected=suspected_total` to recover collapsed voices.
    suspected_total: int = 0
    detected_total: int = 0


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


class SpeakerAnalysis(BaseModel):
    names: dict[str, str]
    # Claude's best guess at how many distinct humans were really in the
    # room (including the agent). When the diarizer undercounts — two
    # close-mic'd voices collapsed into one cluster — this comes back
    # higher than `len(transcript.utterances.speakers)` and the caller
    # should re-transcribe with `speakers_expected=suspected_total`.
    suspected_total: int


def analyze_speakers(transcript: aai.Transcript, agent_speaker: str) -> SpeakerAnalysis:
    utterances_text = "\n".join(
        f"[{u.speaker}] {u.text}" for u in (transcript.utterances or [])
    )
    detected = sorted({u.speaker for u in (transcript.utterances or [])})

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=1024,
        system=(
            f"You analyze diarized open-house transcripts. Speaker {agent_speaker} is "
            "the real-estate agent. Every other speaker is a visitor. Two tasks:\n\n"
            "1. Extract each visitor's first name. Visitors typically introduce "
            "themselves when the agent asks. Use lowercase. Omit speakers whose "
            "name is not mentioned.\n\n"
            "2. Estimate how many distinct humans were really in the conversation, "
            "including the agent. Diarization sometimes collapses two close-mic'd "
            "voices into one cluster — watch for these tells inside a single speaker "
            "label: two different first names being introduced (\"hi I'm sarah\" "
            "then later \"and I'm mike\"), back-and-forth that reads like two people "
            "talking to each other, contradictory self-references (one line says "
            "\"my wife and I\", another says \"I'm single\"), or wildly different "
            "conversational styles. If you see clear evidence of a merge, return a "
            "higher count. If the transcript is consistent with the detected count, "
            f"return the detected count. Detected speakers: {detected}.\n\n"
            "Return JSON only, no prose, format: "
            '{"names": {"B": "sarah", "C": "mike"}, "suspected_total": 3}'
        ),
        messages=[{"role": "user", "content": utterances_text}],
    )
    text = _extract_json(response.content[0].text)
    data = json.loads(text)
    suspected = int(data.get("suspected_total") or len(detected))
    # Floor the suspected count at what we already detected — Claude should
    # never tell us there are *fewer* people than AAI already found.
    suspected = max(suspected, len(detected))
    return SpeakerAnalysis(names=data.get("names") or {}, suspected_total=suspected)


def extract_speaker_names(transcript: aai.Transcript, agent_speaker: str) -> dict[str, str]:
    return analyze_speakers(transcript, agent_speaker).names


def identify_agent_and_visitors(
    transcript: aai.Transcript, visitors_csv: Optional[Path] = None
) -> IdentificationResult:
    agent = detect_agent_speaker(transcript)
    analysis = analyze_speakers(transcript, agent)
    speaker_names = analysis.names
    detected_total = len({u.speaker for u in (transcript.utterances or [])})

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
            suspected_total=analysis.suspected_total,
            detected_total=detected_total,
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
        suspected_total=analysis.suspected_total,
        detected_total=detected_total,
    )
