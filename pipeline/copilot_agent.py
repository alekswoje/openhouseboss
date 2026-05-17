"""Open House Copilot — global in-app agent.

This is the user-facing "Ask anything" agent surfaced on the iOS home
screen. Unlike `leads_agent.py` (which is narrowly focused on the leads
inbox and produces a confirmable bulk-send plan), this agent answers
open-ended questions across the agent's full workspace — sessions,
visitors, follow-ups, stats — and can return a navigation action so the
iOS client can jump straight to the relevant screen.

Architecture: Anthropic tool use loop. Each user turn runs to completion
on the server — Claude calls tools (which read from in-memory sessions
+ stats) until it has enough context to produce a final reply. The reply
is either plain text or text + a single navigation `action` the client
executes when the user taps the result.

State model: stateless per turn. The client sends the full chat history
as a list of `{role, text}` pairs; we replay it as user/assistant turns
(tool transcripts elided — Claude re-derives them by re-calling tools as
needed). Simpler than persisting tool-use threads server-side and good
enough for chat-style continuity.
"""

from __future__ import annotations

import json
from typing import Any, Callable, Iterable

from anthropic import Anthropic

MODEL = "claude-sonnet-4-6"

# Hard cap on the tool-use loop so a misbehaving model can't infinite-loop
# the user's turn. 8 is generous — most questions resolve in 1-3 tool calls.
MAX_TOOL_ITERATIONS = 8


# --------------------------------------------------------------------------
# Tool schemas — what Claude sees
# --------------------------------------------------------------------------

TOOLS: list[dict] = [
    {
        "name": "list_open_houses",
        "description": (
            "List the user's recent open-house sessions (most recent first). "
            "Use this to answer 'show me my last open house', 'how many "
            "did I do this month', or to find a session id before calling "
            "get_open_house. Returns session_id, address, date, duration, "
            "visitor count, and hot-lead count for each."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "limit": {
                    "type": "integer",
                    "description": "Max sessions to return (default 12, max 50).",
                },
            },
        },
    },
    {
        "name": "get_open_house",
        "description": (
            "Get full detail for one open-house session: address, date, "
            "visitor breakdown (with names, tags, scores, summaries, "
            "follow-up draft status), top signals, weather, script "
            "coverage. Use after list_open_houses to drill into one, or "
            "when the user names a session by address."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
            },
            "required": ["session_id"],
        },
    },
    {
        "name": "find_session_by_address",
        "description": (
            "Fuzzy-match an open-house session by an address fragment the "
            "user mentioned (e.g. 'the Maple St one', '123 Oak'). Returns "
            "up to 5 matches with session_id, address, date. Use this "
            "before get_open_house when the user references an address "
            "instead of a session id."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string"},
            },
            "required": ["query"],
        },
    },
    {
        "name": "list_leads",
        "description": (
            "List the user's leads (visitors) across all sessions. Filterable "
            "by tag (Buyer/Seller/Browser), minimum interest score, follow-up "
            "status (drafted/sent/replied/archived), and limit. Returns "
            "per-lead: session_id, visitor name + speaker, email/phone, tag, "
            "score, status, address, and a short summary."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "tag": {
                    "type": "string",
                    "enum": ["Buyer", "Seller", "Browser"],
                },
                "min_score": {"type": "integer", "description": "0-100"},
                "status": {
                    "type": "string",
                    "enum": ["drafted", "sent", "replied", "archived"],
                },
                "limit": {"type": "integer", "description": "Default 30, max 100."},
            },
        },
    },
    {
        "name": "get_lead",
        "description": (
            "Get full detail for one lead: contact info, tag/score/signals, "
            "the current AI follow-up draft, notes, tasks, sent-email history. "
            "Identified by (session_id, visitor name, speaker)."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "session_id": {"type": "string"},
                "name": {"type": "string"},
                "speaker": {"type": "string", "description": "Optional diarization label."},
            },
            "required": ["session_id", "name"],
        },
    },
    {
        "name": "get_insights",
        "description": (
            "Get the cross-session analytics dashboard: session counts, "
            "visitor totals, hot-lead counts, average scores, report send "
            "rate, best day-of-week / hour-of-day, and the 20 most recent "
            "sessions. Use for 'how did I do this month', 'when's my best "
            "time to host', 'how many hot buyers do I have'."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "period": {
                    "type": "string",
                    "enum": ["week", "month", "year", "all"],
                },
            },
        },
    },
    {
        "name": "open_screen",
        "description": (
            "Hand the user off to a specific screen inside the iOS app. "
            "Call this AT THE END of your response when the user clearly "
            "wants to navigate somewhere ('show me X', 'open Y', 'take "
            "me to Z', 'draft a follow-up'). Don't call it for pure "
            "information questions. Pick exactly one target per response."
            "\n\nTargets:\n"
            "- session: show one open-house session's detail (requires session_id)\n"
            "- lead: show one lead's detail (requires session_id, name, optional speaker)\n"
            "- followup: jump straight into composing/editing a lead's follow-up email (requires session_id, name, optional speaker)\n"
            "- leads: open the Leads inbox (optional session_id to pre-filter)\n"
            "- insights: open the Insights dashboard\n"
            "- record: open the Record screen to start a new open house\n"
            "- kiosk: open the kiosk sign-in surface"
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "target": {
                    "type": "string",
                    "enum": [
                        "session", "lead", "followup",
                        "leads", "insights", "record", "kiosk",
                    ],
                },
                "session_id": {"type": "string"},
                "name": {"type": "string"},
                "speaker": {"type": "string"},
            },
            "required": ["target"],
        },
    },
]


