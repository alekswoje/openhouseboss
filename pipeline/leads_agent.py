"""Conversational agent over an individual agent's leads inbox.

The Leads tab on iPad shows everything an agent has — visitor names, tags,
scores, signals, follow-up drafts, contact info, the address where each
lead came from, lead state (sent / replied / archived). On any non-trivial
account that's too much to scan by hand, so this module exposes a single
entry point — `query_leads_agent` — that takes the agent's natural-language
message and the lead corpus and returns either:

  - an "answer": plain text response to a question
    (e.g. "How many buyer leads do I have right now?")
  - a "plan": a concrete batch action the agent can review and confirm
    (e.g. "Send the $2,500 buyer credit blast to all 12 buyer leads")

The plan is fully materialized — every recipient has a personalized body,
the agent sees ALL recipients up front, and ONE confirmation kicks off all
the sends. No per-lead confirmation loop, no fan-out surprise.

This module is pure (no FastAPI, no DB) so it can be unit-tested with
fixture leads. The server handles authorization and Gmail send.
"""

import json

from anthropic import Anthropic

from .analyze import _build_library_block, _scrub_placeholders
from .identify import _extract_json

MODEL = "claude-sonnet-4-6"


def _summarize_leads_for_llm(leads: list[dict]) -> str:
    """Compact one-line-per-lead serialization for the LLM. We strip
    everything the agent doesn't need to reason about (full transcripts,
    notes, sent-email history) and keep what matters for filter decisions:
    name, contact, tag, score, signals, summary, address.

    The `idx` is stable across this single request so the LLM can refer to
    leads by index in its plan rather than echoing the full record."""
    blocks = []
    for idx, lead in enumerate(leads):
        v = lead.get("visitor") or {}
        a = lead.get("analysis") or {}
        ls = lead.get("lead_state") or {}
        signals = ", ".join(a.get("signals") or [])
        blocks.append(
            f"[{idx}] name={v.get('name') or '?'} | "
            f"tag={a.get('tag') or '?'} | "
            f"score={a.get('score') or 0} | "
            f"email={v.get('email') or '(none)'} | "
            f"phone={v.get('phone') or '(none)'} | "
            f"status={ls.get('status') or 'drafted'} | "
            f"address={lead.get('address') or '(unknown)'} | "
            f"signals=[{signals}] | "
            f"summary={(a.get('summary') or '').strip()[:240]}"
        )
    return "\n".join(blocks)


def query_leads_agent(
    message: str,
    leads: list[dict],
    agent_name: str = "",
    mentioned_offers: list[dict] | None = None,
    mentioned_templates: list[dict] | None = None,
    available_offers: list[dict] | None = None,
    available_templates: list[dict] | None = None,
) -> dict:
    """Run one turn of the leads-agent conversation.

    `leads` items must each have: visitor{name,email,phone,speaker},
    analysis{summary,tag,score,signals,follow_up_draft},
    lead_state{status}, plus `address` (the open-house address) and
    `session_id` so the plan can point back at concrete recipients.

    Returns a dict:
      {"kind": "answer", "text": "..."}
      {"kind": "plan",
       "summary": "...",
       "action": "send_email",
       "subject": "...",
       "recipients": [
         {"session_id", "name", "speaker", "email", "address", "body"},
         ...
       ],
       "skipped": [
         {"name", "reason"}  # e.g. no email on file
       ]}
    """
    if not leads:
        return {
            "kind": "answer",
            "text": "You don't have any leads yet — record a session or "
                    "add one manually and I'll have something to work with.",
        }

    lead_block = _summarize_leads_for_llm(leads)
    agent_clause = f"The agent's name is {agent_name}." if agent_name else ""

    library_block = _build_library_block(
        mentioned_offers=mentioned_offers or [],
        mentioned_templates=mentioned_templates or [],
        available_offers=available_offers or [],
        available_templates=available_templates or [],
    )

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=4000,
        system=(
            "You are an assistant inside a real-estate CRM. The user is a "
            "real-estate agent. You have access to their entire leads inbox "
            "(see Leads below). When they ask a question, answer it from "
            "this data — be concrete (counts, names, addresses). When they "
            "ask you to send messages, propose a CONCRETE PLAN: pick which "
            "leads to send to (using the filter they described — e.g. "
            "'buyer leads', 'hot buyers from the Maple St open house', "
            "'everyone we haven't contacted'), and write a personalized "
            "body for EACH recipient.\n\n"
            "Bodies must be SHORT (3-4 sentences, under 70 words), mobile-"
            "friendly, end with a single ask. Address recipients by first "
            "name. Reference what they said when natural. No greeting "
            "boilerplate, no 'I hope this finds you well'. DO NOT include "
            "any sign-off, signature line, or agent name — the email client "
            "appends the agent's signature automatically. End each body "
            "with the ask sentence. NEVER use bracketed placeholders like "
            "[Agent Name], [Address], [Phone], etc. — they get sent as-is "
            "and embarrass the agent. If you don't know a value, leave it "
            "out.\n\n"
            "Skip leads with no email and report them in `skipped`. Do NOT "
            "invent leads, do NOT include duplicates. Use ONLY the leads "
            "below — refer to them by their visitor name + speaker + "
            "session_id when building recipients.\n\n"
            f"{agent_clause}\n\n"
            "Return JSON only, no prose. Either:\n"
            "{\n"
            '  "kind": "answer",\n'
            '  "text": "..."\n'
            "}\n"
            "or:\n"
            "{\n"
            '  "kind": "plan",\n'
            '  "summary": "1-sentence what-and-to-whom",\n'
            '  "action": "send_email",\n'
            '  "subject": "...",\n'
            '  "recipients": [\n'
            '    {"session_id": "...", "name": "...", "speaker": "...",\n'
            '     "email": "...", "address": "...", "body": "..."}\n'
            "  ],\n"
            '  "skipped": [{"name": "...", "reason": "..."}]\n'
            "}\n\n"
            "Leads (one per line, [idx] is for your bookkeeping only):\n"
            + lead_block
            + ("\n\n" + library_block if library_block else "")
        ),
        messages=[{"role": "user", "content": message}],
    )
    text = _extract_json(response.content[0].text)
    parsed = json.loads(text)
    # Defensive: even with prompt guidance, models occasionally drop a
    # [Bracketed Placeholder] into a per-recipient body. Scrub them so a
    # bulk send doesn't push [Agent Name] into 30 inboxes.
    if parsed.get("kind") == "plan":
        for r in parsed.get("recipients") or []:
            if isinstance(r, dict) and isinstance(r.get("body"), str):
                r["body"] = _scrub_placeholders(r["body"])
    return parsed
