"""SQLite-backed mirror of the MLS Grid Property feed.

Schema is narrow on purpose — just the fields the iOS New-Listing form
fills in plus an FTS5 index for type-ahead address search. The full
original record is preserved in `raw_json` so we can fish out additional
fields later (school district, etc.) without re-replicating.

Lives on the Render-attached disk at `sessions/mls.db` so it survives
restarts and redeploys.
"""

import json
import os
import sqlite3
import threading
from pathlib import Path
from typing import Iterable, Optional


_DEFAULT_PATH = Path("sessions") / "mls.db"


def db_path() -> Path:
    raw = os.getenv("MLS_DB_PATH")
    return Path(raw) if raw else _DEFAULT_PATH


_write_lock = threading.Lock()
_conn: Optional[sqlite3.Connection] = None


def _new_connection() -> sqlite3.Connection:
    path = db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path), check_same_thread=False, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    return conn


def _init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
    CREATE TABLE IF NOT EXISTS properties (
        listing_id        TEXT PRIMARY KEY,
        mls               TEXT NOT NULL,
        standard_status   TEXT,
        property_type     TEXT,
        property_subtype  TEXT,
        unparsed_address  TEXT,
        street_number     TEXT,
        street_name       TEXT,
        street_suffix     TEXT,
        unit_number       TEXT,
        city              TEXT,
        state             TEXT,
        postal_code       TEXT,
        county            TEXT,
        subdivision       TEXT,
        list_price        INTEGER,
        bedrooms          INTEGER,
        bathrooms_total   REAL,
        living_area       INTEGER,
        lot_size_sqft     REAL,
        year_built        INTEGER,
        latitude          REAL,
        longitude         REAL,
        photos_count      INTEGER,
        public_remarks    TEXT,
        list_agent_name   TEXT,
        list_office_name  TEXT,
        modification_ts   TEXT,
        updated_at        TEXT NOT NULL,
        raw_json          TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_props_modts  ON properties(modification_ts);
    CREATE INDEX IF NOT EXISTS idx_props_status ON properties(standard_status);
    CREATE INDEX IF NOT EXISTS idx_props_city   ON properties(city);

    CREATE VIRTUAL TABLE IF NOT EXISTS properties_fts USING fts5(
        listing_id UNINDEXED,
        address,
        city,
        postal_code,
        tokenize='unicode61'
    );

    CREATE TABLE IF NOT EXISTS replication_state (
        mls                   TEXT PRIMARY KEY,
        last_modification_ts  TEXT,
        initial_complete      INTEGER DEFAULT 0,
        last_run_at           TEXT,
        last_error            TEXT
    );
    """
    )
    conn.commit()


def db() -> sqlite3.Connection:
    """Process-global connection. SQLite + WAL handles reader concurrency;
    writes are serialized by `_write_lock`."""
    global _conn
    if _conn is None:
        _conn = _new_connection()
        _init_schema(_conn)
    return _conn


def _compose_address(rec: dict) -> str:
    """Prefer the MLS-supplied UnparsedAddress; fall back to composing
    from parts if missing."""
    full = (rec.get("UnparsedAddress") or "").strip()
    if full:
        return full
    parts = [
        rec.get("StreetNumber"),
        rec.get("StreetDirPrefix"),
        rec.get("StreetName"),
        rec.get("StreetSuffix"),
        rec.get("StreetDirSuffix"),
    ]
    return " ".join(str(p) for p in parts if p).strip()


def _int(val) -> Optional[int]:
    return int(val) if isinstance(val, (int, float)) else None


def _float(val) -> Optional[float]:
    return float(val) if isinstance(val, (int, float)) else None


def upsert(records: Iterable[dict]) -> tuple[int, int]:
    """Insert/replace properties. Returns `(kept, deleted)`. Records with
    `MlgCanView=False` are deleted locally per the feed's delete protocol."""
    kept = 0
    deleted = 0
    with _write_lock:
        conn = db()
        cur = conn.cursor()
        try:
            for rec in records:
                listing_id = rec.get("ListingId") or rec.get("ListingKey")
                if not listing_id:
                    continue
                if rec.get("MlgCanView") is False:
                    cur.execute("DELETE FROM properties WHERE listing_id=?", (listing_id,))
                    cur.execute("DELETE FROM properties_fts WHERE listing_id=?", (listing_id,))
                    deleted += 1
                    continue

                address = _compose_address(rec)
                baths = (
                    _float(rec.get("BathroomsTotalInteger"))
                    if rec.get("BathroomsTotalInteger") is not None
                    else _float(rec.get("BathroomsTotal"))
                )
                row = (
                    listing_id,
                    rec.get("OriginatingSystemName") or "",
                    rec.get("StandardStatus"),
                    rec.get("PropertyType"),
                    rec.get("PropertySubType"),
                    address,
                    str(rec.get("StreetNumber") or "") or None,
                    rec.get("StreetName"),
                    rec.get("StreetSuffix"),
                    rec.get("UnitNumber"),
                    rec.get("City"),
                    rec.get("StateOrProvince"),
                    rec.get("PostalCode"),
                    rec.get("CountyOrParish"),
                    rec.get("SubdivisionName"),
                    _int(rec.get("ListPrice")),
                    _int(rec.get("BedroomsTotal")),
                    baths,
                    _int(rec.get("LivingArea")),
                    _float(rec.get("LotSizeSquareFeet")),
                    _int(rec.get("YearBuilt")),
                    rec.get("Latitude"),
                    rec.get("Longitude"),
                    _int(rec.get("PhotosCount")),
                    rec.get("PublicRemarks"),
                    rec.get("ListAgentFullName"),
                    rec.get("ListOfficeName"),
                    rec.get("ModificationTimestamp"),
                    rec.get("ModificationTimestamp"),
                    json.dumps(rec, default=str),
                )
                cur.execute(
                    """
                    INSERT INTO properties (
                        listing_id, mls, standard_status, property_type,
                        property_subtype, unparsed_address,
                        street_number, street_name, street_suffix, unit_number,
                        city, state, postal_code, county, subdivision,
                        list_price, bedrooms, bathrooms_total, living_area,
                        lot_size_sqft, year_built, latitude, longitude,
                        photos_count, public_remarks, list_agent_name,
                        list_office_name, modification_ts, updated_at, raw_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(listing_id) DO UPDATE SET
                        mls=excluded.mls,
                        standard_status=excluded.standard_status,
                        property_type=excluded.property_type,
                        property_subtype=excluded.property_subtype,
                        unparsed_address=excluded.unparsed_address,
                        street_number=excluded.street_number,
                        street_name=excluded.street_name,
                        street_suffix=excluded.street_suffix,
                        unit_number=excluded.unit_number,
                        city=excluded.city,
                        state=excluded.state,
                        postal_code=excluded.postal_code,
                        county=excluded.county,
                        subdivision=excluded.subdivision,
                        list_price=excluded.list_price,
                        bedrooms=excluded.bedrooms,
                        bathrooms_total=excluded.bathrooms_total,
                        living_area=excluded.living_area,
                        lot_size_sqft=excluded.lot_size_sqft,
                        year_built=excluded.year_built,
                        latitude=excluded.latitude,
                        longitude=excluded.longitude,
                        photos_count=excluded.photos_count,
                        public_remarks=excluded.public_remarks,
                        list_agent_name=excluded.list_agent_name,
                        list_office_name=excluded.list_office_name,
                        modification_ts=excluded.modification_ts,
                        updated_at=excluded.updated_at,
                        raw_json=excluded.raw_json
                    """,
                    row,
                )
                cur.execute("DELETE FROM properties_fts WHERE listing_id=?", (listing_id,))
                cur.execute(
                    "INSERT INTO properties_fts (listing_id, address, city, postal_code) VALUES (?, ?, ?, ?)",
                    (listing_id, address, rec.get("City") or "", rec.get("PostalCode") or ""),
                )
                kept += 1
            conn.commit()
        finally:
            cur.close()
    return kept, deleted


def autocomplete(query: str, limit: int = 10) -> list[dict]:
    """FTS5 prefix match across address, city, postal code. Returns slim
    dicts for the iOS dropdown — full details come from `get_property`."""
    q = (query or "").strip()
    if not q:
        return []
    tokens = [t for t in q.replace(",", " ").split() if t.isalnum() or any(c.isalnum() for c in t)]
    if not tokens:
        return []
    fts_query = " ".join(f'"{t}"*' for t in tokens)
    cur = db().cursor()
    try:
        cur.execute(
            """
            SELECT p.listing_id, p.unparsed_address, p.city, p.state,
                   p.postal_code, p.list_price, p.bedrooms, p.bathrooms_total,
                   p.living_area, p.standard_status, p.photos_count
            FROM properties_fts f
            JOIN properties     p ON p.listing_id = f.listing_id
            WHERE properties_fts MATCH ?
              AND p.standard_status = 'Active'
            ORDER BY p.list_price IS NULL, p.list_price DESC
            LIMIT ?
            """,
            (fts_query, limit),
        )
        return [dict(r) for r in cur.fetchall()]
    except sqlite3.OperationalError:
        return []
    finally:
        cur.close()


def get_property(listing_id: str) -> Optional[dict]:
    cur = db().cursor()
    try:
        cur.execute("SELECT * FROM properties WHERE listing_id=?", (listing_id,))
        row = cur.fetchone()
        if not row:
            return None
        d = dict(row)
        raw = d.pop("raw_json", None)
        if raw:
            try:
                d["raw"] = json.loads(raw)
            except json.JSONDecodeError:
                d["raw"] = None
        return d
    finally:
        cur.close()


def get_state(mls: str) -> dict:
    cur = db().cursor()
    try:
        cur.execute("SELECT * FROM replication_state WHERE mls=?", (mls,))
        row = cur.fetchone()
        return dict(row) if row else {
            "mls": mls,
            "last_modification_ts": None,
            "initial_complete": 0,
            "last_run_at": None,
            "last_error": None,
        }
    finally:
        cur.close()


def set_state(mls: str, **kwargs) -> None:
    with _write_lock:
        conn = db()
        cur = conn.cursor()
        try:
            current = get_state(mls)
            current.update(kwargs)
            cur.execute(
                """
                INSERT INTO replication_state (mls, last_modification_ts, initial_complete, last_run_at, last_error)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(mls) DO UPDATE SET
                    last_modification_ts=excluded.last_modification_ts,
                    initial_complete=excluded.initial_complete,
                    last_run_at=excluded.last_run_at,
                    last_error=excluded.last_error
                """,
                (
                    current["mls"],
                    current["last_modification_ts"],
                    int(current["initial_complete"] or 0),
                    current["last_run_at"],
                    current["last_error"],
                ),
            )
            conn.commit()
        finally:
            cur.close()


def stats() -> dict:
    cur = db().cursor()
    try:
        cur.execute("SELECT COUNT(*) AS n FROM properties WHERE standard_status='Active'")
        active = cur.fetchone()["n"]
        cur.execute("SELECT COUNT(*) AS n FROM properties")
        total = cur.fetchone()["n"]
        cur.execute("SELECT MAX(modification_ts) AS m FROM properties")
        latest = cur.fetchone()["m"]
        return {"active": active, "total": total, "latest_modification_ts": latest}
    finally:
        cur.close()
