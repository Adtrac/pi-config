# /// script
# requires-python = ">=3.12"
# ///

from __future__ import annotations

import argparse
import json
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


def load_snapshot(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return data


def to_decimal(value: Any) -> Decimal | None:
    if value is None or value == "":
        return None
    try:
        return Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None


def fmt_number(value: Any, digits: int = 0) -> str:
    decimal_value = to_decimal(value)
    if decimal_value is None:
        return "n/a"
    quantized = decimal_value if digits > 0 else decimal_value.quantize(Decimal("1"))
    if digits > 0:
        quantized = decimal_value.quantize(Decimal("1." + ("0" * digits)))
    return f"{quantized:,.{digits}f}" if digits > 0 else f"{int(quantized):,}"


def fmt_money(value: Any) -> str:
    decimal_value = to_decimal(value)
    if decimal_value is None:
        return "n/a"
    return f"{decimal_value:,.2f}"


def fmt_pct(value: Any) -> str:
    decimal_value = to_decimal(value)
    if decimal_value is None:
        return "n/a"
    return f"{decimal_value:.2f}%"


def fmt_ts(value: Any) -> str:
    if not value:
        return "n/a"
    text = str(value)
    try:
        if text.endswith("Z"):
            text = text[:-1] + "+00:00"
        return datetime.fromisoformat(text).strftime("%Y-%m-%d %H:%M UTC")
    except ValueError:
        return str(value)


def fmt_date(value: Any) -> str:
    if not value:
        return "n/a"
    text = str(value)
    if "T" in text:
        text = text.split("T", 1)[0]
    return text


def bullet(text: str) -> str:
    return f"- {text}"


def md_table(headers: list[str], rows: list[list[str]]) -> list[str]:
    if not rows:
        return ["_None_"]
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join(["---"] * len(headers)) + " |"]
    for row in rows:
        out.append("| " + " | ".join(row) + " |")
    return out


def collect_overview(snapshot: dict[str, Any]) -> list[str]:
    campaign = snapshot["campaign"]
    counts = snapshot["counts"]
    reporting = snapshot["reporting"]
    overall = reporting.get("overall") or {}
    delivery = reporting.get("delivery_to_date_pct") or {}
    playouts = snapshot.get("playout_orders", {}).get("overall") or {}
    assessments = snapshot.get("assessments", {}).get("by_state") or {}
    patterns = snapshot.get("noteworthy_patterns") or []
    high_patterns = [p["message"] for p in patterns if p.get("severity") == "high"]

    lines = ["## Executive summary", ""]
    lines.append(
        bullet(
            f"Campaign status is **{campaign.get('status', 'n/a')}**. Date range: **{fmt_date(campaign.get('start_date'))} → {fmt_date(campaign.get('end_date'))}**."
        )
    )
    lines.append(
        bullet(
            f"Scope: **{counts.get('flight_count', 0)}** flight, **{counts.get('asset_count', 0)}** asset, **{counts.get('booked_player_count', 0)}** booked players across **{counts.get('booked_site_count', 0)}** site(s)."
        )
    )
    lines.append(
        bullet(
            f"Assessments: **{assessments.get('accepted', 0)} accepted**, **{assessments.get('pending', 0)} pending**, **{assessments.get('rejected', 0)} rejected**."
        )
    )
    lines.append(
        bullet(
            f"Delivery to date: **{fmt_pct(delivery.get('playouts'))} playouts**, **{fmt_pct(delivery.get('target_contacts'))} target contacts**, **{fmt_pct(delivery.get('price'))} price**."
        )
    )
    lines.append(
        bullet(
            f"Playout-order history: **{playouts.get('success_count', 0)} success**, **{playouts.get('failure_count', 0)} failure**, latest execution day **{fmt_date(playouts.get('last_execution_day'))}**."
        )
    )
    lines.append(
        bullet(
            f"Analytics report rows: **{fmt_number(overall.get('total_rows'))}**, rows with actuals: **{fmt_number(overall.get('rows_with_actuals'))}**."
        )
    )
    if high_patterns:
        lines.append("")
        lines.append("### Highest-priority findings")
        lines.append("")
        for message in high_patterns:
            lines.append(bullet(message))
    return lines


