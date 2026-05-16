"""Open House Report — synthesizes a polished, homeowner-facing report
from a finished session.

Input: the full session.json dict (the same shape iOS sees).
Output: a structured SessionReport (JSON) + a rendered HTML string suitable
for emailing the homeowner and exporting to PDF.

The transcript is our moat — most agents send reports built from memory and
a sign-in sheet. We have multi-speaker diarization, per-visitor analysis,
and dwell-time signals from utterance timestamps. The prompt below leans
into that: cross-visitor pattern detection, anonymized verbatim quotes,
and engagement signals.

Hard guardrails baked in:
  - No demographic descriptors (Fair Housing Act risk — these reports are
    discoverable in writing).
  - All quotes anonymized; never name a visitor in the report body.
  - Themes flagged only when ≥2 visitors raised them.
  - Defensive against single-data-point overreaction.
"""
import html
import json
import re
from typing import Any

from anthropic import Anthropic
from pydantic import BaseModel, Field

from .identify import _extract_json

MODEL = "claude-sonnet-4-6"


# --- Schema --------------------------------------------------------------


class ReportThemeQuote(BaseModel):
    quote: str
    # Anonymized speaker descriptor ("One visitor", "A couple touring
    # together", "An unrepresented buyer"). NEVER a real name or
    # demographic descriptor. Validated downstream.
    attribution: str = ""


class ReportTheme(BaseModel):
    title: str                             # short, e.g. "Kitchen layout"
    frequency: int                         # how many distinct visitors raised it
    summary: str                           # one sentence
    quotes: list[ReportThemeQuote] = Field(default_factory=list)


class ReportStandoutVisitor(BaseModel):
    # Anonymized label only — "Group A", "Couple #2", "Unrepresented buyer".
    # Never a real name. The agent privately knows who it is via the visitor
    # detail view in-app; the homeowner doesn't need to.
    label: str
    score: int                             # 0-100 from per-visitor analysis
    summary: str                           # what they asked / lingered on
    follow_up_status: str                  # "Following up Monday", "Tour booked", "Not pursuing"


class SessionReport(BaseModel):
    # Top-level fields
    headline: str                          # the TL;DR — one line
    tldr: list[str]                        # 2-4 bullet points

    # Body sections
    traffic_summary: str                   # 1-2 sentences interpreting turnout
    highlights: list[ReportTheme]          # what visitors liked, with quotes
    concerns: list[ReportTheme]            # what visitors objected to, with quotes
    price_signal: str                      # what was said + inferred signal
    standout_visitors: list[ReportStandoutVisitor]
    agent_take: str                        # 1 short paragraph, human interpretation
    next_steps: list[str]                  # 2-4 concrete actions

    # Metadata (filled by the endpoint, not Claude)
    address: str = ""
    date_label: str = ""                   # "Saturday, March 5, 2026, 12-3pm"
    duration_minutes: int = 0
    visitor_count: int = 0
    group_count_estimate: int = 0
    agent_name: str = ""
    generated_at: str = ""                 # ISO timestamp


# --- Prompt construction -------------------------------------------------


def _build_visitor_blocks(session: dict) -> str:
    """Format per-visitor analysis the prompt can reason over without
    needing to re-read the raw transcript. Each block is one visitor's
    summary, score, tag, and signal phrases — distilled signal the
    homeowner cares about."""
    result = session.get("result") or {}
    visitors = result.get("visitors") or []
    if not visitors:
        return "(no visitors detected in this session)"

    blocks: list[str] = []
    for i, entry in enumerate(visitors, 1):
        v = entry.get("visitor") or {}
        a = entry.get("analysis") or {}
        speaker = v.get("speaker") or "?"
        # We anonymize on the prompt side too — Claude is told "Visitor A",
        # not the real name. Reduces chance of name leaking into the report.
        label = f"Visitor #{i} (speaker {speaker})"
        tag = a.get("tag") or "Browser"
        score = a.get("score") or 0
        words = a.get("words_spoken") or 0
        summary = (a.get("summary") or "").strip()
        signals = a.get("signals") or []
        signals_line = " · ".join(signals) if signals else "(none)"
        blocks.append(
            f"--- {label}\n"
            f"Tag: {tag} (score {score}/100, spoke {words} words)\n"
            f"Summary: {summary or '(no summary)'}\n"
            f"Signals: {signals_line}"
        )
    return "\n\n".join(blocks)


