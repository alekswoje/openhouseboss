"""Preset + user-created open-house scripts.

A script is a structured walkthrough of what the agent intends to say at each
stage of an open house. After the session is transcribed and diarized, we hand
the script + transcript to Claude and get back a per-step coverage report.

We ship one preset (Aleks's buyer/seller flow) and persist user-created
scripts to disk under `scripts_data/`. Both kinds appear in /scripts and can
be referenced by id when starting a session.
"""

import json
import uuid
from pathlib import Path
from typing import Optional

from pydantic import BaseModel


class ScriptStep(BaseModel):
    id: str               # stable id, used in coverage results
    section: str          # e.g. "Buyer Lead Flow"
    label: str            # e.g. "Step 1 — Establish the Timeline"
    quote: str            # the actual line the agent intended to deliver
    intent: str           # *why* this step matters (helps Claude grade flex)


class Script(BaseModel):
    id: str
    name: str
    description: str
    steps: list[ScriptStep]


# ─────────── Aleks's buyer + seller flows ───────────
# Transcribed from the agent's PDF; phrasing matches verbatim so coverage
# grading can use the literal quote as the strongest signal. The original
# bundled `aleks_buyer_seller_v1` has been split into two standalone
# scripts so the agent picks the right one for the visitor in front of them
# without dragging the irrelevant half into coverage scoring.

ALEKS_BUYER_SCRIPT = Script(
    id="aleks_buyer_v1",
    name="Aleks — Buyer Flow",
    description="Buyer qualification flow with the $2,500 rebate close.",
    steps=[
        ScriptStep(
            id="opener",
            section="Buyer",
            label="The Opener",
            quote=(
                "Hey, I'm Aleks — glad you came out! What brought you in today, "
                "are you actively looking or just getting a feel for the area?"
            ),
            intent=(
                "Warm introduction + immediate qualification. Sorts neighbors "
                "from buyers without ceremony."
            ),
        ),
        ScriptStep(
            id="buyer_timeline",
            section="Buyer",
            label="Step 1 — Establish the Timeline",
            quote=(
                "So are you just starting to explore the market, or are you "
                "getting close to making a move?"
            ),
            intent=(
                "Timeline is the single biggest indicator of lead quality. "
                "Listen for move-in dates or 'just looking' language."
            ),
        ),
        ScriptStep(
            id="buyer_search_history",
            section="Buyer",
            label="Step 2 — Gauge Search History",
            quote=(
                "How long have you been looking? And what have you seen so far?"
            ),
            intent=(
                "Duration + specificity = seriousness. Also reveals what "
                "they've already rejected."
            ),
        ),
        ScriptStep(
            id="buyer_pain",
            section="Buyer",
            label="Step 3 — Uncover Pain",
            quote="What's kept you from pulling the trigger on something yet?",
            intent=(
                "The single most important question. Shifts from small talk "
                "to real information about what's blocking them."
            ),
        ),
        ScriptStep(
            id="buyer_offer_check",
            section="Buyer",
            label="Step 4 — Offer Check",
            quote="Have you made any offers on anything?",
            intent=(
                "Making an offer = strong seriousness signal. Also surfaces "
                "whether they're already locked in with another agent."
            ),
        ),
        ScriptStep(
            id="buyer_lender",
            section="Buyer",
            label="Step 5 — Financial Readiness (soft)",
            quote=(
                "Are you working with a lender yet, or is that still something "
                "you're figuring out?"
            ),
            intent=(
                "Softer than 'are you pre-approved?' — gets the same answer "
                "without feeling like an interrogation."
            ),
        ),
        ScriptStep(
            id="buyer_release",
            section="Buyer",
            label="Step 6 — The Release (with hook)",
            quote=(
                "Well I don't want to keep you — go take a look around. Come "
                "find me when you're done — I want to tell you about something "
                "I'm doing exclusively for people who come through today."
            ),
            intent=(
                "Removes sales pressure. The hook gives them a concrete "
                "reason to come back."
            ),
        ),
        ScriptStep(
            id="buyer_reengage",
            section="Buyer",
            label="Step 7 — The Re-Engage",
            quote=(
                "So — what'd you think? Can you see yourself here? What would "
                "make it a yes for you?"
            ),
            intent=(
                "'See yourself here' invites emotion. 'What would make it a "
                "yes?' gets them to describe their perfect home."
            ),
        ),
        ScriptStep(
            id="buyer_close_rebate",
            section="Buyer",
            label="Step 8 — Close + Reveal the $2,500 Rebate",
            quote=(
                "I'm offering a $2,500 rebate at closing, exclusively for "
                "buyers who came through this open house today. If we work "
                "together and you close on something, that money goes back "
                "in your pocket. What's your timeline looking like — are you "
                "open to jumping on a quick call this week?"
            ),
            intent=(
                "Reveals the rebate as a reward for seriousness, not a "
                "gimmick. Creates urgency: today only, this open house only."
            ),
        ),
    ],
)


