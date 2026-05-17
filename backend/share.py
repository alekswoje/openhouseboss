"""Shareable public links for Open House Reports.

A homeowner can be on any device — sometimes the agent wants to drop a
link in iMessage instead of (or alongside) the emailed PDF/HTML version.
This module mints a short URL-safe token and serves a polished public
HTML page that doesn't require Foyer-side auth.

Token lifecycle:
  1. Agent taps Share Link in ReportView → POST /sessions/{id}/report/share
  2. Backend mints token, stores in session.json under `share` AND in
     a flat index at sessions/_auth/share_index.json for O(1) lookup.
     Returns the public URL.
  3. Recipient opens https://.../r/{token} → GET /r/{token} renders
     the report as a stand-alone HTML page (with OG meta tags so link
     previews look right in iMessage / Slack / Gmail).
  4. Agent can DELETE the share to revoke — the public URL then 404s.

Tokens are unguessable (96 bits of entropy via secrets.token_urlsafe(12))
and the index is the only way to resolve token → session, so revocation
is hard-deletion (no soft state needed). Once revoked, the entry is
removed from the index and the share block on the session is cleared.

Public-page rendering is intentionally separate from the email HTML
renderer: the email needs to render inside Gmail's restrictive sandbox,
the public page can use a richer (responsive, OG-tagged) template that
looks great on phones and laptops.
"""
from __future__ import annotations

import html
import json
import os
import secrets
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

# Default to the public brand domain. The static site at
# openhousecopilot.com forwards /r/* → this backend's /r/{token} via
# `web/_redirects` (Render static-site convention; Netlify/Vercel use
# the same file). When that's not configured (local dev, broken
# routing) override SHARE_BASE_URL via env var.
SHARE_BASE_URL = (
    os.environ.get("SHARE_BASE_URL")
    or "https://openhousecopilot.com"
).rstrip("/")

_INDEX_DIR = Path("sessions") / "_auth"
_INDEX_FILE = _INDEX_DIR / "share_index.json"
_index_lock = threading.RLock()