def _build_transcript_excerpt(session: dict, max_chars: int = 60_000) -> str:
    """Diarized transcript with speaker labels, truncated to keep prompt
    cost bounded. Most open houses are well under 60k chars; longer ones
    get the front 60k (covers the opening + most of the substantive
    feedback) plus a "[truncated]" marker."""
    result = session.get("result") or {}
    utterances = result.get("utterances") or []
    if utterances:
        lines = []
        running = 0
        for u in utterances:
            line = f"[Speaker {u.get('speaker')}] {u.get('text', '')}"
            if running + len(line) > max_chars:
                lines.append("\n[... transcript truncated for length ...]")
                break
            lines.append(line)
            running += len(line) + 1
        return "\n".join(lines)
    full = (result.get("full_transcript") or "")
    if len(full) > max_chars:
        return full[:max_chars] + "\n[... transcript truncated for length ...]"
    return full


def _duration_minutes(session: dict) -> int:
    """Best-effort duration from the last utterance's end timestamp.
    Falls back to 0 if utterances are missing."""
    result = session.get("result") or {}
    utterances = result.get("utterances") or []
    if not utterances:
        return 0
    end_ms = max((u.get("end_ms") or u.get("start_ms") or 0) for u in utterances)
    return int(end_ms / 60_000)


