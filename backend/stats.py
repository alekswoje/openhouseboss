"""Per-session stats — durable storage + aggregations for the Insights tab.

One row per completed session, denormalized so the dashboard can answer
"best day of week", "best hour of day", "score distribution" etc. with
group-by queries instead of re-reading every session.json on every load.

Data flow:
  - Session completes → capture_session_stats(session, user_id) writes/upserts
    a row in session_stats.
  - Insights tab calls query_insights(user_id, period) → returns precomputed
    aggregations.
  - On backend boot, backfill_from_disk() scans sessions/{id}/session.json
    for any rows missing from the DB and inserts them. Idempotent — re-runs
    are safe (upsert keyed by session_id).

Storage:
  - If DATABASE_URL is set (Render Postgres add-on): Postgres.
  - Otherwise: SQLite at sessions/_auth/stats.db so local dev "just works"
    without spinning up a postgres container.
"""
import json
import os
import threading
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional

from sqlalchemy import (
    Boolean, Column, DateTime, Float, Integer, MetaData, String, Table,
    case, create_engine, func, select, text,
)
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.engine import Engine


_SESSIONS_DIR = Path("sessions")
_SQLITE_PATH = _SESSIONS_DIR / "_auth" / "stats.db"
_metadata = MetaData()


# Single denormalized table — one row per completed session. Every column
# the Insights dashboard groups or filters on is materialized here so the
# aggregation queries stay cheap. We re-derive everything from session.json
# on capture, so a schema change is just a backfill away.
session_stats = Table(
    "session_stats", _metadata,

    # Identity
    Column("session_id", String(64), primary_key=True),
    Column("user_id", String(64), nullable=False, index=True),

    # Timing — kept BOTH as a UTC timestamp and as denormalized day/hour
    # tokens. Group-by on day_of_week / hour_of_day stays trivial, but
    # callers that need the actual instant still have it.
    Column("created_at", DateTime(timezone=True), nullable=False, index=True),
    Column("completed_at", DateTime(timezone=True), nullable=True),
    Column("day_of_week", Integer, nullable=False),     # 0=Mon … 6=Sun
    Column("hour_of_day", Integer, nullable=False),     # 0-23 local? UTC. Caller-side display formats.
    Column("duration_min", Integer, nullable=False, default=0),

    # Address — for "best-performing listings" rollups + the row label in
    # the timeline. Free-text; multiple sessions at the same address
    # group naturally.
    Column("address", String(256), nullable=True),

    # Visitor breakdown — all integers so SUM/AVG queries work.
    Column("visitor_count_total", Integer, nullable=False, default=0),
    Column("visitor_count_buyer", Integer, nullable=False, default=0),
    Column("visitor_count_seller", Integer, nullable=False, default=0),
    Column("visitor_count_browser", Integer, nullable=False, default=0),
    Column("hot_visitor_count", Integer, nullable=False, default=0),       # score >= 70
    Column("warm_visitor_count", Integer, nullable=False, default=0),      # 40-69
    Column("cold_visitor_count", Integer, nullable=False, default=0),      # 0-39
    Column("avg_visitor_score", Float, nullable=False, default=0.0),
    Column("max_visitor_score", Integer, nullable=False, default=0),

    # Engagement — total words across all parties; lets us reason about
    # "did the agent talk too much" if we ever surface that.
    Column("words_spoken_agent", Integer, nullable=False, default=0),
    Column("words_spoken_visitors", Integer, nullable=False, default=0),

    # Performance — script coverage score from the existing pipeline.
    Column("script_coverage_score", Integer, nullable=True),

    # Post-session actions — capture how the agent followed up. Drives
    # the "what % of sessions ended with a report sent" KPI.
    Column("followups_sent_count", Integer, nullable=False, default=0),
    Column("report_generated", Boolean, nullable=False, default=False),
    Column("report_sent", Boolean, nullable=False, default=False),

    # Weather (Phase 4 — nullable for now).
    Column("weather_temp_f", Float, nullable=True),
    Column("weather_summary", String(64), nullable=True),

    # Bookkeeping — when the stats row was last refreshed. Useful for
    # debugging stale captures.
    Column("updated_at", DateTime(timezone=True), nullable=False),
)


# Lazy-init the engine so importing this module is cheap (the FastAPI
# app imports a lot at startup; we don't want to pay for a Postgres
# connection until the first query actually fires).
_engine: Optional[Engine] = None
_engine_lock = threading.Lock()