ALEKS_SELLER_SCRIPT = Script(
    id="aleks_seller_v1",
    name="Aleks — Seller Flow",
    description="Neighbor-to-seller pivot ending with a free comp analysis offer.",
    steps=[
        ScriptStep(
            id="seller_pricing",
            section="Seller",
            label="Step 1 — Spot the Signal & Pivot",
            quote=(
                "Oh perfect — so you probably know this area better than "
                "anyone. Honestly, what do you think of the house? Do you "
                "think it's priced right for the neighborhood?"
            ),
            intent=(
                "Flatters the neighbor as a local expert. Whether they "
                "engage with pricing tells you if they're a seller signal."
            ),
        ),
        ScriptStep(
            id="seller_curiosity",
            section="Seller",
            label="Step 2 — Test the Seller Curiosity",
            quote=(
                "Have you thought about what your place might be worth in "
                "this market?"
            ),
            intent=(
                "People don't wonder about home value unless it's crossed "
                "their mind. Even a casual yes = potential seller lead."
            ),
        ),
        ScriptStep(
            id="seller_marketing",
            section="Seller",
            label="Step 3 — Pitch the Unfair Advantage",
            quote=(
                "If you're ever thinking about listing, I do full drone video "
                "and professional photography as part of my marketing package "
                "— no upcharge, it's just what I do. Homes I list look "
                "completely different from what you typically see out here."
            ),
            intent=(
                "Speaks to the real concern — how will my home be presented? "
                "Positions you as premium without saying it outright."
            ),
        ),
        ScriptStep(
            id="seller_comp",
            section="Seller",
            label="Step 4 — Free Comp Analysis Offer",
            quote=(
                "Tell you what — I'll do a free comp analysis for your "
                "address and put together what a full marketing plan would "
                "look like for your home. No commitment, just so you have "
                "the information. What's the best way to reach you?"
            ),
            intent=(
                "Low-friction yes for them, strong follow-up hook for you. "
                "The comp deliverable gets you back in front of them."
            ),
        ),
    ],
)


PRESETS: list[Script] = [ALEKS_BUYER_SCRIPT, ALEKS_SELLER_SCRIPT]

# User-created scripts live in this directory; one JSON file per script.
USER_SCRIPTS_DIR = Path("scripts_data")
USER_SCRIPTS_DIR.mkdir(exist_ok=True)

# Single-step undo. Before any agent-edit we snapshot the current script
# here, keyed by id; undo restores the snapshot and deletes it. One slot per
# script — chained edits overwrite the snapshot, so undo always rolls back
# the most recent change.
REVISIONS_DIR = USER_SCRIPTS_DIR / "_revisions"
REVISIONS_DIR.mkdir(exist_ok=True)


def _load_user_scripts() -> list[Script]:
    """Read all user-created scripts from disk. Cheap — there shouldn't be
    more than a handful per agent."""
    scripts: list[Script] = []
    for f in sorted(USER_SCRIPTS_DIR.glob("*.json")):
        try:
            scripts.append(Script(**json.loads(f.read_text())))
        except Exception:
            # Ignore malformed files rather than 500 on /scripts list.
            continue
    return scripts


def get_script(script_id: Optional[str]) -> Optional[Script]:
    if not script_id:
        return None
    # User override takes precedence over the bundled preset. That's how
    # editing a preset works: we drop a file at scripts_data/{preset_id}.json
    # and subsequent reads return the agent's edited version. Deleting the
    # override file resets the preset to factory.
    user_file = USER_SCRIPTS_DIR / f"{script_id}.json"
    if user_file.exists():
        try:
            return Script(**json.loads(user_file.read_text()))
        except Exception:
            pass  # fall through to preset if file is malformed
    for s in PRESETS:
        if s.id == script_id:
            return s
    return None