def render_overview_table(snapshot: dict[str, Any]) -> list[str]:
    campaign = snapshot["campaign"]
    reporting = snapshot["reporting"]
    overall = reporting.get("overall") or {}
    playouts = snapshot.get("playout_orders", {}).get("overall") or {}
    rows = [
        ["Campaign ID", str(campaign.get("id", "n/a"))],
        ["Name", str(campaign.get("name", "n/a"))],
        ["Status", str(campaign.get("status", "n/a"))],
        ["Asset status", str(campaign.get("asset_status", "n/a"))],
        ["Start date", fmt_date(campaign.get("start_date"))],
        ["End date", fmt_date(campaign.get("end_date"))],
        ["Fulfillment", fmt_number(campaign.get("fulfillment"))],
        ["Performance index", fmt_number(campaign.get("performance_index"))],
        ["Booked on", fmt_ts(campaign.get("booking_date"))],
        ["Last report import", fmt_ts(overall.get("last_import_datetime"))],
        ["Latest day with actuals", fmt_date(overall.get("latest_day_with_actuals"))],
        ["Latest playout-order execution", fmt_ts(playouts.get("last_playout_time"))],
    ]
    return ["## Campaign overview", ""] + md_table(["Field", "Value"], rows)


def render_financials(snapshot: dict[str, Any]) -> list[str]:
    campaign = snapshot["campaign"]
    rows = [
        ["Estimated contacts", fmt_number(campaign.get("estimated_contacts"))],
        ["Estimated playouts", fmt_number(campaign.get("estimated_playouts"))],
        ["Ratecard price", fmt_money(campaign.get("ratecard_price"))],
        ["Gross price", fmt_money(campaign.get("gross_price"))],
        ["Net price", fmt_money(campaign.get("net_price"))],
        ["Netnet price", fmt_money(campaign.get("netnet_price"))],
        ["Netnet final price", fmt_money(campaign.get("netnet_final_price"))],
        ["Agency commission", fmt_money(campaign.get("agency_commission"))],
        ["Value-added services total", fmt_money(campaign.get("value_added_services_total"))],
        ["Fix-price correction factor", fmt_number(campaign.get("fix_price_correction_factor"), 4)],
        ["Price level report status", str(campaign.get("price_level_report_status", "n/a"))],
    ]
    return ["## Financial and feasibility context", ""] + md_table(["Metric", "Value"], rows)


def render_flights(snapshot: dict[str, Any]) -> list[str]:
    flights = snapshot.get("flights") or []
    rows: list[list[str]] = []
    for flight in flights:
        reporting = flight.get("reporting") or {}
        pct = "n/a"
        plan = to_decimal(reporting.get("plan_playouts_to_date"))
        actual = to_decimal(reporting.get("actual_playouts_to_date"))
        if plan and plan > 0:
            pct = fmt_pct((actual or Decimal("0")) * Decimal("100") / plan)
        rows.append(
            [
                str(flight.get("name", "n/a")),
                fmt_date(flight.get("start_date")),
                fmt_date(flight.get("end_date")),
                str(flight.get("goal_type", "n/a")),
                fmt_number(flight.get("goal_amount")),
                fmt_number(flight.get("booked_player_count")),
                fmt_number(flight.get("attached_asset_count")),
                pct,
                fmt_date(reporting.get("latest_day_with_actuals")),
            ]
        )
    return ["## Flights", ""] + md_table(
        [
            "Flight",
            "Start",
            "End",
            "Goal type",
            "Goal",
            "Booked players",
            "Assets",
            "Playout delivery to date",
            "Latest day with actuals",
        ],
        rows,
    )


def render_history(snapshot: dict[str, Any]) -> list[str]:
    history = snapshot.get("history", {}).get("items") or []
    lines = ["## Campaign history", ""]
    if not history:
        return lines + ["_No history items found._"]
    for item in history:
        lines.append(
            bullet(
                f"**{fmt_ts(item.get('created_on'))}** — `{item.get('item_type', 'n/a')}` by **{item.get('actor_email', 'n/a')}**"
                + (f" on flight **{item.get('flight_name')}**" if item.get("flight_name") else "")
                + f": {item.get('change_summary', '')}"
            )
        )
    return lines


