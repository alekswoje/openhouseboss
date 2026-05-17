"""Open-Meteo weather lookup, point-resolution.

Why Open-Meteo: free, no key, accurate at the lat/lon level (not "city in
general"), and serves both recent (past ~90 days via the forecast endpoint
with past_days) and historical (via the archive endpoint) data from the
same JSON shape. We use it strictly point-to-point — the agent's iOS client
geocodes the property address via CLGeocoder and passes lat/lon at session
creation. We don't accept "city" as a fallback because that's exactly the
imprecision the user explicitly ruled out.

Fetch flow:
  1. Session reaches status="ready" → background thread calls
     enrich_session_with_weather(session)
  2. We pick the hour that matches the session's midpoint (more
     representative than the start instant — agents arrive 30+ minutes
     early to set up)
  3. The result lands on session["weather"] = {temp_f, condition_label,
     condition_code, wind_mph, humidity_pct, precipitation_in,
     cloud_cover_pct, fetched_at}

All network errors are swallowed and logged — weather is decorative; a
500 from Open-Meteo or a missing latitude must NEVER block the agent's
ability to view a session or send a report.
"""
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

import requests

log = logging.getLogger(__name__)

# Forecast endpoint covers ~92 days of past + ~16 days forecast in one
# request. We stick to past_days=7 — agents see "stats for this open
# house" the same week they record, beyond that the report is already
# generated and weather is moot.
_OPEN_METEO_FORECAST = "https://api.open-meteo.com/v1/forecast"
_OPEN_METEO_ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"

# Older sessions whose weather we still want (e.g. backfill) hit the
# archive endpoint instead. ERA5-based; lags ~5 days behind real-time.
_ARCHIVE_CUTOFF_DAYS = 5

_REQUEST_TIMEOUT_S = 8  # forgiving — Open-Meteo is usually <1s but we'd
                       # rather a slow link not block the snapshot pipe


# WMO weather codes — same set the Open-Meteo docs publish. Mapped to
# short labels we put in the report header. Buckets are deliberately
# coarse: agents don't need "isolated thunderstorm with hail", they need
# "thunderstorm". Full spec at https://open-meteo.com/en/docs.
_WMO_LABELS: dict[int, str] = {
    0:  "Clear",
    1:  "Mostly clear",
    2:  "Partly cloudy",
    3:  "Overcast",
    45: "Foggy",
    48: "Foggy",
    51: "Light drizzle",
    53: "Drizzle",
    55: "Heavy drizzle",
    56: "Freezing drizzle",
    57: "Freezing drizzle",
    61: "Light rain",
    63: "Rain",
    65: "Heavy rain",
    66: "Freezing rain",
    67: "Freezing rain",
    71: "Light snow",
    73: "Snow",
    75: "Heavy snow",
    77: "Snow grains",
    80: "Rain showers",
    81: "Rain showers",
    82: "Heavy showers",
    85: "Snow showers",
    86: "Heavy snow showers",
    95: "Thunderstorm",
    96: "Thunderstorm w/ hail",
    99: "Severe thunderstorm",
}


def _label_for_code(code: Optional[int]) -> str:
    if code is None:
        return ""
    return _WMO_LABELS.get(int(code), "Unknown")


def _parse_iso(ts: Optional[str]) -> Optional[datetime]:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None


def _pick_endpoint(when: datetime) -> str:
    """Forecast endpoint serves the recent past via `past_days`; archive
    serves older history. We pick based on age of the timestamp."""
    age = datetime.now(timezone.utc) - when
    if age <= timedelta(days=_ARCHIVE_CUTOFF_DAYS):
        return _OPEN_METEO_FORECAST
    return _OPEN_METEO_ARCHIVE


def _build_params(endpoint: str, lat: float, lon: float, when: datetime) -> dict:
    """Open-Meteo's forecast vs archive endpoints take subtly different
    parameter shapes — wrap the divergence here so callers don't have to
    care which one we hit."""
    common = {
        "latitude": f"{lat:.5f}",
        "longitude": f"{lon:.5f}",
        "hourly": "temperature_2m,weather_code,wind_speed_10m,"
                  "relative_humidity_2m,precipitation,cloud_cover",
        "temperature_unit": "fahrenheit",
        "wind_speed_unit": "mph",
        "precipitation_unit": "inch",
        "timezone": "UTC",
    }
    if endpoint == _OPEN_METEO_FORECAST:
        # past_days covers up to ~92 days of history — enough for our
        # recent-session use case. forecast_days=1 keeps the payload
        # small (we only care about the past hour).
        days_back = max(1, (datetime.now(timezone.utc) - when).days + 1)
        common["past_days"] = str(min(days_back, 92))
        common["forecast_days"] = "1"
    else:
        # Archive needs explicit dates. ±1 day of slack avoids edge cases
        # at midnight UTC boundaries.
        date = when.date()
        common["start_date"] = (date - timedelta(days=1)).isoformat()
        common["end_date"] = (date + timedelta(days=1)).isoformat()
    return common