def save_user_script(name: str, description: str, steps: list[dict]) -> Script:
    """Persist a new user-created script and return it with a generated id.
    Steps come in as plain dicts so this works with the FastAPI form payload."""
    script_id = f"user_{uuid.uuid4().hex[:10]}"
    parsed_steps = []
    for i, s in enumerate(steps):
        parsed_steps.append(ScriptStep(
            id=s.get("id") or f"step_{i+1}",
            section=s.get("section") or "Custom",
            label=s.get("label") or f"Step {i+1}",
            quote=s.get("quote") or "",
            intent=s.get("intent") or "",
        ))
    script = Script(
        id=script_id, name=name, description=description, steps=parsed_steps,
    )
    (USER_SCRIPTS_DIR / f"{script_id}.json").write_text(
        json.dumps(script.model_dump(), indent=2)
    )
    return script


def update_user_script(script_id: str, name: str, description: str, steps: list[dict]) -> Optional[Script]:
    """Overwrite a script in place. Works for both user-created scripts and
    presets — editing a preset writes an override file at the preset's id, and
    subsequent reads return the edited version. Returns None only if the id
    is neither a known preset nor an existing user script."""
    preset_ids = {s.id for s in PRESETS}
    user_file = USER_SCRIPTS_DIR / f"{script_id}.json"
    if script_id not in preset_ids and not user_file.exists():
        return None
    parsed_steps = []
    for i, s in enumerate(steps):
        parsed_steps.append(ScriptStep(
            id=s.get("id") or f"step_{i+1}",
            section=s.get("section") or "Custom",
            label=s.get("label") or f"Step {i+1}",
            quote=s.get("quote") or "",
            intent=s.get("intent") or "",
        ))
    script = Script(
        id=script_id, name=name, description=description, steps=parsed_steps,
    )
    user_file.write_text(json.dumps(script.model_dump(), indent=2))
    return script


def delete_user_script(script_id: str) -> bool:
    """Remove a user-created script, or reset a preset to factory by deleting
    its override file. Returns False only if there's nothing on disk to remove
    AND the id isn't a known preset."""
    preset_ids = {s.id for s in PRESETS}
    f = USER_SCRIPTS_DIR / f"{script_id}.json"
    if f.exists():
        f.unlink()
        return True
    # Deleting a preset with no override is a no-op success — the agent is
    # asking to "reset" something that's already at factory.
    return script_id in preset_ids


def list_scripts_summary() -> list[dict]:
    """Compact list for the iOS Scripts tab — presets + user scripts. Each
    preset id is deduped: if the agent has saved an override, the override
    wins and `is_preset` stays true so the UI keeps the badge and DELETE
    resets it to factory. `can_undo` flags scripts that have a stored
    pre-edit revision the user can roll back to."""
    preset_ids = {s.id for s in PRESETS}
    user_scripts = _load_user_scripts()
    user_ids = {s.id for s in user_scripts}
    items = []
    # Presets that haven't been overridden show first; overridden ones come
    # through the user-scripts loop below with is_preset still true.
    for s in PRESETS:
        if s.id in user_ids:
            continue
        items.append({
            "id": s.id,
            "name": s.name,
            "description": s.description,
            "step_count": len(s.steps),
            "is_preset": True,
            "can_undo": _revision_path(s.id).exists(),
        })
    for s in user_scripts:
        items.append({
            "id": s.id,
            "name": s.name,
            "description": s.description,
            "step_count": len(s.steps),
            "is_preset": s.id in preset_ids,
            "can_undo": _revision_path(s.id).exists(),
        })
    return items


# ─────────── Revisions (single-step undo) ───────────

def _revision_path(script_id: str) -> Path:
    return REVISIONS_DIR / f"{script_id}.json"


def snapshot_revision(script: Optional[Script]) -> None:
    """Persist `script` as the pre-edit revision for its id. Call this BEFORE
    any agent-edit so undo restores the right state. A `None` script means
    'this id had no prior state' (a fresh agent-create) — we still write a
    sentinel so undo deletes the freshly-created script."""
    if script is None:
        return
    _revision_path(script.id).write_text(
        json.dumps(script.model_dump(), indent=2)
    )


def snapshot_absent(script_id: str) -> None:
    """Mark `script_id` as having no prior state, so undo deletes it."""
    _revision_path(script_id).write_text(json.dumps({"absent": True}))


def restore_revision(script_id: str) -> Optional[Script]:
    """Roll back to the last snapshot for `script_id`. Returns the restored
    script (or None if the snapshot says the script didn't exist pre-edit, in
    which case the caller should delete the current script). Raises
    FileNotFoundError if there's no revision to restore."""
    path = _revision_path(script_id)
    if not path.exists():
        raise FileNotFoundError(f"No revision for {script_id}")
    raw = json.loads(path.read_text())
    path.unlink()
    if raw.get("absent"):
        return None
    return Script(**raw)


def has_revision(script_id: str) -> bool:
    return _revision_path(script_id).exists()