def render_assets(snapshot: dict[str, Any]) -> list[str]:
    assets = snapshot.get("assets") or []
    lines = ["## Assets and assessments", ""]
    if not assets:
        return lines + ["_No assets found._"]
    for asset in assets:
        assessment_summary = asset.get("assessment_summary") or {}
        attached_to = asset.get("attached_to") or []
        cms_links = asset.get("cms_links") or []
        lines.append(f"### {asset.get('asset_name', 'Unnamed asset')}")
        lines.append("")
        lines.append(
            bullet(
                f"Type: **{asset.get('media_type', 'n/a')}**, orientation: **{asset.get('orientation', 'n/a')}**, duration: **{fmt_number(asset.get('video_duration'), 2)}s**"
            )
        )
        lines.append(
            bullet(
                f"Assessments: **{assessment_summary.get('accepted_count', 0)} accepted**, **{assessment_summary.get('pending_count', 0)} pending**, **{assessment_summary.get('rejected_count', 0)} rejected**"
            )
        )
        lines.append(bullet(f"CMS links: **{len(cms_links)}**"))
        if attached_to:
            lines.append(bullet("Attached to: " + ", ".join(f"{x.get('flight_name')} / {x.get('spot_group_name')}" for x in attached_to)))
        if cms_links:
            lines.append(bullet("CMS targets: " + ", ".join(f"{x.get('cms_name')} ({x.get('cms_asset_id')})" for x in cms_links)))
        assessment_rows = assessment_summary.get("assessment_rows") or []
        if assessment_rows:
            rows = []
            for row in assessment_rows:
                rows.append(
                    [
                        str(row.get("site_name", "n/a")),
                        str(row.get("player_name", "n/a")),
                        str(row.get("player_status", "n/a")),
                        str(row.get("state", "n/a")),
                        str(row.get("message") or ""),
                    ]
                )
            lines.extend(md_table(["Site", "Player", "Player status", "Assessment", "Message"], rows))
        lines.append("")
    return lines


def render_delivery(snapshot: dict[str, Any]) -> list[str]:
    reporting = snapshot.get("reporting") or {}
    overall = reporting.get("overall") or {}
    delivery = reporting.get("delivery_to_date_pct") or {}
    recent = reporting.get("recent_daily") or []
    lines = ["## Delivery performance", ""]
    lines.extend(
        md_table(
            ["Metric", "Value"],
            [
                ["Planned playouts to date", fmt_number(overall.get("plan_playouts_to_date"))],
                ["Actual playouts to date", fmt_number(overall.get("actual_playouts_to_date"))],
                ["Playout delivery to date", fmt_pct(delivery.get("playouts"))],
                ["Planned target contacts to date", fmt_number(overall.get("plan_target_contacts_to_date"))],
                ["Actual target contacts to date", fmt_number(overall.get("actual_target_contacts_to_date"))],
                ["Target-contact delivery to date", fmt_pct(delivery.get("target_contacts"))],
                ["Planned price to date", fmt_money(overall.get("plan_price_to_date"))],
                ["Actual price to date", fmt_money(overall.get("actual_price_to_date"))],
                ["Price delivery to date", fmt_pct(delivery.get("price"))],
                ["Future planned days still in report table", fmt_number(overall.get("future_planned_days"))],
                ["Future planned playouts still in report table", fmt_number(overall.get("future_plan_playouts"))],
            ],
        )
    )
    lines.append("")
    lines.append("### Recent daily view")
    lines.append("")
    rows = []
    for row in recent:
        rows.append(
            [
                fmt_date(row.get("day")),
                fmt_number(row.get("plan_playouts")),
                fmt_number(row.get("actual_playouts")),
                fmt_pct(row.get("playout_delivery_pct")),
                fmt_number(row.get("plan_target_contacts")),
                fmt_number(row.get("actual_target_contacts")),
                fmt_pct(row.get("target_contact_delivery_pct")),
            ]
        )
    lines.extend(
        md_table(
            ["Day", "Plan playouts", "Actual playouts", "Playout %", "Plan contacts", "Actual contacts", "Contact %"],
            rows,
        )
    )
    return lines


