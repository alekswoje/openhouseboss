import json
import os
import secrets
import threading
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

load_dotenv(override=True)

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from backend import auth as auth_lib
from backend import mls_store
from backend import mls_replicator
from backend import stats as stats_lib
from pipeline.analyze import analyze_visitor, generate_session_name, refine_draft
from pipeline.copilot_agent import run_copilot_turn
from pipeline.leads_agent import query_leads_agent
from pipeline.identify import identify_agent_and_visitors
from pipeline.mock import load_mock_transcript
from pipeline.report import (
    SessionReport,
    generate_report as _generate_report,
    refine_report as _refine_report,
    render_report_html,
)
from pipeline.script_agent import agent_create_script, agent_edit_script
from pipeline.script_coverage import grade_against_script
from pipeline.scripts import (
    Script,
    USER_SCRIPTS_DIR,
    get_script,
    has_revision,
    list_scripts_summary,
    restore_revision,
    save_user_script,
    snapshot_absent,
    snapshot_revision,
    update_user_script,
    delete_user_script,
)
from pipeline.tags import DEFAULT_TAGS
from pipeline.transcribe import transcribe_with_speakers
from pipeline.weather import enrich_session_with_weather
from backend import share as share_lib

SESSIONS_DIR = Path("sessions")
SESSIONS_DIR.mkdir(exist_ok=True)

# Newsletter signup log. JSONL — one line per subscriber — so re-reading
# is trivial and a redeploy on Render only loses entries that haven't
# also been mirrored to the logs (see `_log_newsletter_signup`).
NEWSLETTER_LOG = SESSIONS_DIR / "newsletter.jsonl"

app = FastAPI(title="OpenHouseBoss API")

# CORS — locked to known web origins. The iOS app is native and ignores
# CORS entirely; the only browsers hitting us are the marketing site
# (openhousecopilot.com) and Render preview URLs. Anything else is a
# third-party page trying to read our cookies and gets denied.
#
# Add an origin without a redeploy by setting EXTRA_CORS_ORIGINS=
# "https://foo.com,https://bar.com" on Render.
_EXTRA_ORIGINS = [
    o.strip()
    for o in os.environ.get("EXTRA_CORS_ORIGINS", "").split(",")
    if o.strip()
]
_PROD_ORIGINS = [
    "https://openhousecopilot.com",
    "https://www.openhousecopilot.com",
    "https://openhouseboss-web.onrender.com",
    "https://openhouseboss-api.onrender.com",
] + _EXTRA_ORIGINS

# Regex covers (a) any *.onrender.com preview URL during deploys, and (b)
# localhost on any port for the dev server (Python http.server, vite, etc).
_CORS_ORIGIN_REGEX = (
    r"^(https://[a-z0-9-]+\.onrender\.com|"
    r"https?://(localhost|127\.0\.0\.1)(:\d+)?)$"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_PROD_ORIGINS,
    allow_origin_regex=_CORS_ORIGIN_REGEX,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Requested-With"],
    allow_credentials=True,
    max_age=600,
)


@app.middleware("http")
async def _security_headers(request: Request, call_next):
    """Per-response security headers.

    - HSTS: tells browsers to only ever talk to this host over HTTPS,
      even if the user types http://. Render terminates TLS at the edge
      so the server itself sees plain HTTP, but the header is forwarded
      to the browser unchanged.
    - X-Content-Type-Options: prevents browsers from MIME-sniffing a
      response into a different content type (e.g. interpreting a
      user-uploaded headshot as JS).
    - Referrer-Policy: don't leak query strings to third-party hosts.
    - X-Frame-Options: forbid embedding the app in another page's
      iframe so a phishing site can't UI-redress us.
    """
    response = await call_next(request)
    response.headers.setdefault(
        "Strict-Transport-Security", "max-age=31536000; includeSubDomains"
    )
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("Referrer-Policy", "strict-origin-when-cross-origin")
    response.headers.setdefault("X-Frame-Options", "DENY")
    return response


@app.get("/healthz")
def healthz():
    return {"ok": True}


# --------------------------------------------------------------------------
# Newsletter — pre-launch waitlist
# --------------------------------------------------------------------------
#
# Open House Copilot is invite-only for now; no one can self-serve a real agent
# account from the marketing site. The "Request access" CTA collects an
# email here instead, so we can ping the list when we're ready to onboard
# the next cohort. The same endpoint backs any future "subscribe to
# updates" surface — there's only one list.
#
# Storage: append a JSON line per signup to sessions/newsletter.jsonl AND
# log to stdout. Render's ephemeral disk wipes the file on redeploy, but
# the stdout log persists in Render's logs viewer for the dashboard
# retention window — so signups aren't lost if I forget to copy the file
# off before the next deploy.

import json as _json_nl
import re as _re_nl
from pydantic import BaseModel as _BaseModel_nl

# RFC-5322-ish but pragmatic: don't reject a real email over a regex
# quibble. Just sanity-check shape and length.
_EMAIL_RE = _re_nl.compile(r"^[^@\s]{1,64}@[^@\s]{1,253}\.[^@\s]{1,63}$")


class NewsletterSignup(_BaseModel_nl):
    email: str
    # Optional free-form context — "where did you hear about us", "I'm
    # an agent at X brokerage", etc. Capped server-side so the log
    # doesn't get spammed.
    note: Optional[str] = None
    # Where the signup came from ("landing", "footer", etc.) so we can
    # tell which CTA is converting if we add more later.
    source: Optional[str] = "landing"


@app.post("/newsletter/subscribe")
def newsletter_subscribe(payload: NewsletterSignup):
    email = (payload.email or "").strip().lower()
    if not email or not _EMAIL_RE.match(email):
        raise HTTPException(status_code=400, detail="Please enter a valid email.")
    if len(email) > 320:
        raise HTTPException(status_code=400, detail="Email too long.")
    note = (payload.note or "").strip()[:500]
    source = (payload.source or "landing").strip()[:32]
    entry = {
        "email": email,
        "note": note or None,
        "source": source,
        "ts": datetime.now(timezone.utc).isoformat(),
    }
    # Best-effort append. We don't surface a server error to the user
    # if the disk is read-only — the stdout log below is the source of
    # truth in that case.
    try:
        with NEWSLETTER_LOG.open("a", encoding="utf-8") as f:
            f.write(_json_nl.dumps(entry) + "\n")
    except OSError:
        pass
    # Persistent record. Show up in Render's logs viewer for a long
    # retention window. Tag the line so it's easy to grep out.
    print(f"[newsletter] {_json_nl.dumps(entry)}", flush=True)
    return {"ok": True}


# --------------------------------------------------------------------------
# Auth — Google Sign-In
# --------------------------------------------------------------------------

@app.get("/auth/google/start")
def google_start(platform: str = "web"):
    """Kicks off Google OAuth. iOS uses ASWebAuthenticationSession to open
    this URL; web frontend just navigates here. The platform query-string
    rides through Google as part of the signed `state` so the callback knows
    where to return the user."""
    state = auth_lib.encode_state(platform)
    return RedirectResponse(auth_lib.build_google_authorize_url(state), status_code=302)


@app.get("/auth/google/callback")
def google_callback(code: str, state: str):
    state_data = auth_lib.decode_state(state)
    platform = state_data.get("platform", "web")

    id_token_str = auth_lib.exchange_code_for_id_token(code)
    payload = auth_lib.verify_google_id_token(id_token_str)
    user = auth_lib.upsert_user_from_google(payload)

    # First time anyone signs in? Inherit every pre-auth session so the
    # agent's existing recordings aren't orphaned.
    if auth_lib.first_user_id() == user["id"]:
        auth_lib.migrate_orphan_sessions_to(user["id"], SESSIONS_DIR)

    jwt_str = auth_lib.mint_session_jwt(user)

    if platform == "ios":
        # Hand the JWT back through the custom URL scheme that
        # ASWebAuthenticationSession listens for.
        return RedirectResponse(
            f"{auth_lib.IOS_CUSTOM_SCHEME}://auth?token={jwt_str}", status_code=302
        )

    # Web: set httpOnly session cookie + bounce to the app.
    resp = RedirectResponse(url="/#/app", status_code=302)
    resp.set_cookie(
        key="fb_session",
        value=jwt_str,
        max_age=int(auth_lib.SESSION_TTL.total_seconds()),
        httponly=True,
        secure=True,
        samesite="lax",
        path="/",
    )
    return resp


@app.get("/auth/me")
def auth_me(user: dict = Depends(auth_lib.get_current_user)):
    """Used by web + iOS to check that the saved token/cookie is still
    valid and to render "signed in as X". Returns the Google identity
    plus the agent profile fields used by the Open House Report's email
    signature."""
    profile = auth_lib.profile_for(user["id"])
    return {
        "id": user["id"],
        "email": user.get("email"),
        "name": user.get("name"),
        "picture": user.get("picture"),
        # Agent profile — empty strings (not nil) so the iOS form binds
        # cleanly. headshot_url is a relative URL the client expands
        # against Config.backendURL.
        "profile": profile,
    }


@app.get("/me/insights")
def get_my_insights(
    period: str = "month",
    user: dict = Depends(auth_lib.get_current_user),
):
    """Aggregated stats across the agent's open-house history. Drives the
    Insights tab — totals + per-day-of-week / per-hour-of-day breakdowns
    + the 20 most recent sessions for the timeline. `period` is one of
    "week", "month", "year", "all"; unknown values fall through to "all"."""
    if period not in {"week", "month", "year", "all"}:
        period = "all"
    return stats_lib.query_insights(user["id"], period=period)


@app.get("/me/profile")
def get_my_profile(user: dict = Depends(auth_lib.get_current_user)):
    """Just the profile bits — separate from /auth/me for clarity and to
    avoid clients re-fetching identity when they only need the brokerage
    block."""
    return auth_lib.profile_for(user["id"])


@app.patch("/me/profile")
def patch_my_profile(
    payload: dict,
    user: dict = Depends(auth_lib.get_current_user),
):
    """Update editable profile fields (brokerage, license_number, phone,
    title, tagline). See auth.PROFILE_FIELDS for the whitelist — keys
    outside it are silently ignored."""
    return auth_lib.update_profile(user["id"], payload)


@app.post("/me/profile/headshot")
async def upload_my_headshot(
    file: UploadFile = File(...),
    user: dict = Depends(auth_lib.get_current_user),
):
    """Upload the agent's headshot — written into the email signature on
    every outgoing report. JPEG/PNG/HEIC/WebP supported; the iOS picker
    normally hands us a JPEG."""
    data = await file.read()
    if not data:
        raise HTTPException(400, "Empty file")
    if len(data) > 8 * 1024 * 1024:
        raise HTTPException(413, "Headshot must be under 8 MB")
    content_type = (file.content_type or "image/jpeg").lower()
    profile = auth_lib.save_headshot(user["id"], data, content_type)
    return profile


@app.delete("/me/profile/headshot")
def delete_my_headshot(user: dict = Depends(auth_lib.get_current_user)):
    return auth_lib.clear_headshot(user["id"])


@app.get("/me/profile/headshot")
def get_my_headshot(user: dict = Depends(auth_lib.get_current_user)):
    """Authenticated: own headshot for the iOS profile editor."""
    p = auth_lib.headshot_path_for(user["id"])
    if not p:
        raise HTTPException(404, "No headshot uploaded")
    media = "image/jpeg" if p.suffix.lower() == ".jpg" else f"image/{p.suffix.lstrip('.')}"
    return FileResponse(p, media_type=media)


@app.get("/me/profile/headshot/{user_id}")
def get_public_headshot(user_id: str):
    """Unauthenticated: serves any agent's headshot by id so the image
    can be referenced from emails the agent sends to homeowners (who
    don't have JWTs). The path-segment id requirement makes URL
    enumeration noticeably harder than a numeric counter would; if this
    ever needs to be locked down further we can add a signed token
    cache-buster."""
    p = auth_lib.headshot_path_for(user_id)
    if not p:
        raise HTTPException(404, "No headshot")
    media = "image/jpeg" if p.suffix.lower() == ".jpg" else f"image/{p.suffix.lstrip('.')}"
    return FileResponse(p, media_type=media)


@app.delete("/me")
def delete_my_account(user: dict = Depends(auth_lib.get_current_user)):
    """Permanently delete the signed-in user and every byte of theirs we
    hold — recorded sessions, transcripts, follow-up drafts, headshot,
    Gmail refresh token, agent profile, the lot.

    Returns a summary of what was wiped + clears the session cookie. The
    iOS app and the web frontend both surface this behind a typed
    confirmation so it can't be triggered by a single misclick.

    Once this returns, the JWT in the requester's cookie is no longer
    valid (decoding still succeeds, but `get_current_user` will 401
    because the user record is gone), so they're effectively logged out
    on every device immediately."""
    summary = auth_lib.delete_user(user["id"], SESSIONS_DIR)
    # Stats live in a separate sqlite/Postgres-style store; nuke this
    # user's rows too if the helper is available. Best-effort — the
    # stats DB only holds aggregates so a stale row here is not a
    # privacy issue, but cleaning up keeps the table honest.
    try:
        if hasattr(stats_lib, "delete_user_stats"):
            stats_lib.delete_user_stats(user["id"])  # type: ignore[attr-defined]
    except Exception as e:
        print(f"[delete_user] stats cleanup failed: {e}", flush=True)

    resp = JSONResponse({"ok": True, **summary})
    # Drop the web session cookie — iOS clients ignore this and discard
    # their stored JWT in the response handler instead.
    resp.delete_cookie("fb_session", path="/")
    return resp


@app.post("/auth/logout")
def auth_logout():
    resp = RedirectResponse(url="/", status_code=302)
    resp.delete_cookie("fb_session", path="/")
    return resp


# Native iOS path that bypasses ASWebAuthenticationSession — if the iOS
# app ever uses the Google Sign-In SDK directly, it can POST the id_token
# straight here and skip the redirect dance. Not used by the current
# webview flow but cheap to keep.
@app.post("/auth/google/ios")
def google_ios(payload: dict):
    id_token_str = (payload.get("id_token") or "").strip()
    if not id_token_str:
        raise HTTPException(400, "id_token is required")
    google_payload = auth_lib.verify_google_id_token(id_token_str)
    user = auth_lib.upsert_user_from_google(google_payload)
    if auth_lib.first_user_id() == user["id"]:
        auth_lib.migrate_orphan_sessions_to(user["id"], SESSIONS_DIR)
    return {
        "token": auth_lib.mint_session_jwt(user),
        "user": {
            "id": user["id"],
            "email": user.get("email"),
            "name": user.get("name"),
            "picture": user.get("picture"),
        },
    }


@app.post("/auth/demo")
def auth_demo(payload: dict):
    """Email + password sign-in used by App Store reviewers and demo days.

    The credential pair is configured via DEMO_EMAIL / DEMO_PASSWORD on the
    server — see auth_lib.authenticate_demo for the constant-time compare
    and the 503 behaviour when the env vars aren't set. Returns the same
    {token, user} shape as /auth/google/ios so iOS can reuse the post-auth
    code path verbatim.
    """
    email = (payload.get("email") or "").strip()
    password = payload.get("password") or ""
    user = auth_lib.authenticate_demo(email, password)
    if auth_lib.first_user_id() == user["id"]:
        auth_lib.migrate_orphan_sessions_to(user["id"], SESSIONS_DIR)
    return {
        "token": auth_lib.mint_session_jwt(user),
        "user": {
            "id": user["id"],
            "email": user.get("email"),
            "name": user.get("name"),
            "picture": user.get("picture"),
        },
    }


