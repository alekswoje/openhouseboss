import csv
import json
import os
import re
from collections import Counter
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from typing import Optional

import assemblyai as aai
from anthropic import Anthropic
from pydantic import BaseModel

MODEL = "claude-sonnet-4-6"


def _diarization_refinement_enabled() -> bool:
    # Default ON. Flip to "false" via Render env var if Claude refinement
    # ever starts producing worse output than the raw provider — we keep
    # the kill switch so we can roll back without a redeploy.
    return os.environ.get("DIARIZATION_REFINE_ENABLED", "true").strip().lower() not in (
        "false", "0", "no", "off",
    )


class Visitor(BaseModel):
    name: str
    email: str
    phone: str
    signed_in_at: Optional[datetime] = None
    speaker: Optional[str] = None
    first_name: Optional[str] = None


class IdentificationResult(BaseModel):
    agent_speaker: str
    matched_visitors: list[Visitor]
    unmatched_speakers: list[str]
    # Claude's estimate of true speaker count (including the agent). When
    # this exceeds the diarizer's count, the caller should re-transcribe
    # with `speakers_expected=suspected_total` to recover collapsed voices.
    suspected_total: int = 0
    detected_total: int = 0


def load_visitors(csv_path: Path) -> list[Visitor]:
    visitors: list[Visitor] = []
    with csv_path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            signed_in: Optional[datetime] = None
            if row.get("signed_in_at"):
                try:
                    signed_in = datetime.fromisoformat(row["signed_in_at"])
                except ValueError:
                    pass
            visitors.append(
                Visitor(
                    name=row["name"],
                    email=row.get("email", ""),
                    phone=row.get("phone", ""),
                    signed_in_at=signed_in,
                    first_name=row["name"].split()[0].lower(),
                )
            )
    return visitors


def detect_agent_speaker(transcript: aai.Transcript) -> str:
    durations: Counter[str] = Counter()
    for utt in transcript.utterances or []:
        durations[utt.speaker] += utt.end - utt.start
    if not durations:
        raise RuntimeError("No utterances found in transcript")
    return durations.most_common(1)[0][0]


def _strip_code_fence(text: str) -> str:
    text = text.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        if text.endswith("```"):
            text = text.rsplit("\n```", 1)[0]
        if text.lower().startswith("json\n"):
            text = text[5:]
    return text


def _extract_json(text: str) -> str:
    """Pull just the first balanced JSON object or array out of an LLM
    response. Models occasionally return JSON followed by trailing prose
    ("{...}\n\nNote: ...") which trips json.loads with the confusing
    "Extra data: line 3 column 1 (char 18)" error. We scan for the first
    '{' or '[' and walk forward tracking depth + string state until we
    find the matching close, then return just that slice."""
    text = _strip_code_fence(text)
    # Find the first top-level opener.
    start = -1
    for i, ch in enumerate(text):
        if ch in "{[":
            start = i
            break
    if start == -1:
        return text  # fall through; json.loads will raise on its own
    depth = 0
    in_str = False
    escape = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
        elif ch in "{[":
            depth += 1
        elif ch in "}]":
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    return text[start:]  # unbalanced; let the caller raise


