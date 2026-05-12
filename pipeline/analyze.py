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


def analyze_visitor(
    transcript: aai.Transcript,
    visitor: Visitor,
    tags: list[Tag],
    templates: list[dict] | None = None,
    force_templates: bool = False,
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
            "DO NOT include any sign-off, signature line, or agent name — the "
            "email client appends the agent's signature automatically. End the "
            "body with the ask sentence. NEVER use bracketed placeholders like "
            "[Agent Name], [Address], [Phone], etc. — they get sent as-is and "
            "embarrass the agent. If you don't know a value, leave it out."
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
        ),
        messages=[{"role": "user", "content": utterances_text}],
    )
    text = _extract_json(response.content[0].text)
    parsed = json.loads(text)
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
    offers: list[dict] | None = None,
) -> str:
    """Rewrite an existing follow-up draft according to the agent's
    instruction ("too long", "add a CTA about the 1pm Saturday tour", "more
    casual", etc.).

    `offers` is the list of @offerName references the agent dropped into
    the instruction, pre-resolved by the caller to the full offer dicts
    {name, headline, body}. The LLM weaves them into the rewrite as
    concrete material (the "$2,500 buyer credit" text, etc.) instead of
    leaving the @reference verbatim.

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

    # Inject offer bodies so the LLM has the actual marketing copy on
    # hand. Mention by @name in the instructions block too so the model
    # ties the agent's free-text reference to the offer content.
    offer_block = ""
    if offers:
        chunks = []
        for o in offers:
            name = (o.get("name") or "").strip()
            headline = (o.get("headline") or "").strip()
            ob = (o.get("body") or "").strip()
            line = f"@{name}"
            if headline:
                line += f" — {headline}"
            chunks.append(line + "\n" + ob)
        offer_block = (
            "The agent's instruction mentions these offers — weave their "
            "content naturally into the rewrite (don't quote them verbatim "
            "unless the agent explicitly asks for it; don't leave the "
            "@reference in the output):\n\n"
            + "\n\n".join(chunks)
            + "\n\n"
        )

    client = Anthropic()
    response = client.messages.create(
        # Haiku on the fast model so the agent isn't waiting 10s for an
        # email rewrite. Haiku is fully capable here — we're not asking
        # it to grade nuance, just to follow a tight instruction like
        # "make this shorter" or "add a CTA about Saturday's tour".
        model=FAST_MODEL,
        max_tokens=400,
        system=(
            "You rewrite a real-estate follow-up email per the agent's "
            "instruction. Keep it short and mobile-friendly. Default to under "
            "4 sentences unless the agent explicitly asks for longer. End with "
            "a single specific ask the lead can reply to. No subject line, no "
            "greetings beyond a short hi/hello, no 'I hope this finds you well' "
            "boilerplate. DO NOT include any sign-off, signature line, or agent "
            "name — the email client appends the agent's signature automatically. "
            "End the body with the ask sentence. NEVER use bracketed placeholders "
            "like [Agent Name], [Address], [Phone], etc. — they get sent as-is "
            "and embarrass the agent. If you don't know a value, leave it out. "
            "Return ONLY the rewritten email body as plain text — no JSON, no "
            "quotes around the result, no commentary, no 'Here is the rewrite'."
        ),
        messages=[{
            "role": "user",
            "content": (
                f"{context_block}"
                f"{offer_block}"
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
