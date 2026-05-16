"""Google Sign-In + backend session JWTs.

Flow:
    iOS / web → /auth/google/start → Google → /auth/google/callback
    Server verifies Google's id_token, upserts a local user, mints a
    backend JWT, and hands it back via either a redirect to a custom
    URL scheme (iOS) or an httpOnly cookie + page redirect (web).

The web OAuth client (id + secret in Render env) is the credential used
for the server-side code exchange. Same client for both iOS and web —
ASWebAuthenticationSession on iOS doesn't actually need a separate iOS
OAuth client when the backend brokers the whole exchange.
"""

from __future__ import annotations

import json
import os
import secrets
import time
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

import jwt
import requests
from fastapi import Header, HTTPException, Request
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------

USERS_DIR = Path("sessions") / "_auth"
USERS_DIR.mkdir(parents=True, exist_ok=True)
USERS_FILE = USERS_DIR / "users.json"

GOOGLE_WEB_CLIENT_ID = os.environ.get("GOOGLE_WEB_CLIENT_ID", "")
GOOGLE_WEB_CLIENT_SECRET = os.environ.get("GOOGLE_WEB_CLIENT_SECRET", "")
GOOGLE_IOS_CLIENT_ID = os.environ.get("GOOGLE_IOS_CLIENT_ID", "")
BACKEND_JWT_SECRET = os.environ.get("BACKEND_JWT_SECRET", "dev-secret-do-not-use-in-prod")

BACKEND_BASE = os.environ.get(
    "BACKEND_BASE_URL", "https://openhouseboss-api.onrender.com"
).rstrip("/")
GOOGLE_REDIRECT_URI = f"{BACKEND_BASE}/auth/google/callback"

IOS_CUSTOM_SCHEME = "com.openhouseboss.app"

SESSION_TTL = timedelta(days=30)
STATE_TTL = timedelta(minutes=15)

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"


# --------------------------------------------------------------------------
# Users — flat JSON file on the persistent disk
# --------------------------------------------------------------------------

def _load_users() -> dict:
    if not USERS_FILE.exists():
        return {"users_by_google_sub": {}, "first_user_id": None}
    try:
        return json.loads(USERS_FILE.read_text())
    except (json.JSONDecodeError, OSError):
        return {"users_by_google_sub": {}, "first_user_id": None}


def _save_users(data: dict) -> None:
    USERS_FILE.write_text(json.dumps(data, indent=2))


def upsert_user_from_google(payload: dict) -> dict:
    """Given Google's verified id_token payload, find or create the user.
    Returns the local user record."""
    sub = payload["sub"]
    email = payload.get("email") or ""
    name = payload.get("name") or email.split("@")[0] or "Foyer agent"
    picture = payload.get("picture")
    now_iso = datetime.now(timezone.utc).isoformat()

    data = _load_users()
    user = data["users_by_google_sub"].get(sub)
    if user is None:
        import uuid as _uuid
        user = {
            "id": str(_uuid.uuid4()),
            "google_sub": sub,
            "email": email,
            "name": name,
            "picture": picture,
            "created_at": now_iso,
            "last_login_at": now_iso,
        }
        data["users_by_google_sub"][sub] = user
        if not data.get("first_user_id"):
            data["first_user_id"] = user["id"]
        _save_users(data)
    else:
        user["last_login_at"] = now_iso
        user["email"] = email or user.get("email")
        user["name"] = name or user.get("name")
        user["picture"] = picture or user.get("picture")
        _save_users(data)
    return user


def get_user_by_id(user_id: str) -> Optional[dict]:
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            return u
    return None


def first_user_id() -> Optional[str]:
    return _load_users().get("first_user_id")


# --------------------------------------------------------------------------
# Backend session JWT
# --------------------------------------------------------------------------

def mint_session_jwt(user: dict) -> str:
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user["id"],
        "email": user.get("email"),
        "name": user.get("name"),
        "iat": int(now.timestamp()),
        "exp": int((now + SESSION_TTL).timestamp()),
    }
    return jwt.encode(payload, BACKEND_JWT_SECRET, algorithm="HS256")