_REFINE_SYSTEM_PROMPT = (
    "You correct speaker diarization on an open-house transcript. "
    "Single-mic phone audio causes two recurring ASR failures:\n"
    "  (a) SPEAKER FLIPS — labels swap on rapid back-and-forth.\n"
    "  (b) LUMPED TURNS — multiple speakers' words collapsed into one "
    "utterance. This is the dominant failure mode on close-talker audio.\n\n"
    "WHO IS WHO:\n"
    "- The AGENT asks questions ('what's your name?', 'what's your "
    "price range?', 'how soon are you looking to move?'), welcomes "
    "visitors ('welcome to the open house', 'thanks for coming'), "
    "introduces themselves as 'the listing agent' / 'the realtor', "
    "describes the property, says 'let me know if you have questions'. "
    "They're running the show.\n"
    "- A VISITOR describes their own needs ('I need a 4th bedroom', "
    "'we have 2 kids', 'we're pre-approved for $X'), gets asked their "
    "name, asks about the property, comments on what they see.\n"
    "- 'Hi Alex' / 'Nice to meet you, Sarah' — the SPEAKER is talking "
    "TO that named person; the named person is the OTHER speaker.\n"
    "- 'I'm X' / 'My name's X' — the speaker is stating their OWN name.\n\n"
    "SPLITTING LUMPED TURNS — be aggressive. Any of these patterns "
    "inside one utterance means it MUST be split:\n"
    "  - A QUESTION followed by an ANSWER ('what's your name? Ethan.') "
    "→ split into 2 turns (question = one speaker, answer = other).\n"
    "  - A NAME EXCHANGE ('What's your name? Ethan. Ethan, Alex. Nice "
    "to meet you. Nice to meet you too.') → split into 4-5 turns: "
    "agent asks, visitor names self, agent repeats+names self, "
    "visitor returns greeting.\n"
    "  - A GREETING + REPLY ('Nice to meet you. Nice to meet you too.') "
    "→ ALWAYS 2 different speakers.\n"
    "  - 'Yeah.' / 'Okay.' / 'Nice.' inline after a visitor statement "
    "is usually the agent acknowledging — split it off as its own turn.\n"
    "  - Self-introductions stitched together ('Hi, I'm Alex. Hey "
    "Alex, I'm Ben.') → 2 turns, one per speaker.\n"
    "When in doubt about whether a chunk has multiple speakers in it, "
    "SPLIT. The downstream pipeline can recover from over-splitting; "
    "it cannot recover from a visitor's words attributed to the agent.\n\n"
    "TWO CORRECTIONS YOU CAN MAKE:\n"
    "1. SPLIT a single utterance into multiple when its text contains "
    "multiple speakers' words. When splitting, distribute start_ms "
    "monotonically (later parts get later timestamps; if you can't "
    "tell, evenly space them between the original start_ms and end_ms).\n"
    "2. RE-LABEL an utterance's speaker when the linguistic content "
    "doesn't match the provider's cluster.\n\n"
    "Don't change the WORDS. Don't add new words. Don't drop words. "
    "Only re-segment and re-label.\n\n"
    "Return JSON only, no prose. Format: a list of objects with the "
    "SAME shape as the input: "
    '[{"speaker": "A", "start_ms": 0, "end_ms": 21000, "text": "..."}, ...]'
)


# Lowercase word/number tokens, keeping internal apostrophes and hyphens
# ("don't", "cul-de-sac") but stripping all other punctuation. Used to
# verify Claude only re-segmented + re-labeled — not substituted words.
_WORD_RE = re.compile(r"[a-z0-9]+(?:[-'][a-z0-9]+)*")


def _word_tokens(text: str) -> list[str]:
    return _WORD_RE.findall(text.lower())


def _merge_short_fragments(
    utts: list[dict],
    *,
    max_fragment_ms: int = 600,
    max_fragment_words: int = 3,
) -> list[dict]:
    """Re-assign sub-second utterances to the surrounding speaker when
    they're sandwiched by the SAME speaker on both sides.

    Real-world failure this targets: AssemblyAI's diarizer sometimes
    spawns a stray short utterance for a brief speaker change that
    didn't actually happen — a "yeah" or "so" gets attributed to a third
    speaker in the middle of a long C↔B exchange, when in reality it's
    just C continuing. Compare-Providers debug bundles consistently
    show this as a fifth speaker `E` collecting fragments that should
    belong to existing speakers.

    Conservative: only triggers when (a) the utterance is short in both
    duration AND word count, AND (b) the immediate neighbors share a
    different speaker. Fragments at the start/end of the transcript or
    between different speakers are left alone — that's where genuine
    speaker changes are most likely.
    """
    if len(utts) < 3:
        return utts
    out = list(utts)
    relabeled = 0
    for i in range(1, len(out) - 1):
        u = out[i]
        try:
            start = int(u.get("start_ms") or 0)
            end = int(u.get("end_ms") or 0)
        except (TypeError, ValueError):
            continue
        duration = end - start
        if duration <= 0 or duration > max_fragment_ms:
            continue
        words = len(_word_tokens(u.get("text", "")))
        if words == 0 or words > max_fragment_words:
            continue
        prev_speaker = out[i - 1].get("speaker")
        next_speaker = out[i + 1].get("speaker")
        if not prev_speaker or prev_speaker != next_speaker:
            continue
        if u.get("speaker") == prev_speaker:
            continue
        out[i] = {**u, "speaker": prev_speaker}
        relabeled += 1
    if relabeled:
        print(
            f"[diarization-refine] merged {relabeled} short fragments into "
            f"surrounding speaker",
            flush=True,
        )
    return out


