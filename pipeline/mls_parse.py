"""Claude-driven extraction of MLS detail sheets.

The MLS Grid feed is broker-gated, so agents whose feed isn't licensed
still need a way to seed Foyer with the property they're hosting. They
already export an MLS detail sheet (PDF) or have a screenshot of the
listing page; this module turns that one-shot upload into the same
structured record the iOS New-Listing form would have gotten from the
autocomplete + /mls/property flow.

Returns a dict shaped to match `_slim_property` in backend/server.py so
the existing iOS `applyFullProperty` handler can consume it unchanged.
Extra fields useful for follow-up email generation (school district,
HOA, features, listing-agent contact, etc.) ride along in the same
payload but are all optional.
"""

import base64
import json
import re
from typing import Optional

from anthropic import Anthropic

MODEL = "claude-sonnet-4-6"


# Mirrors _slim_property's keys plus an `extras` blob of MLS context
# the form doesn't render today but that downstream follow-up email
# generation can lean on. Every key is optional — Claude returns null
# when the sheet doesn't carry a value.
_SCHEMA_HINT = """{
  "listing_id":      "MLS#  (string, e.g. \"2381472\") or null",
  "address":         "Single-line street address — \"1936 17th Ave NE\"",
  "street_number":   "string or null",
  "street_name":     "string or null",
  "street_suffix":   "string or null (\"Ave\", \"St\", ...)",
  "unit_number":     "string or null",
  "city":            "string or null",
  "state":           "2-letter USPS or null (\"WA\")",
  "postal_code":     "5-digit or null",
  "county":          "string or null",
  "subdivision":     "Neighborhood / subdivision name or null",
  "list_price":      "integer dollars or null  (no $ / commas)",
  "bedrooms":        "integer or null",
  "bathrooms_total": "number or null  (count half-baths — 2.5 etc.)",
  "living_area":     "integer sqft (interior) or null",
  "lot_size_sqft":   "number or null  (convert acres → sqft if needed)",
  "year_built":      "4-digit integer or null",
  "latitude":        "number or null  (omit unless explicitly listed)",
  "longitude":       "number or null",
  "photos_count":    "integer or null",
  "public_remarks":  "Marketing description / public remarks. Full text.",
  "list_agent_name": "string or null",
  "list_office_name":"Listing brokerage name or null",
  "standard_status": "\"Active\" / \"Pending\" / \"Sold\" etc. or null",
  "extras": {
    "property_type":      "Single Family / Condo / Townhouse / ... or null",
    "property_subtype":   "string or null",
    "days_on_market":     "integer or null",
    "hoa_dues":           "integer monthly dollars or null",
    "hoa_frequency":      "\"Monthly\" / \"Annually\" / ... or null",
    "annual_taxes":       "integer dollars or null",
    "tax_year":           "integer or null",
    "school_district":    "string or null",
    "elementary_school":  "string or null",
    "middle_school":      "string or null",
    "high_school":        "string or null",
    "parking":            "\"2-car attached\" / \"Garage\" / ... or null",
    "garage_spaces":      "integer or null",
    "stories":            "number or null",
    "view":               "string or null (\"Mountain\", \"Water\", ...)",
    "waterfront":         "string or null",
    "heating":            "string or null",
    "cooling":            "string or null",
    "appliances":         ["list", "of", "strings"]  // omit empty,
    "interior_features":  ["list", "of", "strings"],
    "exterior_features":  ["list", "of", "strings"],
    "listing_agent_email":"string or null",
    "listing_agent_phone":"string or null",
    "listing_date":       "YYYY-MM-DD or null",
    "open_house_times":   ["raw strings as printed"]
  }
}"""


_SYSTEM_PROMPT = (
    "You extract structured listing data from real-estate MLS detail "
    "sheets (PDF, screenshot, or photo). Return a SINGLE JSON OBJECT "
    "that matches the schema below. No markdown fences, no commentary "
    "— just the JSON. Use null for fields the sheet doesn't show. "
    "Never invent values; never guess price or sqft from photos.\n\n"
    "Schema:\n" + _SCHEMA_HINT
)


def _strip_fence(s: str) -> str:
    s = s.strip()
    if s.startswith("```"):
        s = re.sub(r"^```(?:json)?\s*", "", s)
        s = re.sub(r"\s*```$", "", s)
    return s.strip()


def _extract_json(raw: str) -> dict:
    """Forgiving JSON extractor — Claude occasionally wraps the object
    in a ```json fence or trails commentary after it. Strip the fence,
    then fall back to the first {...} balanced span if pure json.loads
    fails."""
    cleaned = _strip_fence(raw)
    try:
        return json.loads(cleaned)
    except json.JSONDecodeError:
        pass
    start = cleaned.find("{")
    if start < 0:
        raise ValueError(f"No JSON object in response: {raw[:200]!r}")
    depth = 0
    for i in range(start, len(cleaned)):
        ch = cleaned[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return json.loads(cleaned[start : i + 1])
    raise ValueError(f"Unbalanced JSON in response: {raw[:200]!r}")


def parse_sheet(file_bytes: bytes, content_type: str) -> dict:
    """Send the MLS sheet to Claude as a document (PDF) or image and
    return the extracted record. Raises ValueError on unsupported MIME
    types so the caller can surface a clean 400."""
    ct = (content_type or "").lower().split(";", 1)[0].strip()

    if ct == "application/pdf":
        block = {
            "type": "document",
            "source": {
                "type": "base64",
                "media_type": "application/pdf",
                "data": base64.b64encode(file_bytes).decode("ascii"),
            },
        }
    elif ct in ("image/jpeg", "image/jpg", "image/png", "image/webp", "image/gif", "image/heic", "image/heif"):
        media_type = "image/jpeg" if ct in ("image/jpg", "image/heic", "image/heif") else ct
        block = {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": media_type,
                "data": base64.b64encode(file_bytes).decode("ascii"),
            },
        }
    else:
        raise ValueError(f"Unsupported content type for MLS sheet: {ct!r}")

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=2000,
        system=_SYSTEM_PROMPT,
        messages=[{
            "role": "user",
            "content": [
                block,
                {"type": "text", "text": "Extract the listing per the schema."},
            ],
        }],
    )
    raw = response.content[0].text
    parsed = _extract_json(raw)

    # Defensive type coercion — Claude occasionally returns the price
    # as "$1,250,000" or "1.25M" despite the schema. Walk the known
    # numeric fields and coerce; drop anything that can't be salvaged.
    _coerce_numeric(parsed, "list_price", int)
    _coerce_numeric(parsed, "bedrooms", int)
    _coerce_numeric(parsed, "bathrooms_total", float)
    _coerce_numeric(parsed, "living_area", int)
    _coerce_numeric(parsed, "lot_size_sqft", float)
    _coerce_numeric(parsed, "year_built", int)
    _coerce_numeric(parsed, "photos_count", int)
    return parsed


def _coerce_numeric(d: dict, key: str, kind) -> None:
    v = d.get(key)
    if v is None or isinstance(v, (int, float)):
        return
    if not isinstance(v, str):
        d[key] = None
        return
    s = v.strip().replace("$", "").replace(",", "").replace("sqft", "").strip()
    m = re.match(r"^([\d.]+)\s*([mMkK]?)", s)
    if not m:
        d[key] = None
        return
    try:
        num = float(m.group(1))
    except ValueError:
        d[key] = None
        return
    mult = {"m": 1_000_000, "M": 1_000_000, "k": 1_000, "K": 1_000}.get(m.group(2), 1)
    num *= mult
    d[key] = int(num) if kind is int else num
