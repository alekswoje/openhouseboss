"""Preset open-house scripts + a tiny helper for looking them up by id.

A script is a structured walkthrough of what the agent intends to say at each
stage of an open house. After the session is transcribed and diarized, we hand
the script + transcript to Claude and get back a per-step coverage report.

For now we ship one preset (the user's own buyer/seller flow). Down the road
we'll add PDF upload + parsing so agents can bring their own — same data
shape, just generated at upload time instead of hardcoded here.
"""

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


# ─────────── Aleks's buyer + seller flow ───────────
# Transcribed from the agent's PDF; phrasing matches verbatim so coverage
# grading can use the literal quote as the strongest signal.
ALEKS_SCRIPT = Script(
    id="aleks_buyer_seller_v1",
    name="Aleks — Buyer + Seller Flow",
    description="Lead qualification flow with the $2,500 buyer rebate close.",
    steps=[
        # Buyer flow
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
        # Seller flow
        ScriptStep(
            id="seller_pricing",
            section="Seller",
            label="Seller Step 1 — Spot the Signal & Pivot",
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
            label="Seller Step 2 — Test the Seller Curiosity",
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
            label="Seller Step 3 — Pitch the Unfair Advantage",
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
            label="Seller Step 4 — Free Comp Analysis Offer",
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


PRESETS: list[Script] = [ALEKS_SCRIPT]


def get_script(script_id: Optional[str]) -> Optional[Script]:
    if not script_id:
        return None
    for s in PRESETS:
        if s.id == script_id:
            return s
    return None


def list_scripts_summary() -> list[dict]:
    """Compact list for the iOS Setup picker."""
    return [
        {
            "id": s.id,
            "name": s.name,
            "description": s.description,
            "step_count": len(s.steps),
        }
        for s in PRESETS
    ]