# --------------------------------------------------------------------------
# Gmail send — separate OAuth grant for the agent's sender account
# --------------------------------------------------------------------------

@app.get("/auth/gmail/start")
def gmail_start(
    request: Request,
    user_token: Optional[str] = None,
    platform: str = "ios",
):
    """Kicks off the Gmail-send OAuth grant. Two callers:

    - iOS via ASWebAuthenticationSession can't send the session cookie, so
      it passes its JWT as `user_token` and we decode it manually.
    - Web hits this from a same-origin link, so the `fb_session` cookie
      arrives automatically and we just delegate to get_current_user.

    The refresh token we capture is keyed on user_id, so once either path
    completes, the connection is visible from every device that signs in
    as the same Google account.
    """
    if platform not in ("ios", "web"):
        platform = "ios"

    user: Optional[dict] = None
    if user_token:
        payload = auth_lib.decode_session_jwt(user_token)
        user = auth_lib.get_user_by_id(payload.get("sub", ""))
    else:
        # Cookie path — only valid for web. We pull the cookie manually
        # here because /auth/gmail/start is a top-level navigation (no
        # custom Authorization header).
        cookie = request.cookies.get("fb_session")
        if cookie:
            try:
                payload = auth_lib.decode_session_jwt(cookie)
                user = auth_lib.get_user_by_id(payload.get("sub", ""))
            except HTTPException:
                user = None

    if user is None:
        raise HTTPException(401, "Not signed in")

    state = auth_lib.encode_gmail_state(user["id"], platform=platform)
    return RedirectResponse(auth_lib.build_gmail_authorize_url(state), status_code=302)


@app.get("/auth/gmail/callback")
def gmail_callback(code: str, state: str):
    state_data = auth_lib.decode_state(state)
    if state_data.get("kind") != "gmail":
        raise HTTPException(400, "OAuth state was not issued for Gmail")
    user_id = state_data.get("user_id")
    platform = state_data.get("platform", "ios")
    if not user_id:
        raise HTTPException(400, "OAuth state is missing user_id")

    tokens = auth_lib.exchange_code_for_full_tokens(code, auth_lib.GMAIL_REDIRECT_URI)
    refresh = tokens.get("refresh_token")
    if not refresh:
        # Should be impossible with prompt=consent + access_type=offline,
        # but Google has been known to drop it if the user re-grants too
        # fast. Tell the client so they can retry with a fresh consent.
        raise HTTPException(401, "Google did not return a refresh token — retry the connection")

    # Pull the agent's Gmail address out of the id_token so we can use it as
    # the From: header on every outgoing message.
    gmail_email = ""
    id_token_str = tokens.get("id_token")
    if id_token_str:
        try:
            id_payload = auth_lib.verify_google_id_token(id_token_str)
            gmail_email = id_payload.get("email", "") or ""
        except HTTPException:
            gmail_email = ""

    auth_lib.set_gmail_credential(user_id, refresh, gmail_email)
    if platform == "web":
        return RedirectResponse(url="/#/profile?gmail=connected", status_code=302)
    return RedirectResponse(
        f"{auth_lib.IOS_CUSTOM_SCHEME}://gmail-connected", status_code=302
    )


@app.get("/auth/gmail/status")
def gmail_status(current_user: dict = Depends(auth_lib.get_current_user)):
    return auth_lib.gmail_status_for(current_user["id"])


@app.post("/auth/gmail/disconnect")
def gmail_disconnect(current_user: dict = Depends(auth_lib.get_current_user)):
    auth_lib.clear_gmail_credential(current_user["id"])
    return {"connected": False}


