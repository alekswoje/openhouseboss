"""Agent-driven script editing.

Instead of letting the agent edit script fields manually, the iOS app pipes a
natural-language instruction here and we ask Claude to mutate the script
JSON via a tool call. Tool use enforces the shape — Claude can't reply in
prose and break the contract.

Two entry points:
  - agent_edit_script(current, instruction): mutate an existing script
  - agent_create_script(instruction):          build one from scratch

Both return a fully-formed `Script` ready to persist. The caller (server.py)
handles revision snapshots and disk writes.
"""

import json
from typing import Optional

from anthropic import Anthropic

from .scripts import Script, ScriptStep

MODEL = "claude-sonnet-4-6"

# Tool the model MUST call. tool_choice forces it, so the model can't reply
# in plain text. The input_schema mirrors the Script pydantic model so what
# comes back is directly serializable.
SAVE_SCRIPT_TOOL = {
    "name": "save_script",
    "description": (
        "Save the updated open-house script. Call this exactly once with the "
        "complete script after applying the agent's requested change. Include "
        "every step — both the ones being changed and the ones being kept."
    ),
    "input_schema": {
        "type": "object",
        "required": ["name", "description", "steps"],
        "properties": {
            "name": {
                "type": "string",
                "description": "Short name for the script. Keep ≤ 60 chars.",
            },
            "description": {
                "type": "string",
                "description": "One sentence describing what this flow is for.",
            },
            "steps": {
                "type": "array",
                "description": "Ordered steps of the script. Preserve order for unchanged steps.",
                "items": {
                    "type": "object",
                    "required": ["id", "section", "label", "quote", "intent"],
                    "properties": {
                        "id": {
                            "type": "string",
                            "description": (
                                "Stable id, snake_case. Re-use the existing id "
                                "when editing a step so coverage history "
                                "matches. Pick a fresh snake_case id for new "
                                "steps."
                            ),
                        },
                        "section": {
                            "type": "string",
                            "description": (
                                "Grouping label, e.g. 'Buyer' or 'Seller'. "
                                "Steps with the same section render together."
                            ),
                        },
                        "label": {
                            "type": "string",
                            "description": "Human-readable step title.",
                        },
                        "quote": {
                            "type": "string",
                            "description": (
                                "The verbatim line the agent intends to "
                                "deliver. Spoken language, not headlines."
                            ),
                        },
                        "intent": {
                            "type": "string",
                            "description": (
                                "Why this step matters — helps the coverage "
                                "grader recognize flexible phrasings."
                            ),
                        },
                    },
                },
            },
        },
    },
}


SYSTEM_PROMPT = (
    "You edit open-house scripts for a real-estate agent. A script is an "
    "ordered set of steps the agent walks visitors through during an open "
    "house. Each step has a verbatim quote (what the agent says) and an "
    "intent (why it matters).\n\n"
    "You MUST respond by calling the save_script tool exactly once. Never "
    "reply with plain text — the calling app only reads the tool input. "
    "When editing an existing script, return the FULL script including all "
    "unchanged steps in their original order — partial returns will overwrite "
    "the script and lose data.\n\n"
    "Editing rules:\n"
    "- Keep existing step ids stable when editing in place; only invent new "
    "ids for genuinely new steps.\n"
    "- Quotes should sound like a real agent speaking, not a headline.\n"
    "- If the user's instruction is ambiguous, make the smallest change "
    "consistent with it — don't rewrite the whole script.\n"
    "- If the user asks for something destructive (e.g. 'remove all seller "
    "steps'), do it — the app has an undo button.\n"
)


def _call_claude_tool(messages: list[dict]) -> dict:
    """Single round-trip to Claude with tool_choice forced. Returns the
    tool input dict (already a script-shaped object). Raises if the model
    fails to call the tool — caller decides how to surface that."""
    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=4000,
        system=SYSTEM_PROMPT,
        tools=[SAVE_SCRIPT_TOOL],
        tool_choice={"type": "tool", "name": "save_script"},
        messages=messages,
    )
    for block in response.content:
        if getattr(block, "type", None) == "tool_use" and block.name == "save_script":
            return block.input
    raise ValueError("Claude did not call save_script — got: " + repr(response.content))


def _script_to_dict(script: Script) -> dict:
    """Compact JSON form we hand to Claude as context. Keeping it identical
    to the tool's input shape avoids any translation in the model's head."""
    return {
        "name": script.name,
        "description": script.description,
        "steps": [
            {
                "id": s.id, "section": s.section, "label": s.label,
                "quote": s.quote, "intent": s.intent,
            } for s in script.steps
        ],
    }


def _parsed_to_script(script_id: str, parsed: dict) -> Script:
    """Coerce the tool input into a Script. Tool schema enforces required
    fields, but we still defensively normalize step ids in case the model
    drifts on the snake_case rule."""
    steps: list[ScriptStep] = []
    seen_ids: set[str] = set()
    for i, raw in enumerate(parsed.get("steps") or []):
        sid = (raw.get("id") or f"step_{i+1}").strip() or f"step_{i+1}"
        # Avoid duplicate ids — coverage grading keys off them and dupes
        # silently merge results across steps.
        if sid in seen_ids:
            sid = f"{sid}_{i+1}"
        seen_ids.add(sid)
        steps.append(ScriptStep(
            id=sid,
            section=(raw.get("section") or "Custom").strip() or "Custom",
            label=(raw.get("label") or f"Step {i+1}").strip() or f"Step {i+1}",
            quote=(raw.get("quote") or "").strip(),
            intent=(raw.get("intent") or "").strip(),
        ))
    return Script(
        id=script_id,
        name=(parsed.get("name") or "Untitled script").strip(),
        description=(parsed.get("description") or "").strip(),
        steps=steps,
    )


def agent_edit_script(current: Script, instruction: str) -> Script:
    """Apply `instruction` to `current` via Claude tool call. Returns a fully-
    formed Script with the same id (caller writes it to the same slot)."""
    user_msg = (
        f"Here is the current script as JSON:\n```json\n"
        f"{json.dumps(_script_to_dict(current), indent=2)}\n```\n\n"
        f"The agent's instruction: {instruction.strip()}\n\n"
        "Apply the change and call save_script with the FULL updated script."
    )
    parsed = _call_claude_tool([{"role": "user", "content": user_msg}])
    return _parsed_to_script(current.id, parsed)


def agent_create_script(new_id: str, instruction: str) -> Script:
    """Build a fresh script from `instruction` and return it stamped with
    `new_id`. Caller picks the id (typically `user_<hex>`)."""
    user_msg = (
        f"Build a new open-house script from this brief: {instruction.strip()}\n\n"
        "Create a name, a one-sentence description, and 4–10 steps that flow "
        "naturally for the agent to deliver in person. Use snake_case ids. "
        "Group steps with a `section` label so related steps render together. "
        "Then call save_script with the full result."
    )
    parsed = _call_claude_tool([{"role": "user", "content": user_msg}])
    return _parsed_to_script(new_id, parsed)
