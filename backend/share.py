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
# Mirrors openhousecopilot.com's exact style — same `.style-ai` theme:
# warm dark-grey background (#212124), cyan accent (#a5f3fc), Geist sans
# throughout, twin-houses brand mark. NO serif anywhere — the website
# uses Geist for every text size. NO gold — that was the wrong palette.
# Tokens copied verbatim from web/brand.css's .style-ai block so any
# future tweak there can be ported in one swap.
#
# Header + footer link to the marketing site because recipients are
# often other agents (sellers share with their kids' realtor, agents
# show teammates) — curiosity → CTA → discovery.

# Public marketing site — also used for the brand header + CTA. Pulled
# from env so a staging/preview deploy can override without code change.
MARKETING_URL = os.environ.get("MARKETING_URL", "https://openhousecopilot.com").rstrip("/")


def render_report_public_html(
    *,
    report: dict,
    agent: dict,
    weather: Optional[dict] = None,
) -> str:
    """Render the public share page using the website's exact style-ai
    theme. `report` is the SessionReport dict (post-validation); `agent`
    is the user record (drives the agent card at the bottom)."""

    def _h(s) -> str:
        return html.escape(str(s or ""))

    # --- Pull report fields ---------------------------------------
    address = (report.get("address") or "Your property").strip()
    date_label = (report.get("date_label") or "").strip()
    weather_label = (report.get("weather_label") or "").strip()
    visitor_count = int(report.get("visitor_count") or 0)
    duration_min = int(report.get("duration_minutes") or 0)
    headline = (report.get("headline") or "").strip()
    tldr_items = report.get("tldr") or []
    price_signal = (report.get("price_signal") or "").strip()
    traffic_summary = (report.get("traffic_summary") or "").strip()
    agent_take = (report.get("agent_take") or "").strip()
    next_steps = report.get("next_steps") or []

    pill_bits: list[str] = []
    if date_label:
        pill_bits.append(date_label)
    if duration_min > 0:
        pill_bits.append(f"{duration_min} min")
    if visitor_count > 0:
        pill_bits.append(
            f"{visitor_count} visitor"
            f"{'s' if visitor_count != 1 else ''}"
        )
    if weather_label:
        pill_bits.append(weather_label)
    pills_html = "".join(
        f'<span class="pill">{_h(p)}</span>' for p in pill_bits
    )

    tldr_html = "".join(f"<li>{_h(b)}</li>" for b in tldr_items)

    # --- Themes / standouts / next steps --------------------------
    def render_themes(themes: list, fallback: str) -> str:
        if not themes:
            return f'<p class="fallback">{_h(fallback)}</p>'
        out: list[str] = []
        for t in themes:
            freq = int(t.get("frequency") or 0)
            freq_chip = (
                f'<span class="theme-freq">{freq} VISITORS</span>'
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
                    f'"{_h(q.get("quote") or "")}"{attribution}'
                    f'</blockquote>'
                )
            out.append(
                f'<div class="theme">'
                f'<div class="theme-head">'
                f'<span class="theme-title">{_h(t.get("title") or "")}</span>'
                f'{freq_chip}</div>'
                f'<p class="theme-summary">{_h(t.get("summary") or "")}</p>'
                f'{quotes_html}'
                f'</div>'
            )
        return "".join(out)

    highlights_html = render_themes(
        report.get("highlights") or [],
        "Nothing recurred across visitors this session."
    )
    concerns_html = render_themes(
        report.get("concerns") or [],
        "No recurring concerns surfaced."
    )

    standouts = report.get("standout_visitors") or []
    if standouts:
        standout_rows: list[str] = []
        for s in standouts:
            score = int(s.get("score") or 0)
            score_tone = "hot" if score >= 70 else ("warm" if score >= 40 else "cool")
            standout_rows.append(
                f'<div class="standout">'
                f'<div class="standout-head">'
                f'<span class="standout-label">{_h(s.get("label") or "")}</span>'
                f'<span class="standout-score tone-{score_tone}">{score}/100</span>'
                f'</div>'
                f'<p class="standout-summary">{_h(s.get("summary") or "")}</p>'
                f'<p class="standout-status">{_h(s.get("follow_up_status") or "")}</p>'
                f'</div>'
            )
        standouts_html = "".join(standout_rows)
    else:
        standouts_html = '<p class="fallback">No standouts this session.</p>'

    next_steps_html = "".join(f"<li>{_h(s)}</li>" for s in next_steps)
    next_steps_block = (
        f'<ol class="next-steps">{next_steps_html}</ol>'
        if next_steps else '<p class="fallback">Stay the course.</p>'
    )

    # --- Agent card -----------------------------------------------
    agent_name = (agent.get("name") or "").strip()
    brokerage = (agent.get("brokerage") or "").strip()
    headshot_filename = agent.get("headshot_filename")
    agent_id = agent.get("id") or ""
    cache_buster = agent.get("headshot_updated_at") or ""
    cb_qs = f"?v={cache_buster}" if cache_buster else ""
    # Headshot served directly from the API origin — the static site's
    # /r/* rewrite doesn't cover /me/profile/*, so we use the bare
    # backend URL. The image is served with public-read at this path.
    headshot_url = (
        f"https://openhouseboss-api.onrender.com/me/profile/headshot/{_h(agent_id)}{cb_qs}"
        if headshot_filename else ""
    )

    if headshot_url:
        agent_card_html = (
            '<div class="agent-card">'
            f'<img class="agent-headshot" src="{headshot_url}" alt="" />'
            '<div class="agent-text">'
            f'<div class="agent-name">{_h(agent_name)}</div>'
            f'<div class="agent-broker">{_h(brokerage)}</div>'
            '</div>'
            '</div>'
        )
    else:
        agent_card_html = (
            '<div class="agent-card no-photo">'
            '<div class="agent-text">'
            f'<div class="agent-name">{_h(agent_name)}</div>'
            f'<div class="agent-broker">{_h(brokerage)}</div>'
            '</div>'
            '</div>'
        )

    # --- OG / Twitter meta ----------------------------------------
    og_description_raw = (tldr_items[0] if tldr_items else headline).strip()
    og_description = _h(og_description_raw[:200])
    og_title = _h(f"Open House Report — {address}")
    marketing = _h(MARKETING_URL)
    mark_url = f"{MARKETING_URL}/mark-400.png"

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
<meta property="og:url" content="{marketing}">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="{og_title}">
<meta name="twitter:description" content="{og_description}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@300;400;500;600;700&family=Geist+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  /* style-ai tokens — straight from web/brand.css. Geist everywhere
     (no serif). Cyan accent (--gold here is a token name retained
     from the brand system, but in this theme it's #a5f3fc cyan). */
  :root {{
    --bg-deep: #212124;
    --bg: #28282b;
    --bg-card: #313135;
    --bg-elev: #3a3a40;
    --gold: #a5f3fc;
    --gold-bright: #cffafe;
    --gold-deep: #67e8f9;
    --gold-soft: rgba(165, 243, 252, 0.10);
    --cream: #ededf2;
    --cream-dim: #b8b8c4;
    --text-dim: #8a8a96;
    --text-muted: #5a5a64;
    --border: rgba(255, 255, 255, 0.06);
    --border-strong: rgba(255, 255, 255, 0.14);
    --hairline: rgba(255, 255, 255, 0.06);
    --terracotta: #f87171;
    --sage: #86efac;
    --hot: #cffafe;
    --warm: #a5f3fc;
    --cool: #5a5a64;
  }}
  * {{ box-sizing: border-box; }}
  html, body {{
    margin: 0; padding: 0;
    background: var(--bg-deep);
    color: var(--cream);
    font-family: 'Geist', -apple-system, BlinkMacSystemFont, system-ui,
                 'Segoe UI', Roboto, sans-serif;
    line-height: 1.55;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    letter-spacing: -0.01em;
  }}
  a {{
    color: var(--gold);
    text-decoration: none;
    transition: color 160ms ease;
  }}
  a:hover {{ color: var(--gold-bright); }}

  .page {{
    max-width: 720px;
    margin: 0 auto;
    padding: 24px 28px 60px 28px;
  }}

  /* --- Brand header (clickable home link) --- */
  .brand {{
    display: flex; align-items: center; gap: 14px;
    padding: 18px 0 20px 0;
    border-bottom: 1px solid var(--hairline);
    margin-bottom: 40px;
  }}
  .brand-link {{
    display: flex; align-items: center; gap: 10px;
    color: var(--cream); font-weight: 500; font-size: 16px;
    letter-spacing: -0.02em;
  }}
  .brand-link:hover {{ color: var(--cream); }}
  .brand-link:hover .brand-mark {{ opacity: 0.85; }}
  .brand-mark {{
    width: 26px; height: 26px;
    display: block;
    transition: opacity 180ms ease;
  }}
  .brand-eyebrow {{
    margin-left: auto;
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; letter-spacing: 0.2em;
    text-transform: uppercase; color: var(--text-dim); font-weight: 500;
  }}

  /* --- Hero --- */
  .hero h1 {{
    margin: 0 0 18px 0;
    font-family: 'Geist', sans-serif;
    font-weight: 600;
    font-size: 56px; line-height: 1.0; letter-spacing: -0.04em;
    color: var(--cream);
  }}
  .hero h1 .accent {{
    color: var(--gold);
  }}
  .pills {{
    display: flex; flex-wrap: wrap; gap: 8px;
    margin-top: 18px;
  }}
  .pill {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; color: var(--text-dim);
    background: transparent;
    padding: 6px 12px; border-radius: 999px;
    border: 1px solid var(--border);
    letter-spacing: 0.04em;
    font-weight: 500;
    text-transform: uppercase;
  }}

  /* --- TL;DR card --- */
  .tldr {{
    margin: 40px 0 16px 0;
    background: var(--bg-card);
    border: 1px solid var(--border-strong);
    border-radius: 14px;
    padding: 28px 30px;
    position: relative;
  }}
  .tldr-eyebrow {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase;
    color: var(--gold); font-weight: 500;
  }}
  .tldr-headline {{
    margin: 12px 0 16px 0;
    font-family: 'Geist', sans-serif;
    font-size: 22px; font-weight: 500; color: var(--cream);
    line-height: 1.3; letter-spacing: -0.02em;
  }}
  .tldr ul {{ margin: 0; padding-left: 22px; font-size: 15px; color: var(--cream-dim); }}
  .tldr li {{ margin: 8px 0; line-height: 1.6; }}
  .tldr li::marker {{ color: var(--gold); }}

  /* --- Section headings --- */
  h2 {{
    margin: 48px 0 14px 0;
    font-family: 'Geist', sans-serif;
    font-weight: 600;
    font-size: 28px; color: var(--cream);
    letter-spacing: -0.03em; line-height: 1.1;
  }}
  p {{
    margin: 0 0 14px 0; font-size: 15px; color: var(--cream-dim);
    line-height: 1.7;
  }}
  .fallback {{
    color: var(--text-muted); font-size: 14px;
  }}

  /* --- Theme blocks --- */
  .theme {{
    margin: 22px 0;
    padding: 20px 22px;
    background: var(--bg-card);
    border: 1px solid var(--hairline);
    border-radius: 12px;
  }}
  .theme-head {{
    display: flex; align-items: center; gap: 12px;
    flex-wrap: wrap;
  }}
  .theme-title {{
    font-family: 'Geist', sans-serif;
    font-size: 18px; font-weight: 600; color: var(--cream);
    letter-spacing: -0.02em;
  }}
  .theme-freq {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 10px; letter-spacing: 0.16em; text-transform: uppercase;
    color: var(--gold); font-weight: 500;
    padding: 4px 10px;
    border-radius: 99px; background: var(--gold-soft);
  }}
  .theme-summary {{
    font-size: 15px; color: var(--cream-dim);
    margin: 10px 0 12px 0; line-height: 1.6;
  }}
  blockquote.quote {{
    margin: 10px 0 8px 0;
    padding: 12px 16px;
    border-left: 2px solid var(--gold);
    background: var(--gold-soft);
    font-family: 'Geist', sans-serif;
    color: var(--cream); font-size: 15px;
    line-height: 1.55;
    border-radius: 0 6px 6px 0;
  }}
  .quote-attr {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; color: var(--text-muted);
    letter-spacing: 0.04em;
  }}

  /* --- Standout visitor cards --- */
  .standout {{
    margin: 14px 0;
    background: var(--bg-card);
    border: 1px solid var(--hairline);
    border-radius: 12px;
    padding: 18px 20px;
  }}
  .standout-head {{
    display: flex; justify-content: space-between; align-items: baseline;
    margin-bottom: 8px;
  }}
  .standout-label {{
    font-family: 'Geist', sans-serif;
    font-size: 17px; font-weight: 600; color: var(--cream);
    letter-spacing: -0.02em;
  }}
  .standout-score {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 13px; font-weight: 600;
  }}
  .tone-hot {{ color: var(--gold-bright); }}
  .tone-warm {{ color: var(--gold); }}
  .tone-cool {{ color: var(--cool); }}
  .standout-summary {{
    font-size: 14px; color: var(--cream-dim); margin: 4px 0 6px 0;
    line-height: 1.6;
  }}
  .standout-status {{
    font-size: 11px; color: var(--text-muted);
    margin: 6px 0 0 0;
    font-family: 'Geist Mono', ui-monospace, monospace;
    letter-spacing: 0.04em; text-transform: uppercase;
  }}

  /* --- Next steps --- */
  ol.next-steps {{
    margin: 10px 0 0 0; padding-left: 24px;
    font-size: 15px; color: var(--cream-dim);
    line-height: 1.7;
  }}
  ol.next-steps li {{ margin: 10px 0; }}
  ol.next-steps li::marker {{ color: var(--gold); font-weight: 600; }}

  /* --- Agent card --- */
  .agent-card {{
    margin-top: 56px; padding: 26px 0 30px 0;
    border-top: 1px solid var(--hairline);
    display: flex; align-items: center; gap: 18px;
  }}
  .agent-headshot {{
    width: 56px; height: 56px; border-radius: 50%;
    object-fit: cover; background: var(--bg-elev);
    display: block;
    border: 1px solid var(--border);
  }}
  .agent-name {{
    font-weight: 600; font-size: 15px; color: var(--cream);
    letter-spacing: -0.02em;
  }}
  .agent-broker {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; color: var(--text-dim);
    margin-top: 4px;
    letter-spacing: 0.05em; text-transform: uppercase;
  }}

  /* --- Footer CTA — pulls curious agents back to the marketing site. */
  .cta-footer {{
    margin-top: 40px; padding: 40px 28px 44px 28px;
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: 14px;
    text-align: center;
  }}
  .cta-eyebrow {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; letter-spacing: 0.2em; text-transform: uppercase;
    color: var(--gold); font-weight: 500;
  }}
  .cta-headline {{
    margin: 12px 0 6px 0;
    font-family: 'Geist', sans-serif;
    font-weight: 600;
    font-size: 30px; color: var(--cream); letter-spacing: -0.03em;
    line-height: 1.1;
  }}
  .cta-headline .accent {{ color: var(--gold); }}
  .cta-sub {{
    font-size: 15px; color: var(--cream-dim); margin: 8px auto 22px auto;
    line-height: 1.6;
    max-width: 460px;
  }}
  .cta-btn {{
    display: inline-flex; align-items: center; gap: 10px;
    padding: 14px 26px;
    background: var(--gold);
    color: #0a0e13 !important;
    font-weight: 600; font-size: 14px;
    border-radius: 999px;
    letter-spacing: -0.01em;
    transition: background 180ms ease, transform 160ms ease;
  }}
  .cta-btn:hover {{
    background: var(--gold-bright);
    transform: translateY(-1px);
  }}
  .cta-btn .arrow {{
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-weight: 500;
  }}

  .footer-mini {{
    margin-top: 28px; text-align: center;
    font-family: 'Geist Mono', ui-monospace, monospace;
    font-size: 11px; letter-spacing: 0.2em; color: var(--text-muted);
    text-transform: uppercase;
  }}
  .footer-mini a {{ font-weight: 500; }}

  @media (max-width: 480px) {{
    .page {{ padding: 20px 20px 50px 20px; }}
    .hero h1 {{ font-size: 40px; letter-spacing: -0.035em; }}
    .tldr {{ padding: 22px 20px; }}
    .tldr-headline {{ font-size: 19px; }}
    h2 {{ font-size: 24px; margin-top: 38px; }}
    .cta-headline {{ font-size: 26px; }}
  }}