def _resolve_database_url() -> str:
    """Pick Postgres when DATABASE_URL is set (Render's convention), fall
    back to a local SQLite file otherwise.

    Render's Postgres add-on exposes the URL as 'postgres://...'. SQLAlchemy
    2.x dropped the 'postgres://' alias and requires 'postgresql://', so
    we normalize that one wart here."""
    url = (os.environ.get("DATABASE_URL") or "").strip()
    if url:
        if url.startswith("postgres://"):
            url = "postgresql://" + url[len("postgres://"):]
        return url
    # Local dev fallback. _auth/ already exists (auth.py creates it on
    # import) so we don't need to mkdir.
    _SQLITE_PATH.parent.mkdir(parents=True, exist_ok=True)
    return f"sqlite:///{_SQLITE_PATH}"


def get_engine() -> Engine:
    global _engine
    if _engine is not None:
        return _engine
    with _engine_lock:
        if _engine is not None:
            return _engine
        url = _resolve_database_url()
        # `future=True` is the default in 2.x; keeping the call short.
        # pool_pre_ping handles Render's idle-disconnect cleanly so we
        # don't see "server closed the connection" on the first query
        # after a slow stretch.
        connect_args: dict[str, Any] = {}
        if url.startswith("sqlite"):
            connect_args["check_same_thread"] = False
        _engine = create_engine(url, pool_pre_ping=True, connect_args=connect_args)
        _metadata.create_all(_engine)
    return _engine


# --- Capture --------------------------------------------------------------


def _parse_iso(ts: Optional[str]) -> Optional[datetime]:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def _derive_stats(session: dict, user_id: str) -> Optional[dict]:
    """Pull the denormalized fields out of a session dict. Returns None if
    the session isn't ready to be captured (no result yet, missing
    timestamps, etc.) — caller is expected to skip those."""
    session_id = session.get("id")
    if not session_id:
        return None
    created_dt = _parse_iso(session.get("created_at"))
    if not created_dt:
        return None
    completed_dt = _parse_iso(session.get("completed_at"))

    result = session.get("result") or {}
    visitors = result.get("visitors") or []
    utterances = result.get("utterances") or []

    # Bucket visitors by tag + score
    buyer = seller = browser = 0
    hot = warm = cold = 0
    scores: list[int] = []
    for v in visitors:
        analysis = v.get("analysis") or {}
        tag = (analysis.get("tag") or "Browser").lower()
        if tag == "buyer":   buyer += 1
        elif tag == "seller": seller += 1
        else:                 browser += 1
        score = int(analysis.get("score") or 0)
        scores.append(score)
        if score >= 70:    hot += 1
        elif score >= 40:  warm += 1
        else:              cold += 1

    # Words by speaker bucket. agent_speaker tells us which utterances
    # belong to the agent; the rest are visitors collectively.
    agent_speaker = (result.get("agent_speaker") or "").strip()
    words_agent = 0
    words_visitors = 0
    end_ms = 0
    for u in utterances:
        wc = len((u.get("text") or "").split())
        if u.get("speaker") == agent_speaker:
            words_agent += wc
        else:
            words_visitors += wc
        end_ms = max(end_ms, u.get("end_ms") or u.get("start_ms") or 0)

    coverage = result.get("script_coverage") or {}
    coverage_score = coverage.get("score")
    if coverage_score is not None:
        try:
            coverage_score = int(coverage_score)
        except (TypeError, ValueError):
            coverage_score = None

    # Follow-ups sent — count lead_state.sent_emails across all visitors.
    followups = 0
    for v in visitors:
        ls = v.get("lead_state") or {}
        followups += len(ls.get("sent_emails") or [])

    report_meta = session.get("report_meta") or {}
    report_generated = bool(session.get("report"))
    report_sent = bool(report_meta.get("sent_at"))

    return {
        "session_id":              session_id,
        "user_id":                 user_id,
        "created_at":              created_dt,
        "completed_at":            completed_dt,
        "day_of_week":             created_dt.weekday(),
        "hour_of_day":             created_dt.hour,
        "duration_min":            int(end_ms / 60_000) if end_ms else 0,
        "address":                 (session.get("address") or None),
        "visitor_count_total":     len(visitors),
        "visitor_count_buyer":     buyer,
        "visitor_count_seller":    seller,
        "visitor_count_browser":   browser,
        "hot_visitor_count":       hot,
        "warm_visitor_count":      warm,
        "cold_visitor_count":      cold,
        "avg_visitor_score":       (sum(scores) / len(scores)) if scores else 0.0,
        "max_visitor_score":       max(scores) if scores else 0,
        "words_spoken_agent":      words_agent,
        "words_spoken_visitors":   words_visitors,
        "script_coverage_score":   coverage_score,
        "followups_sent_count":    followups,
        "report_generated":        report_generated,
        "report_sent":             report_sent,
        # Weather columns left null until Phase 4 wires Open-Meteo.
        "weather_temp_f":          None,
        "weather_summary":         None,
        "updated_at":              datetime.now(timezone.utc),
    }


