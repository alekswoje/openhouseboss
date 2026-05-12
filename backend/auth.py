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
    """{connected, email} — used by iOS to decide whether to show the
    Connect Gmail prompt or jump straight to sending."""
    user = get_user_by_id(user_id)
    if not user:
        return {"connected": False, "email": None}
    return {
        "connected": bool(user.get("gmail_refresh_token")),
        "email": user.get("gmail_account_email"),
    }


def gmail_refresh_token_for(user_id: str) -> Optional[str]:
    user = get_user_by_id(user_id)
    return user.get("gmail_refresh_token") if user else None


def gmail_email_for(user_id: str) -> Optional[str]:
    user = get_user_by_id(user_id)
    return user.get("gmail_account_email") if user else None


def send_gmail_email(
    user_id: str,
    to: str,
    subject: str,
    body: str,
) -> dict:
    """Send a plain-text email through the agent's connected Gmail account.

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
    from_email = gmail_email_for(user_id) or ""

    msg = EmailMessage()
    msg["To"] = to
    if from_email:
        msg["From"] = from_email
    msg["Subject"] = subject
    msg.set_content(body or "")
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
        raise HTTPException(502, f"Gmail send failed: {resp.text}")
    return resp.json()
