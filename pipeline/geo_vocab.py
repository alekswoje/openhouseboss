"""Region-aware vocabulary hints for AssemblyAI transcription.

AssemblyAI gets common proper nouns wrong on phone-mic open-house audio —
"Bellevue" becomes "Belleville", "Sammamish" becomes "Samamesh", agents'
first names become acoustically similar English words. Two AAI features
fix this at the recognition layer:

- `word_boost`: a list of strings (max 1000 chars total) that the
  decoder weighs more heavily during recognition. Best for proper nouns
  the model has seen but doesn't preferentially output.
- `custom_spelling`: explicit "from → to" replacement rules applied to
  the final transcript. Best for systematic mistranscriptions where the
  acoustic match is bad enough that boosting alone won't flip it.

We pick the vocab based on the session's address — "Bellevue, WA" gets
the Seattle-metro pack; addresses we don't recognize fall through to an
empty vocab. The post-transcription cleanup (apply_geo_replacements)
runs unconditionally as a safety net since regex is essentially free
compared to a Claude pass.

Adding a new region: append to `_REGIONS` with a (predicate, vocab) pair.
The predicate gets the lowercased address; return True if this pack
should apply. Vocab is a dict with `word_boost` and `custom_spelling`
keys. Order matters — first matching region wins.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Callable


@dataclass(frozen=True)
class GeoVocab:
    # Words to boost during AAI recognition. Each entry is a single word
    # or short phrase. AAI caps the total list at ~1000 chars; we don't
    # police it here, just keep the per-region packs reasonable.
    word_boost: list[str] = field(default_factory=list)

    # Replacement rules applied to the final transcript after AAI
    # returns. Each tuple is (compiled regex matching the wrong form,
    # the correct form). Case-insensitive at the regex level; we
    # preserve casing where possible by using the canonical form
    # verbatim in the replacement.
    custom_spelling: list[tuple[re.Pattern[str], str]] = field(default_factory=list)

    @property
    def is_empty(self) -> bool:
        return not self.word_boost and not self.custom_spelling


# ---------------------------------------------------------------------------
# Seattle / Eastside metro
# ---------------------------------------------------------------------------
#
# Covers Bellevue, the Issaquah / Sammamish corridor, North Bend, Mercer
# Island, Redmond, Kirkland, Bellingham, etc. — anywhere our agents
# currently work. Common mistranscriptions seen in real session debug
# bundles are encoded as custom-spelling rules so even with weak audio
# the final transcript reads correctly.
_SEATTLE_BOOST = [
    # Core cities the agent + visitors reference most often
    "Bellevue", "Sammamish", "Issaquah", "Redmond", "Kirkland",
    "Mercer Island", "Bothell", "Renton", "Tukwila", "Kent",
    "Auburn", "Federal Way", "Lynnwood", "Edmonds", "Mukilteo",
    "Everett", "Tacoma", "Burien", "Shoreline", "Maple Valley",
    "Snoqualmie", "North Bend", "Bellingham", "Eastside", "Westside",
    "Seattle", "Woodinville", "Carnation", "Duvall",
    # Neighborhoods + landmarks that show up in conversation
    "Issaquah Highlands", "Pine Lake", "Maidenbauer", "Klahanie",
    "Cougar Mountain", "Tiger Mountain", "Lake Sammamish",
    "Lake Washington", "Capitol Hill", "Queen Anne", "Ballard",
    "Fremont", "Wallingford", "U-District",
    # Schools / districts (visitors often ask about these)
    "PCMS", "Pine Lake Middle School", "Skyline", "Eastlake",
    "Inglewood", "Tesla STEM",
    # Real-estate vocabulary that gets butchered on noisy audio
    "HOA", "MLS", "ADU", "DADU", "escrow", "contingency",
    "earnest money", "pre-approved", "pre-qualified",
]

# Patterns are case-insensitive. We anchor on word boundaries so we
# don't munge embedded substrings ("Bellville Plaza" → "Bellevue Plaza"
# is fine; "Bellvilleway" is not — but that's unlikely to occur).
_SEATTLE_SPELLING: list[tuple[re.Pattern[str], str]] = [
    # The "Belleville" / "Bellville" → "Bellevue" pair was the
    # specific failure the user flagged. AAI consistently mishears
    # Bellevue as one of these in noisy multi-speaker audio.
    (re.compile(r"\bBelleville\b", re.IGNORECASE), "Bellevue"),
    (re.compile(r"\bBellville\b", re.IGNORECASE), "Bellevue"),
    (re.compile(r"\bBelview\b", re.IGNORECASE), "Bellevue"),
    # Sammamish variants
    (re.compile(r"\bSamamesh\b", re.IGNORECASE), "Sammamish"),
    (re.compile(r"\bSamanesh\b", re.IGNORECASE), "Sammamish"),
    (re.compile(r"\bSamana\b", re.IGNORECASE), "Sammamish"),
    (re.compile(r"\bSpamish\b", re.IGNORECASE), "Sammamish"),
    # Issaquah variants
    (re.compile(r"\bIssaquan\b", re.IGNORECASE), "Issaquah"),
    (re.compile(r"\bIsiquaw\b", re.IGNORECASE), "Issaquah"),
    (re.compile(r"\bSquaw Highlands\b", re.IGNORECASE), "Issaquah Highlands"),
    # Maidenbauer is a Bellevue park / community center
    (re.compile(r"\bMaidenbower\b", re.IGNORECASE), "Maidenbauer"),
]


def _is_seattle(addr_lower: str) -> bool:
    return any(needle in addr_lower for needle in (
        "bellevue", "sammamish", "issaquah", "redmond", "kirkland",
        "seattle", "mercer island", "bothell", "renton", "kent",
        "lynnwood", "edmonds", "everett", "bellingham", "snoqualmie",
        "north bend", "maple valley", "woodinville", "shoreline",
        " wa ", " wa,", ", wa", "washington",
    ))


# Ordered list of (predicate, vocab) pairs. First match wins. Add new
# regions by appending here.
_REGIONS: list[tuple[Callable[[str], bool], GeoVocab]] = [
    (_is_seattle, GeoVocab(word_boost=_SEATTLE_BOOST, custom_spelling=_SEATTLE_SPELLING)),
]


def vocab_for_address(address: str | None) -> GeoVocab:
    """Return the vocab pack that matches the session's address.

    Falls back to an empty vocab (no boosting, no replacements) when the
    address is missing or doesn't match any region — better to let AAI
    use its default behavior than to apply Seattle vocab to a Florida
    open house and break worse mistranscriptions there.
    """
    if not address:
        return GeoVocab()
    addr_lower = address.lower()
    for predicate, vocab in _REGIONS:
        if predicate(addr_lower):
            return vocab
    return GeoVocab()


def apply_geo_replacements(text: str, vocab: GeoVocab) -> str:
    """Run the custom-spelling rules over `text`. Each rule is a
    compiled regex with a fixed replacement; runs in microseconds, safe
    to apply to long transcripts. Returns the input unchanged when the
    vocab has no rules."""
    if not vocab.custom_spelling or not text:
        return text
    out = text
    for pattern, replacement in vocab.custom_spelling:
        out = pattern.sub(replacement, out)
    return out