def fetch_weather(
    lat: float,
    lon: float,
    when: datetime,
) -> Optional[dict]:
    """Pull the weather observation closest to `when` for the given
    point. Returns None on any error (network, missing data, malformed
    response). Caller decides whether to record None or skip.

    `when` should be the SESSION MIDPOINT, not the start — agents arrive
    early to set up and the relevant weather is what visitors saw, not
    what the agent saw setting up.
    """
    endpoint = _pick_endpoint(when)
    params = _build_params(endpoint, lat, lon, when)

    try:
        resp = requests.get(endpoint, params=params, timeout=_REQUEST_TIMEOUT_S)
        if not resp.ok:
            log.warning(
                "open-meteo %s returned %d: %s",
                endpoint, resp.status_code, resp.text[:200],
            )
            return None
        payload = resp.json()
    except (requests.RequestException, ValueError) as exc:
        log.warning("open-meteo fetch failed: %s", exc)
        return None

    hourly = payload.get("hourly") or {}
    times: list[str] = hourly.get("time") or []
    if not times:
        return None

    # Find the index of the hour closest to `when`. Open-Meteo hours are
    # ISO strings ("2026-05-16T13:00"); parse each and pick the smallest
    # absolute delta. ~100 entries max so a linear scan is fine.
    target = when.replace(tzinfo=None, minute=0, second=0, microsecond=0)
    best_i = -1
    best_delta = timedelta.max
    for i, t in enumerate(times):
        try:
            dt = datetime.fromisoformat(t)
        except ValueError:
            continue
        delta = abs(dt - target)
        if delta < best_delta:
            best_delta = delta
            best_i = i

    if best_i < 0:
        return None

    def _at(key: str):
        arr = hourly.get(key)
        if not isinstance(arr, list) or best_i >= len(arr):
            return None
        return arr[best_i]

    temp = _at("temperature_2m")
    code = _at("weather_code")
    wind = _at("wind_speed_10m")
    humidity = _at("relative_humidity_2m")
    precip = _at("precipitation")
    cloud = _at("cloud_cover")

    # Bail when the hour we landed on has nothing — Open-Meteo nulls
    # individual cells during edge-of-coverage windows.
    if temp is None and code is None:
        return None

    return {
        "temp_f":             float(temp) if temp is not None else None,
        "condition_code":     int(code) if code is not None else None,
        "condition_label":    _label_for_code(code),
        "wind_mph":           float(wind) if wind is not None else None,
        "humidity_pct":       float(humidity) if humidity is not None else None,
        "precipitation_in":   float(precip) if precip is not None else None,
        "cloud_cover_pct":    float(cloud) if cloud is not None else None,
        "observed_at":        times[best_i] + "Z",
        "fetched_at":         datetime.now(timezone.utc).isoformat(),
        "source":             "open-meteo",
    }


def _session_midpoint(session: dict) -> Optional[datetime]:
    """Pick the middle of the session for the weather lookup. Falls back
    to created_at when we don't have utterance timestamps yet."""
    created = _parse_iso(session.get("created_at"))
    if not created:
        return None
    result = session.get("result") or {}
    utterances = result.get("utterances") or []
    if utterances:
        end_ms = max(
            (u.get("end_ms") or u.get("start_ms") or 0)
            for u in utterances
        )
        if end_ms > 0:
            return created + timedelta(milliseconds=end_ms // 2)
    return created


def enrich_session_with_weather(session: dict) -> Optional[dict]:
    """Look up weather for the session's lat/lon at its midpoint and
    write it onto session['weather']. Idempotent — re-running just
    refreshes the data. Returns the weather dict (also written into the
    session) or None when nothing was written (missing lat/lon, network
    error, etc.). Caller is responsible for persisting the session.

    Honors a kill-switch env var (DISABLE_WEATHER=true) so we can
    silence Open-Meteo without a code change if their service ever
    starts misbehaving."""
    if os.environ.get("DISABLE_WEATHER", "").strip().lower() in {"true", "1", "yes"}:
        return None
    lat = session.get("latitude")
    lon = session.get("longitude")
    if lat is None or lon is None:
        return None
    try:
        lat_f = float(lat)
        lon_f = float(lon)
    except (TypeError, ValueError):
        return None
    when = _session_midpoint(session)
    if when is None:
        return None
    weather = fetch_weather(lat_f, lon_f, when)
    if weather is None:
        return None
    session["weather"] = weather
    return weather
