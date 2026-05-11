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
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from pipeline.analyze import analyze_visitor
from pipeline.identify import identify_agent_and_visitors
from pipeline.mock import load_mock_transcript
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


def _process(session_id: str, audio_path: Optional[Path], mock_path: Optional[Path], visitors_path: Optional[Path], speakers_expected: Optional[int] = None) -> None:
    try:
        if mock_path:
            transcript = load_mock_transcript(mock_path)
        else:
            assert audio_path is not None
            transcript = transcribe_with_speakers(audio_path, speakers_expected=speakers_expected)

        identification = identify_agent_and_visitors(transcript, visitors_path)
        visitors_out = []
        for visitor in identification.matched_visitors:
            analysis = analyze_visitor(transcript, visitor, DEFAULT_TAGS)
            visitors_out.append({
                "visitor": visitor.model_dump(mode="json"),
                "analysis": analysis.model_dump(),
            })

        _update(
            session_id,
            status="ready",
            completed_at=datetime.now(timezone.utc).isoformat(),
            result={
                "agent_speaker": identification.agent_speaker,
                "unmatched_speakers": identification.unmatched_speakers,
                "visitors": visitors_out,
                "full_transcript": transcript.text,
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
        args=(session_id, audio_path, mock_path, visitors_path, speakers_expected),
        daemon=True,
    ).start()
    return {"id": session_id, "status": "processing"}


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
        _sessions[session_id].update({
            "status": "processing",
            "completed_at": None,
            "error": None,
            "speakers_expected": speakers_expected,
        })
        _persist(session_id)

    threading.Thread(
        target=_process,
        args=(session_id, audio_path, None, None, speakers_expected),
        daemon=True,
    ).start()
    return {"id": session_id, "status": "processing"}


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