SYSTEM_PROMPT = """You are the Copilot inside an iOS app for real estate \
agents who host open houses. The user is a real estate agent. You have \
tools to read their sessions, leads, follow-ups, and stats.

Style:
- Concrete and brief. Names, numbers, addresses — not platitudes.
- Plain text only. NO markdown headers, NO bold, NO bullet lists unless the \
  user explicitly asks. Short paragraphs, dashes for lightweight lists.
- Default to 2-4 sentences. Use longer only when the user asked for a \
  detailed breakdown.
- Speak in first person as the agent's assistant ("I checked your last \
  three sessions — ...").
- Never invent leads, addresses, or numbers. If a tool returns nothing \
  matching, say so and suggest what to try.

When the user wants to GO somewhere ("show me", "open", "take me to", \
"pull up", "draft a follow-up to X"), call open_screen as the last tool \
before producing your final reply. Your reply should be one short \
sentence introducing what they're about to see (e.g. "Opening the \
Maple St session — 14 visitors, 3 hot."). The client navigates on tap.

When the user is ASKING a question ("how many...", "who are my..."), \
answer it directly without calling open_screen.

Today is a real workday for this agent. Be useful, not chatty."""


# --------------------------------------------------------------------------
# Tool dispatch — pure functions over a `state` dict the caller supplies
# --------------------------------------------------------------------------
#
# We don't import the FastAPI session cache here — instead the server
# passes in a `tool_context` dict with the bits we need (user_id, a
# callable to list sessions, etc.). Keeps this module pure and unit-
# testable with a stub context.


def _summarize_session(session: dict) -> dict:
    """Compact projection of a session for list views. Drops transcript +
    audio paths; keeps the fields the agent reasons about."""
    result = session.get("result") or {}
    visitors = result.get("visitors") or []
    hot = sum(
        1 for v in visitors
        if int(((v.get("analysis") or {}).get("score") or 0)) >= 70
    )
    return {
        "session_id": session.get("id"),
        "address": session.get("address") or "(no address)",
        "name": session.get("name"),
        "created_at": session.get("created_at"),
        "completed_at": session.get("completed_at"),
        "status": session.get("status"),
        "visitor_count": len(visitors),
        "hot_visitor_count": hot,
        "duration_min": _duration_minutes(result),
        "report_sent": bool((session.get("report_meta") or {}).get("sent_at")),
    }