</style>
</head>
<body>
<div class="page">

  <header class="brand">
    <a class="brand-link" href="{marketing}" target="_blank" rel="noopener">
      <img class="brand-mark" src="{mark_url}" alt="" />
      <span>Open House Copilot</span>
    </a>
    <span class="brand-eyebrow">Open House Report</span>
  </header>

  <section class="hero">
    <h1>{_h(address)}</h1>
    <div class="pills">{pills_html}</div>
  </section>

  <section class="tldr">
    <div class="tldr-eyebrow">TL;DR</div>
    <div class="tldr-headline">{_h(headline)}</div>
    <ul>{tldr_html}</ul>
  </section>

  <h2>Traffic</h2>
  <p>{_h(traffic_summary)}</p>

  <h2>What stood out</h2>
  {highlights_html}

  <h2>Concerns + objections</h2>
  {concerns_html}

  <h2>Price signal</h2>
  <p>{_h(price_signal)}</p>

  <h2>Standout visitors</h2>
  {standouts_html}

  <h2>My take</h2>
  <p>{_h(agent_take)}</p>

  <h2>Recommended next steps</h2>
  {next_steps_block}

  {agent_card_html}

  <section class="cta-footer">
    <div class="cta-eyebrow">Curious?</div>
    <div class="cta-headline">Every open house, <span class="accent">quietly remembered.</span></div>
    <p class="cta-sub">Open House Copilot listens through your phone, identifies each guest who walked in, and drafts the follow-up before you've locked the front door.</p>
    <a class="cta-btn" href="{marketing}" target="_blank" rel="noopener">
      Learn more <span class="arrow">→</span>
    </a>
  </section>

  <div class="footer-mini">
    Generated by <a href="{marketing}" target="_blank" rel="noopener">Open House Copilot</a>
  </div>

