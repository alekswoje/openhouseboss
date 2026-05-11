import json
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from dotenv import load_dotenv

load_dotenv(override=True)

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

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

_sessions: dict[str, dict] = {}
_sessions_lock = threading.Lock()


def _persist(session_id: str) -> None:
    path = SESSIONS_DIR / session_id / "session.json"
    path.write_text(json.dumps(_sessions[session_id], indent=2, default=str))


def _update(session_id: str, **updates) -> None:
    with _sessions_lock:
        _sessions[session_id].update(updates)
        _persist(session_id)


def _process(session_id: str, audio_path: Optional[Path], mock_path: Optional[Path], visitors_path: Optional[Path], speakers_expected: Optional[int] = None, script_id: Optional[str] = None) -> None:
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

        now_iso = datetime.now(timezone.utc).isoformat()
        visitors_out = []
        for visitor in identification.matched_visitors:
            analysis = analyze_visitor(transcript, visitor, DEFAULT_TAGS)
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
            error=str(e),
            completed_at=datetime.now(timezone.utc).isoformat(),
        )


@app.post("/sessions")
async def create_session(
    audio: Optional[UploadFile] = File(None),
    visitors: Optional[UploadFile] = File(None),
    mock_transcript: Optional[UploadFile] = File(None),
    address: Optional[str] = Form(None),
    speakers_expected: Optional[int] = Form(None),
    script_id: Optional[str] = Form(None),
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
    }
    with _sessions_lock:
        _sessions[session_id] = session
        _persist(session_id)

    threading.Thread(
        target=_process,
        args=(session_id, audio_path, mock_path, visitors_path, speakers_expected, script_id),
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
async def reprocess_session(session_id: str, speakers_expected: Optional[int] = Form(None)):
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
        args=(session_id, audio_path, None, None, speakers_expected, existing_script_id),
        daemon=True,
    ).start()
    return {"id": session_id, "status": "processing"}


_VALID_LEAD_STATUSES = {"drafted", "sent", "replied", "archived"}
_VALID_LEAD_TAGS = {"Buyer", "Seller", "Browser"}


@app.post("/leads")
def create_manual_lead(payload: dict):
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
        f"Hi {first_name},\n\n"
        f"Great meeting you{at_clause} — thanks for stopping by. "
        f"I'd love to stay in touch about your home search. "
        f"Let me know if you'd like to see anything else or have "
        f"questions about the area.\n\n"
        f"Talk soon,"
    )

    session = {
        "id": session_id,
        "status": "ready",
        "kind": "manual",
        "address": address,
        "script_id": None,
        "created_at": now_iso,
        "completed_at": now_iso,
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
def update_visitor_state(session_id: str, payload: dict):
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
        if session is None:
            raise HTTPException(404, f"Session {session_id} not found")

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


@app.get("/sessions/{session_id}/audio")
def get_session_audio(session_id: str):
    """Stream the saved recording so a different device (laptop, iPad) can
    play back a session that was recorded elsewhere. Centralized backend =
    audio lives here, not on the recording device."""
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
def get_session(session_id: str):
    with _sessions_lock:
        session = _sessions.get(session_id)
    if session:
        return session

    path = SESSIONS_DIR / session_id / "session.json"
    if path.exists():
        session = json.loads(path.read_text())
        with _sessions_lock:
            _sessions[session_id] = session
        return session

    raise HTTPException(404, f"Session {session_id} not found")


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
    for entry in SESSIONS_DIR.iterdir():
        if not entry.is_dir():
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
def list_sessions():
    _hydrate_sessions_from_disk()
    with _sessions_lock:
        items = [_summarize(s) for s in _sessions.values()]
    items.sort(key=lambda x: x["created_at"], reverse=True)
    return {"sessions": items}


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
