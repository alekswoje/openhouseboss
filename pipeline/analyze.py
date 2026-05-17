import json

import assemblyai as aai
from anthropic import Anthropic
from pydantic import BaseModel

from .identify import Visitor, _extract_json
from .tags import Tag

MODEL = "claude-sonnet-4-6"
# Lightweight model for short rewrites where speed beats nuance. The full
# analyze pass stays on Sonnet for tone-sensitive judgment; refine is a
# narrow "rewrite this email per the agent's nudge" task that Haiku
# handles in 1-3s vs Sonnet's 5-15s. The latency win matters because the
# user is staring at the editor waiting for the AI's output.
FAST_MODEL = "claude-haiku-4-5"


class VisitorAnalysis(BaseModel):
    summary: str
    tag: str
    tag_reason: str
    score: int          # 0–100 interest / urgency score
    signals: list[str]  # 3–5 short phrase chips like "Pre-approved $1.4M"
    follow_up_draft: str
    words_spoken: int


def _render_template_for_visitor(template: dict, visitor: Visitor) -> dict:
    """Apply the well-known auto-fill slots ({first_name}, {full_name}) before
    the LLM sees the template. Anything else (e.g. {call_to_action}) is left
    for the LLM (soft) or the agent (forced) to fill in. This keeps the LLM
    from hallucinating common-name slots."""
    first = (visitor.name or "").strip().split(" ")[0] if visitor.name else ""
    full = (visitor.name or "").strip()
    def _fill(text: str) -> str:
        return (text or "").replace("{first_name}", first).replace("{full_name}", full)
    return {
        "name": template.get("name") or "",
        "match_hints": template.get("match_hints") or "",
        "subject": _fill(template.get("subject") or ""),
        "body": _fill(template.get("body") or ""),
    }


def _template_instructions(templates: list[dict], force: bool) -> str:
    if not templates:
        return ""
    blocks = []
    for i, t in enumerate(templates, 1):
        blocks.append(
            f"--- Template {i}: {t['name']}\n"
            f"Match hints (when this fits the lead): {t['match_hints'] or '(none)'}\n"
            f"Subject: {t['subject'] or '(none)'}\n"
            f"Body:\n{t['body']}\n"
        )
    catalog = "\n".join(blocks)
    if force:
        return (
            "\n\nTHE AGENT HAS PROVIDED FOLLOW-UP TEMPLATES AND REQUIRES THAT YOU USE ONE.\n"
            "Pick the template whose match hints best fit this lead. Use its body VERBATIM, "
            "fixing only grammar/punctuation if needed. Replace any `{slot}` token by "
            "inferring its value from the conversation when possible; if you cannot infer it, "
            "leave it as `[slot]` so the agent fills it in. Do not invent new sentences. "
            "Templates:\n" + catalog
        )
    return (
        "\n\nThe agent has provided follow-up templates. If one of them clearly fits this "
        "lead based on its match hints, base your draft heavily on that template — keep its "
        "structure, tone, and key phrases, but rewrite freely to match what the visitor "
        "actually said. Replace any `{slot}` tokens with concrete values when possible. "
        "If no template fits, draft from scratch as usual. Templates:\n" + catalog
    )


def _voice_instructions(samples: list[str] | None) -> str:
    """If the agent pasted a few of their own past follow-ups, those become
    the dominant voice anchor — beats any general "be casual" instruction.
    Empty / unset → we lean on the in-prompt good/bad examples alone."""
    cleaned = [s.strip() for s in (samples or []) if s and s.strip()]
    if not cleaned:
        return ""
    chunks = "\n\n".join(f"--- sample {i+1}:\n{s}" for i, s in enumerate(cleaned[:5]))
    return (
        "===== AGENT'S OWN PAST FOLLOW-UPS (HIGHEST AUTHORITY ON VOICE) =====\n"
        "These are real notes this agent has sent. Match THEIR voice — their "
        "capitalization habits, their punctuation, their level of warmth, "
        "their typical length, the way they open and close. If their voice "
        "conflicts with any general example above, FOLLOW THE AGENT. Do not "
        "copy phrases verbatim; absorb the rhythm.\n\n"
        + chunks
        + "\n\n===== END AGENT VOICE =====\n\n"
    )