def _duration_minutes(result: dict) -> int:
    utterances = result.get("utterances") or []
    if not utterances:
        return 0
    end = max(
        int(u.get("end_ms") or u.get("start_ms") or 0)
        for u in utterances
    )
    return end // 60_000


def _session_detail(session: dict) -> dict:
    """Full-fat detail for one session. Trims transcript to a summary so the
    LLM context doesn't explode on a 90-minute open house."""
    result = session.get("result") or {}
    visitors = result.get("visitors") or []
    visitor_rows = []
    for entry in visitors:
        v = entry.get("visitor") or {}
        a = entry.get("analysis") or {}
        ls = entry.get("lead_state") or {}
        visitor_rows.append({
            "name": v.get("name") or "",
            "speaker": v.get("speaker") or "",
            "email": v.get("email") or None,
            "phone": v.get("phone") or None,
            "tag": a.get("tag") or None,
            "score": a.get("score") or 0,
            "signals": (a.get("signals") or [])[:5],
            "summary": (a.get("summary") or "")[:400],
            "follow_up_status": ls.get("status") or "drafted",
            "has_draft": bool(a.get("follow_up_draft") or ls.get("draft_override")),
        })
    weather = session.get("weather") or {}
    coverage = result.get("script_coverage") or {}
    return {
        "session_id": session.get("id"),
        "address": session.get("address"),
        "name": session.get("name"),
        "created_at": session.get("created_at"),
        "completed_at": session.get("completed_at"),
        "duration_min": _duration_minutes(result),
        "visitors": visitor_rows,
        "weather": {
            "temp_f": weather.get("temp_f"),
            "condition": weather.get("condition_label"),
        } if weather else None,
        "script_coverage_score": coverage.get("score") if coverage else None,
        "report_sent": bool((session.get("report_meta") or {}).get("sent_at")),
    }


def _lead_row(session: dict, entry: dict) -> dict:
    v = entry.get("visitor") or {}
    a = entry.get("analysis") or {}
    ls = entry.get("lead_state") or {}
    return {
        "session_id": session.get("id"),
        "address": session.get("address") or "",
        "name": v.get("name") or "",
        "speaker": v.get("speaker") or "",
        "email": v.get("email") or None,
        "phone": v.get("phone") or None,
        "tag": a.get("tag") or None,
        "score": int(a.get("score") or 0),
        "status": ls.get("status") or "drafted",
        "summary": (a.get("summary") or "")[:240],
    }


def _lead_detail(session: dict, entry: dict) -> dict:
    base = _lead_row(session, entry)
    a = entry.get("analysis") or {}
    ls = entry.get("lead_state") or {}
    base["signals"] = a.get("signals") or []
    base["follow_up_draft"] = (
        ls.get("draft_override")
        or a.get("follow_up_draft")
        or ""
    )[:1200]
    base["notes"] = [
        {"text": n.get("text", ""), "at": n.get("created_at")}
        for n in (ls.get("notes") or [])
    ][:10]
    base["tasks"] = [
        {"text": t.get("text", ""), "done": bool(t.get("done"))}
        for t in (ls.get("tasks") or [])
    ][:10]
    base["sent_emails"] = [
        {"subject": e.get("subject", ""), "to": e.get("to"), "at": e.get("sent_at")}
        for e in (ls.get("sent_emails") or [])
    ][-5:]
    return base