@app.post("/auth/gmail/send_from")
def gmail_set_send_from(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Set (or clear) the Send-as alias that gets stamped on the From:
    header of every outgoing follow-up. Body: {address: "..." | null}.

    The agent has to verify the alias inside Gmail (Settings → Accounts →
    Send mail as) for it to actually appear on outgoing mail — Gmail
    silently rewrites unverified addresses. We don't try to verify here;
    if it doesn't work, the From: silently falls back to the connected
    mailbox.
    """
    address = payload.get("address")
    if address is not None and not isinstance(address, str):
        raise HTTPException(400, "address must be a string or null")
    auth_lib.set_gmail_send_from(current_user["id"], address)
    return auth_lib.gmail_status_for(current_user["id"])


# --------------------------------------------------------------------------
# Follow-up templates (per user) + draft preferences
# --------------------------------------------------------------------------

@app.get("/me/templates")
def list_my_templates(current_user: dict = Depends(auth_lib.get_current_user)):
    return {
        "templates": auth_lib.list_templates_for(current_user["id"]),
        "force_templates": auth_lib.force_templates_for(current_user["id"]),
    }


@app.post("/me/templates")
def create_my_template(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    return auth_lib.create_template(current_user["id"], payload)


@app.patch("/me/templates/{template_id}")
def update_my_template(
    template_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    return auth_lib.update_template(current_user["id"], template_id, payload)


@app.delete("/me/templates/{template_id}")
def delete_my_template(
    template_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    auth_lib.delete_template(current_user["id"], template_id)
    return {"deleted": True}


@app.post("/me/force_templates")
def set_my_force_templates(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    force = bool(payload.get("force"))
    auth_lib.set_force_templates(current_user["id"], force)
    return {"force_templates": force}


# --------------------------------------------------------------------------
# Offers / campaigns (per user)
# --------------------------------------------------------------------------


@app.get("/me/offers")
def list_my_offers(current_user: dict = Depends(auth_lib.get_current_user)):
    return {"offers": auth_lib.list_offers_for(current_user["id"])}


@app.post("/me/offers")
def create_my_offer(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    return auth_lib.create_offer(current_user["id"], payload)


@app.patch("/me/offers/{offer_id}")
def update_my_offer(
    offer_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    return auth_lib.update_offer(current_user["id"], offer_id, payload)


@app.delete("/me/offers/{offer_id}")
def delete_my_offer(
    offer_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    auth_lib.delete_offer(current_user["id"], offer_id)
    return {"deleted": offer_id}


@app.post("/me/offers/{offer_id}/enabled")
def set_my_offer_enabled(
    offer_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    return auth_lib.set_offer_enabled(
        current_user["id"], offer_id, bool(payload.get("enabled"))
    )


@app.post("/me/templates/{template_id}/enabled")
def set_my_template_enabled(
    template_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    return auth_lib.set_template_enabled(
        current_user["id"], template_id, bool(payload.get("enabled"))
    )


# --------------------------------------------------------------------------
# Leads AI agent — ask questions, propose batch sends
# --------------------------------------------------------------------------


def _collect_user_leads(user_id: str) -> list[dict]:
    """Flatten the user's sessions into a single lead list. Each entry
    carries enough context (session_id, address, lead_state) that the agent
    can build a concrete recipient list."""
    _hydrate_sessions_from_disk()
    out: list[dict] = []
    with _sessions_lock:
        for session in _sessions.values():
            if session.get("user_id") != user_id:
                continue
            result = session.get("result") or {}
            address = session.get("address") or ""
            for entry in result.get("visitors") or []:
                v = entry.get("visitor") or {}
                a = entry.get("analysis") or {}
                ls = entry.get("lead_state") or {}
                out.append({
                    "session_id": session.get("id"),
                    "address": address,
                    "visitor": {
                        "name": v.get("name") or "",
                        "speaker": v.get("speaker") or "",
                        "email": v.get("email") or "",
                        "phone": v.get("phone") or "",
                    },
                    "analysis": {
                        "summary": a.get("summary") or "",
                        "tag": a.get("tag") or "",
                        "score": a.get("score") or 0,
                        "signals": a.get("signals") or [],
                        "follow_up_draft": a.get("follow_up_draft") or "",
                    },
                    "lead_state": {
                        "status": ls.get("status") or "drafted",
                    },
                })
    return out


@app.post("/me/leads/agent")
def leads_agent_chat(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """One turn of the leads-AI conversation.

    Body: {message: str}
    Returns either:
      - {"kind": "answer", "text": "..."}
      - {"kind": "plan", "summary", "action": "send_email", "subject",
         "recipients": [{session_id, name, speaker, email, address, body}],
         "skipped": [{name, reason}]}

    Plan stays stateless on the server — the iOS client decides whether to
    show the plan, lets the agent confirm, and then calls
    /me/leads/agent/execute with the plan dict.
    """
    message = (payload.get("message") or "").strip()
    if not message:
        raise HTTPException(400, "message is required")

    leads = _collect_user_leads(current_user["id"])
    agent_name = (current_user.get("name") or "").strip()
    # Resolve @-references and gather the agent's full library of enabled
    # offers + templates so the AI can pick the best fit on its own when
    # nothing's explicitly @-tagged.
    ctx = _ai_context(current_user["id"], message)
    try:
        result = query_leads_agent(
            message=message,
            leads=leads,
            agent_name=agent_name,
            mentioned_offers=ctx["mentioned_offers"],
            mentioned_templates=ctx["mentioned_templates"],
            available_offers=ctx["available_offers"],
            available_templates=ctx["available_templates"],
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"AI agent failed: {exc}")
    if not isinstance(result, dict) or "kind" not in result:
        raise HTTPException(502, "AI agent returned an unexpected response")
    return result


@app.post("/me/leads/agent/execute")
def leads_agent_execute(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Execute a plan returned by /me/leads/agent.

    Body: {plan: {action: "send_email", subject, recipients: [...]}}

    Sends one email per recipient via the user's connected Gmail and
    records each as a sent_email in the matching visitor's lead_state.
    Returns {sent: N, failed: [{name, error}]}. A failure on one recipient
    does NOT roll back successful sends — the agent gets a per-recipient
    failure list to retry by hand if needed.
    """
    plan = payload.get("plan") or {}
    if not isinstance(plan, dict):
        raise HTTPException(400, "plan must be an object")
    if plan.get("action") != "send_email":
        raise HTTPException(400, "Only action=send_email is supported")
    recipients = plan.get("recipients") or []
    if not isinstance(recipients, list) or not recipients:
        raise HTTPException(400, "plan.recipients must be a non-empty list")
    subject = (plan.get("subject") or "").strip()
    if not subject:
        raise HTTPException(400, "plan.subject is required")

    sent_count = 0
    failed: list[dict] = []
    for r in recipients:
        try:
            session_id = (r.get("session_id") or "").strip()
            name = (r.get("name") or "").strip()
            speaker = (r.get("speaker") or "").strip()
            email = (r.get("email") or "").strip()
            body = (r.get("body") or "").strip()
            if not email or not body or not session_id or not name:
                failed.append({
                    "name": name or "(unknown)",
                    "error": "missing email/body/session/name on recipient",
                })
                continue

            # Authorize: only send for sessions the user actually owns.
            with _sessions_lock:
                session = _sessions.get(session_id)
                if session is None:
                    path = SESSIONS_DIR / session_id / "session.json"
                    if path.exists():
                        session = json.loads(path.read_text())
                        _sessions[session_id] = session
                if session is None or session.get("user_id") != current_user["id"]:
                    failed.append({"name": name, "error": "session not found or not yours"})
                    continue

            gmail_result = auth_lib.send_gmail_email(
                user_id=current_user["id"],
                to=email,
                subject=subject,
                body=body,
            )
            message_id = gmail_result.get("id")
            sent_count += 1

            # Record send + flip status on the matching visitor.
            with _sessions_lock:
                session = _sessions.get(session_id) or session
                result = session.get("result") or {}
                for entry in result.get("visitors") or []:
                    v = entry.get("visitor") or {}
                    if (v.get("name") or "") == name and (v.get("speaker") or "") == speaker:
                        now_iso = datetime.now(timezone.utc).isoformat()
                        state = _ensure_lead_state(entry)
                        state["status"] = "sent"
                        state["updated_at"] = now_iso
                        if not state.get("sent_at"):
                            state["sent_at"] = now_iso
                        state["sent_emails"].append({
                            "id": str(uuid.uuid4()),
                            "to": email,
                            "subject": subject,
                            "body": body,
                            "sent_at": now_iso,
                            "message_id": message_id,
                            "scheduled": False,
                            "source": "agent_bulk",
                        })
                        entry["lead_state"] = state
                        _persist(session_id)
                        break
        except HTTPException as exc:
            failed.append({"name": r.get("name") or "(unknown)", "error": exc.detail})
        except Exception as exc:  # noqa: BLE001
            failed.append({"name": r.get("name") or "(unknown)", "error": str(exc)})

    return {"sent": sent_count, "failed": failed}


# --------------------------------------------------------------------------
# Copilot — global "ask anything" agent surfaced on the iOS home screen
# --------------------------------------------------------------------------
#
# Stateless per turn. iOS sends the full chat history (text-only) and we
# replay it through Claude with the copilot tool set. Reads only — no
# email sends or session mutations here. When the model decides the user
# wants to navigate somewhere, it calls the open_screen tool and we
# return the resulting `action` so the client can route on tap.


@app.post("/agent/chat")
def copilot_chat(
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """One turn of the Copilot conversation.

    Body: {turns: [{role: "user"|"assistant", text: str}, ...]}
    The last turn must be from the user.

    Returns:
      {
        "text": "...",            # plain-text reply
        "action": {...} | null,   # optional {target, session_id?, name?, speaker?}
        "tool_calls": [{"name", "summary"}, ...]
      }
    """
    turns = payload.get("turns") or []
    if not isinstance(turns, list) or not turns:
        raise HTTPException(400, "turns is required")
    if turns[-1].get("role") != "user":
        raise HTTPException(400, "Last turn must be from the user")

    # Hydrate so the tool helpers see every session that's been written to
    # disk (cold-start safety — the in-memory cache may not have been
    # touched yet by any prior request this process handled).
    _hydrate_sessions_from_disk()
    user_id = current_user["id"]

    def _list_user_sessions() -> list[dict]:
        with _sessions_lock:
            return [
                dict(s)
                for s in _sessions.values()
                if s.get("user_id") == user_id
            ]

    def _user_insights(period: str) -> dict:
        return stats_lib.query_insights(user_id, period=period)

    agent_name = (current_user.get("name") or "").strip()

    try:
        result = run_copilot_turn(
            turns=turns,
            agent_name=agent_name,
            list_user_sessions=_list_user_sessions,
            get_user_insights=_user_insights,
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(502, f"Copilot failed: {exc}")
    return result


# --------------------------------------------------------------------------
# Contact verification for the kiosk sign-in form
# --------------------------------------------------------------------------

# Lightweight email + phone validation called as the guest fills out the
# iPad sign-in form. We never block on this — the iOS client shows live
# state ("checking", "looks good", "looks off") so the guest can correct
# obvious typos before tapping Done.

import re as _re
import phonenumbers as _phonenumbers
from phonenumbers import NumberParseException as _NumberParseException
import dns.resolver as _dns_resolver
import dns.exception as _dns_exception

_EMAIL_REGEX = _re.compile(
    r"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"
)

# Domains we've seen in disposable-email lists. The guest can still submit
# but we flag them so the agent knows the lead is junky.
_DISPOSABLE_EMAIL_DOMAINS = {
    "mailinator.com", "guerrillamail.com", "10minutemail.com", "tempmail.com",
    "yopmail.com", "throwawaymail.com", "trashmail.com", "fakeinbox.com",
    "maildrop.cc", "getnada.com", "sharklasers.com", "dispostable.com",
}


def _verify_email(raw: str) -> dict:
    s = (raw or "").strip().lower()
    if not s:
        return {"valid": False, "reason": "Email is required"}
    if not _EMAIL_REGEX.match(s):
        return {"valid": False, "reason": "Doesn't look like an email"}
    domain = s.split("@", 1)[1]
    if domain in _DISPOSABLE_EMAIL_DOMAINS:
        return {"valid": False, "reason": "Disposable inbox — won't reach you"}
    try:
        answers = _dns_resolver.resolve(domain, "MX", lifetime=2.5)
        if not list(answers):
            return {"valid": False, "reason": "Domain can't receive mail"}
    except _dns_resolver.NXDOMAIN:
        return {"valid": False, "reason": "Domain doesn't exist"}
    except _dns_resolver.NoAnswer:
        # Some domains use A-only mail — uncommon but valid per RFC 5321.
        try:
            _dns_resolver.resolve(domain, "A", lifetime=2.5)
        except _dns_exception.DNSException:
            return {"valid": False, "reason": "Domain doesn't exist"}
    except _dns_exception.DNSException:
        # Timeout / network issue — don't block the guest, just say "couldn't
        # check". The iOS client treats unknown as soft-valid.
        return {"valid": True, "reason": "unverified", "checked": False, "formatted": s}
    return {"valid": True, "reason": "ok", "formatted": s}


def _verify_phone(raw: str) -> dict:
    s = (raw or "").strip()
    if not s:
        return {"valid": False, "reason": "Phone is required"}
    try:
        parsed = _phonenumbers.parse(s, "US")
    except _NumberParseException:
        return {"valid": False, "reason": "Doesn't look like a phone number"}
    if not _phonenumbers.is_valid_number(parsed):
        return {"valid": False, "reason": "Not a valid US number"}
    formatted = _phonenumbers.format_number(
        parsed, _phonenumbers.PhoneNumberFormat.NATIONAL
    )
    e164 = _phonenumbers.format_number(
        parsed, _phonenumbers.PhoneNumberFormat.E164
    )
    return {"valid": True, "reason": "ok", "formatted": formatted, "e164": e164}


@app.post("/verify/contact")
def verify_contact(payload: dict):
    """Validate an email and/or phone the guest just typed into the kiosk.

    Body: {email?, phone?}. Either field is optional — only the ones that
    are present are checked, so the iOS client can debounce per-field.

    Returns: {email?: {valid, reason, formatted?}, phone?: {valid, reason,
    formatted?, e164?}}. valid=true with reason="unverified" means we
    couldn't reach DNS to do an MX check; the client treats that as
    soft-valid so a flaky network doesn't block sign-ins.
    """
    out: dict = {}
    if "email" in payload:
        out["email"] = _verify_email(payload.get("email") or "")
    if "phone" in payload:
        out["phone"] = _verify_phone(payload.get("phone") or "")
    return out


_sessions: dict[str, dict] = {}
# Re-entrant lock so endpoints that need the lock AND call helpers like
# `_load_session` (which also takes the lock) don't deadlock. A plain
# threading.Lock would self-deadlock as soon as a handler nested two
# `with _sessions_lock:` blocks on the same thread — refine_visitor_draft
# and update_visitor_contact hit this and hung forever, surfacing as
# "request timed out" on iOS. RLock counts ownership per thread.
_sessions_lock = threading.RLock()


def _persist(session_id: str) -> None:
    path = SESSIONS_DIR / session_id / "session.json"
    session = _sessions[session_id]
    path.write_text(json.dumps(session, indent=2, default=str))
    # Capture stats for the Insights dashboard. Idempotent — the helper
    # only writes for sessions with status=ready, and a re-call after
    # (e.g.) the agent sends the report just updates the existing row.
    # Wrapped in try/except so a stats failure can never break the
    # session-save path the agent's UI depends on.
    try:
        user_id = session.get("user_id")
        if user_id and session.get("status") == "ready":
            stats_lib.capture_session_stats(session, user_id)
    except Exception as exc:  # noqa: BLE001
        # Log but swallow — Insights can be re-derived from disk via
        # backfill_from_disk() on the next backend start.
        print(f"[stats] capture failed for {session_id}: {exc}", flush=True)


def _update(session_id: str, **updates) -> None:
    with _sessions_lock:
        _sessions[session_id].update(updates)
        _persist(session_id)


def _process(session_id: str, audio_path: Optional[Path], mock_path: Optional[Path], visitors_path: Optional[Path], speakers_expected: Optional[int] = None, script_id: Optional[str] = None, user_id: Optional[str] = None, analysis_depth: str = "full", check_in_id: Optional[str] = None) -> None:
    """analysis_depth:
      - "full":  re-transcribe + diarize + run per-visitor Claude analysis +
                 script coverage. Used on session creation and final end.
      - "light": same transcription + diarization + coverage, but skip
                 per-visitor Claude analysis. Visitors that existed in the
                 prior result keep their cached analysis; new visitors get
                 a placeholder analysis filled in on the next full pass.
                 Used by mid-session snapshot ticks to keep cost down."""
    try:
        if mock_path:
            transcript = load_mock_transcript(mock_path)
        else:
            assert audio_path is not None
            transcript = transcribe_with_speakers(audio_path, speakers_expected=speakers_expected)

        # Bail out before the Claude pipeline if AssemblyAI couldn't pick out
        # any speech — feeding an empty utterances list to identify/analyze
        # builds a user message with empty content, which Anthropic rejects
        # with a 400 and leaks to the agent's UI as a raw API error. Surface
        # the canned "silent recording" message via _friendly_error instead.
        if not (transcript.utterances or []):
            raise Exception(
                "The recording was silent — no speech detected. "
                "Check the mic / unmute and try again."
            )

        identification = identify_agent_and_visitors(transcript, visitors_path)

        if not mock_path:
            # Auto-correct diarization undercount. AssemblyAI without a
            # `speakers_expected` hint tends to collapse close-mic'd voices —
            # e.g. an agent + two friends all sitting near the phone get
            # clustered as just two speakers. When Claude's read of the
            # transcript suggests there were actually more distinct people,
            # re-transcribe with that count as a hint. Only kicks in when the
            # caller didn't already pass a hint (so manual Re-analyze still
            # wins) and only allows one auto-retry to keep cost bounded.
            if (
                speakers_expected is None
                and identification.suspected_total > identification.detected_total
            ):
                # Cap the hint at 10 to avoid hallucinated 16-way splits eating
                # a chunk of AAI quota on a recording with two people.
                hint = min(identification.suspected_total, 10)
                print(
                    f"[{session_id}] diarization undercount: detected="
                    f"{identification.detected_total}, suspected={hint} — "
                    f"re-transcribing with speakers_expected={hint}",
                    flush=True,
                )
                transcript = transcribe_with_speakers(audio_path, speakers_expected=hint)
                identification = identify_agent_and_visitors(transcript, visitors_path)

        # Lead state from a prior run (if this is a reanalyze) — keyed by
        # (name, speaker) so the agent doesn't lose their "sent / snoozed /
        # archived" markers just because we re-ran diarization.
        # We also stash the prior `analysis` dicts so light snapshots can
        # reuse them instead of paying for another Claude pass.
        prior_states: dict[tuple[str, str], dict] = {}
        prior_analyses: dict[tuple[str, str], dict] = {}
        with _sessions_lock:
            prior_visitors = ((_sessions.get(session_id) or {}).get("result") or {}).get("visitors") or []
        for entry in prior_visitors:
            v = entry.get("visitor") or {}
            key = (v.get("name") or "", v.get("speaker") or "")
            state = entry.get("lead_state")
            if state:
                prior_states[key] = state
            an = entry.get("analysis")
            if an:
                prior_analyses[key] = an

        # Pull this agent's follow-up templates + their forced-mode preference
        # so analyze_visitor can bake them into the initial AI draft.
        templates = auth_lib.list_templates_for(user_id) if user_id else []
        force_templates = auth_lib.force_templates_for(user_id) if user_id else False
        # The agent's own past follow-ups become the authoritative voice
        # anchor in the prompt — beats any generic "be casual" instruction.
        voice_samples = auth_lib.voice_samples_for(user_id) if user_id else []

        now_iso = datetime.now(timezone.utc).isoformat()
        visitors_out = []
        for visitor in identification.matched_visitors:
            v_dict = visitor.model_dump(mode="json")
            key = (v_dict.get("name") or "", v_dict.get("speaker") or "")

            if analysis_depth == "light":
                # Reuse a prior analysis if we have one for this (name, speaker).
                # New visitors get a stub analysis — agent still sees them in
                # the lead list, but their summary/draft fill in on the final
                # full pass at end of session.
                analysis_dict = prior_analyses.get(key) or {
                    "summary": "",
                    "tag": "Browser",
                    "tag_reason": "Pending full analysis at session end.",
                    "score": 0,
                    "signals": [],
                    "follow_up_draft": "",
                    "words_spoken": sum(
                        len(u.text.split())
                        for u in (transcript.utterances or [])
                        if u.speaker == visitor.speaker
                    ),
                }
            else:
                analysis = analyze_visitor(
                    transcript, visitor, DEFAULT_TAGS,
                    templates=templates,
                    force_templates=force_templates,
                    voice_samples=voice_samples,
                )
                analysis_dict = analysis.model_dump()

            lead_state = prior_states.get(key) or {
                "status": "drafted",
                "sent_at": None,
                "snoozed_until": None,
                "updated_at": now_iso,
            }
            visitors_out.append({
                "visitor": v_dict,
                "analysis": analysis_dict,
                "lead_state": lead_state,
            })

        # Script coverage — only runs if the agent attached a script to this
        # session. Grades the agent's utterances against the script steps.
        script_coverage_out = None
        script = get_script(script_id)
        if script is not None:
            try:
                coverage = grade_against_script(
                    transcript, script, identification.agent_speaker
                )
                script_coverage_out = coverage.model_dump()
            except Exception as ce:
                # Don't fail the whole session if coverage grading errors —
                # surface the error inline so the UI can show it.
                script_coverage_out = {
                    "script_id": script.id,
                    "script_name": script.name,
                    "error": str(ce),
                }

        # Speaker-attributed turn list — needed by the iOS Summary so the
        # agent can see what they said and who they were talking to. Raw
        # `transcript.text` is just a flat string with no turn boundaries.
        utterances_out = [
            {
                "speaker": u.speaker,
                "text": u.text,
                "start_ms": int(getattr(u, "start", 0) or 0),
                "end_ms": int(getattr(u, "end", 0) or 0),
            }
            for u in (transcript.utterances or [])
        ]

        now_finish = datetime.now(timezone.utc).isoformat()
        updates: dict = dict(
            status="ready",
            completed_at=now_finish,
            # `last_snapshot_at` ticks every pass so the iPad can render
            # "Updated 5m ago"; `is_live` tells the client whether more
            # snapshots are still on the way (light) or the agent has
            # ended the session (full).
            last_snapshot_at=now_finish,
            is_live=(analysis_depth == "light"),
            result={
                "agent_speaker": identification.agent_speaker,
                "unmatched_speakers": identification.unmatched_speakers,
                "visitors": visitors_out,
                "full_transcript": transcript.text,
                "utterances": utterances_out,
                "script_coverage": script_coverage_out,
            },
        )
        # If this run was triggered by a companion check-in, stamp the
        # completed id so the companion's polling loop knows its requested
        # snapshot finished. Also clear the pending flag — the iPhone
        # polling loop uses pending != last to decide whether to act.
        if check_in_id:
            updates["last_check_in_id"] = check_in_id
            updates["pending_check_in_id"] = None

        # Weather enrichment — only on the FINAL "full" pass (not the
        # mid-session "light" snapshots that fire every few minutes,
        # which would burn Open-Meteo for no UX gain). Pulled here so
        # the weather block lands in the same persist that flips status
        # to "ready". Fail-soft: a missing lat/lon or Open-Meteo glitch
        # never blocks the session from going ready.
        if analysis_depth != "light":
            with _sessions_lock:
                projected = dict(_sessions.get(session_id) or {})
                projected.update(updates)
            try:
                weather = enrich_session_with_weather(projected)
                if weather is not None:
                    updates["weather"] = weather
            except Exception as wexc:  # noqa: BLE001
                print(f"[weather] enrich failed for {session_id}: {wexc}", flush=True)

            # Auto-name unaddressed sessions so the agent's list shows
            # something memorable instead of "Session a1b2c3d4". Only fires
            # when both `name` (agent nickname) and `address` are empty —
            # if either is set, the display chain in Models.swift already
            # has something better to show.
            if not (projected.get("name") or "").strip() and not (projected.get("address") or "").strip():
                try:
                    coined = generate_session_name(transcript, identification.agent_speaker)
                    if coined:
                        updates["name"] = coined
                except Exception as nexc:  # noqa: BLE001
                    print(f"[name] auto-name failed for {session_id}: {nexc}", flush=True)

        _update(session_id, **updates)
    except Exception as e:
        err_updates: dict = dict(
            status="error",
            error=_friendly_error(str(e)),
            completed_at=datetime.now(timezone.utc).isoformat(),
        )
        # Even on failure we should clear the pending flag so the companion
        # can request another check-in instead of being stuck "Listening…"
        # forever. Stamp last_check_in_id too so its polling loop unblocks.
        if check_in_id:
            err_updates["last_check_in_id"] = check_in_id
            err_updates["pending_check_in_id"] = None
        _update(session_id, **err_updates)


def _friendly_error(raw: str) -> str:
    """Translate raw provider errors into something a real estate agent can
    actually act on. Falls through to the original string if nothing maps —
    we still want the technical detail somewhere, just not as the only
    thing the user sees."""
    lower = raw.lower()
    if "language_detection" in lower and "no spoken audio" in lower:
        return (
            "We couldn't hear any speech in this recording. "
            "The mic may have been muted or too far from the conversation — "
            "try recording again, ideally with the iPad on a table near the group."
        )
    if "no spoken audio" in lower or "silent" in lower:
        return "The recording was silent. Try again with the mic closer to the conversation."
    if "audio is too short" in lower or "too short" in lower:
        return "The recording was too short to analyze. Try one that's at least 15 seconds long."
    if "rate limit" in lower or "429" in lower:
        return "We're being rate-limited by the transcription service. Wait a minute and try again."
    if "timeout" in lower or "timed out" in lower:
        return "The transcription service took too long to respond. Try the session again."
    return raw


@app.post("/sessions")
async def create_session(
    audio: Optional[UploadFile] = File(None),
    visitors: Optional[UploadFile] = File(None),
    mock_transcript: Optional[UploadFile] = File(None),
    address: Optional[str] = Form(None),
    name: Optional[str] = Form(None),
    speakers_expected: Optional[int] = Form(None),
    script_id: Optional[str] = Form(None),
    homeowner_email: Optional[str] = Form(None),
    homeowner_name: Optional[str] = Form(None),
    # Geocoded property point — iOS resolves the address via CLGeocoder
    # before upload and passes lat/lon here. Drives Open-Meteo weather
    # enrichment when the session reaches "ready". Optional: mock flows
    # and addresses we can't geocode still create sessions cleanly.
    latitude: Optional[float] = Form(None),
    longitude: Optional[float] = Form(None),
    current_user: dict = Depends(auth_lib.get_current_user),
):
    if not audio and not mock_transcript:
        raise HTTPException(400, "Provide audio or mock_transcript")
    if audio and mock_transcript:
        raise HTTPException(400, "Send only one of audio or mock_transcript")

    session_id = str(uuid.uuid4())
    session_dir = SESSIONS_DIR / session_id
    session_dir.mkdir()

    # iOS path: no kiosk CSV. The pipeline will synthesize visitors from the
    # diarized speakers in that case.
    visitors_path: Optional[Path] = None
    if visitors is not None:
        visitors_path = session_dir / "visitors.csv"
        visitors_path.write_bytes(await visitors.read())

    audio_path: Optional[Path] = None
    mock_path: Optional[Path] = None
    if audio:
        audio_path = session_dir / (audio.filename or "audio.m4a")
        audio_path.write_bytes(await audio.read())
    if mock_transcript:
        mock_path = session_dir / "mock_transcript.json"
        mock_path.write_bytes(await mock_transcript.read())

    session = {
        "id": session_id,
        "status": "processing",
        "address": (address or "").strip() or None,
        # Agent-supplied nickname for the session ("Yellow craftsman on Elm").
        # Display fallback chain everywhere is `name -> address -> date`.
        # Editable later via PATCH /sessions/{id}.
        "name": (name or "").strip() or None,
        "script_id": script_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "completed_at": None,
        "result": None,
        "error": None,
        "user_id": current_user["id"],
        # Homeowner identity for the eventual Open House Report. Optional at
        # session-create time; can be filled in later via PATCH /homeowner.
        "homeowner_email": (homeowner_email or "").strip() or None,
        "homeowner_name": (homeowner_name or "").strip() or None,
        # Geocoded property point — drives Open-Meteo weather enrichment
        # at status="ready". nil → no weather (we never fall back to
        # city-level by design).
        "latitude": latitude,
        "longitude": longitude,
    }
    with _sessions_lock:
        _sessions[session_id] = session
        _persist(session_id)

    threading.Thread(
        target=_process,
        args=(session_id, audio_path, mock_path, visitors_path, speakers_expected, script_id, current_user["id"]),
        daemon=True,
    ).start()
    return {"id": session_id, "status": "processing"}


@app.post("/sessions/{session_id}/snapshot")
async def snapshot_session(
    session_id: str,
    audio: UploadFile = File(...),
    speakers_expected: Optional[int] = Form(None),
    analysis_depth: str = Form("light"),
    check_in_id: Optional[str] = Form(None),
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Mid-session audio snapshot. Pass `analysis_depth=light` (default) to
    re-transcribe + re-grade script coverage without paying for a per-visitor
    Claude pass; `full` runs the whole pipeline (used by the final upload
    when the agent ends the session). Replaces the session's audio file on
    disk so the next snapshot's diarization sees the full audio history.

    `check_in_id` is optional. When set, this snapshot is fulfilling a
    companion-device check-in request — `_process` stamps it onto the
    session as `last_check_in_id` when finished so the companion's polling
    loop knows the request completed.
    """
    if analysis_depth not in ("light", "full"):
        raise HTTPException(400, "analysis_depth must be 'light' or 'full'")
    session_dir = SESSIONS_DIR / session_id
    if not session_dir.exists():
        raise HTTPException(404, f"Session {session_id} not found")
    with _sessions_lock:
        if session_id not in _sessions:
            path = session_dir / "session.json"
            if path.exists():
                _sessions[session_id] = json.loads(path.read_text())
        session = _sessions.get(session_id)
        _require_owner(session, current_user, session_id)
        existing_script_id = session.get("script_id")

    # Replace the in-flight audio with whatever the client just uploaded.
    # We accept the entire concatenated audio so far (diarization needs the
    # full history to keep speaker labels consistent across snapshots).
    #
    # Stream the body to disk in 64 KB chunks instead of `await audio.read()`
    # which would slurp the entire body (40+ MB on long finalize uploads)
    # into RAM — on a 512 MB Render worker that's enough to push us over
    # the limit when combined with the VAD/PyAV decode that runs next.
    audio_path: Optional[Path] = None
    for candidate in session_dir.iterdir():
        if candidate.suffix.lower() in {".m4a", ".mp4", ".wav", ".mp3", ".aac"}:
            audio_path = candidate
            break
    if audio_path is None:
        audio_path = session_dir / (audio.filename or "audio.m4a")
    import shutil as _shutil
    with open(audio_path, "wb") as out:
        _shutil.copyfileobj(audio.file, out, length=64 * 1024)
    if audio_path.stat().st_size == 0:
        raise HTTPException(400, "Empty audio upload")

    with _sessions_lock:
        _sessions[session_id].update({
            "status": "processing",
            "speakers_expected": speakers_expected,
        })
        _persist(session_id)

    threading.Thread(
        target=_process,
        args=(session_id, audio_path, None, None, speakers_expected, existing_script_id, current_user["id"], analysis_depth, check_in_id),
        daemon=True,
    ).start()
    return {"id": session_id, "status": "processing", "analysis_depth": analysis_depth}


# --------------------------------------------------------------------------
# Live companion — second-device coaching view
# --------------------------------------------------------------------------
#
# The agent opens openhousecopilot.com/#/live on their laptop / iPad
# while their phone records. Same Google account = same auth cookie, so
# no pairing dance: the page just asks "what session is live right now?"
# and renders the coaching UI for it.
#
# Flow:
#   1. Companion device (laptop) loads #/live; auth via existing cookie.
#   2. GET /live/sessions/current → most recent is_live=true session.
#   3. Polls GET /live/sessions/{id} every 3s for the slim view.
#   4. Tapping "Check in" → POST /live/sessions/{id}/check_in → backend
#      stamps session.pending_check_in_id.
#   5. iPhone's polling loop sees pending_check_in_id != last_handled →
#      triggers a snapshot tagged with that id; _process stamps
#      last_check_in_id when complete.
#   6. Companion's polling loop sees last_check_in_id == requested →
#      shows the fresh coverage.

def _live_session_view(session: dict) -> dict:
    """Slim, companion-safe projection of a session. Strips lead PII
    (visitor names, emails, follow-up drafts) and only exposes what the
    coaching view actually needs: address, liveness, snapshot timestamps,
    pending/last check-in ids, and the existing script-coverage block."""
    result = session.get("result") or {}
    return {
        "id": session.get("id"),
        "address": session.get("address"),
        "name": session.get("name"),
        "is_live": session.get("is_live"),
        "status": session.get("status"),
        "started_at": session.get("created_at"),
        "last_snapshot_at": session.get("last_snapshot_at"),
        "pending_check_in_id": session.get("pending_check_in_id"),
        "last_check_in_id": session.get("last_check_in_id"),
        "script_coverage": result.get("script_coverage"),
        "error": session.get("error"),
    }


@app.get("/live/sessions/current")
def get_current_live_session(
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Returns the agent's most-recently-snapshotted in-flight session, or
    {session: null} if none are live. The companion page polls this on
    load to find what to render."""
    _hydrate_sessions_from_disk()
    with _sessions_lock:
        candidates = [
            s for s in _sessions.values()
            if s.get("user_id") == current_user["id"] and s.get("is_live")
        ]
    if not candidates:
        return {"session": None}
    candidates.sort(
        key=lambda s: s.get("last_snapshot_at") or s.get("created_at") or "",
        reverse=True,
    )
    return {"session": _live_session_view(candidates[0])}


@app.get("/live/sessions/{session_id}")
def get_live_session(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Slim companion read of one session. Same-account auth (cookie for
    web, bearer for iOS) — owner check via `_require_owner`."""
    session = _load_session(session_id)
    _require_owner(session, current_user, session_id)
    return _live_session_view(session)


@app.post("/live/sessions/{session_id}/check_in")
def request_live_check_in(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Companion taps "Check in" → stamp a new pending_check_in_id onto
    the session. The iPhone's polling loop sees it and kicks a snapshot.
    If a check-in is already pending, return that one instead of stacking
    — the UI shows "Listening…" either way and there's no value in
    queueing.
    """
    with _sessions_lock:
        session = _sessions.get(session_id)
        if session is None:
            path = SESSIONS_DIR / session_id / "session.json"
            if path.exists():
                session = json.loads(path.read_text())
                _sessions[session_id] = session
        _require_owner(session, current_user, session_id)
        pending = session.get("pending_check_in_id")
        if pending:
            return {"check_in_id": pending, "queued": False}
        new_id = str(uuid.uuid4())
        session["pending_check_in_id"] = new_id
        session["pending_check_in_requested_at"] = datetime.now(timezone.utc).isoformat()
        _persist(session_id)
    return {"check_in_id": new_id, "queued": True}


@app.get("/scripts")
def list_scripts():
    """Compact list of available preset scripts for the iOS Setup picker."""
    return {"scripts": list_scripts_summary()}


@app.get("/scripts/{script_id}")
def get_script_detail(script_id: str):
    """Full script with all steps — used by the Setup screen to preview
    what the agent is about to attach."""
    s = get_script(script_id)
    if s is None:
        raise HTTPException(404, f"Script {script_id} not found")
    return s.model_dump()


@app.post("/scripts")
async def create_script(payload: dict):
    """Persist a new user-created script. Body shape:
    { "name": str, "description": str, "steps": [{label, quote, intent}, ...] }"""
    name = (payload.get("name") or "").strip()
    if not name:
        raise HTTPException(400, "name is required")
    description = (payload.get("description") or "").strip()
    steps = payload.get("steps") or []
    if not isinstance(steps, list) or not steps:
        raise HTTPException(400, "at least one step is required")
    script = save_user_script(name=name, description=description, steps=steps)
    return script.model_dump()


@app.patch("/scripts/{script_id}")
async def edit_script(script_id: str, payload: dict):
    """Update a script. Body shape matches `POST /scripts`:
    { name, description, steps[] }. Works for both user-created scripts and
    presets — editing a preset writes an override file so the agent's tweaks
    win on subsequent reads; DELETE the same id later to reset to factory."""
    name = (payload.get("name") or "").strip()
    if not name:
        raise HTTPException(400, "name is required")
    description = (payload.get("description") or "").strip()
    steps = payload.get("steps") or []
    if not isinstance(steps, list) or not steps:
        raise HTTPException(400, "at least one step is required")
    updated = update_user_script(script_id, name=name, description=description, steps=steps)
    if updated is None:
        raise HTTPException(404, f"Script {script_id} not found")
    return updated.model_dump()


@app.delete("/scripts/{script_id}")
def remove_script(script_id: str):
    # User scripts: delete the file. Presets: drop any override file, which
    # resets the script to the factory version bundled in pipeline/scripts.py.
    # 404 only when the id is neither a known preset nor on disk.
    if not delete_user_script(script_id):
        raise HTTPException(404, f"Script {script_id} not found")
    return {"deleted": script_id}


# ── Agent-driven script editing ──────────────────────────────────────────
#
# The in-app editor is read-only now; all mutations route through Claude
# via tool_use. The model never replies in prose — it MUST call the
# save_script tool, which is shaped like the Script pydantic model.
# Before each mutation we snapshot the pre-edit state to a single-slot
# revisions dir so /undo can roll back one step.

def _save_script_to_disk(script: Script) -> Script:
    """Persist a Script (presets land as overrides at the same id; user
    scripts overwrite their existing file). Mirrors save_user_script /
    update_user_script's write path without re-validating step shapes,
    since the agent already produced a fully-formed Script."""
    (USER_SCRIPTS_DIR / f"{script.id}.json").write_text(
        json.dumps(script.model_dump(), indent=2)
    )
    return script


@app.post("/scripts/agent-edit/{script_id}")
async def agent_edit_script_endpoint(script_id: str, payload: dict):
    """Mutate an existing script via a natural-language instruction.
    Body: { "instruction": "..." }. Returns the updated Script. The pre-edit
    state is snapshotted so the next call to /scripts/{id}/undo reverts it."""
    instruction = (payload.get("instruction") or "").strip()
    if not instruction:
        raise HTTPException(400, "instruction is required")
    current = get_script(script_id)
    if current is None:
        raise HTTPException(404, f"Script {script_id} not found")
    try:
        snapshot_revision(current)
        updated = agent_edit_script(current, instruction)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"Agent edit failed: {e}")
    _save_script_to_disk(updated)
    out = updated.model_dump()
    out["can_undo"] = True
    return out


@app.post("/scripts/agent-create")
async def agent_create_script_endpoint(payload: dict):
    """Create a new script from a natural-language brief.
    Body: { "instruction": "..." }. Returns the new Script. The snapshot
    marks the id as 'absent' pre-edit so undo deletes it."""
    instruction = (payload.get("instruction") or "").strip()
    if not instruction:
        raise HTTPException(400, "instruction is required")
    new_id = f"user_{uuid.uuid4().hex[:10]}"
    try:
        created = agent_create_script(new_id, instruction)
        snapshot_absent(new_id)
    except Exception as e:  # noqa: BLE001
        raise HTTPException(502, f"Agent create failed: {e}")
    _save_script_to_disk(created)
    out = created.model_dump()
    out["can_undo"] = True
    return out


@app.post("/scripts/{script_id}/undo")
def undo_script(script_id: str):
    """Restore the pre-edit snapshot for `script_id`. If the snapshot is the
    'absent' sentinel (i.e. the script was created by the agent), the
    current script is deleted instead. Returns { "deleted": id } or the
    restored Script."""
    if not has_revision(script_id):
        raise HTTPException(404, f"No undo available for {script_id}")
    try:
        restored = restore_revision(script_id)
    except FileNotFoundError:
        raise HTTPException(404, f"No undo available for {script_id}")
    if restored is None:
        # Pre-edit state was 'absent' — the script was created by the agent.
        # Undo = delete it; the user is back to where they started.
        delete_user_script(script_id)
        return {"deleted": script_id}
    _save_script_to_disk(restored)
    out = restored.model_dump()
    out["can_undo"] = False
    return out


@app.post("/sessions/{session_id}/reprocess")
async def reprocess_session(
    session_id: str,
    speakers_expected: Optional[int] = Form(None),
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Re-run the pipeline on a saved audio file with a (usually different)
    speakers_expected hint. Lets the agent fix a diarization undercount
    without re-recording the session."""
    session_dir = SESSIONS_DIR / session_id
    if not session_dir.exists():
        raise HTTPException(404, f"Session {session_id} not found")

    # Find the audio file in the session dir (filename was preserved at
    # upload time — could be recording.m4a or similar).
    audio_path: Optional[Path] = None
    for candidate in session_dir.iterdir():
        if candidate.suffix.lower() in {".m4a", ".mp4", ".wav", ".mp3", ".aac"}:
            audio_path = candidate
            break
    if audio_path is None:
        raise HTTPException(400, "No audio file saved for this session")

    with _sessions_lock:
        if session_id not in _sessions:
            path = session_dir / "session.json"
            if path.exists():
                _sessions[session_id] = json.loads(path.read_text())
        _require_owner(_sessions.get(session_id), current_user, session_id)
        existing_script_id = _sessions[session_id].get("script_id")
        _sessions[session_id].update({
            "status": "processing",
            "completed_at": None,
            "error": None,
            "speakers_expected": speakers_expected,
        })
        _persist(session_id)

    # Re-run uses the same script the session was originally created with —
    # the agent can't switch scripts mid-flight, that would be confusing.
    threading.Thread(
        target=_process,
        args=(session_id, audio_path, None, None, speakers_expected, existing_script_id, current_user["id"]),
        daemon=True,
    ).start()
    return {"id": session_id, "status": "processing"}


_VALID_LEAD_STATUSES = {"drafted", "sent", "replied", "archived"}
_VALID_LEAD_TAGS = {"Buyer", "Seller", "Browser"}


def _load_session(session_id: str) -> Optional[dict]:
    """Pull a session from the in-memory cache, falling back to disk. Caller
    still has to acquire `_sessions_lock` for write operations."""
    with _sessions_lock:
        session = _sessions.get(session_id)
    if session is None:
        path = SESSIONS_DIR / session_id / "session.json"
        if path.exists():
            session = json.loads(path.read_text())
            with _sessions_lock:
                _sessions[session_id] = session
    return session


def _find_visitor_entry(session: dict, name: str, speaker: str) -> Optional[dict]:
    """Locate a visitor inside a session by (name, speaker) — the same
    composite key the iOS app uses as VisitorResult.id. Returns the dict
    in-place so callers can mutate it and persist."""
    result = session.get("result") or {}
    for entry in result.get("visitors") or []:
        v = entry.get("visitor") or {}
        if (v.get("name") or "") == name and (v.get("speaker") or "") == speaker:
            return entry
    return None


def _ensure_lead_state(entry: dict) -> dict:
    """Lead state is created lazily so older sessions don't need a migration.
    Initializes notes/tasks/sent_emails arrays + scheduled_email field too."""
    state = dict(entry.get("lead_state") or {})
    state.setdefault("status", "drafted")
    state.setdefault("notes", [])
    state.setdefault("tasks", [])
    state.setdefault("sent_emails", [])
    state.setdefault("scheduled_email", None)
    # `draft_override` carries the agent's edited version of the AI draft —
    # nil = "use the AI's follow_up_draft as-is", otherwise it's the
    # authoritative subject/body for both manual and scheduled sends.
    state.setdefault("draft_override", None)
    entry["lead_state"] = state
    return state


def _resolve_visitor(
    session_id: str, payload_or_query: dict, current_user: dict
) -> tuple[dict, dict, dict]:
    """Shared front-half of every notes/tasks/schedule endpoint: load the
    session, verify ownership, locate the visitor by (name, speaker), and
    return (session, entry, lead_state). Raises the appropriate HTTPException
    if anything's missing."""
    name = (payload_or_query.get("name") or "").strip()
    speaker = payload_or_query.get("speaker")
    speaker = (speaker or "").strip() if isinstance(speaker, str) else ""
    if not name:
        raise HTTPException(400, "name is required")
    session = _load_session(session_id)
    _require_owner(session, current_user, session_id)
    entry = _find_visitor_entry(session, name, speaker)
    if entry is None:
        raise HTTPException(404, f"Visitor {name!r} (speaker={speaker!r}) not found")
    state = _ensure_lead_state(entry)
    return session, entry, state


def _require_owner(session: Optional[dict], user: dict, session_id: str) -> None:
    """Raises 404 if session missing, 403 if owned by someone else. Sessions
    created before auth landed have no user_id — fall through so the first
    user's orphan-migration step can claim them on next read."""
    if session is None:
        raise HTTPException(404, f"Session {session_id} not found")
    owner = session.get("user_id")
    if owner and owner != user["id"]:
        raise HTTPException(404, f"Session {session_id} not found")


@app.post("/leads")
def create_manual_lead(payload: dict, current_user: dict = Depends(auth_lib.get_current_user)):
    """Create a stand-alone lead with no recording — typed in by the agent
    on the spot. Stored as a one-visitor session with kind="manual" so all
    downstream code (inbox, FUB push, follow-up flow) works without a
    parallel data path. The Sessions tab filters these out so they don't
    clutter the open-house history.
    """
    name = (payload.get("name") or "").strip()
    if not name:
        raise HTTPException(400, "name is required")
    email = (payload.get("email") or "").strip()
    phone = (payload.get("phone") or "").strip()
    tag = (payload.get("tag") or "Browser").strip().capitalize()
    if tag not in _VALID_LEAD_TAGS:
        tag = "Browser"
    address = (payload.get("address") or "").strip() or None

    session_id = str(uuid.uuid4())
    session_dir = SESSIONS_DIR / session_id
    session_dir.mkdir()

    now_iso = datetime.now(timezone.utc).isoformat()
    first_name = name.split()[0] if name else "there"
    at_clause = f" at {address}" if address else ""
    template_draft = (
        f"Hi {first_name} — great meeting you{at_clause}. "
        f"Want me to send a few similar listings to compare?\n\n"
    )

    session = {
        "id": session_id,
        "status": "ready",
        "kind": "manual",
        "address": address,
        "script_id": None,
        "created_at": now_iso,
        "completed_at": now_iso,
        "user_id": current_user["id"],
        "result": {
            "agent_speaker": "",
            "unmatched_speakers": [],
            "visitors": [{
                "visitor": {
                    "name": name,
                    "email": email,
                    "phone": phone,
                    "speaker": None,
                },
                "analysis": {
                    "summary": "Manually added lead — no recording.",
                    "tag": tag,
                    "tag_reason": "Tag set by agent at capture.",
                    "score": 50,
                    "signals": [],
                    "follow_up_draft": template_draft,
                    "words_spoken": 0,
                },
                "lead_state": {
                    "status": "drafted",
                    "sent_at": None,
                    "snoozed_until": None,
                    "updated_at": now_iso,
                },
            }],
            "full_transcript": "",
            "utterances": [],
            "script_coverage": None,
        },
        "error": None,
    }
    with _sessions_lock:
        _sessions[session_id] = session
        _persist(session_id)
    return session


@app.post("/sessions/{session_id}/visitors/state")
def update_visitor_state(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Flip lead_state for a single visitor in a session.

    Body: {name, speaker?, status, snoozed_until?}
    Visitor is matched by (name, speaker) since that's the de facto unique
    key the iOS app uses too (VisitorResult.id). Status must be one of
    drafted / sent / replied / archived. snoozed_until is an ISO8601 string
    or null.
    """
    name = (payload.get("name") or "").strip()
    speaker = payload.get("speaker")
    speaker = (speaker or "").strip() if isinstance(speaker, str) else ""
    status = (payload.get("status") or "").strip()
    snoozed_until = payload.get("snoozed_until")

    if not name:
        raise HTTPException(400, "name is required")
    if status not in _VALID_LEAD_STATUSES:
        raise HTTPException(400, f"status must be one of {sorted(_VALID_LEAD_STATUSES)}")

    with _sessions_lock:
        session = _sessions.get(session_id)
        if session is None:
            path = SESSIONS_DIR / session_id / "session.json"
            if path.exists():
                session = json.loads(path.read_text())
                _sessions[session_id] = session
        _require_owner(session, current_user, session_id)

        result = session.get("result")
        if not result:
            raise HTTPException(409, "Session has no result yet — wait for processing to finish")

        visitors = result.get("visitors") or []
        target = None
        for entry in visitors:
            v = entry.get("visitor") or {}
            if (v.get("name") or "") == name and (v.get("speaker") or "") == speaker:
                target = entry
                break
        if target is None:
            raise HTTPException(404, f"Visitor {name!r} (speaker={speaker!r}) not found in session")

        now_iso = datetime.now(timezone.utc).isoformat()
        state = dict(target.get("lead_state") or {})
        state["status"] = status
        state["updated_at"] = now_iso
        if status == "sent" and not state.get("sent_at"):
            state["sent_at"] = now_iso
        if "snoozed_until" in payload:
            state["snoozed_until"] = snoozed_until
        target["lead_state"] = state
        _persist(session_id)
        return state


@app.post("/sessions/{session_id}/visitors/draft/refine")
def refine_visitor_draft(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Rewrite the current follow-up draft according to a free-text
    instruction ("shorter", "add a CTA for Saturday's open house", etc.).

    Body: {name, speaker?, instruction, base_body?}
        name         — visitor display name (composite key)
        speaker      — diarization label (composite key)
        instruction  — what the agent wants changed
        base_body    — optional override of the draft to rewrite (lets the
                       client refine its IN-PROGRESS edit before saving).
                       Default: the lead's current override or AI draft.

    Returns {body} with the rewritten text. The caller decides what to do
    with it — usually drops it into the draft editor for review.
    """
    instruction = (payload.get("instruction") or "").strip()
    if not instruction:
        raise HTTPException(400, "instruction is required")

    # Read under the lock, but do the Claude call outside it.
    with _sessions_lock:
        session = _load_session(session_id)
        _require_owner(session, current_user, session_id)
        name = (payload.get("name") or "").strip()
        speaker = payload.get("speaker")
        speaker = (speaker or "").strip() if isinstance(speaker, str) else ""
        entry = _find_visitor_entry(session, name, speaker)
        if entry is None:
            raise HTTPException(404, f"Visitor {name!r} not found")
        visitor = entry.get("visitor") or {}
        analysis = entry.get("analysis") or {}
        override = (entry.get("lead_state") or {}).get("draft_override") or {}
        client_base = payload.get("base_body")
        if isinstance(client_base, str):
            base_body = client_base
        else:
            base_body = override.get("body") or analysis.get("follow_up_draft") or ""
        address = session.get("address")
        summary = analysis.get("summary") or ""
        tag = analysis.get("tag") or ""
        display_name = visitor.get("name") or name

    # Resolve any @reference tokens (offers OR templates) the agent put
    # in the instruction. Also expose ALL enabled offers + templates so
    # the LLM can pick the best fit on its own when nothing's explicitly
    # mentioned ("pick the best offer for this lead" works without a
    # specific @reference).
    ctx = _ai_context(current_user["id"], instruction)

    new_body = refine_draft(
        current_body=base_body,
        instruction=instruction,
        visitor_name=display_name,
        visitor_summary=summary,
        visitor_tag=tag,
        address=address,
        mentioned_offers=ctx["mentioned_offers"],
        mentioned_templates=ctx["mentioned_templates"],
        available_offers=ctx["available_offers"],
        available_templates=ctx["available_templates"],
        voice_samples=auth_lib.voice_samples_for(current_user["id"]),
    )
    return {"body": new_body, "resolved_offers": [
        {"id": o.get("id"), "name": o.get("name")}
        for o in ctx["mentioned_offers"]
    ]}


def _resolve_at_mentions(user_id: str, text: str) -> list[dict]:
    """Find every `@reference` in `text` and resolve each to either an
    offer or a template owned by the user.

    Offer + template names are free-form (spaces, punctuation), so we
    can't just regex out the next word — we'd lose multi-word names. The
    resolver instead:
      1. Builds a sorted list of all enabled offer + template names
         (longest first) for the user.
      2. For each `@` in the text, walks the candidate names by length
         and accepts the FIRST one that matches case-insensitively at
         that position. Longest-first wins so "@$2,500 buyer credit"
         beats a hypothetical shorter "@$2,500".
      3. Deduplicates by (kind, id) so an offer mentioned twice only
         shows up once in the LLM context.

    Returns a list of {"kind": "offer"|"template", "offer"|"template": dict}.
    """
    if not text:
        return []
    offers = auth_lib.list_enabled_offers_for(user_id)
    templates = auth_lib.list_enabled_templates_for(user_id)
    # Build a flat candidate list sorted by name length descending so
    # the longest match wins.
    candidates: list[tuple[str, str, dict]] = []
    for o in offers:
        name = (o.get("name") or "").strip()
        if name:
            candidates.append(("offer", name, o))
    for t in templates:
        name = (t.get("name") or "").strip()
        if name:
            candidates.append(("template", name, t))
    candidates.sort(key=lambda c: -len(c[1]))

    lower_text = text.lower()
    seen: set[tuple[str, str]] = set()
    out: list[dict] = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] != "@":
            i += 1
            continue
        # Try each candidate name at this position, longest first.
        matched = None
        for kind, name, obj in candidates:
            name_lower = name.lower()
            end = i + 1 + len(name_lower)
            if end <= n and lower_text[i + 1:end] == name_lower:
                matched = (kind, name, obj, end)
                break
        if matched is None:
            i += 1
            continue
        kind, _name, obj, end = matched
        key = (kind, obj.get("id") or "")
        if key not in seen:
            seen.add(key)
            out.append({"kind": kind, kind: obj})
        i = end
    return out


def _ai_context(user_id: str, message: str) -> dict:
    """Gather the pool of offers + templates the LLM should have access
    to for a refine or leads-agent call. Returns:
      {
        "mentioned_offers":    [...],   # explicitly @-referenced
        "mentioned_templates": [...],   # explicitly @-referenced
        "available_offers":    [...],   # all enabled, for default consideration
        "available_templates": [...],   # all enabled, for default consideration
      }
    The LLM uses `mentioned_*` as "must include this" instructions and
    treats `available_*` as "feel free to pick the best one if it fits"
    options. This is what the user wanted: '@-reference forces it,
    otherwise the AI picks the best on its own'.
    """
    matches = _resolve_at_mentions(user_id, message or "")
    mentioned_offers = [m["offer"] for m in matches if m["kind"] == "offer"]
    mentioned_templates = [m["template"] for m in matches if m["kind"] == "template"]
    return {
        "mentioned_offers": mentioned_offers,
        "mentioned_templates": mentioned_templates,
        "available_offers": auth_lib.list_enabled_offers_for(user_id),
        "available_templates": auth_lib.list_enabled_templates_for(user_id),
    }


@app.patch("/sessions/{session_id}/visitors/contact")
def update_visitor_contact(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Edit a lead's contact info (display name, email, phone).

    Body: {name, speaker?, new_name?, new_email?, new_phone?}
        name        — current display name (composite key)
        speaker     — current diarization label (composite key)
        new_name    — optional new display name (renames the visitor in-place)
        new_email   — optional new email (pass "" to clear)
        new_phone   — optional new phone (pass "" to clear)

    Returns the updated visitor entry: {visitor, analysis, lead_state}.

    Note: keeping `speaker` stable lets every other endpoint (notes, tasks,
    schedules, state) keep working without a cascade — we only rewrite the
    name field. Lead-state, notes, sent_emails etc. are preserved on the
    same entry by reference.
    """
    name = (payload.get("name") or "").strip()
    speaker = payload.get("speaker")
    speaker = (speaker or "").strip() if isinstance(speaker, str) else ""
    if not name:
        raise HTTPException(400, "name is required")

    new_name_raw = payload.get("new_name")
    new_email_raw = payload.get("new_email")
    new_phone_raw = payload.get("new_phone")

    with _sessions_lock:
        session = _load_session(session_id)
        _require_owner(session, current_user, session_id)
        entry = _find_visitor_entry(session, name, speaker)
        if entry is None:
            raise HTTPException(404, f"Visitor {name!r} (speaker={speaker!r}) not found")

        visitor = dict(entry.get("visitor") or {})
        if isinstance(new_name_raw, str):
            cleaned = new_name_raw.strip()
            if not cleaned:
                raise HTTPException(400, "new_name cannot be empty")
            visitor["name"] = cleaned
        if isinstance(new_email_raw, str):
            visitor["email"] = new_email_raw.strip()
        if isinstance(new_phone_raw, str):
            visitor["phone"] = new_phone_raw.strip()
        entry["visitor"] = visitor

        state = _ensure_lead_state(entry)
        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        _persist(session_id)
        return entry


@app.post("/sessions/{session_id}/visitors/send_email")
def send_visitor_email(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Send a follow-up email via the agent's connected Gmail account, then
    flip the visitor's lead_state to `sent`.

    Body: {name, speaker?, to?, subject?, body?}
        name        — visitor display name, matches the iOS VisitorResult.id
        speaker     — diarization label, disambiguates same-named visitors
        to          — recipient; defaults to the visitor's captured email
        subject     — defaults to "Following up — {session address}"
        body        — defaults to the AI-drafted follow-up

    Returns {sent, message_id, lead_state}. 400 here means Gmail isn't
    connected; the iOS client treats that as "show Connect Gmail prompt".
    """
    name = (payload.get("name") or "").strip()
    speaker = payload.get("speaker")
    speaker = (speaker or "").strip() if isinstance(speaker, str) else ""
    if not name:
        raise HTTPException(400, "name is required")

    with _sessions_lock:
        session = _sessions.get(session_id)
        if session is None:
            path = SESSIONS_DIR / session_id / "session.json"
            if path.exists():
                session = json.loads(path.read_text())
                _sessions[session_id] = session
        _require_owner(session, current_user, session_id)

        result = session.get("result")
        if not result:
            raise HTTPException(409, "Session has no result yet")

        visitors = result.get("visitors") or []
        target = None
        for entry in visitors:
            v = entry.get("visitor") or {}
            if (v.get("name") or "") == name and (v.get("speaker") or "") == speaker:
                target = entry
                break
        if target is None:
            raise HTTPException(404, f"Visitor {name!r} (speaker={speaker!r}) not found")

        visitor_info = target.get("visitor") or {}
        analysis = target.get("analysis") or {}
        override = (target.get("lead_state") or {}).get("draft_override") or {}
        to_addr = (payload.get("to") or visitor_info.get("email") or "").strip()
        if not to_addr:
            raise HTTPException(400, "No recipient email — visitor has no email on file")

        address = session.get("address") or "the open house"
        subject = (
            payload.get("subject")
            or override.get("subject")
            or f"Following up — {address}"
        ).strip()
        body = (
            payload.get("body")
            or override.get("body")
            or analysis.get("follow_up_draft")
            or ""
        ).strip()
        if not body:
            raise HTTPException(400, "Email body is empty")

    # Gmail send runs outside the session lock so a slow Google call
    # doesn't block other writes against this session.
    gmail_result = auth_lib.send_gmail_email(
        user_id=current_user["id"],
        to=to_addr,
        subject=subject,
        body=body,
    )
    message_id = gmail_result.get("id")

    # Mirror the visitor-state endpoint: flip to sent + record sent_at, and
    # append to the lead's sent_emails history so the agent can see what was
    # already sent without digging into Gmail.
    with _sessions_lock:
        session = _sessions.get(session_id) or session
        result = session.get("result") or {}
        for entry in result.get("visitors") or []:
            v = entry.get("visitor") or {}
            if (v.get("name") or "") == name and (v.get("speaker") or "") == speaker:
                now_iso = datetime.now(timezone.utc).isoformat()
                state = _ensure_lead_state(entry)
                state["status"] = "sent"
                state["updated_at"] = now_iso
                if not state.get("sent_at"):
                    state["sent_at"] = now_iso
                state["sent_emails"].append({
                    "id": str(uuid.uuid4()),
                    "to": to_addr,
                    "subject": subject,
                    "body": body,
                    "sent_at": now_iso,
                    "message_id": message_id,
                    "scheduled": False,
                })
                entry["lead_state"] = state
                _persist(session_id)
                return {"sent": True, "message_id": message_id, "lead_state": state}

    return {"sent": True, "message_id": message_id, "lead_state": None}


# --------------------------------------------------------------------------
# Lead CRM — notes, tasks, scheduled sends, sent-email history
# --------------------------------------------------------------------------


@app.post("/sessions/{session_id}/visitors/notes")
def add_note(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Append a free-text note to a lead. Notes are agent-only — never sent
    anywhere — used for context the agent picks up across calls/visits."""
    body = (payload.get("body") or "").strip()
    if not body:
        raise HTTPException(400, "body is required")
    with _sessions_lock:
        session, entry, state = _resolve_visitor(session_id, payload, current_user)
        now_iso = datetime.now(timezone.utc).isoformat()
        note = {
            "id": str(uuid.uuid4()),
            "body": body,
            "created_at": now_iso,
            "updated_at": now_iso,
        }
        state["notes"].append(note)
        state["updated_at"] = now_iso
        _persist(session_id)
        return {"lead_state": state, "note": note}


@app.patch("/sessions/{session_id}/visitors/notes/{note_id}")
def update_note(
    session_id: str,
    note_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    body = (payload.get("body") or "").strip()
    if not body:
        raise HTTPException(400, "body is required")
    with _sessions_lock:
        session, entry, state = _resolve_visitor(session_id, payload, current_user)
        for note in state["notes"]:
            if note.get("id") == note_id:
                note["body"] = body
                note["updated_at"] = datetime.now(timezone.utc).isoformat()
                state["updated_at"] = note["updated_at"]
                _persist(session_id)
                return {"lead_state": state, "note": note}
        raise HTTPException(404, f"Note {note_id} not found")


@app.delete("/sessions/{session_id}/visitors/notes/{note_id}")
def delete_note(
    session_id: str,
    note_id: str,
    name: str,
    speaker: str = "",
    current_user: dict = Depends(auth_lib.get_current_user),
):
    with _sessions_lock:
        session, entry, state = _resolve_visitor(
            session_id, {"name": name, "speaker": speaker}, current_user
        )
        before = len(state["notes"])
        state["notes"] = [n for n in state["notes"] if n.get("id") != note_id]
        if len(state["notes"]) == before:
            raise HTTPException(404, f"Note {note_id} not found")
        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        _persist(session_id)
        return {"lead_state": state}


@app.post("/sessions/{session_id}/visitors/tasks")
def add_task(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Append a task (to-do) to a lead — e.g. 'Send comps Thursday', 'Call
    back after inspection'. Optional due_at is an ISO8601 string; the iPad
    surfaces it next to the task title."""
    title = (payload.get("title") or "").strip()
    if not title:
        raise HTTPException(400, "title is required")
    due_at = payload.get("due_at")
    if due_at is not None and not isinstance(due_at, str):
        raise HTTPException(400, "due_at must be an ISO8601 string or null")
    with _sessions_lock:
        session, entry, state = _resolve_visitor(session_id, payload, current_user)
        now_iso = datetime.now(timezone.utc).isoformat()
        task = {
            "id": str(uuid.uuid4()),
            "title": title,
            "due_at": due_at,
            "done": False,
            "created_at": now_iso,
            "done_at": None,
        }
        state["tasks"].append(task)
        state["updated_at"] = now_iso
        _persist(session_id)
        return {"lead_state": state, "task": task}


@app.patch("/sessions/{session_id}/visitors/tasks/{task_id}")
def update_task(
    session_id: str,
    task_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    with _sessions_lock:
        session, entry, state = _resolve_visitor(session_id, payload, current_user)
        for task in state["tasks"]:
            if task.get("id") == task_id:
                if "title" in payload:
                    title = (payload.get("title") or "").strip()
                    if not title:
                        raise HTTPException(400, "title cannot be empty")
                    task["title"] = title
                if "due_at" in payload:
                    task["due_at"] = payload.get("due_at")
                if "done" in payload:
                    done = bool(payload.get("done"))
                    task["done"] = done
                    task["done_at"] = (
                        datetime.now(timezone.utc).isoformat() if done else None
                    )
                state["updated_at"] = datetime.now(timezone.utc).isoformat()
                _persist(session_id)
                return {"lead_state": state, "task": task}
        raise HTTPException(404, f"Task {task_id} not found")


@app.delete("/sessions/{session_id}/visitors/tasks/{task_id}")
def delete_task(
    session_id: str,
    task_id: str,
    name: str,
    speaker: str = "",
    current_user: dict = Depends(auth_lib.get_current_user),
):
    with _sessions_lock:
        session, entry, state = _resolve_visitor(
            session_id, {"name": name, "speaker": speaker}, current_user
        )
        before = len(state["tasks"])
        state["tasks"] = [t for t in state["tasks"] if t.get("id") != task_id]
        if len(state["tasks"]) == before:
            raise HTTPException(404, f"Task {task_id} not found")
        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        _persist(session_id)
        return {"lead_state": state}


@app.patch("/sessions/{session_id}/visitors/draft")
def update_draft(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Save (or clear) the agent's edited follow-up draft for a single lead.
    Body: {name, speaker?, subject?, body?}. Empty body OR explicit
    {clear: true} → wipe the override and fall back to the AI draft.
    """
    clear = bool(payload.get("clear"))
    subject = payload.get("subject")
    body = payload.get("body")
    if not clear:
        if not isinstance(body, str) or not body.strip():
            raise HTTPException(400, "body is required (or pass {clear: true})")
    with _sessions_lock:
        _, _, state = _resolve_visitor(session_id, payload, current_user)
        now_iso = datetime.now(timezone.utc).isoformat()
        if clear:
            state["draft_override"] = None
        else:
            state["draft_override"] = {
                "subject": (subject or "").strip() or None,
                "body": body.strip(),
                "updated_at": now_iso,
            }
        state["updated_at"] = now_iso
        _persist(session_id)
        return {"lead_state": state}


@app.post("/sessions/{session_id}/visitors/schedule_email")
def schedule_email(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Queue a Gmail send for a future time. A background worker
    (_scheduled_send_worker) sweeps every 30s and fires anything whose
    send_at has passed. Only one scheduled send per lead — submitting again
    replaces the queued send. Body: {name, speaker?, send_at, to?, subject?, body?}.
    send_at is an ISO8601 timestamp."""
    send_at_raw = (payload.get("send_at") or "").strip()
    if not send_at_raw:
        raise HTTPException(400, "send_at is required")
    try:
        send_at = datetime.fromisoformat(send_at_raw.replace("Z", "+00:00"))
    except ValueError:
        raise HTTPException(400, "send_at must be an ISO8601 timestamp")
    if send_at.tzinfo is None:
        send_at = send_at.replace(tzinfo=timezone.utc)
    if send_at <= datetime.now(timezone.utc):
        raise HTTPException(400, "send_at must be in the future")

    with _sessions_lock:
        session, entry, state = _resolve_visitor(session_id, payload, current_user)
        visitor_info = entry.get("visitor") or {}
        analysis = entry.get("analysis") or {}
        override = state.get("draft_override") or {}
        to_addr = (payload.get("to") or visitor_info.get("email") or "").strip()
        if not to_addr:
            raise HTTPException(400, "No recipient email — visitor has no email on file")
        address = session.get("address") or "the open house"
        subject = (
            payload.get("subject")
            or override.get("subject")
            or f"Following up — {address}"
        ).strip()
        body = (
            payload.get("body")
            or override.get("body")
            or analysis.get("follow_up_draft")
            or ""
        ).strip()
        if not body:
            raise HTTPException(400, "Email body is empty")

        now_iso = datetime.now(timezone.utc).isoformat()
        state["scheduled_email"] = {
            "send_at": send_at.isoformat(),
            "to": to_addr,
            "subject": subject,
            "body": body,
            "queued_at": now_iso,
            # Cache the agent's user_id so the worker can find the right
            # Gmail refresh token when it fires (the session has user_id but
            # we keep it duplicated here for clarity).
            "user_id": current_user["id"],
        }
        state["updated_at"] = now_iso
        _persist(session_id)
        return {"lead_state": state, "scheduled_email": state["scheduled_email"]}


@app.delete("/sessions/{session_id}/visitors/schedule_email")
def cancel_scheduled_email(
    session_id: str,
    name: str,
    speaker: str = "",
    current_user: dict = Depends(auth_lib.get_current_user),
):
    with _sessions_lock:
        session, entry, state = _resolve_visitor(
            session_id, {"name": name, "speaker": speaker}, current_user
        )
        state["scheduled_email"] = None
        state["updated_at"] = datetime.now(timezone.utc).isoformat()
        _persist(session_id)
        return {"lead_state": state}


# --------------------------------------------------------------------------
# Scheduled-send worker
# --------------------------------------------------------------------------


def _scheduled_send_worker() -> None:
    """Background thread that fires queued Gmail sends as their send_at
    passes. Sleeps 30s between sweeps — fine for a real-estate workflow
    where minute-level precision is plenty. Falls back gracefully on any
    single-lead error so one bad address can't stall the queue."""
    import time

    while True:
        try:
            time.sleep(30)
            now = datetime.now(timezone.utc)
            # Snapshot a list of (session_id, name, speaker, payload) for
            # anything that's due so we don't iterate while mutating.
            due: list[tuple[str, str, str, dict]] = []
            with _sessions_lock:
                for sid, session in list(_sessions.items()):
                    for entry in ((session.get("result") or {}).get("visitors") or []):
                        sched = ((entry.get("lead_state") or {}).get("scheduled_email")) or None
                        if not sched:
                            continue
                        try:
                            sa = datetime.fromisoformat(
                                (sched.get("send_at") or "").replace("Z", "+00:00")
                            )
                        except ValueError:
                            continue
                        if sa.tzinfo is None:
                            sa = sa.replace(tzinfo=timezone.utc)
                        if sa <= now:
                            v = entry.get("visitor") or {}
                            due.append((
                                sid,
                                v.get("name") or "",
                                v.get("speaker") or "",
                                dict(sched),
                            ))

            for sid, name, speaker, sched in due:
                user_id = sched.get("user_id") or ""
                to_addr = sched.get("to") or ""
                subject = sched.get("subject") or ""
                body = sched.get("body") or ""
                try:
                    gmail_result = auth_lib.send_gmail_email(
                        user_id=user_id,
                        to=to_addr,
                        subject=subject,
                        body=body,
                    )
                    message_id = gmail_result.get("id")
                    error = None
                except Exception as ex:
                    message_id = None
                    error = str(ex)

                with _sessions_lock:
                    session = _sessions.get(sid)
                    if not session:
                        continue
                    for entry in ((session.get("result") or {}).get("visitors") or []):
                        v = entry.get("visitor") or {}
                        if (v.get("name") or "") != name or (v.get("speaker") or "") != speaker:
                            continue
                        state = _ensure_lead_state(entry)
                        now_iso = datetime.now(timezone.utc).isoformat()
                        if error is None:
                            state["status"] = "sent"
                            if not state.get("sent_at"):
                                state["sent_at"] = now_iso
                            state["sent_emails"].append({
                                "id": str(uuid.uuid4()),
                                "to": to_addr,
                                "subject": subject,
                                "body": body,
                                "sent_at": now_iso,
                                "message_id": message_id,
                                "scheduled": True,
                            })
                            state["scheduled_email"] = None
                        else:
                            # Don't auto-retry forever — record the failure
                            # on the scheduled record and stop trying. Agent
                            # can resubmit from the UI.
                            sched["error"] = error
                            sched["failed_at"] = now_iso
                            state["scheduled_email"] = sched
                        state["updated_at"] = now_iso
                        _persist(sid)
                        break
        except Exception:
            # Worker must never crash — sleep and try again next sweep.
            continue


_worker_thread: Optional[threading.Thread] = None


@app.on_event("startup")
def _start_scheduled_worker():
    global _worker_thread
    if _worker_thread is None or not _worker_thread.is_alive():
        _hydrate_sessions_from_disk()
        _worker_thread = threading.Thread(
            target=_scheduled_send_worker, daemon=True, name="scheduled-send-worker"
        )
        _worker_thread.start()
    # Replicate the MLS Grid Property feed into a local SQLite store so the
    # iOS New-Listing form can do address autocomplete. No-ops if
    # MLS_GRID_TOKEN isn't set.
    mls_replicator.start()


@app.get("/sessions/{session_id}/audio")
def get_session_audio(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Stream the saved recording so a different device (laptop, iPad) can
    play back a session that was recorded elsewhere. Centralized backend =
    audio lives here, not on the recording device."""
    # Owner check first — pull session metadata so we can verify before
    # exposing the file. Falls back to disk if the in-memory cache misses.
    with _sessions_lock:
        session = _sessions.get(session_id)
    if session is None:
        path = SESSIONS_DIR / session_id / "session.json"
        if path.exists():
            session = json.loads(path.read_text())
            with _sessions_lock:
                _sessions[session_id] = session
    _require_owner(session, current_user, session_id)

    session_dir = SESSIONS_DIR / session_id
    if not session_dir.exists():
        raise HTTPException(404, f"Session {session_id} not found")
    for candidate in session_dir.iterdir():
        if candidate.suffix.lower() in {".m4a", ".mp4", ".wav", ".mp3", ".aac"}:
            media_type = {
                ".m4a": "audio/mp4",
                ".mp4": "audio/mp4",
                ".wav": "audio/wav",
                ".mp3": "audio/mpeg",
                ".aac": "audio/aac",
            }.get(candidate.suffix.lower(), "application/octet-stream")
            return FileResponse(candidate, media_type=media_type, filename=candidate.name)
    raise HTTPException(404, "No audio file saved for this session")


@app.get("/sessions/{session_id}")
def get_session(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    with _sessions_lock:
        session = _sessions.get(session_id)
    if session is None:
        path = SESSIONS_DIR / session_id / "session.json"
        if path.exists():
            session = json.loads(path.read_text())
            with _sessions_lock:
                _sessions[session_id] = session
    _require_owner(session, current_user, session_id)
    return session


@app.post("/sessions/{session_id}/abtest")
def abtest_session(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Run the saved audio through AssemblyAI, Deepgram, and Speechmatics in
    parallel and return their diarized transcripts side-by-side. Used by the
    iOS detail view's "Compare providers" button to evaluate which provider
    handles tricky open-house diarization best on real recordings.

    Each provider runs on a worker thread; a per-provider failure (e.g.
    missing API key, provider 5xx) is reported inline rather than failing
    the whole request — we want partial results visible in the UI."""
    from concurrent.futures import ThreadPoolExecutor
    from dataclasses import asdict
    from pipeline.abtest_diarization import (
        run_assemblyai, run_assemblyai_refined,
        run_deepgram, run_speechmatics,
    )

    session_dir = SESSIONS_DIR / session_id
    if not session_dir.exists():
        raise HTTPException(404, f"Session {session_id} not found")

    with _sessions_lock:
        if session_id not in _sessions:
            path = session_dir / "session.json"
            if path.exists():
                _sessions[session_id] = json.loads(path.read_text())
        _require_owner(_sessions.get(session_id), current_user, session_id)

    audio_path: Optional[Path] = None
    for candidate in session_dir.iterdir():
        if candidate.suffix.lower() in {".m4a", ".mp4", ".wav", ".mp3", ".aac"}:
            audio_path = candidate
            break
    if audio_path is None:
        raise HTTPException(400, "No audio file saved for this session")

    keys = {
        "assemblyai": os.environ.get("ASSEMBLYAI_API_KEY", ""),
        # Refined lane reuses the AAI key — it's AAI + a Claude post-pass.
        "assemblyai_refined": os.environ.get("ASSEMBLYAI_API_KEY", ""),
        "deepgram": os.environ.get("DEEPGRAM_API_KEY", ""),
        "speechmatics": os.environ.get("SPEECHMATICS_API_KEY", ""),
    }
    runners = {
        "assemblyai": run_assemblyai,
        "assemblyai_refined": run_assemblyai_refined,
        "deepgram": run_deepgram,
        "speechmatics": run_speechmatics,
    }

    results: dict[str, dict] = {}
    with ThreadPoolExecutor(max_workers=4) as ex:
        futures = {
            provider: ex.submit(runners[provider], audio_path, keys[provider])
            for provider in runners
            if keys[provider]
        }
        for provider, fut in futures.items():
            results[provider] = asdict(fut.result())
    # Stable order: raw AAI baseline, then AAI+refine (production), then
    # Deepgram, then Speechmatics. Putting raw + refined adjacent makes
    # the value of the Claude post-pass visible at a glance.
    order = ["assemblyai", "assemblyai_refined", "deepgram", "speechmatics"]
    for provider in order:
        if provider not in results:
            results[provider] = {
                "provider": provider,
                "elapsed_s": 0.0,
                "speaker_count": 0,
                "utterances": [],
                "error": f"{provider.upper()}_API_KEY not set on backend",
            }
    return {"results": [results[p] for p in order]}


# --------------------------------------------------------------------------
# Open House Report — homeowner-facing report generated from a session.
#
# Stored on the session dict as `report` (the structured SessionReport) plus
# `report_meta` (metadata: generated_at, updated_at, agent edits). The
# report is regenerable from the transcript + visitor analyses, but cached
# so the agent's edits aren't blown away on re-fetch.
# --------------------------------------------------------------------------


def _load_session_or_404(session_id: str, current_user: dict) -> dict:
    """Pull a session from the in-memory cache, hydrating from disk if
    needed. Returns the session dict (mutable, lock-managed elsewhere) or
    raises 404 / 403."""
    with _sessions_lock:
        session = _sessions.get(session_id)
        if session is None:
            path = SESSIONS_DIR / session_id / "session.json"
            if path.exists():
                session = json.loads(path.read_text())
                _sessions[session_id] = session
        _require_owner(session, current_user, session_id)
        return session


def _format_date_label(iso_ts: Optional[str]) -> str:
    """Render '2026-05-16T14:30:00Z' → 'Saturday, May 16, 2026'. Strips
    the time portion — the homeowner just wants the day. Used in the
    report header."""
    if not iso_ts:
        return ""
    try:
        d = datetime.fromisoformat(iso_ts.replace("Z", "+00:00"))
    except ValueError:
        return ""
    return d.strftime("%A, %B %-d, %Y")


def _stamp_report_metadata(report: SessionReport, session: dict) -> SessionReport:
    """Fill in the metadata fields on the report from session-level data.
    Done outside the Claude call so the model can't drift on facts that
    we already know precisely (address, visitor count, etc.)."""
    result = session.get("result") or {}
    visitors = result.get("visitors") or []
    utterances = result.get("utterances") or []
    duration_min = 0
    if utterances:
        end_ms = max((u.get("end_ms") or u.get("start_ms") or 0) for u in utterances)
        duration_min = int(end_ms / 60_000)

    report.address = session.get("address") or ""
    report.date_label = _format_date_label(session.get("created_at"))
    report.duration_minutes = duration_min
    report.visitor_count = len(visitors)
    # Heuristic: open house visitors typically arrive in pairs (couples).
    report.group_count_estimate = max(0, (len(visitors) + 1) // 2)
    report.generated_at = datetime.now(timezone.utc).isoformat()

    # Weather — Phase 4. Pulled from session["weather"] which Open-Meteo
    # populated when the session completed (or when /coordinate fired
    # later). Sessions without a geocode or recorded before Phase 4 have
    # no weather block — the report just renders without the chip.
    weather = session.get("weather") or {}
    temp = weather.get("temp_f")
    condition = (weather.get("condition_label") or "").strip()
    if temp is not None or condition:
        report.weather_temp_f = float(temp) if temp is not None else None
        report.weather_condition = condition
        bits = []
        if condition:
            bits.append(condition)
        if temp is not None:
            bits.append(f"{int(round(temp))}°F")
        report.weather_label = ", ".join(bits)
    return report


def _agent_signature_html(user: dict) -> str:
    """Render the agent's branded signature for the Open House Report.
    Delegates to auth.build_email_signature_html so the same signature
    works for follow-up emails later — single source of branded chrome."""
    return auth_lib.build_email_signature_html(user)


@app.patch("/sessions/{session_id}")
def update_session_metadata(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Update mutable session metadata. Currently only `name` — agent-set
    nickname for the session. Pass empty string to clear it back to nil so
    the display falls through to `address`."""
    session = _load_session_or_404(session_id, current_user)
    with _sessions_lock:
        if "name" in payload:
            v = (payload.get("name") or "").strip()
            session["name"] = v or None
        _persist(session_id)
        return {"id": session_id, "name": session.get("name")}


@app.post("/sessions/{session_id}/coordinate")
def set_session_coordinate(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Stamp lat/lon on a session and immediately try to pull weather
    from Open-Meteo. iOS calls this from the Report tab when the agent
    taps Generate — by the time the report renders, the weather chip is
    in place. Idempotent: re-posting with the same coords just re-fetches
    weather (useful when Open-Meteo's coverage gap clears).

    Body: {latitude: float, longitude: float}. We intentionally do NOT
    accept "city" or address strings — Phase 4 was explicit that weather
    must be point-resolution or omitted entirely."""
    try:
        lat = float(payload.get("latitude"))
        lon = float(payload.get("longitude"))
    except (TypeError, ValueError):
        raise HTTPException(400, "latitude and longitude are required floats")
    if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
        raise HTTPException(400, "latitude/longitude out of valid range")

    session = _load_session_or_404(session_id, current_user)
    with _sessions_lock:
        session["latitude"] = lat
        session["longitude"] = lon
        _persist(session_id)

    # Weather call lives OUTSIDE the lock — Open-Meteo takes ~1s and we
    # don't want to hold the sessions mutex on a network call. Best-
    # effort: a failure just means the chip won't appear in the report.
    try:
        weather = enrich_session_with_weather(session)
        if weather is not None:
            with _sessions_lock:
                cur = _sessions.get(session_id) or session
                cur["weather"] = weather
                _persist(session_id)
            return {"latitude": lat, "longitude": lon, "weather": weather}
    except Exception as exc:  # noqa: BLE001
        print(f"[weather] coordinate enrich failed for {session_id}: {exc}", flush=True)
    return {"latitude": lat, "longitude": lon, "weather": None}


@app.post("/sessions/{session_id}/homeowner")
def set_homeowner(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Update the homeowner's name + email on a session. Both optional —
    pass empty string to clear. Used by iOS when the agent didn't capture
    these at session creation and adds them later before sending the
    report."""
    session = _load_session_or_404(session_id, current_user)
    with _sessions_lock:
        if "homeowner_email" in payload:
            v = (payload.get("homeowner_email") or "").strip()
            session["homeowner_email"] = v or None
        if "homeowner_name" in payload:
            v = (payload.get("homeowner_name") or "").strip()
            session["homeowner_name"] = v or None
        _persist(session_id)
        return {
            "homeowner_email": session.get("homeowner_email"),
            "homeowner_name": session.get("homeowner_name"),
        }


@app.post("/sessions/{session_id}/report")
def create_or_regenerate_report(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Generate (or regenerate) the open house report from the session
    data. Overwrites any cached report — the agent's manual edits are
    lost on regen by design (otherwise stale edits drift over fresh
    Claude output). The iOS client warns before calling this when a
    report already exists."""
    session = _load_session_or_404(session_id, current_user)
    if not session.get("result"):
        raise HTTPException(409, "Session has no analysis yet — wait for processing to finish")

    # Claude call runs outside the lock — generation takes ~10-30s.
    report = _generate_report(session)
    report = _stamp_report_metadata(report, session)

    with _sessions_lock:
        # Re-fetch in case another writer touched the session while we
        # were calling Claude (snapshot pipeline etc).
        session = _sessions.get(session_id) or session
        session["report"] = report.model_dump()
        session["report_meta"] = {
            "generated_at": report.generated_at,
            "updated_at": report.generated_at,
            "edited": False,
            "sent_at": (session.get("report_meta") or {}).get("sent_at"),
        }
        _persist(session_id)

    return {"report": session["report"], "report_meta": session["report_meta"]}


@app.get("/sessions/{session_id}/report")
def get_report(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Return the cached report (or 404 if it hasn't been generated yet).
    iOS checks this on Report tab open; if 404, shows the Generate button."""
    session = _load_session_or_404(session_id, current_user)
    report = session.get("report")
    if not report:
        raise HTTPException(404, "Report not generated yet")
    return {"report": report, "report_meta": session.get("report_meta") or {}}


@app.patch("/sessions/{session_id}/report")
def update_report(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Save the agent's edits to the report. Body is the full
    SessionReport JSON (iOS sends the entire edited structure rather
    than a diff — the report is small and this avoids merge headaches).
    Sets `edited: true` so the UI can show a 'Custom' badge."""
    session = _load_session_or_404(session_id, current_user)
    with _sessions_lock:
        # Validate the payload by routing it through the Pydantic model
        # — keeps a broken iOS build from corrupting the saved report.
        try:
            validated = SessionReport(**payload)
        except (TypeError, ValueError) as exc:
            raise HTTPException(400, f"Invalid report payload: {exc}")
        session["report"] = validated.model_dump()
        meta = session.get("report_meta") or {}
        meta["updated_at"] = datetime.now(timezone.utc).isoformat()
        meta["edited"] = True
        session["report_meta"] = meta
        _persist(session_id)
        return {"report": session["report"], "report_meta": meta}


@app.post("/sessions/{session_id}/report/refine")
def refine_report(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Apply a natural-language instruction to the cached report. Haiku
    rewrites only the fields the instruction touches and returns the
    full structure; we overwrite the saved report. Used by iOS's
    "Edit with AI" sheet — the agent describes what's wrong and the
    model fixes it. Replaces the per-section TextEditor flow."""
    instruction = (payload.get("instruction") or "").strip()
    if not instruction:
        raise HTTPException(400, "instruction is required")

    session = _load_session_or_404(session_id, current_user)
    current = session.get("report")
    if not current:
        raise HTTPException(409, "Report not generated yet")

    # Haiku call runs outside the lock — typically 2-4s for a refine.
    try:
        refined = _refine_report(current, instruction)
    except ValueError as exc:
        raise HTTPException(502, str(exc))
    refined_dict = refined.model_dump()

    with _sessions_lock:
        # Re-fetch in case another writer touched the session mid-flight.
        session = _sessions.get(session_id) or session
        session["report"] = refined_dict
        meta = session.get("report_meta") or {}
        meta["updated_at"] = datetime.now(timezone.utc).isoformat()
        meta["edited"] = True
        session["report_meta"] = meta
        _persist(session_id)
        return {"report": session["report"], "report_meta": meta}


@app.get("/sessions/{session_id}/report.html", response_class=HTMLResponse)
def get_report_html(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Return the rendered HTML version of the report — for the iOS
    'Export PDF' flow (WKWebView loads this URL, then renders to PDF)
    and for previewing the email body the homeowner will see."""
    session = _load_session_or_404(session_id, current_user)
    raw = session.get("report")
    if not raw:
        raise HTTPException(404, "Report not generated yet")
    report = SessionReport(**raw)
    html_body = render_report_html(
        report,
        agent_signature_html=_agent_signature_html(current_user),
    )
    return HTMLResponse(content=html_body)


@app.post("/sessions/{session_id}/report/share")
def create_report_share(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Mint (or re-return) a public share token + URL for this report.
    Idempotent — calling twice without revoking returns the same token.
    The recipient opens the URL with no auth required."""
    session = _load_session_or_404(session_id, current_user)
    if not session.get("report"):
        raise HTTPException(409, "Report not generated yet")
    share = share_lib.create_share(
        session_id=session_id, user_id=current_user["id"]
    )
    # Mirror the share state onto the session so iOS sees it on the
    # next /sessions/{id} fetch without a separate /share call.
    with _sessions_lock:
        cur = _sessions.get(session_id) or session
        cur["share"] = {
            "token": share["token"],
            "url": share["url"],
            "created_at": share["created_at"],
            "view_count": share["view_count"],
        }
        _persist(session_id)
    return share


@app.get("/sessions/{session_id}/report/share")
def get_report_share(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Returns the active share state ({token, url, created_at,
    view_count, last_viewed_at}) or 404 if no share exists. Lets the
    iOS Report tab show "Shared · viewed N times" without minting a
    new token on view."""
    _load_session_or_404(session_id, current_user)
    state = share_lib.get_share_state(session_id=session_id)
    if not state:
        raise HTTPException(404, "Report not shared")
    return state


@app.delete("/sessions/{session_id}/report/share")
def revoke_report_share(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Revoke any active share token for this report. Idempotent —
    returns {revoked: bool} so iOS knows whether anything changed."""
    session = _load_session_or_404(session_id, current_user)
    revoked = share_lib.revoke_share(
        session_id=session_id, user_id=current_user["id"]
    )
    with _sessions_lock:
        cur = _sessions.get(session_id) or session
        cur.pop("share", None)
        _persist(session_id)
    return {"revoked": revoked}


@app.get("/r/{token}", response_class=HTMLResponse)
def public_report(token: str):
    """Public, no-auth route the homeowner opens from the share link.
    Renders a polished stand-alone HTML page (with OG meta tags so
    iMessage / Slack / Gmail link previews look right). Unknown or
    revoked tokens get a friendly "link expired" page rather than a
    bare 404 — the link might've come from an old email thread."""
    entry = share_lib.lookup_token(token)
    if entry is None:
        return HTMLResponse(
            content=share_lib.render_revoked_html(),
            status_code=404,
        )
    session_id = entry.get("session_id")
    user_id = entry.get("user_id")
    with _sessions_lock:
        session = _sessions.get(session_id)
        if session is None:
            path = SESSIONS_DIR / session_id / "session.json"
            if path.exists():
                session = json.loads(path.read_text())
                _sessions[session_id] = session
    if not session or not session.get("report"):
        return HTMLResponse(
            content=share_lib.render_revoked_html(),
            status_code=404,
        )
    agent = auth_lib.get_user_by_id(user_id) or {}
    html_body = share_lib.render_report_public_html(
        report=session["report"],
        agent=agent,
        weather=session.get("weather"),
    )
    return HTMLResponse(content=html_body)


@app.post("/sessions/{session_id}/report/send")
def send_report(
    session_id: str,
    payload: dict,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Email the report to the homeowner via the agent's connected Gmail
    account. Body fields (all optional, all override session defaults):
      - to:      recipient email (defaults to session.homeowner_email)
      - subject: defaults to "Open House Report — {address}"
      - greeting: prepended above the report ("Hi Sarah — here's the
                  recap from Saturday's open house...")

    The HTML body is the rendered report. The plain-text fallback is a
    short note pointing to the HTML version (mail clients that can't
    render HTML get the headline + TL;DR plus a "see HTML version" line).
    """
    session = _load_session_or_404(session_id, current_user)
    raw = session.get("report")
    if not raw:
        raise HTTPException(409, "Report not generated yet")

    to_addr = (
        (payload.get("to") or "").strip()
        or (session.get("homeowner_email") or "").strip()
    )
    if not to_addr:
        raise HTTPException(
            400,
            "No recipient email — set the homeowner's email first "
            "(POST /sessions/{id}/homeowner) or pass `to` in the body."
        )

    address = session.get("address") or "your open house"
    subject = (
        payload.get("subject")
        or f"Open House Report — {address}"
    ).strip()
    greeting = (payload.get("greeting") or "").strip()

    report = SessionReport(**raw)
    html_body = render_report_html(
        report,
        agent_signature_html=_agent_signature_html(current_user),
    )

    # If the agent included a personal greeting, splice it in just above
    # the report's headline card. Avoids them needing to edit the HTML
    # template by hand.
    if greeting:
        greeting_html = (
            f'<div style="max-width:640px;margin:0 auto 0 auto;'
            f'padding:20px 28px 0 28px;background:#fff;'
            f'font-family:-apple-system,BlinkMacSystemFont,Helvetica Neue,Arial,sans-serif;'
            f'font-size:14px;color:#1a1a1a;line-height:1.6;'
            f'white-space:pre-wrap;">{html_module.escape(greeting)}</div>'
        )
        # Inject after the opening <body> tag.
        html_body = html_body.replace("<body", "<body").replace(
            '<div style="max-width:640px;margin:0 auto;padding:32px 28px;background:#fff;">',
            greeting_html + '<div style="max-width:640px;margin:0 auto;padding:20px 28px 32px 28px;background:#fff;">',
            1,
        )

    text_fallback = _report_plain_text_fallback(report, greeting=greeting)

    gmail_result = auth_lib.send_gmail_email(
        user_id=current_user["id"],
        to=to_addr,
        subject=subject,
        body=text_fallback,
        html_body=html_body,
    )
    message_id = gmail_result.get("id")

    with _sessions_lock:
        session = _sessions.get(session_id) or session
        now_iso = datetime.now(timezone.utc).isoformat()
        meta = session.get("report_meta") or {}
        meta["sent_at"] = now_iso
        meta["sent_to"] = to_addr
        meta["sent_message_id"] = message_id
        session["report_meta"] = meta
        _persist(session_id)
        return {
            "sent": True,
            "to": to_addr,
            "message_id": message_id,
            "report_meta": meta,
        }


def _report_plain_text_fallback(report: SessionReport, *, greeting: str = "") -> str:
    """Plain-text version of the report for mail clients that can't render
    HTML. Kept concise — the HTML version is the real product; this just
    needs to convey the essentials so a text-only client isn't useless."""
    lines: list[str] = []
    if greeting:
        lines.append(greeting)
        lines.append("")
    lines.append(f"OPEN HOUSE REPORT — {report.address or 'your property'}")
    if report.date_label:
        lines.append(report.date_label)
    lines.append("")
    lines.append(report.headline)
    lines.append("")
    for b in report.tldr:
        lines.append(f"  • {b}")
    lines.append("")
    lines.append("(View the formatted version in any HTML-capable mail client.)")
    return "\n".join(lines)


# Imported here (not at top) because `html` is a tiny stdlib module we only
# need inside the report-send flow. Aliased to avoid shadowing FastAPI's
# HTMLResponse import already in scope.
import html as html_module  # noqa: E402


def _summarize(s: dict) -> dict:
    result = s.get("result") or {}
    visitors = result.get("visitors") or []
    return {
        "id": s["id"],
        "status": s["status"],
        "address": s.get("address"),
        # Agent-set nickname. iOS display fallback chain is name -> address
        # -> date, so older sessions without a name still show their address.
        "name": s.get("name"),
        "created_at": s["created_at"],
        "completed_at": s.get("completed_at"),
        "visitor_count": len(visitors),
        # "recorded" (default) for sessions from an audio capture, "manual"
        # for entries the agent typed in. The Sessions tab filters out
        # "manual" so the open-house history stays clean; the Leads inbox
        # shows everything.
        "kind": s.get("kind") or "recorded",
        # True while the agent is still recording (the periodic snapshot
        # pipeline set status=ready on a light pass). iOS uses this to mark
        # the row "IN PROGRESS" instead of treating it like a finished one.
        "is_live": bool(s.get("is_live")),
    }


def _hydrate_sessions_from_disk() -> None:
    # Sessions are in-memory by default; on cold start, scan the sessions/
    # directory so list_sessions returns previously-completed runs too.
    # Skip "_"-prefixed dirs (e.g. _auth) — those aren't session payloads.
    for entry in SESSIONS_DIR.iterdir():
        if not entry.is_dir() or entry.name.startswith("_"):
            continue
        path = entry / "session.json"
        if not path.exists():
            continue
        with _sessions_lock:
            if entry.name in _sessions:
                continue
            try:
                _sessions[entry.name] = json.loads(path.read_text())
            except (json.JSONDecodeError, OSError):
                pass


@app.get("/sessions")
def list_sessions(current_user: dict = Depends(auth_lib.get_current_user)):
    _hydrate_sessions_from_disk()
    with _sessions_lock:
        items = [
            _summarize(s)
            for s in _sessions.values()
            if s.get("user_id") == current_user["id"]
        ]
    items.sort(key=lambda x: x["created_at"], reverse=True)
    return {"sessions": items}


@app.delete("/sessions/{session_id}")
def delete_session(
    session_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Permanently delete a session and its on-disk artifacts (audio,
    transcript, analysis). The iOS confirmation dialog is the only safety
    net — server-side this is irreversible. Lead state for any visitors in
    this session goes away with it since lead records live nested inside
    the session payload."""
    with _sessions_lock:
        session = _sessions.get(session_id)
    if session is None:
        path = SESSIONS_DIR / session_id / "session.json"
        if path.exists():
            session = json.loads(path.read_text())
    _require_owner(session, current_user, session_id)

    with _sessions_lock:
        _sessions.pop(session_id, None)

    session_dir = SESSIONS_DIR / session_id
    if session_dir.exists():
        import shutil
        try:
            shutil.rmtree(session_dir)
        except OSError as exc:
            raise HTTPException(500, f"Could not delete session files: {exc}")

    return {"deleted": session_id}


@app.delete("/sessions/{session_id}/visitors/{visitor_index}")
def delete_visitor(
    session_id: str,
    visitor_index: int,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Drop a single lead from a session without affecting the rest. The
    index is the visitor's position in result.visitors (0-based). Used by
    the iOS Leads inbox swipe-to-delete. We keep the session record itself
    so the audio + transcript remain available for the other leads."""
    with _sessions_lock:
        session = _sessions.get(session_id)
    if session is None:
        path = SESSIONS_DIR / session_id / "session.json"
        if path.exists():
            session = json.loads(path.read_text())
            with _sessions_lock:
                _sessions[session_id] = session
    _require_owner(session, current_user, session_id)

    result = session.get("result") or {}
    visitors = result.get("visitors") or []
    if visitor_index < 0 or visitor_index >= len(visitors):
        raise HTTPException(404, "Visitor index out of range")

    removed = visitors.pop(visitor_index)
    result["visitors"] = visitors
    session["result"] = result
    _persist(session_id)
    return {"deleted_visitor": removed.get("visitor", {}).get("name"), "remaining": len(visitors)}


# --------------------------------------------------------------------------
# MLS Grid — address autocomplete + listing detail
#
# The replicator (backend/mls_replicator.py) keeps a local SQLite mirror of
# the NWMLS Property feed in sync. These endpoints are what the iOS New
# Listing form hits: type-ahead from /mls/autocomplete, full record from
# /mls/property/{id} after the agent picks a suggestion.
# --------------------------------------------------------------------------


def _slim_property(p: dict) -> dict:
    """Reshape a stored property row into a slim DTO the iOS Listing form
    can map 1:1 onto its fields. Drops the heavy raw_json blob."""
    return {
        "listing_id":      p.get("listing_id"),
        "address":         p.get("unparsed_address"),
        "street_number":   p.get("street_number"),
        "street_name":     p.get("street_name"),
        "street_suffix":   p.get("street_suffix"),
        "unit_number":     p.get("unit_number"),
        "city":            p.get("city"),
        "state":           p.get("state"),
        "postal_code":     p.get("postal_code"),
        "county":          p.get("county"),
        "subdivision":     p.get("subdivision"),
        "list_price":      p.get("list_price"),
        "bedrooms":        p.get("bedrooms"),
        "bathrooms_total": p.get("bathrooms_total"),
        "living_area":     p.get("living_area"),
        "lot_size_sqft":   p.get("lot_size_sqft"),
        "year_built":      p.get("year_built"),
        "latitude":        p.get("latitude"),
        "longitude":       p.get("longitude"),
        "photos_count":    p.get("photos_count"),
        "public_remarks":  p.get("public_remarks"),
        "list_agent_name": p.get("list_agent_name"),
        "list_office_name": p.get("list_office_name"),
        "standard_status": p.get("standard_status"),
    }


@app.get("/mls/autocomplete")
def mls_autocomplete(
    q: str,
    limit: int = 10,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Type-ahead lookup for the iOS Listing form. Returns up to `limit`
    active-residential matches against the FTS index over address/city/zip.
    Suggestions are slim so the dropdown is cheap; the iOS app fetches the
    full record from /mls/property/{id} once the agent taps one."""
    safe_limit = max(1, min(int(limit or 10), 25))
    results = mls_store.autocomplete(q, limit=safe_limit)
    return {"suggestions": [_slim_property(r) for r in results]}


@app.get("/mls/property/{listing_id}")
def mls_property(
    listing_id: str,
    current_user: dict = Depends(auth_lib.get_current_user),
):
    """Full normalized property record for the agent's selected suggestion."""
    prop = mls_store.get_property(listing_id)
    if not prop:
        raise HTTPException(404, f"Listing {listing_id} not found in local mirror")
    slim = _slim_property(prop)
    slim["modification_ts"] = prop.get("modification_ts")
    return slim


@app.get("/mls/status")
def mls_status(current_user: dict = Depends(auth_lib.get_current_user)):
    """Replication health for the admin/debug surface."""
    from pipeline import mls_grid
    mls = mls_grid.origin_system()
    return {
        "enabled": bool(mls_grid.token()),
        "base_url": mls_grid.base_url(),
        "mls": mls,
        "state": mls_store.get_state(mls),
        "stats": mls_store.stats(),
    }


WEB_DIR = Path(__file__).parent.parent / "web"


@app.get("/upload", response_class=HTMLResponse)
def upload_page():
    return (Path(__file__).parent / "index.html").read_text()


if WEB_DIR.is_dir():
    app.mount("/", StaticFiles(directory=WEB_DIR, html=True), name="web")
else:
    @app.get("/", response_class=HTMLResponse)
    def index():
        return (Path(__file__).parent / "index.html").read_text()