def analyze_visitor(
    transcript: aai.Transcript,
    visitor: Visitor,
    tags: list[Tag],
    templates: list[dict] | None = None,
    force_templates: bool = False,
    voice_samples: list[str] | None = None,
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

    rendered_templates = [
        _render_template_for_visitor(t, visitor) for t in (templates or [])
    ]
    template_block = _template_instructions(rendered_templates, force_templates)
    voice_block = _voice_instructions(voice_samples)

    system_prompt = (
        "You help a real-estate agent follow up after an open house. You are given "
        "a diarized transcript; focus on the visitor identified below. Produce a "
        "short summary (3–5 sentences) of what they said and what they seem to want, "
        "pick exactly one tag from the list, score their interest/urgency 0–100 "
        "(0=cold, 50=warm, 80+=hot/transacting soon), extract 3–5 short signal "
        "phrases (each ≤4 words — concrete facts like 'Pre-approved $1.4M', "
        "'Close in 60 days', 'Owner 15 yrs'), and draft a short follow-up note "
        "from the agent to the visitor.\n\n"
        "===== VOICE — THIS IS THE WHOLE GAME =====\n"
        "The draft must sound like a busy real human agent dashing off a note "
        "between showings. NOT an AI assistant writing a polished email. If "
        "the recipient could tell ChatGPT wrote it, you have failed.\n\n"
        "HARD RULES:\n"
        "- 1–3 short sentences. Under 50 words. Sometimes 1 sentence is right.\n"
        "- Lowercase opening is fine and often better (\"hey,\" \"good meeting "
        "you today\" — no capital H). Contractions everywhere. Fragments OK.\n"
        "- NO formulaic close. Sometimes end with a question, sometimes don't. "
        "Often the strongest move is to OFFER TO BACK OFF: \"no rush on your "
        "end,\" \"i'll leave you alone til you want me back,\" \"either way "
        "works.\" Real agents do this constantly. AI never does.\n"
        "- Reference one specific thing they said, but don't shoehorn it. If "
        "nothing concrete stood out, a loose acknowledgment is fine.\n\n"
        "BANNED PHRASES (instant AI tells — never use any of these or "
        "anything close):\n"
        "  • \"Great meeting you\" / \"It was great meeting you\"\n"
        "  • \"I really enjoyed\" / \"I loved hearing\"\n"
        "  • \"I'd love to\" / \"I would love to\"\n"
        "  • \"I hope this finds you well\" / \"I hope you're doing well\"\n"
        "  • \"Feel free to\" / \"Please don't hesitate\"\n"
        "  • \"I look forward to\" / \"Looking forward to hearing\"\n"
        "  • \"Would you be open to a [N]-minute call\"\n"
        "  • \"Let me know if\" (as a closer)\n"
        "  • \"touch base\" / \"circle back\" / \"reach out\"\n"
        "  • Any opener that's about YOUR feelings about the meeting\n\n"
        "GOOD EXAMPLES (study the voice — short, human, lowercase-y, "
        "willing to back off):\n"
        "  ex1 (warm browser, just looking): \"hey, good meeting you today. "
        "welcome out of redmond — that's a move. if anything in the 7s pops "
        "up that's actually worth a look i'll send it over. no rush on your "
        "end.\"\n"
        "  ex2 (warm, asks something real): \"nice meeting you today. want "
        "me to just send stuff as it comes up in your range, or wait til "
        "you've got a sharper read on what you're after?\"\n"
        "  ex3 (cold/short, optional close): \"hey nice meeting you. happy "
        "to keep an eye on things in your range. otherwise i'll leave you "
        "alone til you want me back.\"\n"
        "  ex4 (something specific they said — kid starting school): "
        "\"good meeting you today. heard you mention the august move for "
        "school — if anything fitting that timeline comes up i'll flag it.\"\n"
        "  ex5 (hot, sold visit): \"good meeting you today! you seemed "
        "pretty into the kitchen — happy to pull a couple comps on similar "
        "remodels in the area if it'd help you think about it.\"\n\n"
        "BAD EXAMPLE (do NOT produce this — every line a tell):\n"
        "  \"Hi Sarah, it was great meeting you at the open house today! I "
        "really enjoyed hearing about your move from Redmond. Given you're "
        "looking in the $700-800K range, I'd love to share some properties "
        "that might catch your eye. Would you be open to a 15-minute call "
        "Thursday to discuss your search criteria?\"\n\n"
        "===== END VOICE =====\n\n"
        + voice_block
        + "ANTI-HALLUCINATION RULES (these matter — the agent sends these "
        "notes as-is and gets caught in a lie if you invent things):\n"
        "- NEVER claim the agent has specific resources, listings, or "
        "deliverables that aren't mentioned in the transcript or the "
        "templates/offers block below. Forbidden examples: \"I have other "
        "homes in your price range\", \"I'll send you the three comps I "
        "pulled\", \"I have a unit in that neighborhood\", \"I've got a "
        "buyer for your place\", \"my colleague specializes in that area\".\n"
        "- Promise-style asks must be open-ended — \"if anything pops up "
        "in your range i'll send it\" is fine; \"i'll send the three "
        "listings i have on the west side\" is not.\n"
        "- Don't invent prices, square footage, neighborhood facts, market "
        "stats, or timeline promises. If the transcript didn't say it and "
        "no template/offer covers it, don't write it.\n"
        "- Short and generic beats specific and wrong. Always.\n\n"
        "DO NOT include any sign-off, signature line, or agent name — the "
        "email client appends the agent's signature automatically. NEVER "
        "use bracketed placeholders like [Agent Name], [Address], [Phone], "
        "etc. — they get sent as-is and embarrass the agent. If you don't "
        "know a value, leave it out."
        + template_block
        + "\n\n"
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
    )

    client = Anthropic()

    def _call(extra_user_hint: str = "") -> str:
        content = utterances_text + (f"\n\n{extra_user_hint}" if extra_user_hint else "")
        response = client.messages.create(
            model=MODEL,
            max_tokens=1500,
            system=system_prompt,
            messages=[{"role": "user", "content": content}],
        )
        return response.content[0].text

    # Defensive parse: Claude occasionally returns an array wrapper, a
    # truncated stub like "[", or text with unquoted values — each of
    # those trips json.loads and would kill the whole session with a raw
    # "Expecting value: line 1 column 2 (char 1)" message in the UI. Try
    # once more with a stricter hint, then fall back to a stub so the
    # session still completes (agent can write the draft themselves).
    parsed: dict | None = None
    for attempt in range(2):
        raw = _call(
            "" if attempt == 0 else
            "IMPORTANT: your previous response was not valid JSON. "
            "Respond with a single JSON OBJECT (starting with '{' and "
            "ending with '}'), no array brackets, no markdown fences, "
            "no commentary."
        )
        try:
            candidate = json.loads(_extract_json(raw))
        except json.JSONDecodeError:
            continue
        if isinstance(candidate, list) and candidate and isinstance(candidate[0], dict):
            candidate = candidate[0]  # tolerate [{...}] wrapping
        if isinstance(candidate, dict):
            parsed = candidate
            break

    if parsed is None:
        parsed = {
            "summary": "",
            "tag": (tags[0].name if tags else "Browser"),
            "tag_reason": "Auto-analysis didn't produce a structured result — review the transcript and tag manually.",
            "score": 0,
            "signals": [],
            "follow_up_draft": "",
        }

    parsed["words_spoken"] = words_spoken
    parsed["follow_up_draft"] = _scrub_placeholders(parsed.get("follow_up_draft") or "")
    return VisitorAnalysis(**parsed)


# Bracketed placeholders ([Agent Name], [Address], [Phone Number], etc.)
# in a drafted email are catastrophic — agents send them as-is and look
# unprofessional. We tell the LLM not to use them, but LLMs ignore
# instructions sometimes, so we also strip them defensively. The signed
# email always has the agent's signature appended client-side, so any
# closing salutation/agent line the LLM produces is also redundant
# noise — we leave that alone (it's harmless if removed by the agent).
import re as _re_placeholders

_BRACKET_PLACEHOLDER_RE = _re_placeholders.compile(r"\[[^\[\]\n]{1,80}\]")


def _build_library_block(
    mentioned_offers: list[dict],
    mentioned_templates: list[dict],
    available_offers: list[dict],
    available_templates: list[dict],
) -> str:
    """Build the LLM-facing block describing offers + templates available
    for this rewrite. Mentioned items are flagged as MUST include; the
    rest are "use if it fits" so the LLM doesn't have to be told
    explicitly to consider them.

    Templates are tone/structure references — the LLM should rewrite in
    that style. Offers are content references — the LLM should weave the
    actual marketing copy into the email.

    Returns an empty string if there's nothing to inject.
    """
    if not (mentioned_offers or mentioned_templates
            or available_offers or available_templates):
        return ""

    sections: list[str] = []

    if mentioned_offers:
        chunks = []
        for o in mentioned_offers:
            name = (o.get("name") or "").strip()
            ob = (o.get("body") or "").strip()
            chunks.append(f"@{name}\n{ob}")
        sections.append(
            "OFFERS THE AGENT REQUIRES YOU TO INCLUDE — weave their "
            "content naturally into the rewrite (do NOT leave the "
            "@reference token in the output, do NOT quote verbatim unless "
            "the offer body already reads like email copy):\n\n"
            + "\n\n".join(chunks)
        )

    if mentioned_templates:
        chunks = []
        for t in mentioned_templates:
            name = (t.get("name") or "").strip()
            body = (t.get("body") or "").strip()
            chunks.append(f"@{name}\n{body}")
        sections.append(
            "TEMPLATES THE AGENT REQUIRES YOU TO USE — base the rewrite "
            "on the template's structure and phrasing, replacing "
            "{slot} tokens with concrete values from the lead's context "
            "or leaving them as [slot] when you can't infer:\n\n"
            + "\n\n".join(chunks)
        )

    # `available_*` is everything else the agent has enabled. We pass it
    # so the LLM can pick the best fit on its own when nothing's
    # explicitly tagged. Skip items that were already listed above.
    mentioned_offer_ids = {o.get("id") for o in mentioned_offers}
    extra_offers = [
        o for o in available_offers
        if o.get("id") not in mentioned_offer_ids
    ]
    if extra_offers:
        chunks = []
        for o in extra_offers:
            name = (o.get("name") or "").strip()
            ob = (o.get("body") or "").strip()
            chunks.append(f"{name}: {ob}")
        sections.append(
            "Available offers (the agent has these on file — feel free to "
            "weave the one that best fits this lead, OR leave them all "
            "out if none fit):\n\n"
            + "\n\n".join(chunks)
        )

    mentioned_template_ids = {t.get("id") for t in mentioned_templates}
    extra_templates = [
        t for t in available_templates
        if t.get("id") not in mentioned_template_ids
    ]
    if extra_templates:
        chunks = []
        for t in extra_templates:
            name = (t.get("name") or "").strip()
            body = (t.get("body") or "").strip()
            hints = (t.get("match_hints") or "").strip()
            line = name
            if hints:
                line += f" (fits when: {hints})"
            chunks.append(f"{line}\n{body}")
        sections.append(
            "Available templates (the agent has these on file — base the "
            "rewrite on the best-fitting one's structure if any fits, OR "
            "ignore them all if none fits naturally):\n\n"
            + "\n\n".join(chunks)
        )

    return "\n\n".join(sections) + "\n\n"


def _scrub_placeholders(text: str) -> str:
    """Remove any [Bracketed] placeholders and tidy the whitespace they
    leave behind. Bracketed text up to 80 chars is treated as a
    placeholder — long enough to catch "[Property Address]" but short
    enough that a legitimate aside in brackets stays. Paragraph breaks
    in the middle of the email are preserved; only stretches of 3+
    blank lines (which only happen when a placeholder sat on its own
    line) get collapsed.
    """
    if not text:
        return text
    cleaned = _BRACKET_PLACEHOLDER_RE.sub("", text)
    # Collapse runs of 3+ newlines to 2 (= one blank line between
    # paragraphs). Anything longer was usually the result of stripping
    # a sign-off on its own line.
    cleaned = _re_placeholders.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def refine_draft(
    current_body: str,
    instruction: str,
    visitor_name: str | None = None,
    visitor_summary: str | None = None,
    visitor_tag: str | None = None,
    address: str | None = None,
    mentioned_offers: list[dict] | None = None,
    mentioned_templates: list[dict] | None = None,
    available_offers: list[dict] | None = None,
    available_templates: list[dict] | None = None,
    voice_samples: list[str] | None = None,
) -> str:
    """Rewrite an existing follow-up draft according to the agent's
    instruction ("too long", "add a CTA about the 1pm Saturday tour", "more
    casual", etc.).

    `mentioned_offers` / `mentioned_templates` are entries the agent
    explicitly @-referenced — the LLM MUST work them in. `available_*`
    are the rest of the agent's enabled library; the LLM can pick from
    these when nothing's explicitly mentioned (e.g. "pick the best
    offer for this lead").

    Kept deliberately tight — we only return the new email body, no JSON
    envelope. The agent will see it slot into the editor where they can
    still make manual tweaks.
    """
    body = (current_body or "").strip()
    ask = (instruction or "").strip()
    if not ask:
        return body

    context_lines = []
    if visitor_name:
        context_lines.append(f"Lead: {visitor_name}")
    if visitor_tag:
        context_lines.append(f"Tag: {visitor_tag}")
    if address:
        context_lines.append(f"Property: {address}")
    if visitor_summary:
        context_lines.append(f"What we heard: {visitor_summary}")
    context_block = ("\n".join(context_lines) + "\n\n") if context_lines else ""

    # Material the LLM can pull from. `mentioned_*` are agent-flagged
    # MUST-include; `available_*` are background options it can use when
    # nothing's explicitly @-referenced.
    library_block = _build_library_block(
        mentioned_offers=mentioned_offers or [],
        mentioned_templates=mentioned_templates or [],
        available_offers=available_offers or [],
        available_templates=available_templates or [],
    )
    voice_block = _voice_instructions(voice_samples)

    client = Anthropic()
    response = client.messages.create(
        # Haiku on the fast model so the agent isn't waiting 10s for an
        # email rewrite. Haiku is fully capable here — we're not asking
        # it to grade nuance, just to follow a tight instruction like
        # "make this shorter" or "add a CTA about Saturday's tour".
        model=FAST_MODEL,
        max_tokens=400,
        system=(
            "You rewrite a real-estate follow-up note per the agent's "
            "instruction. The output must sound like a busy human agent — "
            "NOT an AI assistant. Default to 1–3 short sentences. Lowercase "
            "openings are fine. Contractions everywhere. Fragments OK. Often "
            "the strongest ending is to offer to back off (\"no rush,\" "
            "\"either way,\" \"i'll leave you alone til you want me back\"); "
            "don't force a yes/no question close unless the agent's "
            "instruction asks for one. Reference one specific thing they "
            "said when it helps, otherwise don't shoehorn.\n\n"
            "BANNED PHRASES (never use): \"Great meeting you\", \"I really "
            "enjoyed\", \"I'd love to\", \"I hope this finds you well\", "
            "\"Feel free to\", \"I look forward to\", \"Would you be open "
            "to a [N]-minute call\", \"touch base\", \"circle back\", "
            "\"reach out\".\n\n"
            "DO NOT include any sign-off, signature line, or agent name — "
            "the email client appends the agent's signature automatically. "
            "NEVER use bracketed placeholders like [Agent Name], [Address], "
            "[Phone], etc. — they get sent as-is and embarrass the agent. "
            "If you don't know a value, leave it out.\n\n"
            "ANTI-HALLUCINATION: never claim the agent has specific "
            "resources or deliverables that aren't in the context block, "
            "the templates/offers block, or already in the current draft. "
            "Don't invent listings (\"I have other homes in your range\"), "
            "comps, market reports, neighborhood facts, prices, or specific "
            "tours the agent didn't mention. Promise-style asks must stay "
            "open-ended (\"if anything pops up i'll send it\"), never "
            "asserting something specific exists. If the agent's "
            "instruction asks for content that isn't supported by the "
            "context (e.g. \"mention the comps I'll send\" when no comps "
            "are in context), keep it open (\"want me to pull a few "
            "comps?\") rather than asserting it exists.\n\n"
            + voice_block +
            "Return ONLY the rewritten note as plain text — no JSON, no "
            "quotes around the result, no commentary, no 'Here is the rewrite'."
        ),
        messages=[{
            "role": "user",
            "content": (
                f"{context_block}"
                f"{library_block}"
                f"Current draft:\n{body or '(empty — write from scratch)'}\n\n"
                f"Agent's instruction: {ask}\n\n"
                "Rewrite the draft now."
            ),
        }],
    )
    text = (response.content[0].text or "").strip()
    # Trim surrounding code-fences/quotes if the model wraps the body.
    if text.startswith("```"):
        # Strip the opening fence (possibly with a language tag) and the
        # trailing fence.
        first_newline = text.find("\n")
        if first_newline != -1:
            text = text[first_newline + 1:]
        if text.endswith("```"):
            text = text[:-3]
        text = text.strip()
    if (text.startswith('"') and text.endswith('"')) or (
        text.startswith("'") and text.endswith("'")
    ):
        text = text[1:-1].strip()
    return _scrub_placeholders(text)


def generate_session_name(
    transcript: aai.Transcript,
    agent_speaker: str | None = None,
) -> str:
    """Coin a short, human-readable label for a session whose address was
    never set — beats showing the agent "Session a1b2c3d4" in their list.
    Haiku for speed/cost; fail-soft (returns "" so caller falls back to
    the existing display chain)."""
    utterances = transcript.utterances or []
    lines = [
        f"[{u.speaker}{' ← agent' if u.speaker == agent_speaker else ''}] {u.text}"
        for u in utterances
    ]
    # Skip near-empty transcripts — a 5-word recording will produce a
    # weird hallucinated label and the date fallback is fine.
    joined = "\n".join(lines).strip()
    if len(joined) < 80:
        return ""

    try:
        client = Anthropic()
        response = client.messages.create(
            model=FAST_MODEL,
            max_tokens=40,
            system=(
                "You coin a 3-5 word label for an open-house recording so the "
                "agent can recognize it in a list later. Pull out the most "
                "memorable concrete detail: visitor name (\"Tour with Sarah & "
                "Mike\"), buyer type (\"Cash investor walkthrough\"), a "
                "neighborhood or feature they fixated on (\"Kitchen-focused "
                "young couple\"), or their situation (\"Relocating family, two "
                "kids\"). Title Case. No quotes, no trailing punctuation, no "
                "\"Open house\" or \"Session\" prefix. Return ONLY the label."
            ),
            messages=[{"role": "user", "content": joined}],
        )
        text = (response.content[0].text or "").strip()
    except Exception:  # noqa: BLE001
        return ""
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1].strip()
    if text.startswith("'") and text.endswith("'"):
        text = text[1:-1].strip()
    text = text.rstrip(".!? ").strip()
    # Cap length defensively — Haiku ignoring the 3-5 word ask shouldn't
    # blow up the list cell.
    if len(text) > 60:
        text = text[:60].rstrip() + "…"
    return text