def _claude_refine_utterances(
    input_payload: list[dict],
    valid_speakers: list[str],
) -> Optional[list[dict]]:
    """Shared core for diarization refinement. Takes a normalized list of
    {speaker, start_ms, end_ms, text} dicts, runs the refine prompt, and
    returns the cleaned list (or None on any parse/validation failure).
    Used by both the production refine pass and the A/B test's refined-AAI
    lane so the Compare Providers view reflects what production actually
    serves."""
    if len(input_payload) < 2:
        return None
    client = Anthropic()
    # max_tokens needs to fit the JSON response. The refined output is
    # roughly the same size as the input (~50 tokens per turn), so a long
    # open-house transcript (~200 turns) needs 10K+ output tokens. 8K was
    # silently truncating the JSON mid-stream, producing parse failures
    # that fell back to raw AAI on every long session. 32K covers ~600
    # turns with margin — plenty for any realistic open-house.
    response = client.messages.create(
        model=MODEL,
        max_tokens=32768,
        system=(
            _REFINE_SYSTEM_PROMPT
            + f"\n\nSpeaker labels you may use: {valid_speakers}. Do NOT "
            "invent new labels — the ASR already detected the speaker "
            "set. If you think there's a third speaker not in the list, "
            "keep the label the provider gave you for that utterance."
        ),
        messages=[{
            "role": "user",
            "content": json.dumps(input_payload, indent=2),
        }],
    )
    raw_response_text = response.content[0].text
    stop_reason = getattr(response, "stop_reason", None)
    print(
        f"[diarization-refine] input_turns={len(input_payload)} "
        f"stop_reason={stop_reason} "
        f"output_chars={len(raw_response_text)}",
        flush=True,
    )
    text = _extract_json(raw_response_text)
    try:
        refined = json.loads(text)
    except json.JSONDecodeError as e:
        print(f"[diarization-refine] JSON parse failed: {e}", flush=True)
        return None
    if not isinstance(refined, list) or not refined:
        print("[diarization-refine] empty / non-list response", flush=True)
        return None
    cleaned: list[dict] = []
    for item in refined:
        if not isinstance(item, dict):
            continue
        speaker = item.get("speaker")
        utt_text = item.get("text")
        if not isinstance(speaker, str) or not isinstance(utt_text, str):
            continue
        # Reject hallucinated speaker labels — Claude occasionally
        # invents "C" when the ASR only found A and B. Drop those rather
        # than silently mislabeling a turn.
        if speaker not in valid_speakers:
            continue
        try:
            start = int(item.get("start_ms") or 0)
        except (TypeError, ValueError):
            start = 0
        try:
            end = int(item.get("end_ms") or 0)
        except (TypeError, ValueError):
            end = 0
        cleaned.append({
            "speaker": speaker,
            "start_ms": start,
            "end_ms": end,
            "text": utt_text,
        })
    if not cleaned:
        return None

    # Verbatim check: the refined transcript should be essentially a
    # re-ordering + re-segmentation of the raw words — Claude occasionally
    # "fixes" a transcription error ("It's good to meet you" → "Okay. So
    # good to meet you"), which corrupts the source-of-truth for downstream
    # attribution.
    #
    # We allow a small tolerance because on long transcripts (200+ turns)
    # Claude almost always drops or normalizes 1-2 filler words ("uh", "um",
    # repeated "yeah") even when explicitly told not to. The strict version
    # rejected the entire refine on a single word delta, which meant the
    # production lane was effectively useless on real open-house sessions
    # — every long recording silently fell back to raw AAI. Tolerance is
    # capped at 1% of input tokens (well below the threshold at which
    # speaker-attribution accuracy meaningfully degrades).
    raw_tokens = Counter()
    for item in input_payload:
        raw_tokens.update(_word_tokens(item.get("text", "")))
    refined_tokens = Counter()
    for item in cleaned:
        refined_tokens.update(_word_tokens(item["text"]))
    total_raw = sum(raw_tokens.values())
    added = refined_tokens - raw_tokens
    dropped = raw_tokens - refined_tokens
    delta = sum(added.values()) + sum(dropped.values())
    tolerance = max(5, total_raw // 100)  # ≤ 1% drift, min 5 tokens
    if delta > tolerance:
        print(
            f"[diarization-refine] verbatim check FAILED ({delta}/{total_raw} "
            f"tokens differ, tolerance={tolerance}) — falling back to raw. "
            f"added={dict(added.most_common(8))} "
            f"dropped={dict(dropped.most_common(8))}",
            flush=True,
        )
        return None
    if delta > 0:
        print(
            f"[diarization-refine] verbatim check OK ({delta}/{total_raw} "
            f"tokens differ, within tolerance={tolerance})",
            flush=True,
        )
    return cleaned


def refine_diarization(transcript: aai.Transcript) -> aai.Transcript:
    """Run Claude over the diarized transcript to fix common single-mic
    diarization errors: speaker swaps on rapid back-and-forth and multiple
    speakers' words merged into one utterance.

    Mutates the transcript's utterances list in place so downstream code
    sees a cleaner diarization with no other changes. Failures are
    non-fatal — if Claude returns malformed JSON or invents speaker
    labels, we keep the original utterances and log.

    Disable via DIARIZATION_REFINE_ENABLED=false on Render."""
    if not _diarization_refinement_enabled():
        return transcript
    utterances = list(transcript.utterances or [])
    if len(utterances) < 2:
        # Nothing to re-segment if there's only one (or zero) utterances —
        # save the round-trip + cost.
        return transcript

    valid_speakers = sorted({u.speaker for u in utterances})
    input_payload = [
        {
            "speaker": u.speaker,
            "start_ms": int(getattr(u, "start", 0) or 0),
            "end_ms": int(getattr(u, "end", 0) or 0),
            "text": u.text,
        }
        for u in utterances
    ]

    cleaned = _claude_refine_utterances(input_payload, valid_speakers)
    if not cleaned:
        # Even when Claude refine fails, sweep short cross-contaminated
        # fragments in the raw output so we don't surface obvious errors
        # to the agent. ("E: 'So.'" in the middle of a long C/B exchange
        # was almost certainly a misclassification, not a real new
        # speaker.)
        merged = _merge_short_fragments(input_payload)
        if merged is input_payload:
            return transcript
        new_utts = [
            SimpleNamespace(
                speaker=item["speaker"],
                text=item["text"],
                start=item["start_ms"],
                end=item["end_ms"],
            )
            for item in merged
        ]
        try:
            transcript.utterances = new_utts
        except Exception:
            pass
        return transcript

    # Also apply fragment-merge on top of Claude's refined output —
    # belt + suspenders.
    cleaned = _merge_short_fragments(cleaned)

    new_utts = [
        SimpleNamespace(
            speaker=item["speaker"],
            text=item["text"],
            start=item["start_ms"],
            end=item["end_ms"],
        )
        for item in cleaned
    ]

    # Try to mutate the AAI transcript's utterances list. AAI's Pydantic
    # model is mutable by default; if a future SDK version freezes it,
    # this assignment will raise and we keep the original utterances.
    try:
        transcript.utterances = new_utts
    except Exception:
        return transcript
    # Refresh the flat text so it reflects the refined ordering. Keep
    # the original on empty join as a safety net.
    joined = " ".join(u.text for u in new_utts).strip()
    if joined:
        try:
            transcript.text = joined
        except Exception:
            pass
    return transcript


class SpeakerAnalysis(BaseModel):
    # Claude's pick for which speaker label is the listing agent, based on
    # linguistic cues (introductions, asking the visitor's name/price range,
    # describing property features). None if Claude is unsure — caller
    # falls back to the duration heuristic.
    agent_speaker: Optional[str] = None
    names: dict[str, str]
    # Claude's best guess at how many distinct humans were really in the
    # room (including the agent). When the diarizer undercounts — two
    # close-mic'd voices collapsed into one cluster — this comes back
    # higher than `len(transcript.utterances.speakers)` and the caller
    # should re-transcribe with `speakers_expected=suspected_total`.
    suspected_total: int


def analyze_speakers(transcript: aai.Transcript) -> SpeakerAnalysis:
    utterances_text = "\n".join(
        f"[{u.speaker}] {u.text}" for u in (transcript.utterances or [])
    )
    detected = sorted({u.speaker for u in (transcript.utterances or [])})

    client = Anthropic()
    response = client.messages.create(
        model=MODEL,
        max_tokens=1024,
        system=(
            "You analyze diarized open-house transcripts. The recording is "
            "the listing agent showing visitors around a property. Three tasks:\n\n"
            "1. Identify which speaker label is the LISTING AGENT. Pick the "
            "speaker whose language is the agent's: introduces themselves as "
            "\"the listing agent\" / \"the agent\" / \"realtor\"; asks the "
            "visitor's name; asks their price range, timeline, what they're "
            "looking for; offers to show them around; describes the property's "
            "features; says things like \"let me know if you have questions\". "
            "The VISITOR is the one being asked these questions, talking about "
            "their own needs (\"I need a 4th bedroom\", \"we have two kids\", "
            "\"we're pre-approved for $X\"). Do NOT use talk-time — a visitor "
            "monologuing about their needs is still a visitor. If the "
            f"transcript truly doesn't tell you, return null. Detected: {detected}.\n\n"
            "2. Extract each visitor's first name. Visitors typically introduce "
            "themselves when the agent asks. Use lowercase. Omit the agent's "
            "own name and any speaker whose name is not mentioned.\n\n"
            "3. Estimate how many distinct humans were really in the conversation, "
            "including the agent. Diarization sometimes collapses two close-mic'd "
            "voices into one cluster — watch for these tells inside a single speaker "
            "label: two different first names being introduced (\"hi I'm sarah\" "
            "then later \"and I'm mike\"), back-and-forth that reads like two people "
            "talking to each other, contradictory self-references (one line says "
            "\"my wife and I\", another says \"I'm single\"), or wildly different "
            "conversational styles. If you see clear evidence of a merge, return a "
            "higher count. If the transcript is consistent with the detected count, "
            "return the detected count.\n\n"
            "Return JSON only, no prose, format: "
            '{"agent_speaker": "A", "names": {"B": "sarah", "C": "mike"}, '
            '"suspected_total": 3}'
        ),
        messages=[{"role": "user", "content": utterances_text}],
    )
    text = _extract_json(response.content[0].text)
    # Defensive: Claude can occasionally return a bare names-only dict
    # (`{"B": "sarah"}`) or wrap the response in a list. Tolerate both —
    # we'd rather lose the undercount signal than fail the whole session.
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        data = {}
    if not isinstance(data, dict):
        data = {}
    names_field = data.get("names")
    if isinstance(names_field, dict):
        names = {k: v for k, v in names_field.items() if isinstance(v, str)}
    elif all(isinstance(v, str) for v in data.values()) and "suspected_total" not in data:
        # Old shape fallback: the whole object IS the names dict.
        names = {k: v for k, v in data.items() if isinstance(v, str)}
    else:
        names = {}
    try:
        suspected = int(data.get("suspected_total") or len(detected))
    except (TypeError, ValueError):
        suspected = len(detected)
    # Floor the suspected count at what we already detected — Claude should
    # never tell us there are *fewer* people than AAI already found.
    suspected = max(suspected, len(detected))
    agent_pick = data.get("agent_speaker")
    if not isinstance(agent_pick, str) or agent_pick not in detected:
        agent_pick = None
    return SpeakerAnalysis(
        agent_speaker=agent_pick,
        names=names,
        suspected_total=suspected,
    )


def identify_agent_and_visitors(
    transcript: aai.Transcript, visitors_csv: Optional[Path] = None
) -> IdentificationResult:
    # Claude picks the agent from linguistic cues (asks "what's your name",
    # "what's your price range", introduces as the listing agent, etc.).
    # Fall back to the longest-talker heuristic only if Claude is unsure —
    # that fallback is wrong whenever the visitor monologues, which is most
    # short open-house clips.
    analysis = analyze_speakers(transcript)
    agent = analysis.agent_speaker or detect_agent_speaker(transcript)
    speaker_names = analysis.names
    detected_total = len({u.speaker for u in (transcript.utterances or [])})

    # iOS path: no kiosk CSV. Each non-agent speaker becomes a visitor —
    # we use their extracted first name when we got one, "Visitor B/C/D" otherwise.
    if visitors_csv is None:
        synthetic: list[Visitor] = []
        all_speakers = {
            u.speaker for u in (transcript.utterances or []) if u.speaker != agent
        }
        for speaker in sorted(all_speakers):
            first = speaker_names.get(speaker)
            name = first.title() if first else f"Visitor {speaker}"
            synthetic.append(Visitor(
                name=name,
                email="",
                phone="",
                speaker=speaker,
                first_name=(first or "").lower() or None,
            ))
        return IdentificationResult(
            agent_speaker=agent,
            matched_visitors=synthetic,
            unmatched_speakers=[],
            suspected_total=analysis.suspected_total,
            detected_total=detected_total,
        )

    visitors = load_visitors(visitors_csv)
    matched: list[Visitor] = []
    unmatched: list[str] = []

    for speaker, first_name in speaker_names.items():
        candidates = [
            v for v in visitors
            if v.first_name == first_name.lower() and v.speaker is None
        ]
        if not candidates:
            unmatched.append(speaker)
            continue
        candidates[0].speaker = speaker
        matched.append(candidates[0])

    return IdentificationResult(
        agent_speaker=agent,
        matched_visitors=matched,
        unmatched_speakers=unmatched,
        suspected_total=analysis.suspected_total,
        detected_total=detected_total,
    )
