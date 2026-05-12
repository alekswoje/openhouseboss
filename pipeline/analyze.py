import json

import assemblyai as aai
from anthropic import Anthropic
from pydantic import BaseModel

from .identify import Visitor, _strip_code_fence
from .tags import Tag

MODEL = "claude-sonnet-4-6"


class VisitorAnalysis(BaseModel):
    summary: str
    tag: str
    tag_reason: str
    score: int          # 0–100 interest / urgency score
    signals: list[str]  # 3–5 short phrase chips like "Pre-approved $1.4M"
    follow_up_draft: str
    words_spoken: int


def analyze_visitor(
    transcript: aai.Transcript, visitor: Visitor, tags: list[Tag]
) -> VisitorAnalysis:
    utterances_text = "\n".join(
        f"[{u.speaker}{' ← visitor' if u.speaker == visitor.speaker else ''}] {u.text}"
        for u in (transcript.utterances or [])
    )
    tag_block = "\n".join(f"- {t.name}: {t.description}" for t in tags)
    tag_names = [t.name for t in tags]

    # Count words the visitor said for the UI's "spoke 142 W" chip.
    words_spoken = sum(
        len(u.text.split())
        for u in (transcript.utterances or [])
        if u.speaker == visitor.speaker
    )

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=1500,
        system=(
            "You help a real-estate agent follow up after an open house. You are given "
            "a diarized transcript; focus on the visitor identified below. Produce a "
            "short summary (3–5 sentences) of what they said and what they seem to want, "
            "pick exactly one tag from the list, score their interest/urgency 0–100 "
            "(0=cold, 50=warm, 80+=hot/transacting soon), extract 3–5 short signal "
            "phrases (each ≤4 words — concrete facts like 'Pre-approved $1.4M', "
            "'Close in 60 days', 'Owner 15 yrs'), and draft a SHORT follow-up email "
            "(STRICT: max 4 sentences total, under 60 words, mobile-friendly, "
            "ending with a single specific question or yes/no ask that converts to "
            "a reply — e.g. 'Want me to send the comps?' or 'Open to a 15-minute call "
            "Thursday?'). No long paragraphs, no boilerplate intro, no 'I hope this "
            "finds you well'. Reference exactly one thing they said, then the ask. "
            "Sign-off is just the agent's name on its own line.\n\n"
            f"Visitor: {visitor.name} (Speaker {visitor.speaker})\n\n"
            f"Tags (pick exactly one):\n{tag_block}\n\n"
            "Return JSON only, no prose, format:\n"
            "{\n"
            '  "summary": "...",\n'
            f'  "tag": "one of {tag_names}",\n'
            '  "tag_reason": "one short sentence",\n'
            '  "score": 0-100,\n'
            '  "signals": ["...", "..."],\n'
            '  "follow_up_draft": "..."\n'
            "}"
        ),
        messages=[{"role": "user", "content": utterances_text}],
    )
    text = _strip_code_fence(response.content[0].text)
    parsed = json.loads(text)
    parsed["words_spoken"] = words_spoken
    return VisitorAnalysis(**parsed)