def _dispatch_tool(
    name: str,
    args: dict,
    *,
    list_user_sessions: Callable[[], list[dict]],
    get_user_insights: Callable[[str], dict],
) -> Any:
    """Execute one tool call. Returns a JSON-serializable result the LLM
    sees as the tool's output. Errors are returned as `{"error": "..."}`
    rather than raised so the model can recover (e.g. retry with a
    different session id)."""
    sessions = list_user_sessions()
    # Stable sort newest-first so list-style tools always return recent items.
    sessions.sort(
        key=lambda s: s.get("created_at") or "",
        reverse=True,
    )

    if name == "list_open_houses":
        limit = max(1, min(int(args.get("limit") or 12), 50))
        recorded = [s for s in sessions if s.get("kind", "recorded") != "manual"]
        return {"sessions": [_summarize_session(s) for s in recorded[:limit]]}

    if name == "get_open_house":
        sid = args.get("session_id") or ""
        match = next((s for s in sessions if s.get("id") == sid), None)
        if not match:
            return {"error": f"No session with id={sid!r}."}
        return _session_detail(match)

    if name == "find_session_by_address":
        q = (args.get("query") or "").strip().lower()
        if not q:
            return {"error": "query is required."}
        hits = []
        for s in sessions:
            haystack = " ".join([
                (s.get("address") or "").lower(),
                (s.get("name") or "").lower(),
            ]).strip()
            if q in haystack:
                hits.append(_summarize_session(s))
            if len(hits) >= 5:
                break
        return {"matches": hits}

    if name == "list_leads":
        tag = args.get("tag")
        min_score = int(args.get("min_score") or 0)
        status = args.get("status")
        limit = max(1, min(int(args.get("limit") or 30), 100))
        rows: list[dict] = []
        for s in sessions:
            for entry in ((s.get("result") or {}).get("visitors") or []):
                row = _lead_row(s, entry)
                if tag and (row["tag"] or "").lower() != tag.lower():
                    continue
                if min_score and row["score"] < min_score:
                    continue
                if status and row["status"] != status:
                    continue
                rows.append(row)
        rows.sort(key=lambda r: r["score"], reverse=True)
        return {"leads": rows[:limit], "total_matched": len(rows)}

    if name == "get_lead":
        sid = args.get("session_id") or ""
        target_name = (args.get("name") or "").strip()
        target_speaker = (args.get("speaker") or "").strip()
        match = next((s for s in sessions if s.get("id") == sid), None)
        if not match:
            return {"error": f"No session with id={sid!r}."}
        for entry in ((match.get("result") or {}).get("visitors") or []):
            v = entry.get("visitor") or {}
            if (v.get("name") or "") != target_name:
                continue
            if target_speaker and (v.get("speaker") or "") != target_speaker:
                continue
            return _lead_detail(match, entry)
        return {"error": f"No lead named {target_name!r} in that session."}

    if name == "get_insights":
        period = args.get("period") or "month"
        if period not in {"week", "month", "year", "all"}:
            period = "month"
        try:
            return get_user_insights(period)
        except Exception as exc:  # noqa: BLE001
            return {"error": f"Insights unavailable: {exc}"}

    if name == "open_screen":
        # The model just declares intent — the client navigates. Echo the
        # args back so the loop can attach them to the final reply.
        target = args.get("target") or ""
        if target not in {
            "session", "lead", "followup",
            "leads", "insights", "record", "kiosk",
        }:
            return {"error": f"Unknown target: {target!r}."}
        return {"ok": True, "target": target}

    return {"error": f"Unknown tool: {name!r}."}


# --------------------------------------------------------------------------
# Public entry point
# --------------------------------------------------------------------------


