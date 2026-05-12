"""MLS Grid RESO Web API client.

Replication-only feed at api.mlsgrid.com/v2 (or api-demo.mlsgrid.com/v2
for test data). OAuth2 Bearer auth via long-lived token from the vendor
admin. We use this to mirror NWMLS active residential listings into a
local SQLite store so the iOS New-Listing form can do type-ahead address
autocomplete; MLS Grid itself does not support address search.

Env vars:
    MLS_GRID_TOKEN              — bearer token from the vendor admin
    MLS_GRID_BASE_URL           — defaults to https://api.mlsgrid.com/v2
                                  set to https://api-demo.mlsgrid.com/v2
                                  while iterating against demo data
    MLS_GRID_ORIGINATING_SYSTEM — defaults to "nwmls"
"""

import logging
import os
import time
from typing import Iterator, Optional
from urllib.parse import quote

import requests

log = logging.getLogger("ohb.mls")

# MLS Grid caps us at 2 RPS. We throttle to 1 RPS to leave headroom for
# any on-demand fetch (e.g. fetch_listing_by_id) that runs alongside the
# background replicator.
_MIN_INTERVAL_S = 1.0
_last_call_at: float = 0.0


def _throttle() -> None:
    global _last_call_at
    wait = _MIN_INTERVAL_S - (time.monotonic() - _last_call_at)
    if wait > 0:
        time.sleep(wait)
    _last_call_at = time.monotonic()


def base_url() -> str:
    return os.getenv("MLS_GRID_BASE_URL", "https://api.mlsgrid.com/v2").rstrip("/")


def origin_system() -> str:
    return os.getenv("MLS_GRID_ORIGINATING_SYSTEM", "nwmls")


def token() -> Optional[str]:
    return os.getenv("MLS_GRID_TOKEN") or None


def _headers(tok: str) -> dict:
    return {
        "Authorization": f"Bearer {tok}",
        "Accept": "application/json",
        "Accept-Encoding": "gzip",
    }


def fetch_page(url: str, tok: str, timeout: float = 60.0) -> dict:
    """Single GET against the API. Honors the rate limit and waits a minute
    if we get HTTP 429 before retrying once."""
    _throttle()
    resp = requests.get(url, headers=_headers(tok), timeout=timeout)
    if resp.status_code == 429:
        log.warning("mls_grid 429 rate-limited; sleeping 60s")
        time.sleep(60)
        resp = requests.get(url, headers=_headers(tok), timeout=timeout)
    resp.raise_for_status()
    return resp.json()


def _filter_str(parts: list[str]) -> str:
    return quote(" and ".join(parts), safe=":,'")


def build_initial_active_query(page_size: int = 1000) -> str:
    """First-pull query: every active residential listing the feed will
    serve us. We filter by both PropertyType and StandardStatus on the
    server to keep the initial dataset small (~10–30k for NWMLS)."""
    flt = _filter_str([
        f"OriginatingSystemName eq '{origin_system()}'",
        "MlgCanView eq true",
        "PropertyType eq 'Residential'",
        "StandardStatus eq 'Active'",
    ])
    return f"{base_url()}/Property?$filter={flt}&$top={page_size}"


def build_delta_query(modification_gt: str, page_size: int = 1000) -> str:
    """Delta query: everything modified since the watermark, including
    records flipped to MlgCanView=false so the store can delete them."""
    flt = _filter_str([
        f"OriginatingSystemName eq '{origin_system()}'",
        f"ModificationTimestamp gt {modification_gt}",
    ])
    return f"{base_url()}/Property?$filter={flt}&$top={page_size}"


def iterate_properties(url: str, tok: str) -> Iterator[dict]:
    """Yield each Property record across all pages, following @odata.nextLink."""
    while url:
        payload = fetch_page(url, tok)
        for record in payload.get("value") or []:
            yield record
        url = payload.get("@odata.nextLink") or ""


def fetch_listing_by_id(listing_id: str, tok: str) -> Optional[dict]:
    """One-shot single-record lookup by prefixed ListingId (e.g. NWM12345).
    Used by the manual MLS# fallback path; the autocomplete UI hits the
    local store instead."""
    flt = _filter_str([
        f"OriginatingSystemName eq '{origin_system()}'",
        f"ListingId eq '{listing_id}'",
    ])
    url = f"{base_url()}/Property?$filter={flt}&$top=1"
    data = fetch_page(url, tok)
    rows = data.get("value") or []
    return rows[0] if rows else None