def render_player_health(snapshot: dict[str, Any]) -> list[str]:
    players = snapshot.get("booked_players") or []
    lines = ["## Player reporting health", ""]
    rows = []
    for player in players:
        rows.append(
            [
                str(player.get("site_name", "n/a")),
                str(player.get("player_name", "n/a")),
                str(player.get("player_status", "n/a")),
                str(player.get("cms_name", "n/a")),
                fmt_number(player.get("plan_playouts_to_date")),
                fmt_number(player.get("actual_playouts_to_date")),
                fmt_pct(player.get("delivery_pct_to_date")),
                fmt_pct(player.get("delivery_pct_last_7d")),
                fmt_date(player.get("latest_day_with_actuals")),
            ]
        )
    lines.extend(
        md_table(
            [
                "Site",
                "Player",
                "Status",
                "CMS",
                "Plan to date",
                "Actual to date",
                "Delivery to date",
                "Delivery last 7d",
                "Latest day with actuals",
            ],
            rows,
        )
    )
    return lines


def render_playout_orders(snapshot: dict[str, Any]) -> list[str]:
    overall = snapshot.get("playout_orders", {}).get("overall") or {}
    recent = snapshot.get("playout_orders", {}).get("recent_daily") or []
    lines = ["## Playout-order execution", ""]
    lines.extend(
        md_table(
            ["Metric", "Value"],
            [
                ["Total rows", fmt_number(overall.get("total_rows"))],
                ["Success rows", fmt_number(overall.get("success_count"))],
                ["Failure rows", fmt_number(overall.get("failure_count"))],
                ["Not executed rows", fmt_number(overall.get("not_executed_count"))],
                ["Distinct execution days", fmt_number(overall.get("distinct_execution_days"))],
                ["First execution day", fmt_date(overall.get("first_execution_day"))],
                ["Last execution day", fmt_date(overall.get("last_execution_day"))],
                ["Last playout-order timestamp", fmt_ts(overall.get("last_playout_time"))],
            ],
        )
    )
    lines.append("")
    lines.append("### Recent execution days")
    lines.append("")
    rows = []
    for row in recent:
        rows.append(
            [
                fmt_date(row.get("execution_day")),
                fmt_number(row.get("success_count")),
                fmt_number(row.get("failure_count")),
                fmt_number(row.get("not_executed_count")),
                fmt_number(row.get("total_rows")),
                fmt_ts(row.get("last_playout_time")),
            ]
        )
    lines.extend(md_table(["Execution day", "Success", "Failure", "Not executed", "Total", "Latest row timestamp"], rows))
    return lines


def render_patterns(snapshot: dict[str, Any]) -> list[str]:
    patterns = snapshot.get("noteworthy_patterns") or []
    lines = ["## Noteworthy patterns", ""]
    if not patterns:
        return lines + ["_No noteworthy patterns detected by the snapshot query._"]
    for pattern in patterns:
        lines.append(bullet(f"**{pattern.get('severity', 'n/a').upper()}** `{pattern.get('code', 'n/a')}` — {pattern.get('message', '')}"))
    return lines


def build_markdown(snapshot: dict[str, Any]) -> str:
    campaign = snapshot["campaign"]
    lines = [
        f"# Campaign report: {campaign.get('name', 'Unnamed campaign')}",
        "",
        f"Generated from snapshot at **{fmt_ts(snapshot.get('generated_at'))}**.",
        "",
    ]
    for section in (
        collect_overview(snapshot),
        render_overview_table(snapshot),
        render_financials(snapshot),
        render_flights(snapshot),
        render_history(snapshot),
        render_assets(snapshot),
        render_delivery(snapshot),
        render_player_health(snapshot),
        render_playout_orders(snapshot),
        render_patterns(snapshot),
    ):
        lines.extend(section)
        lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render a readable markdown report from a campaign snapshot JSON file.")
    parser.add_argument("snapshot", type=Path, help="Path to the snapshot JSON file")
    parser.add_argument("-o", "--output", type=Path, help="Where to write the markdown report")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    snapshot = load_snapshot(args.snapshot)
    markdown = build_markdown(snapshot)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(markdown)
        print(args.output)
    else:
        print(markdown)


if __name__ == "__main__":
    main()
