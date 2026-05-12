import json
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

load_dotenv(override=True)

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from backend import auth as auth_lib
from pipeline.analyze import analyze_visitor
from pipeline.identify import identify_agent_and_visitors
from pipeline.mock import load_mock_transcript
from pipeline.script_coverage import grade_against_script
from pipeline.scripts import get_script, list_scripts_summary, save_user_script, delete_user_script
from pipeline.tags import DEFAULT_TAGS
from pipeline.transcribe import transcribe_with_speakers

SESSIONS_DIR = Path("sessions")
SESSIONS_DIR.mkdir(exist_ok=True)

app = FastAPI(title="OpenHouseBoss API")

# Open CORS for the demo — the iOS app and the static web frontend hit this
# from anywhere. Tighten allow_origins in prod if you start handling real PII.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/healthz")
def healthz():
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
    valid and to render "signed in as X". Returns a slim user profile."""
    return {
        "id": user["id"],
        "email": user.get("email"),
        "name": user.get("name"),
        "picture": user.get("picture"),
    }


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
_sessions_lock = threading.Lock()


def _persist(session_id: str) -> None:
    path = SESSIONS_DIR / session_id / "session.json"
    path.write_text(json.dumps(_sessions[session_id], indent=2, default=str))


def _update(session_id: str, **updates) -> None:
    with _sessions_lock:
        _sessions[session_id].update(updates)
        _persist(session_id)


def _process(session_id: str, audio_path: Optional[Path], mock_path: Optional[Path], visitors_path: Optional[Path], speakers_expected: Optional[int] = None, script_id: Optional[str] = None, user_id: Optional[str] = None) -> None:
    try:
        if mock_path:
            transcript = load_mock_transcript(mock_path)
        else:
            assert audio_path is not None
            transcript = transcribe_with_speakers(audio_path, speakers_expected=speakers_expected)

        identification = identify_agent_and_visitors(transcript, visitors_path)

        # Lead state from a prior run (if this is a reanalyze) — keyed by
        # (name, speaker) so the agent doesn't lose their "sent / snoozed /
        # archived" markers just because we re-ran diarization.
        prior_states: dict[tuple[str, str], dict] = {}
        with _sessions_lock:
            prior_visitors = ((_sessions.get(session_id) or {}).get("result") or {}).get("visitors") or []
        for entry in prior_visitors:
            v = entry.get("visitor") or {}
            state = entry.get("lead_state")
            if state:
                key = (v.get("name") or "", v.get("speaker") or "")
                prior_states[key] = state

        # Pull this agent's follow-up templates + their forced-mode preference
        # so analyze_visitor can bake them into the initial AI draft.
        templates = auth_lib.list_templates_for(user_id) if user_id else []
        force_templates = auth_lib.force_templates_for(user_id) if user_id else False

        now_iso = datetime.now(timezone.utc).isoformat()
        visitors_out = []
        for visitor in identification.matched_visitors:
            analysis = analyze_visitor(
                transcript, visitor, DEFAULT_TAGS,
                templates=templates,
                force_templates=force_templates,
            )
            v_dict = visitor.model_dump(mode="json")
            key = (v_dict.get("name") or "", v_dict.get("speaker") or "")
            lead_state = prior_states.get(key) or {
                "status": "drafted",
                "sent_at": None,
                "snoozed_until": None,
                "updated_at": now_iso,
            }
            visitors_out.append({
                "visitor": v_dict,
                "analysis": analysis.model_dump(),
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

        _update(
            session_id,
            status="ready",
            completed_at=datetime.now(timezone.utc).isoformat(),
            result={
                "agent_speaker": identification.agent_speaker,
                "unmatched_speakers": identification.unmatched_speakers,
                "visitors": visitors_out,
                "full_transcript": transcript.text,
                "utterances": utterances_out,
                "script_coverage": script_coverage_out,
            },
        )
    except Exception as e:
        _update(
            session_id,
            status="error",
            error=_friendly_error(str(e)),
            completed_at=datetime.now(timezone.utc).isoformat(),
        )


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
    speakers_expected: Optional[int] = Form(None),
    script_id: Optional[str] = Form(None),
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
        "script_id": script_id,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "completed_at": None,
        "result": None,
        "error": None,
        "user_id": current_user["id"],
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


@app.delete("/scripts/{script_id}")
def remove_script(script_id: str):
    if not delete_user_script(script_id):
        raise HTTPException(400, "Cannot delete that script (preset or unknown)")
    return {"deleted": script_id}


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


def _summarize(s: dict) -> dict:
    result = s.get("result") or {}
    visitors = result.get("visitors") or []
    return {
        "id": s["id"],
        "status": s["status"],
        "address": s.get("address"),
        "created_at": s["created_at"],
        "completed_at": s.get("completed_at"),
        "visitor_count": len(visitors),
        # "recorded" (default) for sessions from an audio capture, "manual"
        # for entries the agent typed in. The Sessions tab filters out
        # "manual" so the open-house history stays clean; the Leads inbox
        # shows everything.
        "kind": s.get("kind") or "recorded",
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
