#!/usr/bin/env uv run
# /// script
# requires-python = ">=3.12"
# ///

from __future__ import annotations

import argparse
from pathlib import Path
from uuid import UUID

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_TEMPLATE = SCRIPT_DIR.parent / "sql" / "campaign_summary_snapshot.sql"
PLACEHOLDER = ":'campaign_id'"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Resolve the campaign_summary_snapshot.sql template for a specific campaign ID."
    )
    parser.add_argument("campaign_id", help="Campaign UUID")
    parser.add_argument(
        "--template",
        type=Path,
        default=DEFAULT_TEMPLATE,
        help=f"Path to the SQL template file (default: {DEFAULT_TEMPLATE})",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Optional output path for the resolved SQL. Prints to stdout when omitted.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    campaign_id = str(UUID(args.campaign_id))
    template = args.template.read_text()
    occurrences = template.count(PLACEHOLDER)
    if occurrences == 0:
        raise SystemExit(f"Placeholder {PLACEHOLDER!r} not found in {args.template}")

    resolved = template.replace(PLACEHOLDER, f"'{campaign_id}'")

    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(resolved)
        print(args.output)
        return

    print(resolved, end="")


if __name__ == "__main__":
    main()