def run_copilot_turn(
    *,
    turns: list[dict],
    agent_name: str,
    list_user_sessions: Callable[[], list[dict]],
    get_user_insights: Callable[[str], dict],
) -> dict:
    """Run one conversation turn through the tool-use loop.

    `turns` is the full chat history as `[{role: "user"|"assistant", text}, ...]`.
    The last turn must be from the user. We replay these as Anthropic
    `messages` (text-only — tool-use scratchwork from prior turns is
    elided, since the model will re-issue any tool calls it needs).

    Returns:
      {
        "text": "...",
        "action": {"target": "...", "session_id": "...", ...} | None,
        "tool_calls": [{"name": "...", "summary": "..."}, ...],
      }
    """
    if not turns or turns[-1].get("role") != "user":
        return {"text": "I didn't catch that. Ask me anything about your sessions, leads, or stats.", "action": None, "tool_calls": []}

    messages: list[dict] = []
    for t in turns:
        role = t.get("role")
        text = (t.get("text") or "").strip()
        if role not in {"user", "assistant"} or not text:
            continue
        messages.append({"role": role, "content": text})

    client = Anthropic()

    system = SYSTEM_PROMPT
    if agent_name:
        system += f"\n\nThe agent's name is {agent_name}."

    tool_calls_log: list[dict] = []
    pending_action: dict | None = None

    for _iter in range(MAX_TOOL_ITERATIONS):
        response = client.messages.create(
            model=MODEL,
            max_tokens=1500,
            system=system,
            tools=TOOLS,
            messages=messages,
        )

        # Append the assistant turn verbatim so the next iteration's
        # tool_result blocks line up with their tool_use ids.
        messages.append({"role": "assistant", "content": response.content})

        if response.stop_reason != "tool_use":
            # Final text turn. Concat any text blocks and return.
            text_parts = [
                block.text for block in response.content
                if getattr(block, "type", None) == "text"
            ]
            final_text = "\n".join(p.strip() for p in text_parts if p).strip()
            if not final_text:
                final_text = "Done."
            return {
                "text": final_text,
                "action": pending_action,
                "tool_calls": tool_calls_log,
            }

        # Execute every tool_use block in this turn and feed results back.
        tool_results: list[dict] = []
        for block in response.content:
            if getattr(block, "type", None) != "tool_use":
                continue
            tool_name = block.name
            tool_input = dict(block.input or {})
            try:
                result = _dispatch_tool(
                    tool_name,
                    tool_input,
                    list_user_sessions=list_user_sessions,
                    get_user_insights=get_user_insights,
                )
            except Exception as exc:  # noqa: BLE001
                result = {"error": f"Tool {tool_name} crashed: {exc}"}

            tool_calls_log.append({
                "name": tool_name,
                "summary": _summarize_tool_call(tool_name, tool_input, result),
            })

            if tool_name == "open_screen" and isinstance(result, dict) and result.get("ok"):
                # Stash the navigation intent; client uses it after the
                # final text turn. Last open_screen wins if model calls
                # it more than once.
                pending_action = {
                    k: v for k, v in tool_input.items() if v is not None
                }

            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": json.dumps(result, default=str),
            })

        messages.append({"role": "user", "content": tool_results})

    # Loop budget exhausted — bail with whatever we have.
    return {
        "text": "I got partway there but ran out of steps. Try a more specific question?",
        "action": pending_action,
        "tool_calls": tool_calls_log,
    }


def _summarize_tool_call(name: str, args: dict, result: Any) -> str:
    """One-line label the iOS client can render as a chip under the
    assistant reply ('Checked 12 sessions', 'Looked up Maple St'). Pure
    cosmetic — keep it tight."""
    if isinstance(result, dict) and "error" in result:
        return f"{name}: {result['error'][:80]}"
    if name == "list_open_houses":
        n = len((result or {}).get("sessions") or [])
        return f"Reviewed {n} recent session{'s' if n != 1 else ''}"
    if name == "get_open_house":
        addr = (result or {}).get("address") or "session"
        return f"Looked up {addr}"
    if name == "find_session_by_address":
        n = len((result or {}).get("matches") or [])
        q = (args.get("query") or "").strip()
        return f"Searched sessions for '{q}' — {n} match{'es' if n != 1 else ''}"
    if name == "list_leads":
        n = len((result or {}).get("leads") or [])
        total = (result or {}).get("total_matched") or n
        return f"Filtered leads — {n} shown of {total}"
    if name == "get_lead":
        return f"Pulled lead {args.get('name', '')}"
    if name == "get_insights":
        return f"Loaded {args.get('period', 'month')} insights"
    if name == "open_screen":
        return f"Opening {args.get('target', '?')}"
    return name