def _upsert_stmt(engine: Engine, row: dict):
    """Use dialect-specific INSERT ... ON CONFLICT so a re-capture (e.g.
    after the agent sends the report) replaces the row instead of
    duplicating. Postgres and SQLite have different syntaxes; SQLAlchemy
    gives us a clean path for each."""
    if engine.dialect.name == "postgresql":
        stmt = pg_insert(session_stats).values(**row)
        return stmt.on_conflict_do_update(
            index_elements=["session_id"],
            set_={k: v for k, v in row.items() if k != "session_id"},
        )
    # SQLite (and any other future dialect): treat ON CONFLICT the same
    # way. Other dialects would need their own branch.
    stmt = sqlite_insert(session_stats).values(**row)
    return stmt.on_conflict_do_update(
        index_elements=["session_id"],
        set_={k: v for k, v in row.items() if k != "session_id"},
    )


def capture_session_stats(session: dict, user_id: str) -> bool:
    """Insert/update a stats row for one session. Returns True if a row
    was written, False if the session wasn't capture-ready (no result
    yet, malformed timestamps). Idempotent — safe to call multiple times
    as the session evolves (e.g. once when analysis finishes, again when
    the report is sent)."""
    row = _derive_stats(session, user_id)
    if row is None:
        return False
    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(_upsert_stmt(engine, row))
    return True


def backfill_from_disk(default_user_id: Optional[str] = None) -> int:
    """One-shot scan: read every sessions/{id}/session.json on disk and
    upsert a row for each. Idempotent — used on cold start to catch
    sessions that completed before this module existed, and any session
    that finished while the previous backend crash was being investigated.

    Returns the count of rows written. Sessions with no `user_id` field
    (orphans created pre-auth) get attributed to `default_user_id` when
    provided, otherwise are skipped (we can't safely guess who owns them)."""
    written = 0
    if not _SESSIONS_DIR.exists():
        return 0
    for entry in _SESSIONS_DIR.iterdir():
        if not entry.is_dir() or entry.name.startswith("_"):
            continue
        path = entry / "session.json"
        if not path.exists():
            continue
        try:
            session = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        user_id = session.get("user_id") or default_user_id
        if not user_id:
            continue
        if session.get("status") != "ready":
            continue
        if capture_session_stats(session, user_id):
            written += 1
    return written


# --- Aggregations ---------------------------------------------------------


PERIOD_DAYS = {
    "week":  7,
    "month": 30,
    "year":  365,
}


def _period_cutoff(period: str) -> Optional[datetime]:
    """Returns the UTC instant marking the start of the period, or None
    for 'all' (no filter)."""
    days = PERIOD_DAYS.get(period)
    if days is None:
        return None
    return datetime.now(timezone.utc) - timedelta(days=days)