def _load_index() -> dict:
    if not _INDEX_FILE.exists():
        return {}
    try:
        return json.loads(_INDEX_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return {}


def _save_index(data: dict) -> None:
    _INDEX_DIR.mkdir(parents=True, exist_ok=True)
    _INDEX_FILE.write_text(json.dumps(data, indent=2))


def mint_token() -> str:
    """16-char URL-safe token (~96 bits of entropy). Short enough to
    paste verbatim, long enough that brute-forcing the index is
    infeasible."""
    return secrets.token_urlsafe(12)


def create_share(*, session_id: str, user_id: str) -> dict:
    """Mint a new share token for the session. If one already exists,
    return the existing one (idempotent — sharing twice = same URL).
    Returns {token, url, created_at, view_count}."""
    with _index_lock:
        index = _load_index()
        # Reuse-on-double-tap: scan for an existing entry pointing at
        # this session (cheap — index is small in absolute terms).
        for token, entry in index.items():
            if entry.get("session_id") == session_id and entry.get("revoked_at") is None:
                return {
                    "token": token,
                    "url": _public_url(token),
                    "created_at": entry.get("created_at"),
                    "view_count": entry.get("view_count", 0),
                }
        token = mint_token()
        now_iso = datetime.now(timezone.utc).isoformat()
        index[token] = {
            "session_id": session_id,
            "user_id": user_id,
            "created_at": now_iso,
            "view_count": 0,
            "revoked_at": None,
        }
        _save_index(index)
        return {
            "token": token,
            "url": _public_url(token),
            "created_at": now_iso,
            "view_count": 0,
        }


def revoke_share(*, session_id: str, user_id: str) -> bool:
    """Drop any active token(s) for this session. Returns True if at
    least one token was revoked, False if there were none to revoke."""
    revoked = False
    with _index_lock:
        index = _load_index()
        for token in list(index.keys()):
            entry = index[token]
            if (
                entry.get("session_id") == session_id
                and entry.get("user_id") == user_id
                and entry.get("revoked_at") is None
            ):
                del index[token]
                revoked = True
        if revoked:
            _save_index(index)
    return revoked


def lookup_token(token: str) -> Optional[dict]:
    """Resolve a public token to its session/user. Returns None on
    unknown or revoked tokens. Increments view_count on every hit
    so the agent can see how popular the link is."""
    with _index_lock:
        index = _load_index()
        entry = index.get(token)
        if not entry or entry.get("revoked_at"):
            return None
        entry["view_count"] = int(entry.get("view_count", 0)) + 1
        entry["last_viewed_at"] = datetime.now(timezone.utc).isoformat()
        index[token] = entry
        _save_index(index)
        return dict(entry)


def get_share_state(*, session_id: str) -> Optional[dict]:
    """Return the share entry for a session without bumping view_count.
    Used by GET /sessions/{id}/report/share so iOS can render the
    'shared' state on the report view."""
    with _index_lock:
        index = _load_index()
        for token, entry in index.items():
            if (
                entry.get("session_id") == session_id
                and entry.get("revoked_at") is None
            ):
                return {
                    "token": token,
                    "url": _public_url(token),
                    "created_at": entry.get("created_at"),
                    "view_count": entry.get("view_count", 0),
                    "last_viewed_at": entry.get("last_viewed_at"),
                }
    return None


def _public_url(token: str) -> str:
    return f"{SHARE_BASE_URL}/r/{token}"


# --- Public HTML page -----------------------------------------------------
#
# Rendered server-side at /r/{token}. Designed to look polished in both
# desktop and mobile webviews (homeowners open these in iMessage,
# Gmail, Safari). Includes:
#   - Open Graph + Twitter meta tags so link previews unfurl with the
#     property address, snippet, and (eventually) a photo.
#   - Responsive single-column layout; no horizontal scroll on phones.
#   - Branded header with the agent's headshot/name/brokerage.
#   - Same content as the in-app + email report (single source of truth
#     for facts), restyled for a stand-alone web page.

def render_report_public_html(
    *,
    report: dict,
    agent: dict,
    weather: Optional[dict] = None,
) -> str:
    """Render the public-facing share page. `report` is the
    SessionReport dict (post-validation); `agent` is the user record
    (for the branded header); `weather` lifts the temp/condition out
    of session.weather if present (the report already carries
    weather_label but the public page renders a richer chip with the
    SF Symbol equivalent → unicode glyph)."""

    def _h(s) -> str:
        return html.escape(str(s or ""))

    # Header — agent identity. Falls back to a clean text-only block
    # when no headshot is configured.
    agent_name = (agent.get("name") or "").strip()
    brokerage = (agent.get("brokerage") or "").strip()
    headshot_filename = agent.get("headshot_filename")
    agent_id = agent.get("id") or ""
    cache_buster = agent.get("headshot_updated_at") or ""
    cb_qs = f"?v={cache_buster}" if cache_buster else ""
    headshot_url = (
        f"{SHARE_BASE_URL}/me/profile/headshot/{_h(agent_id)}{cb_qs}"
        if headshot_filename else ""
    )

    # Hero — property + date + weather chip.
    address = (report.get("address") or "Your property").strip()
    date_label = (report.get("date_label") or "").strip()
    weather_label = (report.get("weather_label") or "").strip()
    visitor_count = int(report.get("visitor_count") or 0)
    duration_min = int(report.get("duration_minutes") or 0)

    # Meta line — same composition as the email but rendered as
    # individual styled pills on the web page for legibility.
    pill_bits: list[str] = []
    if date_label: pill_bits.append(date_label)
    if duration_min > 0: pill_bits.append(f"{duration_min} min")
    if visitor_count > 0:
        pill_bits.append(f"{visitor_count} visitor{'s' if visitor_count != 1 else ''}")
    if weather_label: pill_bits.append(weather_label)
    pills_html = "".join(
        f'<span class="pill">{_h(p)}</span>' for p in pill_bits
    )

    # TL;DR
    headline = (report.get("headline") or "").strip()
    tldr_items = report.get("tldr") or []
    tldr_html = "".join(f"<li>{_h(b)}</li>" for b in tldr_items)

    # Sections
    def render_themes(themes: list, fallback: str) -> str:
        if not themes:
            return f'<p class="fallback">{_h(fallback)}</p>'
        out: list[str] = []
        for t in themes:
            freq = int(t.get("frequency") or 0)
            freq_chip = (
                f'<span class="theme-freq">{freq} visitors</span>'
                if freq >= 2 else ""
            )
            quotes_html = ""
            for q in t.get("quotes") or []:
                attribution = (
                    f' <span class="quote-attr">— {_h(q.get("attribution") or "")}</span>'
                    if q.get("attribution") else ""
                )
                quotes_html += (
                    f'<blockquote class="quote">'
                    f'“{_h(q.get("quote") or "")}”{attribution}'
                    f'</blockquote>'
                )
            out.append(
                f'<div class="theme">'
                f'<div class="theme-head"><span class="theme-title">{_h(t.get("title") or "")}</span>{freq_chip}</div>'
                f'<p class="theme-summary">{_h(t.get("summary") or "")}</p>'
                f'{quotes_html}'
                f'</div>'
            )
        return "".join(out)

    highlights_html = render_themes(report.get("highlights") or [], "Nothing recurred across visitors this session.")
    concerns_html = render_themes(report.get("concerns") or [], "No recurring concerns surfaced.")

    standouts = report.get("standout_visitors") or []
    if standouts:
        rows: list[str] = []
        for s in standouts:
            score = int(s.get("score") or 0)
            score_tone = (
                "hot" if score >= 70 else
                ("warm" if score >= 40 else "cool")
            )
            rows.append(
                f'<div class="standout">'
                f'<div class="standout-head">'
                f'<span class="standout-label">{_h(s.get("label") or "")}</span>'
                f'<span class="standout-score tone-{score_tone}">{score}/100</span>'
                f'</div>'
                f'<p class="standout-summary">{_h(s.get("summary") or "")}</p>'
                f'<p class="standout-status">{_h(s.get("follow_up_status") or "")}</p>'
                f'</div>'
            )
        standouts_html = "".join(rows)
    else:
        standouts_html = '<p class="fallback">No standouts this session.</p>'

    price_signal = _h(report.get("price_signal") or "")
    traffic_summary = _h(report.get("traffic_summary") or "")
    agent_take = _h(report.get("agent_take") or "")

    next_steps = report.get("next_steps") or []
    next_steps_html = "".join(f"<li>{_h(s)}</li>" for s in next_steps)
    next_steps_block = (
        f'<ol class="next-steps">{next_steps_html}</ol>'
        if next_steps else '<p class="fallback">Stay the course.</p>'
    )

    # OG description — first TL;DR bullet (or headline). Plain text,
    # truncated; iMessage / Slack quote up to ~200 chars in previews.
    og_description_raw = (tldr_items[0] if tldr_items else headline).strip()
    og_description = _h(og_description_raw[:200])
    og_title_raw = f"Open House Report — {address}"
    og_title = _h(og_title_raw)

    # Header block — agent identity. Either a row with headshot or a
    # text-only signature for agents who haven't uploaded a photo.
    if headshot_url:
        agent_header = f"""
        <div class="agent-row">
          <img class="agent-headshot" src="{headshot_url}" alt="" />
          <div class="agent-text">
            <div class="agent-name">{_h(agent_name)}</div>
            <div class="agent-broker">{_h(brokerage)}</div>
          </div>
        </div>
        """
    else:
        agent_header = f"""
        <div class="agent-row no-photo">
          <div class="agent-text">
            <div class="agent-name">{_h(agent_name)}</div>
            <div class="agent-broker">{_h(brokerage)}</div>
          </div>
        </div>
        """

    # All-in-one HTML document. Inlined styles so we don't depend on
    # a CDN being reachable when the homeowner opens it from a hotel
    # Wi-Fi network. System font stack so it looks native on iPhone,
    # Mac, and Android out of the box.
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{og_title}</title>
<meta name="description" content="{og_description}">
<meta property="og:title" content="{og_title}">
<meta property="og:description" content="{og_description}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="Open House Copilot">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="{og_title}">
<meta name="twitter:description" content="{og_description}">
<style>
  :root {{
    --bg: #faf7f0;
    --surface: #ffffff;
    --ink: #1a1a1a;
    --ink-dim: #555;
    --ink-mute: #888;
    --line: #e5e1d8;
    --accent: #c9a55b;
    --accent-deep: #a07f3a;
    --hot: #b8612f;
    --warm: #c9a55b;
    --cool: #8a8a8a;
  }}
  * {{ box-sizing: border-box; }}
  body {{
    margin: 0;
    background: var(--bg);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue",
                 "Segoe UI", Roboto, sans-serif;
    line-height: 1.55;
    -webkit-font-smoothing: antialiased;
  }}
  .page {{
    max-width: 720px;
    margin: 0 auto;
    padding: 32px 24px 80px 24px;
  }}
  .brand {{
    display: flex;
    align-items: center;
    gap: 10px;
    padding-bottom: 18px;
    border-bottom: 1px solid var(--line);
    margin-bottom: 22px;
  }}
  .brand-mark {{
    width: 28px; height: 28px; border-radius: 7px;
    background: var(--ink);
    color: #fff; font-weight: 700; font-size: 14px;
    display: flex; align-items: center; justify-content: center;
    font-family: Georgia, serif;
  }}
  .brand-name {{
    font-family: Georgia, "Times New Roman", serif;
    font-size: 17px; letter-spacing: -0.2px; color: var(--ink);
  }}
  .brand-tag {{
    font-size: 11px; letter-spacing: 1.5px; text-transform: uppercase;
    color: var(--accent); font-weight: 600; margin-left: auto;
  }}

  .hero h1 {{
    margin: 0 0 6px 0;
    font-family: Georgia, "Times New Roman", serif;
    font-size: 30px; line-height: 1.15; letter-spacing: -0.5px;
  }}
  .pills {{
    margin-top: 10px;
    display: flex; flex-wrap: wrap; gap: 6px;
  }}
  .pill {{
    font-size: 11px; color: var(--ink-dim);
    background: #f0ede4; padding: 4px 10px; border-radius: 99px;
    border: 1px solid var(--line);
    letter-spacing: 0.2px;
  }}

  .tldr {{
    margin: 24px 0;
    background: #fff;
    border: 1px solid var(--line);
    border-left: 3px solid var(--accent);
    border-radius: 12px;
    padding: 18px 20px;
  }}
  .tldr-eyebrow {{
    font-size: 10px; letter-spacing: 2px; text-transform: uppercase;
    color: var(--accent); font-weight: 700;
  }}
  .tldr-headline {{
    margin: 6px 0 12px 0;
    font-size: 17px; font-weight: 600; color: var(--ink);
    line-height: 1.4;
  }}
  .tldr ul {{ margin: 0; padding-left: 20px; font-size: 14px; color: var(--ink-dim); }}
  .tldr li {{ margin: 4px 0; }}

  h2 {{
    margin: 32px 0 10px 0;
    font-family: Georgia, "Times New Roman", serif;
    font-size: 19px; color: var(--ink); letter-spacing: -0.2px;
  }}
  p {{ margin: 0 0 12px 0; font-size: 14px; color: var(--ink-dim); }}
  .fallback {{ font-style: italic; color: var(--ink-mute); font-size: 13px; }}

  .theme {{ margin: 14px 0; }}
  .theme-head {{ display: flex; align-items: baseline; gap: 10px; }}
  .theme-title {{ font-size: 15px; font-weight: 600; color: var(--ink); }}
  .theme-freq {{
    font-size: 11px; color: var(--ink-mute); font-weight: 500;
  }}
  .theme-summary {{ font-size: 13px; color: var(--ink-dim); margin: 4px 0 6px 0; }}
  blockquote.quote {{
    margin: 6px 0 6px 0; padding: 8px 14px;
    border-left: 2px solid var(--accent);
    background: #faf7f0;
    font-style: italic; color: var(--ink); font-size: 13px;
    border-radius: 0 6px 6px 0;
  }}
  .quote-attr {{ font-size: 11px; color: var(--ink-mute); font-style: normal; }}

  .standout {{
    margin: 10px 0;
    background: #fff;
    border: 1px solid var(--line);
    border-radius: 10px;
    padding: 12px 14px;
  }}
  .standout-head {{
    display: flex; justify-content: space-between; align-items: baseline;
    margin-bottom: 4px;
  }}
  .standout-label {{ font-weight: 600; font-size: 14px; color: var(--ink); }}
  .standout-score {{ font-size: 12px; font-weight: 700; }}
  .tone-hot {{ color: var(--hot); }}
  .tone-warm {{ color: var(--warm); }}
  .tone-cool {{ color: var(--cool); }}
  .standout-summary {{ font-size: 13px; color: var(--ink-dim); margin: 2px 0; }}
  .standout-status {{ font-size: 11px; color: var(--ink-mute); font-style: italic; margin: 4px 0 0 0; }}

  ol.next-steps {{
    margin: 6px 0 0 0; padding-left: 22px;
    font-size: 14px; color: var(--ink-dim);
  }}
  ol.next-steps li {{ margin: 6px 0; }}

  .agent-card {{
    margin-top: 36px; padding-top: 22px;
    border-top: 1px solid var(--line);
  }}
  .agent-row {{ display: flex; align-items: center; gap: 14px; }}
  .agent-headshot {{
    width: 56px; height: 56px; border-radius: 50%;
    object-fit: cover; background: #eee; display: block;
  }}
  .agent-name {{ font-weight: 600; font-size: 14px; color: var(--ink); }}
  .agent-broker {{ font-size: 12px; color: var(--ink-mute); }}

  .footer {{
    margin-top: 36px; text-align: center;
    font-size: 10px; letter-spacing: 1.5px; color: var(--ink-mute);
    text-transform: uppercase;
  }}
  .footer a {{ color: var(--accent); text-decoration: none; font-weight: 600; }}

  @media (max-width: 480px) {{
    .page {{ padding: 22px 18px 60px 18px; }}
    .hero h1 {{ font-size: 26px; }}
  }}
</style>
</head>
<body>
<div class="page">
  <div class="brand">
    <div class="brand-mark">F</div>
    <div class="brand-name">Open House Copilot</div>
    <div class="brand-tag">Open House Report</div>
  </div>

  <div class="hero">
    <h1>{_h(address)}</h1>
    <div class="pills">{pills_html}</div>
  </div>

  <div class="tldr">
    <div class="tldr-eyebrow">TL;DR</div>
    <div class="tldr-headline">{_h(headline)}</div>
    <ul>{tldr_html}</ul>
  </div>

  <h2>Traffic</h2>
  <p>{traffic_summary}</p>

  <h2>What stood out</h2>
  {highlights_html}

  <h2>Concerns + objections</h2>
  {concerns_html}

  <h2>Price signal</h2>
  <p>{price_signal}</p>

  <h2>Standout visitors</h2>
  {standouts_html}

  <h2>My take</h2>
  <p>{agent_take}</p>

  <h2>Recommended next steps</h2>
  {next_steps_block}

  <div class="agent-card">{agent_header}</div>

  <div class="footer">
    Generated by <a href="https://openhousecopilot.com">Open House Copilot</a>
  </div>
</div>
</body>
</html>"""


def render_revoked_html() -> str:
    """Tiny stand-alone page shown when a token is unknown or revoked.
    Friendlier than a bare 404 — the recipient might've gotten a stale
    link from an old email thread."""
    return """<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Link expired</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font-family: -apple-system, BlinkMacSystemFont, Helvetica, sans-serif;
       background: #faf7f0; color: #1a1a1a; margin: 0; padding: 0;
       display: flex; align-items: center; justify-content: center;
       min-height: 100vh; }
.box { max-width: 420px; margin: 24px; text-align: center; padding: 28px;
       background: #fff; border-radius: 14px; border: 1px solid #e5e1d8; }
h1 { font-family: Georgia, serif; font-size: 22px; margin: 0 0 6px 0; }
p  { font-size: 14px; color: #555; line-height: 1.5; margin: 4px 0; }
small { color: #888; font-size: 11px; letter-spacing: 1.5px;
        text-transform: uppercase; }
a { color: #c9a55b; text-decoration: none; font-weight: 600; }
</style></head>
<body><div class="box">
  <small>OPEN HOUSE COPILOT</small>
  <h1>Link no longer available</h1>
  <p>This open house report link has expired or been revoked. Ask the agent who shared it for an updated link.</p>
</div></body></html>"""
