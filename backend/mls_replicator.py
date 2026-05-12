"""Background MLS Grid replicator.

Polls the Property feed for the configured OriginatingSystem (default
`nwmls`) on a fixed cadence. The initial pull pages through every active
residential listing; subsequent runs use a delta query keyed on
`ModificationTimestamp gt <watermark>` so we only fetch what changed.

Starts at app boot if `MLS_GRID_TOKEN` is set; silently no-ops otherwise
so the rest of the backend keeps working in environments without the
token (local dev, ephemeral preview deploys).
"""

import logging
import os
import threading
import time
from datetime import datetime, timezone
from typing import Optional

from pipeline import mls_grid
from backend import mls_store

log = logging.getLogger("ohb.mls.replicator")


def _enabled() -> bool:
    return bool(mls_grid.token())


def _poll_interval() -> float:
    try:
        return max(15.0, float(os.getenv("MLS_POLL_INTERVAL_SECONDS", "60")))
    except ValueError:
        return 60.0


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _batched(it, size):
    batch: list[dict] = []
    for x in it:
        batch.append(x)
        if len(batch) >= size:
            yield batch
            batch = []
    if batch:
        yield batch


def _initial_pull(tok: str, mls: str) -> Optional[str]:
    """Page through every active residential listing. Returns the greatest
    ModificationTimestamp seen so the next delta picks up where we left off."""
    url = mls_grid.build_initial_active_query()
    log.info("mls.replicator initial-pull start mls=%s", mls)
    max_ts: Optional[str] = None
    kept_total = 0
    for batch in _batched(mls_grid.iterate_properties(url, tok), 500):
        for rec in batch:
            ts = rec.get("ModificationTimestamp")
            if ts and (max_ts is None or ts > max_ts):
                max_ts = ts
        kept, _ = mls_store.upsert(batch)
        kept_total += kept
        if max_ts:
            mls_store.set_state(mls, last_modification_ts=max_ts, last_run_at=_now_iso())
        log.info("mls.replicator initial-pull batch kept=%d running_total=%d", kept, kept_total)
    mls_store.set_state(mls, initial_complete=1, last_run_at=_now_iso())
    log.info("mls.replicator initial-pull complete total=%d max_ts=%s", kept_total, max_ts)
    return max_ts


def _delta_pull(tok: str, mls: str, watermark: str) -> str:
    """Pull everything modified since the watermark. Includes deletes."""
    url = mls_grid.build_delta_query(watermark)
    max_ts = watermark
    kept_total = 0
    deleted_total = 0
    for batch in _batched(mls_grid.iterate_properties(url, tok), 500):
        for rec in batch:
            ts = rec.get("ModificationTimestamp")
            if ts and ts > max_ts:
                max_ts = ts
        kept, deleted = mls_store.upsert(batch)
        kept_total += kept
        deleted_total += deleted
    if kept_total or deleted_total:
        log.info(
            "mls.replicator delta kept=%d deleted=%d max_ts=%s",
            kept_total, deleted_total, max_ts,
        )
        mls_store.set_state(mls, last_modification_ts=max_ts, last_run_at=_now_iso())
    return max_ts


def _loop() -> None:
    tok = mls_grid.token()
    if not tok:
        log.info("mls.replicator disabled (MLS_GRID_TOKEN not set)")
        return
    mls = mls_grid.origin_system()
    log.info("mls.replicator starting mls=%s base=%s", mls, mls_grid.base_url())

    while True:
        state = mls_store.get_state(mls)
        try:
            if not state.get("initial_complete"):
                _initial_pull(tok, mls)
            else:
                watermark = state.get("last_modification_ts")
                if watermark:
                    _delta_pull(tok, mls, watermark)
            mls_store.set_state(mls, last_error=None, last_run_at=_now_iso())
        except Exception as e:
            log.exception("mls.replicator error: %s", e)
            mls_store.set_state(mls, last_error=str(e)[:500], last_run_at=_now_iso())
        time.sleep(_poll_interval())


_thread: Optional[threading.Thread] = None


def start() -> None:
    global _thread
    if not _enabled():
        return
    if _thread is not None and _thread.is_alive():
        return
    _thread = threading.Thread(target=_loop, daemon=True, name="mls-replicator")
    _thread.start()