</div>
</body>
</html>"""


def render_revoked_html() -> str:
    """Stand-alone page shown when a token is unknown or revoked. Same
    style-ai theme as the live page so a stale link still lands on
    coherent brand chrome instead of a generic 404."""
    marketing = html.escape(MARKETING_URL)
    mark_url = f"{MARKETING_URL}/mark-400.png"
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Link no longer available — Open House Copilot</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600&display=swap" rel="stylesheet">
<style>
  :root {{
    --bg-deep: #212124;
    --bg-card: #313135;
    --gold: #a5f3fc;
    --gold-bright: #cffafe;
    --cream: #ededf2;
    --cream-dim: #b8b8c4;
    --text-muted: #5a5a64;
    --border: rgba(255,255,255,0.06);
    --border-strong: rgba(255,255,255,0.14);
  }}
  * {{ box-sizing: border-box; }}
  html, body {{
    margin: 0; padding: 0;
    background: var(--bg-deep);
    color: var(--cream);
    font-family: 'Geist', -apple-system, BlinkMacSystemFont, system-ui, sans-serif;
    min-height: 100vh;
    display: flex; align-items: center; justify-content: center;
    -webkit-font-smoothing: antialiased;
    letter-spacing: -0.01em;
  }}
  .box {{
    max-width: 440px; margin: 24px; text-align: center;
    padding: 42px 34px;
    background: var(--bg-card);
    border-radius: 14px;
    border: 1px solid var(--border-strong);
  }}
  .mark {{
    width: 38px; height: 38px;
    margin: 0 auto 22px auto;
    display: block;
  }}
  small {{
    color: var(--gold); font-size: 11px; letter-spacing: 0.2em;
    text-transform: uppercase; font-weight: 500;
    font-family: 'Geist', sans-serif;
  }}
  h1 {{
    font-family: 'Geist', sans-serif;
    font-weight: 600;
    font-size: 28px; margin: 14px 0 10px 0; color: var(--cream);
    letter-spacing: -0.03em; line-height: 1.15;
  }}
  p {{
    font-size: 15px; color: var(--cream-dim);
    line-height: 1.6; margin: 8px 0 22px 0;
  }}
  a.btn {{
    display: inline-flex; align-items: center; gap: 8px;
    padding: 13px 24px; border-radius: 999px;
    background: var(--gold); color: #0a0e13;
    font-weight: 600; font-size: 14px;
    text-decoration: none;
    letter-spacing: -0.01em;
    transition: background 180ms ease, transform 160ms ease;
  }}
  a.btn:hover {{
    background: var(--gold-bright);
    transform: translateY(-1px);
  }}
</style>
</head>
<body>
<div class="box">
  <img class="mark" src="{mark_url}" alt="" />
  <small>Open House Copilot</small>
  <h1>Link no longer available</h1>
  <p>This open house report link has expired or been revoked. Ask the agent who shared it for an updated link.</p>
  <a class="btn" href="{marketing}">Visit Open House Copilot →</a>
</div>
</body>
</html>"""