def query_insights(user_id: str, period: str = "month") -> dict:
    """Return the dashboard payload for the Insights tab. Single round
    trip — all aggregations computed in one connection block.

    Shape:
      {
        period: "month",
        session_count: 12,
        visitor_count: 87,
        hot_visitor_count: 14,
        reports_sent_count: 9,
        report_send_rate: 0.75,
        avg_visitors_per_session: 7.25,
        avg_score: 38.2,
        avg_duration_min: 92,
        by_day_of_week: [{day: 0, sessions: 1, visitors: 5, hot: 1}, ...],
        by_hour_of_day: [{hour: 12, ...}, ...],
        best_day_of_week: 5,            # 0..6 or null
        best_hour_of_day: 13,           # 0..23 or null
        recent_sessions: [{session_id, address, created_at, visitor_count_total, hot_visitor_count, avg_visitor_score, report_sent}, ...]
      }
    """
    cutoff = _period_cutoff(period)
    engine = get_engine()

    where = [session_stats.c.user_id == user_id]
    if cutoff is not None:
        where.append(session_stats.c.created_at >= cutoff)

    with engine.connect() as conn:
        # Totals
        totals_q = select(
            func.count(session_stats.c.session_id).label("session_count"),
            func.coalesce(func.sum(session_stats.c.visitor_count_total), 0).label("visitor_count"),
            func.coalesce(func.sum(session_stats.c.hot_visitor_count), 0).label("hot_visitor_count"),
            func.coalesce(func.sum(session_stats.c.followups_sent_count), 0).label("followups_sent_count"),
            func.coalesce(
                func.sum(case((session_stats.c.report_sent == True, 1), else_=0)),
                0
            ).label("reports_sent_count"),
            func.coalesce(func.avg(session_stats.c.avg_visitor_score), 0.0).label("avg_score"),
            func.coalesce(func.avg(session_stats.c.duration_min), 0.0).label("avg_duration_min"),
        ).where(*where)
        totals = conn.execute(totals_q).mappings().first() or {}

        # Group by day of week (0..6, Mon..Sun)
        dow_q = (
            select(
                session_stats.c.day_of_week,
                func.count().label("sessions"),
                func.coalesce(func.sum(session_stats.c.visitor_count_total), 0).label("visitors"),
                func.coalesce(func.sum(session_stats.c.hot_visitor_count), 0).label("hot"),
                func.coalesce(func.avg(session_stats.c.avg_visitor_score), 0.0).label("avg_score"),
            )
            .where(*where)
            .group_by(session_stats.c.day_of_week)
            .order_by(session_stats.c.day_of_week)
        )
        by_dow = [dict(r) for r in conn.execute(dow_q).mappings().all()]

        # Group by hour (0..23 UTC — caller renders in local time)
        hour_q = (
            select(
                session_stats.c.hour_of_day,
                func.count().label("sessions"),
                func.coalesce(func.sum(session_stats.c.visitor_count_total), 0).label("visitors"),
                func.coalesce(func.sum(session_stats.c.hot_visitor_count), 0).label("hot"),
                func.coalesce(func.avg(session_stats.c.avg_visitor_score), 0.0).label("avg_score"),
            )
            .where(*where)
            .group_by(session_stats.c.hour_of_day)
            .order_by(session_stats.c.hour_of_day)
        )
        by_hour = [dict(r) for r in conn.execute(hour_q).mappings().all()]

        # Recent sessions — 20 most-recent rows for the timeline + table.
        recent_q = (
            select(
                session_stats.c.session_id,
                session_stats.c.address,
                session_stats.c.created_at,
                session_stats.c.duration_min,
                session_stats.c.visitor_count_total,
                session_stats.c.hot_visitor_count,
                session_stats.c.avg_visitor_score,
                session_stats.c.script_coverage_score,
                session_stats.c.report_sent,
            )
            .where(*where)
            .order_by(session_stats.c.created_at.desc())
            .limit(20)
        )
        recent = [
            {
                **dict(r),
                # JSON-serializable timestamp
                "created_at": r["created_at"].isoformat() if r["created_at"] else None,
            }
            for r in conn.execute(recent_q).mappings().all()
        ]

    session_count = int(totals.get("session_count") or 0)
    visitor_count = int(totals.get("visitor_count") or 0)
    reports_sent = int(totals.get("reports_sent_count") or 0)
    avg_visitors = (visitor_count / session_count) if session_count else 0.0
    report_send_rate = (reports_sent / session_count) if session_count else 0.0

    # Best day/hour: pick the bucket with the highest visitor-count signal.
    # Falls back to None if the period has no data (avoids confusing
    # "best day = Monday" on a 0-session week).
    best_dow = max(by_dow, key=lambda r: r["visitors"])["day_of_week"] if by_dow else None
    best_hour = max(by_hour, key=lambda r: r["visitors"])["hour_of_day"] if by_hour else None

    return {
        "period": period,
        "session_count": session_count,
        "visitor_count": visitor_count,
        "hot_visitor_count": int(totals.get("hot_visitor_count") or 0),
        "reports_sent_count": reports_sent,
        "report_send_rate": round(report_send_rate, 3),
        "followups_sent_count": int(totals.get("followups_sent_count") or 0),
        "avg_visitors_per_session": round(avg_visitors, 2),
        "avg_score": round(float(totals.get("avg_score") or 0.0), 1),
        "avg_duration_min": round(float(totals.get("avg_duration_min") or 0.0), 1),
        "by_day_of_week": by_dow,
        "by_hour_of_day": by_hour,
        "best_day_of_week": best_dow,
        "best_hour_of_day": best_hour,
        "recent_sessions": recent,
    }