def decode_session_jwt(token: str) -> dict:
    try:
        return jwt.decode(token, BACKEND_JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError as e:
        raise HTTPException(401, f"Invalid session: {e}")


# --------------------------------------------------------------------------
# Live-companion JWT — scoped to ONE session, expires in hours
# --------------------------------------------------------------------------
#
# Issued by /live/redeem after a pairing code is exchanged. Lets a second
# device (laptop, iPad) read a single in-flight session and request coaching
# check-ins, WITHOUT handing it the agent's full account token. The scope
# claim is checked in `get_live_companion` so a stolen companion JWT can't
# be used against /sessions, /leads, Gmail send, etc.

LIVE_COMPANION_TTL = timedelta(hours=4)


def mint_live_companion_jwt(session_id: str, user_id: str) -> tuple[str, datetime]:
    """Returns (jwt, expires_at). The token's `sub` is the OWNING user so
    audit logs still attribute reads to the agent; the `scope` + `session_id`
    claims are what gate access."""
    now = datetime.now(timezone.utc)
    exp = now + LIVE_COMPANION_TTL
    payload = {
        "sub": user_id,
        "scope": "live_companion",
        "session_id": session_id,
        "iat": int(now.timestamp()),
        "exp": int(exp.timestamp()),
    }
    return jwt.encode(payload, BACKEND_JWT_SECRET, algorithm="HS256"), exp


def get_live_companion(
    session_id: str,
    authorization: Optional[str] = Header(default=None),
) -> dict:
    """FastAPI dependency for the /live/sessions/{session_id}/* endpoints.
    Requires a bearer token with scope=live_companion whose session_id claim
    matches the URL path. Returns {user_id, session_id}."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(401, "Missing live-companion token")
    token = authorization.split(" ", 1)[1].strip()
    try:
        payload = jwt.decode(token, BACKEND_JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError as e:
        raise HTTPException(401, f"Invalid live-companion token: {e}")
    if payload.get("scope") != "live_companion":
        raise HTTPException(403, "Token is not a live-companion token")
    if payload.get("session_id") != session_id:
        raise HTTPException(403, "Token is not valid for this session")
    return {"user_id": payload.get("sub", ""), "session_id": session_id}


# --------------------------------------------------------------------------
# OAuth state (signed, no server storage)
# --------------------------------------------------------------------------

def encode_state(platform: str) -> str:
    """Sign {platform, nonce, exp} so we can trust the state param without a
    server-side store. The nonce is mostly a CSRF guard — the cookie below
    is the second factor."""
    now = datetime.now(timezone.utc)
    payload = {
        "platform": platform if platform in ("ios", "web") else "web",
        "nonce": secrets.token_urlsafe(16),
        "exp": int((now + STATE_TTL).timestamp()),
    }
    return jwt.encode(payload, BACKEND_JWT_SECRET, algorithm="HS256")


def decode_state(state: str) -> dict:
    try:
        return jwt.decode(state, BACKEND_JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError as e:
        raise HTTPException(400, f"Invalid OAuth state: {e}")


# --------------------------------------------------------------------------
# Google ID token verification + code exchange
# --------------------------------------------------------------------------

def verify_google_id_token(id_token_str: str) -> dict:
    """Validates the JWT signature + audience against either client ID
    (web is canonical; iOS is accepted too in case we later hand iOS its
    own id_token directly without going through the backend exchange)."""
    valid_audiences = [a for a in (GOOGLE_WEB_CLIENT_ID, GOOGLE_IOS_CLIENT_ID) if a]
    if not valid_audiences:
        raise HTTPException(500, "Server is missing Google client ID configuration")
    last_err: Exception | None = None
    for aud in valid_audiences:
        try:
            payload = google_id_token.verify_oauth2_token(
                id_token_str, google_requests.Request(), aud
            )
            return payload
        except ValueError as e:
            last_err = e
    raise HTTPException(401, f"Google ID token failed verification: {last_err}")


def exchange_code_for_id_token(code: str) -> str:
    """Server-side OAuth code exchange using the WEB client credential."""
    if not (GOOGLE_WEB_CLIENT_ID and GOOGLE_WEB_CLIENT_SECRET):
        raise HTTPException(500, "Server is missing Google web client credentials")
    resp = requests.post(
        GOOGLE_TOKEN_URL,
        data={
            "code": code,
            "client_id": GOOGLE_WEB_CLIENT_ID,
            "client_secret": GOOGLE_WEB_CLIENT_SECRET,
            "redirect_uri": GOOGLE_REDIRECT_URI,
            "grant_type": "authorization_code",
        },
        timeout=10,
    )
    if not resp.ok:
        raise HTTPException(401, f"Google token exchange failed: {resp.text}")
    tokens = resp.json()
    id_token_str = tokens.get("id_token")
    if not id_token_str:
        raise HTTPException(401, "Google response missing id_token")
    return id_token_str


def build_google_authorize_url(state: str) -> str:
    qs = urllib.parse.urlencode({
        "client_id": GOOGLE_WEB_CLIENT_ID,
        "redirect_uri": GOOGLE_REDIRECT_URI,
        "response_type": "code",
        "scope": "openid email profile",
        "state": state,
        "access_type": "online",
        "include_granted_scopes": "true",
        "prompt": "select_account",
    })
    return f"{GOOGLE_AUTH_URL}?{qs}"


# --------------------------------------------------------------------------
# Request-side helpers (used as FastAPI dependencies)
# --------------------------------------------------------------------------

def get_current_user(
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> dict:
    """Resolve the caller to a User. Prefers Authorization: Bearer <jwt>
    (iOS path), falls back to the `fb_session` cookie (web path)."""
    token: Optional[str] = None
    if authorization and authorization.lower().startswith("bearer "):
        token = authorization.split(" ", 1)[1].strip()
    elif "fb_session" in request.cookies:
        token = request.cookies["fb_session"]
    if not token:
        raise HTTPException(401, "Not signed in")
    payload = decode_session_jwt(token)
    user = get_user_by_id(payload.get("sub", ""))
    if user is None:
        raise HTTPException(401, "User no longer exists")
    return user


def try_current_user(
    request: Request,
    authorization: Optional[str] = Header(default=None),
) -> Optional[dict]:
    try:
        return get_current_user(request, authorization)
    except HTTPException:
        return None


# --------------------------------------------------------------------------
# Orphan session migration
# --------------------------------------------------------------------------

def migrate_orphan_sessions_to(user_id: str, sessions_dir: Path) -> int:
    """Attribute every session.json without a user_id to this user. Run on
    first login so the agent doesn't lose pre-auth sessions. Returns the
    number of sessions migrated."""
    if not sessions_dir.exists():
        return 0
    count = 0
    for entry in sessions_dir.iterdir():
        if not entry.is_dir() or entry.name.startswith("_"):
            continue
        path = entry / "session.json"
        if not path.exists():
            continue
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if data.get("user_id"):
            continue
        data["user_id"] = user_id
        try:
            path.write_text(json.dumps(data, indent=2, default=str))
            count += 1
        except OSError:
            continue
    return count


# --------------------------------------------------------------------------
# Gmail send — separate OAuth grant
# --------------------------------------------------------------------------
#
# The base /auth/google/* flow uses `openid email profile` for identity
# only. To send mail on the agent's behalf we run a second consent
# (`gmail.send`) with `access_type=offline` so Google hands us a refresh
# token. The refresh token is stored per-user (next to google_sub) and the
# short-lived access token is fetched on-demand right before each send.

GMAIL_SCOPE = "https://www.googleapis.com/auth/gmail.send"
GMAIL_REDIRECT_URI = f"{BACKEND_BASE}/auth/gmail/callback"
GMAIL_API_BASE = "https://gmail.googleapis.com/gmail/v1"


def encode_gmail_state(user_id: str, platform: str = "ios") -> str:
    """Like encode_state but carries the user_id forward so the callback
    knows which agent to attach the refresh token to."""
    now = datetime.now(timezone.utc)
    payload = {
        "kind": "gmail",
        "user_id": user_id,
        "platform": platform if platform in ("ios", "web") else "ios",
        "nonce": secrets.token_urlsafe(16),
        "exp": int((now + STATE_TTL).timestamp()),
    }
    return jwt.encode(payload, BACKEND_JWT_SECRET, algorithm="HS256")


def build_gmail_authorize_url(state: str) -> str:
    qs = urllib.parse.urlencode({
        "client_id": GOOGLE_WEB_CLIENT_ID,
        "redirect_uri": GMAIL_REDIRECT_URI,
        "response_type": "code",
        # `openid email` lets us read the Gmail address the agent chose in
        # the consent picker — that's the From: address we send under.
        "scope": f"openid email {GMAIL_SCOPE}",
        "state": state,
        "access_type": "offline",
        "include_granted_scopes": "true",
        # consent forces a fresh refresh_token even if the agent had
        # previously granted this scope; Google omits refresh_token
        # otherwise. Cheap insurance.
        "prompt": "consent",
    })
    return f"{GOOGLE_AUTH_URL}?{qs}"


def exchange_code_for_full_tokens(code: str, redirect_uri: str) -> dict:
    """Returns the full token response (access_token + refresh_token +
    id_token) — distinct from exchange_code_for_id_token which throws the
    refresh token away."""
    if not (GOOGLE_WEB_CLIENT_ID and GOOGLE_WEB_CLIENT_SECRET):
        raise HTTPException(500, "Server is missing Google web client credentials")
    resp = requests.post(
        GOOGLE_TOKEN_URL,
        data={
            "code": code,
            "client_id": GOOGLE_WEB_CLIENT_ID,
            "client_secret": GOOGLE_WEB_CLIENT_SECRET,
            "redirect_uri": redirect_uri,
            "grant_type": "authorization_code",
        },
        timeout=10,
    )
    if not resp.ok:
        raise HTTPException(401, f"Google token exchange failed: {resp.text}")
    return resp.json()


def refresh_gmail_access_token(refresh_token: str) -> str:
    """Trade a stored refresh token for a fresh ~1-hour access token."""
    if not (GOOGLE_WEB_CLIENT_ID and GOOGLE_WEB_CLIENT_SECRET):
        raise HTTPException(500, "Server is missing Google web client credentials")
    resp = requests.post(
        GOOGLE_TOKEN_URL,
        data={
            "refresh_token": refresh_token,
            "client_id": GOOGLE_WEB_CLIENT_ID,
            "client_secret": GOOGLE_WEB_CLIENT_SECRET,
            "grant_type": "refresh_token",
        },
        timeout=10,
    )
    if not resp.ok:
        # 400 invalid_grant means the user revoked access — caller should
        # surface "reconnect Gmail" rather than treat this as a real 500.
        raise HTTPException(401, f"Gmail token refresh failed: {resp.text}")
    return resp.json()["access_token"]


def set_gmail_credential(user_id: str, refresh_token: str, gmail_email: str) -> None:
    """Attach Gmail connection details to the user record."""
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            u["gmail_refresh_token"] = refresh_token
            u["gmail_account_email"] = gmail_email
            u["gmail_connected_at"] = datetime.now(timezone.utc).isoformat()
            _save_users(data)
            return
    raise HTTPException(404, "User not found")


def clear_gmail_credential(user_id: str) -> None:
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            u.pop("gmail_refresh_token", None)
            u.pop("gmail_account_email", None)
            u.pop("gmail_connected_at", None)
            _save_users(data)
            return


def gmail_status_for(user_id: str) -> dict:
    """{connected, email, send_from} — used by iOS and web to render the
    Connect Gmail card and the optional Send-as alias picker."""
    user = get_user_by_id(user_id)
    if not user:
        return {"connected": False, "email": None, "send_from": None}
    return {
        "connected": bool(user.get("gmail_refresh_token")),
        "email": user.get("gmail_account_email"),
        # Optional alias the user verified in Gmail's "Send mail as"
        # settings. If set, we put it on the From: header so recipients
        # see this address instead of the authenticated mailbox.
        "send_from": user.get("gmail_send_from") or None,
    }


def gmail_refresh_token_for(user_id: str) -> Optional[str]:
    user = get_user_by_id(user_id)
    return user.get("gmail_refresh_token") if user else None


def gmail_email_for(user_id: str) -> Optional[str]:
    user = get_user_by_id(user_id)
    return user.get("gmail_account_email") if user else None


def gmail_send_from_for(user_id: str) -> Optional[str]:
    """The Send-as alias the agent wants on every outgoing message, or
    None to use the authenticated Gmail account. Caller is responsible
    for falling back gracefully — Gmail itself silently rewrites the
    From: header if the alias isn't verified in Gmail settings, so this
    is best-effort by design."""
    user = get_user_by_id(user_id)
    return (user or {}).get("gmail_send_from") or None


def set_gmail_send_from(user_id: str, address: Optional[str]) -> None:
    """Save (or clear) the Send-as alias. Pass None / empty to clear."""
    addr = (address or "").strip()
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            if addr:
                u["gmail_send_from"] = addr
            else:
                u.pop("gmail_send_from", None)
            _save_users(data)
            return
    raise HTTPException(404, "User not found")


# --------------------------------------------------------------------------
# Agent profile — brokerage, license, phone, title, tagline, headshot.
# Used in the Open House Report header + the email signature appended to
# every outgoing send. All fields are optional; the report-rendering side
# silently skips any that aren't filled in, so an agent who only sets
# brokerage still gets a cleaner signature than the default name-only one.
# --------------------------------------------------------------------------

# Fields the user can edit via PATCH /me/profile. Listed explicitly so an
# accidentally-typed `gmail_refresh_token` in the payload can't sneak past
# update_profile and overwrite the OAuth credential.
PROFILE_FIELDS = (
    "brokerage",
    "license_number",
    "phone",
    "title",
    "tagline",
)


def profile_for(user_id: str) -> dict:
    """Return {brokerage, license_number, phone, title, tagline,
    headshot_url} — the bits the iOS profile screen renders. Always
    returns strings (empty when unset) so the iOS form doesn't have to
    paper over nil vs "" everywhere."""
    user = get_user_by_id(user_id) or {}
    headshot = user.get("headshot_filename")
    return {
        "brokerage":      user.get("brokerage") or "",
        "license_number": user.get("license_number") or "",
        "phone":          user.get("phone") or "",
        "title":          user.get("title") or "",
        "tagline":        user.get("tagline") or "",
        # Relative URL — the iOS client expands against Config.backendURL.
        # `?v={epoch}` cache-buster forces avatars to refresh on iOS after
        # re-upload (URLCache otherwise pins the old image for hours).
        "headshot_url": (
            f"/me/profile/headshot?v={user.get('headshot_updated_at') or ''}"
            if headshot else None
        ),
    }


def update_profile(user_id: str, updates: dict) -> dict:
    """Patch the editable profile fields. Unknown keys are ignored —
    PROFILE_FIELDS is the whitelist. Empty string clears a field; nil
    leaves it unchanged."""
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            for k in PROFILE_FIELDS:
                if k not in updates:
                    continue
                v = updates[k]
                if isinstance(v, str):
                    v = v.strip()
                if v == "" or v is None:
                    u.pop(k, None)
                else:
                    u[k] = v
            _save_users(data)
            return profile_for(user_id)
    raise HTTPException(404, "User not found")


def headshot_path_for(user_id: str) -> Optional[Path]:
    """Disk path for the user's uploaded headshot, or nil if none exists.
    The file is stored under sessions/_auth/headshots/{user_id}.{ext} so
    it persists on Render's mounted disk alongside users.json."""
    user = get_user_by_id(user_id) or {}
    name = user.get("headshot_filename")
    if not name:
        return None
    p = USERS_DIR / "headshots" / name
    return p if p.exists() else None


def save_headshot(user_id: str, data: bytes, content_type: str) -> dict:
    """Write the uploaded image to disk and record the filename + a
    timestamp on the user. Returns the updated profile dict.

    `content_type` picks the extension — we trust the iOS client to send
    image/jpeg or image/png. Other types are coerced to .bin (best-effort
    so a wrong content-type doesn't lose the upload entirely)."""
    ext_map = {
        "image/jpeg": ".jpg",
        "image/jpg":  ".jpg",
        "image/png":  ".png",
        "image/heic": ".heic",
        "image/webp": ".webp",
    }
    ext = ext_map.get(content_type.lower(), ".bin")
    headshot_dir = USERS_DIR / "headshots"
    headshot_dir.mkdir(parents=True, exist_ok=True)
    filename = f"{user_id}{ext}"
    (headshot_dir / filename).write_bytes(data)

    # Clean up any pre-existing file with a different extension so we
    # don't leak orphans when the user uploads a PNG after a JPEG.
    for old in headshot_dir.glob(f"{user_id}.*"):
        if old.name != filename:
            old.unlink(missing_ok=True)

    now_iso = datetime.now(timezone.utc).isoformat()
    users = _load_users()
    for u in users["users_by_google_sub"].values():
        if u["id"] == user_id:
            u["headshot_filename"] = filename
            u["headshot_updated_at"] = now_iso
            _save_users(users)
            break
    return profile_for(user_id)


def clear_headshot(user_id: str) -> dict:
    """Delete the headshot file and clear its fields on the user. Idempotent
    — called when the agent taps Remove in the profile editor."""
    headshot_dir = USERS_DIR / "headshots"
    if headshot_dir.exists():
        for old in headshot_dir.glob(f"{user_id}.*"):
            old.unlink(missing_ok=True)
    users = _load_users()
    for u in users["users_by_google_sub"].values():
        if u["id"] == user_id:
            u.pop("headshot_filename", None)
            u.pop("headshot_updated_at", None)
            _save_users(users)
            break
    return profile_for(user_id)


def build_email_signature_html(user: dict, *, base_url: Optional[str] = None) -> str:
    """Render the agent's signature for outgoing emails (Open House
    Report, future follow-ups). Uses every available profile field;
    missing fields are silently skipped so a minimally-configured agent
    still gets a passable signature.

    `base_url` is prepended to the relative headshot URL so the image
    renders inside Gmail / Apple Mail. Defaults to BACKEND_BASE."""
    import html as _html

    def _esc(s: Optional[str]) -> str:
        return _html.escape(s or "")

    name = (user.get("name") or "").strip()
    title = (user.get("title") or "").strip()
    brokerage = (user.get("brokerage") or "").strip()
    license_num = (user.get("license_number") or "").strip()
    phone = (user.get("phone") or "").strip()
    email = (user.get("email") or "").strip()
    tagline = (user.get("tagline") or "").strip()
    headshot_name = user.get("headshot_filename")

    base = (base_url or BACKEND_BASE).rstrip("/")
    headshot_html = ""
    if headshot_name:
        # Public-ish URL — the report-send endpoint signs the image
        # request via a one-off token in a future iteration; for now the
        # headshot endpoint allows unauthenticated reads since the URL
        # ends up in emails sent to homeowners (who don't have JWTs).
        cache_buster = user.get("headshot_updated_at") or ""
        cb_qs = f"?v={cache_buster}" if cache_buster else ""
        headshot_html = (
            f'<td style="vertical-align:top;padding-right:14px;">'
            f'<img src="{base}/me/profile/headshot/{_esc(user.get("id") or "")}{cb_qs}" '
            f'width="64" height="64" alt="" '
            f'style="border-radius:50%;display:block;object-fit:cover;'
            f'background:#eee;">'
            f'</td>'
        )

    # Top line — name, optional title.
    title_span = (
        f'<span style="color:#888;font-weight:400;">  ·  {_esc(title)}</span>'
        if title else ""
    )
    top_line = (
        f'<div style="font-weight:600;font-size:14px;color:#1a1a1a;">'
        f'{_esc(name)}{title_span}'
        f'</div>'
    )

    # Brokerage + license, on one line when both present.
    broker_bits: list[str] = []
    if brokerage: broker_bits.append(_esc(brokerage))
    if license_num: broker_bits.append(f'License # {_esc(license_num)}')
    broker_line = (
        f'<div style="font-size:12px;color:#555;margin-top:2px;">'
        f'{" · ".join(broker_bits)}</div>'
        if broker_bits else ""
    )

    # Contact line — phone + email, clickable.
    contact_bits: list[str] = []
    if phone:
        # Normalize the phone for the tel: link (digits only) but keep
        # the human-formatted version in the visible text.
        digits = "".join(c for c in phone if c.isdigit() or c == "+")
        contact_bits.append(
            f'<a href="tel:{_esc(digits)}" '
            f'style="color:#555;text-decoration:none;">{_esc(phone)}</a>'
        )
    if email:
        contact_bits.append(
            f'<a href="mailto:{_esc(email)}" '
            f'style="color:#555;text-decoration:none;">{_esc(email)}</a>'
        )
    contact_line = (
        f'<div style="font-size:12px;color:#555;margin-top:2px;">'
        f'{" · ".join(contact_bits)}</div>'
        if contact_bits else ""
    )

    tagline_line = (
        f'<div style="font-size:11px;color:#888;font-style:italic;'
        f'margin-top:6px;">{_esc(tagline)}</div>'
        if tagline else ""
    )

    text_block = (
        f'<td style="vertical-align:top;">'
        f'{top_line}{broker_line}{contact_line}{tagline_line}'
        f'</td>'
    )

    return (
        f'<table cellpadding="0" cellspacing="0" border="0" '
        f'style="border-collapse:collapse;">'
        f'<tr>{headshot_html}{text_block}</tr>'
        f'</table>'
    )


# --------------------------------------------------------------------------
# Follow-up templates (per user)
# --------------------------------------------------------------------------
# Stored on the user record as `templates: [{id, name, match_hints, subject,
# body, created_at, updated_at}]`. Slots are free-form `{snake_case}` tokens
# the agent embeds in subject/body; the drafting pipeline fills the well-
# known ones (first_name, full_name, property_address, agent_name) and leaves
# the rest for the LLM (soft mode) or the agent (forced mode) to populate.

def list_templates_for(user_id: str) -> list[dict]:
    """All of the user's templates. Older records didn't have `enabled` —
    migrate them on-read so the rest of the codebase can assume the field
    is always present."""
    arr = []
    for t in ((get_user_by_id(user_id) or {}).get("templates") or []):
        if "enabled" not in t:
            t["enabled"] = True
        arr.append(t)
    return arr


def list_enabled_templates_for(user_id: str) -> list[dict]:
    return [t for t in list_templates_for(user_id) if t.get("enabled", True)]


def get_template_by_name(user_id: str, name: str) -> dict | None:
    target = (name or "").strip().lower()
    if not target:
        return None
    for t in list_templates_for(user_id):
        if (t.get("name") or "").strip().lower() == target:
            return t
    return None


def set_template_enabled(user_id: str, template_id: str, enabled: bool) -> dict:
    now_iso = datetime.now(timezone.utc).isoformat()
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = list(u.get("templates") or [])
            for t in arr:
                if t.get("id") == template_id:
                    t["enabled"] = bool(enabled)
                    t["updated_at"] = now_iso
                    u["templates"] = arr
                    _save_users(data)
                    return t
            raise HTTPException(404, "Template not found")
    raise HTTPException(404, "User not found")


def force_templates_for(user_id: str) -> bool:
    user = get_user_by_id(user_id)
    return bool((user or {}).get("force_templates"))


def set_force_templates(user_id: str, force: bool) -> None:
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            u["force_templates"] = bool(force)
            _save_users(data)
            return
    raise HTTPException(404, "User not found")


def _validate_template_payload(payload: dict) -> dict:
    name = (payload.get("name") or "").strip()
    subject = (payload.get("subject") or "").strip()
    body = (payload.get("body") or "").strip()
    hints = (payload.get("match_hints") or "").strip()
    if not name:
        raise HTTPException(400, "Template name is required")
    if not body:
        raise HTTPException(400, "Template body is required")
    enabled = payload.get("enabled")
    if enabled is None:
        enabled = True
    return {
        "name": name, "subject": subject, "body": body,
        "match_hints": hints, "enabled": bool(enabled),
    }


def create_template(user_id: str, payload: dict) -> dict:
    import uuid as _uuid
    fields = _validate_template_payload(payload)
    now_iso = datetime.now(timezone.utc).isoformat()
    template = {
        "id": str(_uuid.uuid4()),
        "name": fields["name"],
        "subject": fields["subject"],
        "body": fields["body"],
        "match_hints": fields["match_hints"],
        "enabled": fields["enabled"],
        "created_at": now_iso,
        "updated_at": now_iso,
    }
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = list(u.get("templates") or [])
            arr.append(template)
            u["templates"] = arr
            _save_users(data)
            return template
    raise HTTPException(404, "User not found")


def update_template(user_id: str, template_id: str, payload: dict) -> dict:
    fields = _validate_template_payload(payload)
    now_iso = datetime.now(timezone.utc).isoformat()
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = list(u.get("templates") or [])
            for t in arr:
                if t.get("id") == template_id:
                    t["name"] = fields["name"]
                    t["subject"] = fields["subject"]
                    t["body"] = fields["body"]
                    t["match_hints"] = fields["match_hints"]
                    t["enabled"] = fields["enabled"]
                    t["updated_at"] = now_iso
                    u["templates"] = arr
                    _save_users(data)
                    return t
            raise HTTPException(404, "Template not found")
    raise HTTPException(404, "User not found")


def delete_template(user_id: str, template_id: str) -> None:
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = [t for t in (u.get("templates") or []) if t.get("id") != template_id]
            u["templates"] = arr
            _save_users(data)
            return
    raise HTTPException(404, "User not found")


# --------------------------------------------------------------------------
# Offers / campaigns (per user)
# --------------------------------------------------------------------------
# Stored on the user record as `offers: [{id, name, headline, body, ...}]`.
# Offers describe a marketing angle the agent wants to push — e.g. "$2,500
# buyer credit", "Saturday 1pm tour" — and can be referenced by name in
# AI refine instructions ("add @buyerCredit to this email") or in the
# leads-AI agent ("send @buyerCredit to all buyer leads"). `name` is a
# short identifier (no spaces) the agent uses as the @reference; the LLM
# sees `headline` + `body` for context.

def list_offers_for(user_id: str) -> list[dict]:
    """Return ALL of the user's offers, including disabled ones. Filtering
    to enabled-only happens at the call site so list views (the Offers
    tab) can still display disabled ones with a toggle."""
    arr = []
    for o in ((get_user_by_id(user_id) or {}).get("offers") or []):
        # Migrate old records that pre-date `enabled` — treat them as on.
        if "enabled" not in o:
            o["enabled"] = True
        arr.append(o)
    return arr


def list_enabled_offers_for(user_id: str) -> list[dict]:
    """Subset used by AI calls — only offers the agent has turned on."""
    return [o for o in list_offers_for(user_id) if o.get("enabled", True)]


def get_offer_by_name(user_id: str, name: str) -> dict | None:
    """Case-insensitive lookup by `name` — used to resolve @reference
    tokens the agent puts in free-text instructions. Matches the whole
    name only (multi-word matching is handled by the resolver since it
    has to peek at surrounding text)."""
    target = (name or "").strip().lower()
    if not target:
        return None
    for o in list_offers_for(user_id):
        if (o.get("name") or "").strip().lower() == target:
            return o
    return None


def _validate_offer_payload(payload: dict) -> dict:
    # Names can be free-form (spaces, punctuation, etc.) — autocomplete on
    # the client lets the agent reference them unambiguously by tapping
    # from a picker, so we don't need an ID-shaped slug anymore.
    name = (payload.get("name") or "").strip()
    body = (payload.get("body") or "").strip()
    if not name:
        raise HTTPException(400, "Offer name is required")
    if not body:
        raise HTTPException(400, "Offer body is required")
    enabled = payload.get("enabled")
    # Default to enabled on create; preserve explicit `false` on edit.
    if enabled is None:
        enabled = True
    return {"name": name, "body": body, "enabled": bool(enabled)}


def create_offer(user_id: str, payload: dict) -> dict:
    import uuid as _uuid
    fields = _validate_offer_payload(payload)
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            existing = (u.get("offers") or [])
            if any((o.get("name") or "").lower() == fields["name"].lower() for o in existing):
                raise HTTPException(400, f"Offer '{fields['name']}' already exists")
            now_iso = datetime.now(timezone.utc).isoformat()
            offer = {
                "id": str(_uuid.uuid4()),
                "name": fields["name"],
                "body": fields["body"],
                "enabled": fields["enabled"],
                "created_at": now_iso,
                "updated_at": now_iso,
            }
            u["offers"] = existing + [offer]
            _save_users(data)
            return offer
    raise HTTPException(404, "User not found")


def update_offer(user_id: str, offer_id: str, payload: dict) -> dict:
    fields = _validate_offer_payload(payload)
    now_iso = datetime.now(timezone.utc).isoformat()
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = list(u.get("offers") or [])
            for o in arr:
                if (o.get("name") or "").lower() == fields["name"].lower() \
                        and o.get("id") != offer_id:
                    raise HTTPException(400, f"Offer '{fields['name']}' already exists")
            for o in arr:
                if o.get("id") == offer_id:
                    o["name"] = fields["name"]
                    o["body"] = fields["body"]
                    o["enabled"] = fields["enabled"]
                    o["updated_at"] = now_iso
                    u["offers"] = arr
                    _save_users(data)
                    return o
            raise HTTPException(404, "Offer not found")
    raise HTTPException(404, "User not found")


def set_offer_enabled(user_id: str, offer_id: str, enabled: bool) -> dict:
    """Quick toggle without re-validating the whole payload."""
    now_iso = datetime.now(timezone.utc).isoformat()
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = list(u.get("offers") or [])
            for o in arr:
                if o.get("id") == offer_id:
                    o["enabled"] = bool(enabled)
                    o["updated_at"] = now_iso
                    u["offers"] = arr
                    _save_users(data)
                    return o
            raise HTTPException(404, "Offer not found")
    raise HTTPException(404, "User not found")


def delete_offer(user_id: str, offer_id: str) -> None:
    data = _load_users()
    for u in data["users_by_google_sub"].values():
        if u["id"] == user_id:
            arr = [o for o in (u.get("offers") or []) if o.get("id") != offer_id]
            u["offers"] = arr
            _save_users(data)
            return
    raise HTTPException(404, "User not found")


def send_gmail_email(
    user_id: str,
    to: str,
    subject: str,
    body: str,
    *,
    html_body: str | None = None,
) -> dict:
    """Send an email through the agent's connected Gmail account.

    `body` is the plain-text version (always sent). When `html_body` is
    provided, the email is sent as multipart/alternative — modern mail
    clients render the HTML version; older clients fall back to text.
    Used by the Open House Report flow to ship a styled report inline.

    Returns Gmail's message resource ({id, threadId, labelIds, ...}). Raises
    HTTPException(400) when Gmail isn't connected — the iOS client treats
    that as "show the Connect Gmail prompt".
    """
    import base64
    from email.message import EmailMessage

    refresh = gmail_refresh_token_for(user_id)
    if not refresh:
        raise HTTPException(400, "Gmail not connected")

    access = refresh_gmail_access_token(refresh)
    # Prefer the user's saved Send-as alias when present; fall back to
    # the authenticated mailbox. Gmail silently rewrites unverified
    # aliases, so this is best-effort by design.
    from_email = (gmail_send_from_for(user_id)
                  or gmail_email_for(user_id)
                  or "")

    msg = EmailMessage()
    msg["To"] = to
    if from_email:
        msg["From"] = from_email
    msg["Subject"] = subject
    msg.set_content(body or "")
    if html_body:
        # Adds an HTML alternative — Gmail/Apple Mail render the HTML;
        # plain-text-only clients still see the body above.
        msg.add_alternative(html_body, subtype="html")
    raw = base64.urlsafe_b64encode(bytes(msg)).decode()

    resp = requests.post(
        f"{GMAIL_API_BASE}/users/me/messages/send",
        headers={
            "Authorization": f"Bearer {access}",
            "Content-Type": "application/json",
        },
        json={"raw": raw},
        timeout=20,
    )
    if not resp.ok:
        # Translate Gmail's raw error into something a real estate agent
        # can actually act on. The most common case in practice is a stale
        # refresh token (revoked, expired, or pointing at the wrong
        # account) — we surface "reconnect Gmail" so the iOS / web client
        # can fall through to the Connect Gmail prompt rather than show a
        # scary 502.
        try:
            payload = resp.json()
        except ValueError:
            payload = {}
        err = (payload.get("error") or {}) if isinstance(payload, dict) else {}
        message = err.get("message") or resp.text
        status = err.get("status") or ""
        if resp.status_code == 401 or "invalid_grant" in message.lower() or status == "UNAUTHENTICATED":
            # Wipe the broken credential so the next status fetch shows
            # disconnected — the UI will then offer Connect Gmail.
            clear_gmail_credential(user_id)
            raise HTTPException(400, "Gmail not connected")
        if "insufficient" in message.lower() or "insufficient_scope" in message.lower():
            # Token came back without gmail.send — almost always means
            # the user's Google Workspace admin blocks unverified third-
            # party apps. Wipe so they can reconnect with a personal
            # account without first manually clicking Disconnect.
            clear_gmail_credential(user_id)
            raise HTTPException(
                400,
                "Your Google account didn't grant permission to send mail "
                "(often a Workspace admin policy that blocks third-party "
                "apps). Reconnect with a personal Gmail account, or have "
                "your admin allow this app."
            )
        if resp.status_code == 403:
            raise HTTPException(400, f"Gmail rejected the send: {message}")
        # Anything else — quota, malformed message, etc. — surface the
        # underlying reason rather than bare 502.
        raise HTTPException(400, f"Gmail send failed: {message}")
    return resp.json()
