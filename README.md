# OpenHouseBoss

Open-house audio → diarized transcript → per-visitor summary, tag, and drafted follow-up.

## Setup

```
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env  # fill in your keys
```

## Run the pipeline

With real audio:
```
python -m pipeline.cli --audio path/to/audio.m4a --visitors samples/visitors.csv
```

With a mock transcript (no audio needed — useful for iterating on prompts):
```
python -m pipeline.cli --mock-transcript samples/mock_transcript.json --visitors samples/visitors.csv
```

Writes `results.json` with one entry per matched visitor: summary, tag, and drafted follow-up message.

## Run the backend (HTTP API + browser test page)

```
uvicorn backend.server:app --reload
```

Then open http://127.0.0.1:8000 for the drag-drop test page, or call the API:

- `POST /sessions` — multipart form: `visitors` (CSV, required), plus either `audio` or `mock_transcript` (JSON). Returns `{id, status: "processing"}`.
- `GET /sessions/{id}` — returns `{status, result, error}`. Poll until `status == "ready"`.
- `GET /sessions` — list all sessions.

Sessions persist to `sessions/<id>/session.json` on disk for inspection.

## Visitors CSV format

Columns: `name,email,phone,signed_in_at` (ISO-8601 timestamp). See `samples/visitors.csv`.

## Repo layout

```
pipeline/      CLI + core pipeline (transcribe → identify → analyze)
backend/       FastAPI server + browser test page
samples/       Mock transcript + sample visitors CSV
sessions/      Created at runtime; one dir per uploaded session
```
