"""Grade the agent's actual conversation against their intended script.

Takes the diarized transcript + a Script and asks Claude, per step:
  - Did the agent hit this step? (hit | partial | missed)
  - Quote the line they used (if any) as evidence.
  - One-sentence suggestion for next time.

Output is structured per-step so the iOS Summary screen can render a row
per script step with a status pill, the quote, and the suggestion.
"""

import json

import assemblyai as aai
from anthropic import Anthropic
from pydantic import BaseModel

from .identify import _extract_json
from .scripts import Script

MODEL = "claude-sonnet-4-6"


class StepCoverage(BaseModel):
    step_id: str
    status: str            # "hit" | "partial" | "missed"
    evidence: str          # quote from agent's transcript or ""
    suggestion: str        # short coaching note


class ScriptCoverage(BaseModel):
    script_id: str
    script_name: str
    overall_summary: str   # 1–2 sentences: how did they do?
    score: int             # 0–100, % of script steps hit/partial
    steps: list[StepCoverage]


def grade_against_script(
    transcript: aai.Transcript, script: Script, agent_speaker: str
) -> ScriptCoverage:
    # Only feed the agent's utterances — that's what we're grading. Cheaper
    # than feeding the whole thing and the visitor lines aren't relevant to
    # whether the *agent* hit each step.
    agent_lines = [
        u.text for u in (transcript.utterances or []) if u.speaker == agent_speaker
    ]
    agent_text = "\n".join(f"- {line}" for line in agent_lines)

    step_block = "\n".join(
        f'  - id: {s.id}\n'
        f'    section: {s.section}\n'
        f'    label: {s.label}\n'
        f'    intended quote: "{s.quote}"\n'
        f'    intent: {s.intent}'
        for s in script.steps
    )

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=4000,
        system=(
            "You are a sales coach reviewing how well a real-estate agent "
            "executed their open-house script. You are given the agent's "
            "actual utterances (one per line) and their intended script "
            "(a list of steps with intended quotes and intent). For each "
            "step, decide if the agent:\n"
            "  - 'hit'     — covered the step's intent clearly, even if "
            "phrased differently from the intended quote.\n"
            "  - 'partial' — touched the topic but missed the key beat "
            "(e.g. asked about timeline but never about pain).\n"
            "  - 'missed'  — didn't address this step at all.\n\n"
            "If hit/partial, quote the closest agent line as evidence "
            "(verbatim, ≤25 words). If missed, evidence is empty.\n"
            "For every step, give one short coaching suggestion (≤20 words) "
            "— what to say next time, or how to deliver it better.\n\n"
            "Be honest. Agents grow from concrete feedback, not flattery.\n\n"
            "Also produce an overall_summary (1–2 sentences) and a score "
            "from 0–100 where 100 = every step hit cleanly.\n\n"
            f"Script: {script.name}\n"
            f"Steps:\n{step_block}\n\n"
            "Return JSON only, no prose, format:\n"
            "{\n"
            '  "overall_summary": "...",\n'
            '  "score": 0-100,\n'
            '  "steps": [\n'
            '    {"step_id": "...", "status": "hit|partial|missed", '
            '"evidence": "...", "suggestion": "..."}\n'
            "  ]\n"
            "}"
        ),
        messages=[{"role": "user", "content": f"Agent utterances:\n{agent_text}"}],
    )
    text = _extract_json(response.content[0].text)
    parsed = json.loads(text)
    return ScriptCoverage(
        script_id=script.id,
        script_name=script.name,
        overall_summary=parsed["overall_summary"],
        score=parsed["score"],
        steps=[StepCoverage(**s) for s in parsed["steps"]],
    )
