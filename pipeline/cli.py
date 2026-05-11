import argparse
import json
import sys
from pathlib import Path

from dotenv import load_dotenv

from .analyze import analyze_visitor
from .identify import identify_agent_and_visitors
from .mock import load_mock_transcript
from .tags import DEFAULT_TAGS
from .transcribe import transcribe_with_speakers


def main() -> None:
    load_dotenv(override=True)
    parser = argparse.ArgumentParser(description="OpenHouseBoss pipeline")
    parser.add_argument("--audio", type=Path, help="Audio file to transcribe")
    parser.add_argument(
        "--mock-transcript",
        type=Path,
        help="Mock transcript JSON (bypasses AssemblyAI; useful for prompt iteration)",
    )
    parser.add_argument("--visitors", type=Path, required=True, help="Visitors CSV")
    parser.add_argument("--output", "-o", type=Path, default=Path("results.json"))
    args = parser.parse_args()

    if not args.audio and not args.mock_transcript:
        parser.error("Provide --audio or --mock-transcript")
    if args.audio and args.mock_transcript:
        parser.error("Use either --audio or --mock-transcript, not both")

    if args.mock_transcript:
        print(f"[1/3] Loading mock transcript {args.mock_transcript.name}...", file=sys.stderr)
        transcript = load_mock_transcript(args.mock_transcript)
    else:
        print(f"[1/3] Transcribing {args.audio.name}...", file=sys.stderr)
        transcript = transcribe_with_speakers(args.audio)

    print("[2/3] Identifying speakers...", file=sys.stderr)
    identification = identify_agent_and_visitors(transcript, args.visitors)
    print(
        f"      agent = Speaker {identification.agent_speaker}, "
        f"matched {len(identification.matched_visitors)} visitor(s), "
        f"unmatched: {identification.unmatched_speakers or 'none'}",
        file=sys.stderr,
    )

    print(f"[3/3] Analyzing {len(identification.matched_visitors)} visitor(s)...", file=sys.stderr)
    visitors_out = []
    for visitor in identification.matched_visitors:
        analysis = analyze_visitor(transcript, visitor, DEFAULT_TAGS)
        visitors_out.append({
            "visitor": visitor.model_dump(mode="json"),
            "analysis": analysis.model_dump(),
        })

    output = {
        "source": str(args.audio or args.mock_transcript),
        "agent_speaker": identification.agent_speaker,
        "unmatched_speakers": identification.unmatched_speakers,
        "visitors": visitors_out,
        "full_transcript": transcript.text,
    }
    args.output.write_text(json.dumps(output, indent=2, default=str))
    print(f"Wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