def _estimate_groups(session: dict) -> int:
    """Heuristic: number of distinct visitor "groups" ≈ ceil(visitors/2) since
    open house visitors typically arrive in pairs (couples). Without arrival-
    time clustering this is the best we can do; the agent can edit if wrong."""
    result = session.get("result") or {}
    visitor_count = len(result.get("visitors") or [])
    if visitor_count == 0:
        return 0
    return max(1, (visitor_count + 1) // 2)


SYSTEM_PROMPT = """You are writing an Open House Report for the homeowner (the seller). \
The real estate agent will review and send this to their client. The report's \
job is to make the homeowner feel informed and managed — not to oversell or \
sugarcoat. Sellers see through "everyone loved it!" reports; they want \
honest, specific, actionable feedback.

LEGAL + FAIR HOUSING GUARDRAILS (these are non-negotiable — written reports \
are discoverable):
- NEVER include demographic descriptors. Forbidden: "young family", "older \
couple", "seemed foreign", "elderly woman", "a hispanic couple", anything \
implying race, national origin, religion, sex, familial status, age, or \
disability. If the transcript contains such descriptors, refuse to use them.
- NEVER name a visitor. Use anonymized labels: "One visitor", "A couple \
touring together", "An unrepresented buyer", "Group A". Even if the \
visitor's name is in the transcript or analysis data, do not put it in the \
report body.
- NEVER use steering language like "good fit for the neighborhood".

CONTENT GUARDRAILS:
- A theme requires ≥2 visitors raising it independently. Single-visitor \
comments stay in standout_visitors, not in highlights or concerns.
- Use direct verbatim quotes where they exist in the transcript — they \
carry weight a paraphrase doesn't. Always anonymized.
- Don't oversell. If turnout was light, say so. If concerns outnumber \
highlights, lead with that.
- The agent_take is YOUR ONE paragraph of interpretation — the rest of \
the report is data + quotes. Use the take to surface the meta-pattern \
(strong interest but price hesitation, broad interest but no urgency, \
etc.) and to frame the next_steps.
- next_steps should be 2-4 concrete actions, not "keep marketing".

TONE:
- Honest, professional, warm but not chatty.
- Bullets for traffic patterns and themes; short prose for the take.
- One page when rendered. Be ruthless about length — cut anything that \
doesn't help the homeowner make a decision.

OUTPUT FORMAT — return ONLY this JSON object, no prose, no markdown:
{
  "headline": "one-sentence headline (e.g. '9 visitors, 2 with strong \
interest; recurring concern about kitchen condition.')",
  "tldr": ["bullet 1", "bullet 2", "bullet 3"],
  "traffic_summary": "1-2 sentence interpretation of turnout quality",
  "highlights": [
    {
      "title": "Short theme name",
      "frequency": 3,
      "summary": "One sentence",
      "quotes": [{"quote": "verbatim", "attribution": "One visitor"}]
    }
  ],
  "concerns": [ ...same shape as highlights... ],
  "price_signal": "What was said about price, plus inferred signal from \
engagement (dwell time, follow-up questions, second-showing asks). If \
nothing was said, state that explicitly.",
  "standout_visitors": [
    {
      "label": "Group A",
      "score": 78,
      "summary": "What they asked, what they lingered on",
      "follow_up_status": "Following up Monday with disclosures"
    }
  ],
  "agent_take": "One short paragraph (3-4 sentences) of human \
interpretation.",
  "next_steps": ["concrete action 1", "concrete action 2"]
}

If a section has nothing to report (e.g. no concerns came up), return an \
empty list rather than padding it. Empty is more honest than padded."""


def generate_report(session: dict) -> SessionReport:
    """Call Claude to produce a structured open house report from the
    session data. Caller passes the session.json dict; we return a
    validated SessionReport. Metadata fields (address, date_label, etc.)
    are stamped by the caller, not Claude, so the model can't drift on
    facts.

    Raises ValueError if Claude returns nothing parseable after retry."""
    visitor_blocks = _build_visitor_blocks(session)
    transcript = _build_transcript_excerpt(session)
    address = session.get("address") or "the property"

    user_content = (
        f"PROPERTY: {address}\n\n"
        f"PER-VISITOR ANALYSIS (already distilled — use as your primary "
        f"source for themes and standouts):\n\n{visitor_blocks}\n\n"
        f"DIARIZED TRANSCRIPT (use for verbatim quotes; speakers are "
        f"labelled by ID, never by name):\n\n{transcript}\n\n"
        f"Write the report now. Return JSON only."
    )

    client = Anthropic()

    def _call(extra_hint: str = "") -> str:
        content = user_content + (f"\n\n{extra_hint}" if extra_hint else "")
        response = client.messages.create(
            model=MODEL,
            max_tokens=4000,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": content}],
        )
        return response.content[0].text

    parsed: dict | None = None
    for attempt in range(2):
        raw = _call(
            "" if attempt == 0 else
            "Your previous response was not valid JSON. Return a single "
            "JSON object only, no markdown fences, no commentary."
        )
        try:
            parsed = json.loads(_extract_json(raw))
            if isinstance(parsed, dict):
                break
        except (json.JSONDecodeError, ValueError):
            continue

    if not isinstance(parsed, dict):
        raise ValueError(
            "Claude did not return a parseable JSON report after 2 attempts. "
            "Retry, or check the model's API status."
        )

    parsed = _scrub_pii_and_demographics(parsed)
    return SessionReport(**parsed)


# --- Defensive scrubbing -------------------------------------------------


# Heuristic demographic-descriptor patterns. The prompt forbids these, but
# LLMs occasionally slip — strip them before they reach the homeowner.
# Each pattern matches a short phrase, not a sentence — we don't want to
# silently drop entire paragraphs, just the offending modifier.
_DEMOGRAPHIC_PATTERNS = [
    r"\b(young|elderly|old|middle[- ]aged|retired|college[- ]aged?)\s+"
    r"(couple|family|man|woman|buyer|visitor|guest|gentleman|lady)s?\b",
    r"\b(hispanic|latino|latina|asian|black|african|white|caucasian|"
    r"indian|chinese|korean|japanese|mexican|european|middle[- ]eastern)\s+"
    r"(couple|family|man|woman|buyer|visitor|guest|gentleman|lady)s?\b",
    r"\b(christian|jewish|muslim|catholic|hindu|buddhist)\s+"
    r"(couple|family|man|woman|buyer|visitor|guest)s?\b",
    r"\b(pregnant|disabled|handicapped)\s+"
    r"(woman|man|buyer|visitor|guest)s?\b",
    # Demographic standalone descriptors of visitors
    r"\b(seemed|appeared|looked)\s+(foreign|elderly|young|wealthy|poor)\b",
]
_DEMOGRAPHIC_RE = re.compile("|".join(_DEMOGRAPHIC_PATTERNS), re.IGNORECASE)


def _scrub_string(s: Any) -> Any:
    if not isinstance(s, str):
        return s
    # Replace demographic phrases with a neutral "visitor" / "group" stub
    # so the sentence still reads. "A young couple mentioned X" becomes
    # "A couple mentioned X" — the protected attribute is gone but the
    # subject survives. Imperfect but better than silent deletion.
    def _replace(m: re.Match[str]) -> str:
        text = m.group(0)
        # Pull the last token (the noun) and prepend a neutral article.
        tokens = text.split()
        noun = tokens[-1]
        return f"a {noun}" if noun[0].lower() not in "aeiou" else f"an {noun}"
    return _DEMOGRAPHIC_RE.sub(_replace, s)


def _scrub_pii_and_demographics(report: dict) -> dict:
    """Walk the structured report and scrub any demographic descriptors
    that slipped past the prompt. This is defense-in-depth — the prompt
    is the primary safeguard."""
    def _walk(node: Any) -> Any:
        if isinstance(node, dict):
            return {k: _walk(v) for k, v in node.items()}
        if isinstance(node, list):
            return [_walk(item) for item in node]
        return _scrub_string(node)
    return _walk(report)


# --- HTML rendering ------------------------------------------------------


def render_report_html(
    report: SessionReport,
    *,
    agent_signature_html: str = "",
) -> str:
    """Render the structured report as a self-contained HTML document.
    Used for both the email body (HTML inline) and PDF generation
    (iOS renders this via WKWebView → PDF). All styling is inlined so
    Gmail / Apple Mail render it faithfully.

    `agent_signature_html` is appended at the bottom of the body if
    provided — typically the agent's name, brokerage, license, phone."""

    def _h(s: str) -> str:
        return html.escape(s or "")

    def _section_title(title: str) -> str:
        return (
            f'<h2 style="margin:28px 0 8px 0;font-family:Georgia,serif;'
            f'font-size:17px;font-weight:600;color:#1a1a1a;'
            f'letter-spacing:-0.2px;">{_h(title)}</h2>'
        )

    def _render_theme(theme: ReportTheme) -> str:
        freq = (
            f' <span style="color:#888;font-size:12px;font-weight:400;">'
            f'· {theme.frequency} visitors</span>'
            if theme.frequency >= 2 else ""
        )
        quotes_html = ""
        for q in theme.quotes:
            attribution = (
                f' <span style="color:#888;font-size:12px;">— {_h(q.attribution)}</span>'
                if q.attribution else ""
            )
            quotes_html += (
                f'<div style="margin:6px 0 6px 12px;padding:8px 12px;'
                f'border-left:2px solid #c9a55b;background:#faf7f0;'
                f'font-style:italic;color:#333;font-size:13px;">'
                f'"{_h(q.quote)}"{attribution}</div>'
            )
        return (
            f'<div style="margin:10px 0;">'
            f'<div style="font-size:14px;font-weight:600;color:#1a1a1a;">'
            f'{_h(theme.title)}{freq}</div>'
            f'<div style="font-size:13px;color:#444;margin-top:3px;">'
            f'{_h(theme.summary)}</div>'
            f'{quotes_html}'
            f'</div>'
        )

    def _render_themes(themes: list[ReportTheme]) -> str:
        if not themes:
            return (
                '<div style="font-size:13px;color:#888;font-style:italic;">'
                'Nothing notable.</div>'
            )
        return "".join(_render_theme(t) for t in themes)

    def _render_standout(v: ReportStandoutVisitor) -> str:
        score_color = "#5d8a4e" if v.score >= 70 else ("#c9a55b" if v.score >= 40 else "#888")
        return (
            f'<div style="margin:10px 0;padding:12px;background:#f8f8f5;'
            f'border-radius:6px;">'
            f'<div style="display:flex;justify-content:space-between;'
            f'align-items:baseline;">'
            f'<span style="font-weight:600;font-size:14px;color:#1a1a1a;">'
            f'{_h(v.label)}</span>'
            f'<span style="font-size:12px;color:{score_color};'
            f'font-weight:600;">{v.score}/100</span>'
            f'</div>'
            f'<div style="font-size:13px;color:#444;margin-top:6px;">'
            f'{_h(v.summary)}</div>'
            f'<div style="font-size:12px;color:#666;margin-top:6px;'
            f'font-style:italic;">{_h(v.follow_up_status)}</div>'
            f'</div>'
        )

    meta_bits: list[str] = []
    if report.date_label:
        meta_bits.append(_h(report.date_label))
    if report.duration_minutes > 0:
        meta_bits.append(f"{report.duration_minutes} min")
    if report.visitor_count > 0:
        meta_bits.append(
            f"{report.visitor_count} visitor"
            f"{'s' if report.visitor_count != 1 else ''}"
        )
        if report.group_count_estimate > 0:
            meta_bits.append(f"~{report.group_count_estimate} groups")
    meta_line = " · ".join(meta_bits)

    tldr_html = "".join(
        f'<li style="margin:4px 0;">{_h(b)}</li>' for b in report.tldr
    )
    next_steps_html = "".join(
        f'<li style="margin:4px 0;">{_h(s)}</li>' for s in report.next_steps
    )

    signature_block = (
        f'<div style="margin-top:36px;padding-top:18px;'
        f'border-top:1px solid #e5e1d8;font-size:12px;color:#666;">'
        f'{agent_signature_html}</div>'
        if agent_signature_html else ""
    )

    return f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Open House Report — {_h(report.address)}</title>
</head>
<body style="margin:0;padding:0;background:#fefdf9;font-family:-apple-system,BlinkMacSystemFont,'Helvetica Neue',Arial,sans-serif;color:#1a1a1a;">
<div style="max-width:640px;margin:0 auto;padding:32px 28px;background:#fff;">

<div style="padding-bottom:18px;border-bottom:1px solid #e5e1d8;">
  <div style="font-family:Georgia,serif;font-size:11px;letter-spacing:2px;color:#c9a55b;font-weight:600;text-transform:uppercase;">Open House Report</div>
  <div style="font-family:Georgia,serif;font-size:24px;font-weight:600;color:#1a1a1a;margin-top:6px;letter-spacing:-0.5px;">{_h(report.address) or 'Your property'}</div>
  <div style="font-size:12px;color:#888;margin-top:4px;">{_h(meta_line)}</div>
</div>

<div style="margin:20px 0;padding:14px 18px;background:#faf7f0;border-left:3px solid #c9a55b;">
  <div style="font-size:15px;font-weight:600;color:#1a1a1a;line-height:1.4;">{_h(report.headline)}</div>
  <ul style="margin:10px 0 0 0;padding-left:18px;font-size:13px;color:#333;">
    {tldr_html}
  </ul>
</div>

{_section_title("Traffic")}
<div style="font-size:13px;color:#444;line-height:1.5;">{_h(report.traffic_summary)}</div>

{_section_title("What stood out — positive")}
{_render_themes(report.highlights)}

{_section_title("Concerns + objections")}
{_render_themes(report.concerns)}

{_section_title("Price signal")}
<div style="font-size:13px;color:#444;line-height:1.5;">{_h(report.price_signal)}</div>

{_section_title("Standout visitors")}
{"".join(_render_standout(v) for v in report.standout_visitors) if report.standout_visitors else '<div style="font-size:13px;color:#888;font-style:italic;">No standouts this session.</div>'}

{_section_title("My take")}
<div style="font-size:13px;color:#444;line-height:1.6;">{_h(report.agent_take)}</div>

{_section_title("Recommended next steps")}
<ul style="margin:6px 0;padding-left:20px;font-size:13px;color:#333;">
  {next_steps_html}
</ul>

{signature_block}

</div>
</body>
</html>"""
