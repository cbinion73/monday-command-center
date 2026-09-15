#!/usr/bin/env python3
"""Build MONDAY's local, evidence-labeled daily Command Brief.

The engine is intentionally local-first. It creates an append-only activity
ledger and an operations receipt, then atomically publishes a bounded plan for
Command Center. It never changes calendars, external tasks, or human journals.
"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo


TZ = ZoneInfo("America/New_York")
HOME = Path.home()
MONDAY_KNOWLEDGE = HOME / "Knowledge Vault" / "Monday Knowledge"
PROJECT_KNOWLEDGE = HOME / "Knowledge Vault" / "Project Knowledge"
PERSONAL_PROJECTS = HOME / "Knowledge Vault" / "Personal Project Knowledge"
# This is deliberately separate from OUTPUT.  Reading the prior Command Center
# plan as the next day's calendar feed made a new day appear empty until a human
# manually rebuilt it.
CALENDAR_FEED = HOME / ".codex" / "monday-planner" / "calendar-feed.json"
OUTPUT = HOME / ".codex" / "monday-planner" / "daily-plan.json"
ARCHIVE_ROOT = HOME / ".codex" / "monday-planner" / "history"


def now() -> datetime:
    return datetime.now(TZ)


def iso(value: datetime | None = None) -> str:
    return (value or now()).isoformat(timespec="seconds")


def atomic_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temp = Path(handle.name)
    os.chmod(temp, 0o600)
    temp.replace(path)


def frontmatter(path: Path) -> dict[str, str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return {}
    if not lines or lines[0] != "---":
        return {}
    result: dict[str, str] = {}
    for line in lines[1:]:
        if line == "---":
            break
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        result[key.strip()] = value.strip().strip('"').strip("'")
    return result


def source(name: str, kind: str, path: Path, *, detail: str) -> dict[str, str]:
    status = "available" if path.exists() else "unavailable"
    fetched = iso(datetime.fromtimestamp(path.stat().st_mtime, TZ)) if path.exists() else iso()
    return {"kind": kind, "name": name, "status": status, "fetchedAt": fetched, "detail": detail}


def projects(root: Path) -> list[dict[str, str]]:
    if not root.is_dir():
        return []
    result = []
    for path in sorted(root.glob("*.md")):
        meta = frontmatter(path)
        if meta.get("type") != "project" or meta.get("status", "").lower() not in {"active", "in-progress", "at-risk"}:
            continue
        result.append({
            "title": path.stem,
            "status": meta.get("status", "unknown"),
            "updated": meta.get("updated") or meta.get("last_evidence_review") or "not recorded",
        })
    return sorted(result, key=lambda item: (item["updated"] != "not recorded", item["updated"]), reverse=True)


def dated_markdown_summary(root: Path) -> str:
    if not root.is_dir():
        return "No readable entries were found."
    entries = list(root.glob("*.md"))
    if not entries:
        return "No readable entries were found."
    latest = max(entries, key=lambda item: item.stat().st_mtime)
    return f"Latest local entry: {latest.name}. Content remains in its owning journal."


def active_decisions(root: Path) -> list[str]:
    if not root.is_dir():
        return []
    result = []
    for path in root.glob("*.md"):
        meta = frontmatter(path)
        if meta.get("type") in {"decision", "decision-record"} and meta.get("status", "").lower() in {"active", "pending", "blocked"}:
            result.append(path.stem)
    return sorted(result)


def jsonl_count(root: Path) -> int:
    if not root.is_dir():
        return 0
    return sum(1 for path in root.glob("*.jsonl") for line in path.read_text(encoding="utf-8").splitlines() if line.strip())


def load_calendar(path: Path, date: str) -> tuple[list[dict[str, str]], str]:
    if not path.is_file():
        return [], "Calendar feed has not been refreshed for this day."
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload = payload.get("plan", payload)
        if payload.get("date") != date:
            found_date = payload.get("date", "an unknown date")
            return [], f"Calendar feed is dated {found_date}, not {date}."
        schedule = []
        for item in payload.get("schedule", []):
            if not all(isinstance(item.get(key), str) for key in ("time", "end", "title")):
                continue
            start = normalized_clock(item["time"])
            end = normalized_clock(item["end"])
            if start and end:
                schedule.append({"time": start, "end": end, "title": item["title"].strip()})
        return schedule, "Titles and times only; calendar remains authoritative."
    except (OSError, json.JSONDecodeError, AttributeError):
        return [], "Calendar feed could not be read or validated."


def normalized_clock(value: str) -> str | None:
    """Normalize the privacy-minimized feed to Command Center's HH:mm contract."""
    for pattern in ("%H:%M", "%I:%M %p"):
        try:
            return datetime.strptime(value.strip(), pattern).strftime("%H:%M")
        except ValueError:
            pass
    return None


def append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, sort_keys=True) + "\n")
    os.chmod(path, 0o600)


def write_receipt(root: Path, date: str, receipt: dict[str, Any]) -> Path:
    path = root / "400 MONDAY Operations" / "Receipts" / f"{date}-planning-pipeline.json"
    atomic_json(path, receipt)
    return path


def build(args: argparse.Namespace) -> tuple[dict[str, Any], dict[str, Any]]:
    timestamp = iso()
    date = now().date().isoformat()
    work_root = PROJECT_KNOWLEDGE / "03 Projects"
    work_projects = projects(work_root)
    personal_projects = projects(PERSONAL_PROJECTS)
    decisions = active_decisions(PROJECT_KNOWLEDGE / "05 Decisions")
    captain_root = HOME / "Knowledge Vault" / "Chris Knowledge" / "500 Personal Journal"
    research_root = MONDAY_KNOWLEDGE / "500 Research Journal"
    ledger_root = MONDAY_KNOWLEDGE / "100 Activity Ledger"
    calendar_path = Path(args.calendar_feed)
    schedule, calendar_detail = load_calendar(calendar_path, date)
    sources = [
        {
            **source("Outlook Calendar via Codex", "calendar", calendar_path, detail=calendar_detail),
            "status": "available" if calendar_detail.startswith("Titles and times") else "unavailable",
        },
        source("Project Knowledge", "work-portfolio", work_root, detail=f"{len(work_projects)} active work project records read."),
        source("Decision Ledger", "commitments", PROJECT_KNOWLEDGE / "05 Decisions", detail=f"{len(decisions)} active, pending, or blocked work decision records read."),
        source("Activity Ledger", "ledger", ledger_root, detail=f"{jsonl_count(ledger_root)} local activity receipt(s) available."),
        source("MONDAY Operations", "operations", MONDAY_KNOWLEDGE / "400 MONDAY Operations", detail="Local receipts and reflections."),
        source("Captain's Log", "human-journal", captain_root, detail=dated_markdown_summary(captain_root)),
        source("Research Chronicle", "research-journal", research_root, detail=dated_markdown_summary(research_root)),
        source("Personal Projects", "personal-portfolio", PERSONAL_PROJECTS, detail=(f"{len(personal_projects)} active personal project records read." if PERSONAL_PROJECTS.exists() else "Dedicated personal-project source is not configured yet.")),
    ]
    unavailable = [item["name"] for item in sources if item["status"] != "available"]
    project_names = [project["title"] for project in work_projects]
    primary = "Protect commitments and review the current operating picture"
    if project_names:
        primary = f"Protect commitments and move {project_names[0]} forward with evidence"
    priorities_a = ["Honor today's fixed commitments"] if schedule else []
    if project_names:
        priorities_a.append(f"Review the next concrete move for {project_names[0]}")
    priorities_b = [f"Assess active project signal: {name}" for name in project_names[1:4]]
    pull_forwards = [f"Clarify the next action and owner for {name}" for name in project_names[:4]]
    pull_forwards.extend(f"Review active decision: {title}" for title in decisions[:2])
    risks = []
    if unavailable:
        risks.append("Unavailable sources: " + ", ".join(unavailable))
    if not PERSONAL_PROJECTS.exists():
        risks.append("Personal Projects is not configured, so personal portfolio recommendations are intentionally withheld.")
    elif not personal_projects:
        risks.append("Personal Project Knowledge is connected but contains no active project records yet.")
    notes = ["Recommendations are evidence-labeled and require your judgment, not blind automation."]
    if risks:
        notes.append(risks[0])
    brief = {
        "mission": primary,
        "pullForwards": pull_forwards,
        "risks": risks,
        "workPortfolio": work_projects[:8],
        "personalPortfolio": personal_projects[:8],
        "sourceHealth": sources,
        "activityLedger": {"date": date, "status": "local", "recordCount": jsonl_count(ledger_root)},
        "operations": {"status": "local", "receipt": f"400 MONDAY Operations/Receipts/{date}-planning-pipeline.json"},
    }
    plan = {
        "schemaVersion": 2,
        "date": date,
        "generatedAt": timestamp,
        "timezone": "America/New_York",
        "sources": sources,
        "primaryFocus": primary,
        "schedule": schedule,
        "priorities": {"a": priorities_a, "b": priorities_b, "c": []},
        "notes": notes,
        "compass": [],
        "brief": brief,
    }
    receipt = {
        "schemaVersion": 1,
        "id": f"ops-{date}-{uuid.uuid4().hex[:8]}",
        "occurredAt": timestamp,
        "kind": "planning-pipeline-run",
        "status": "completed",
        "summary": "Built the local MONDAY Command Brief.",
        "sourceHealth": [{"name": item["name"], "status": item["status"]} for item in sources],
        "outputs": [str(OUTPUT), str(ARCHIVE_ROOT / f"{date}.json"), f"400 MONDAY Operations/Receipts/{date}-planning-pipeline.json"],
        "limitations": risks,
    }
    return plan, receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--calendar-feed", default=str(CALENDAR_FEED), help="Bounded calendar plan JSON produced by Codex")
    parser.add_argument("--output", default=str(OUTPUT), help="Command Center plan output path")
    parser.add_argument("--dry-run", action="store_true", help="Print the plan without writing records")
    parser.add_argument("--activity-summary", default="", help="Optional observed activity summary to append to today's ledger")
    args = parser.parse_args()
    if not args.dry_run:
        (MONDAY_KNOWLEDGE / "100 Activity Ledger").mkdir(parents=True, exist_ok=True)
        (MONDAY_KNOWLEDGE / "400 MONDAY Operations" / "Receipts").mkdir(parents=True, exist_ok=True)
    plan, receipt = build(args)
    if args.dry_run:
        print(json.dumps(plan, indent=2))
        return
    ledger = MONDAY_KNOWLEDGE / "100 Activity Ledger" / f"{plan['date']}.jsonl"
    append_jsonl(ledger, {"schemaVersion": 1, "id": receipt["id"], "occurredAt": receipt["occurredAt"], "kind": receipt["kind"], "summary": receipt["summary"], "source": "MONDAY Planning Engine", "classification": "local-operations"})
    if args.activity_summary.strip():
        append_jsonl(ledger, {"schemaVersion": 1, "id": f"activity-{uuid.uuid4().hex[:10]}", "occurredAt": iso(), "kind": "observed-authorized-work", "summary": args.activity_summary.strip(), "source": "current authorized Codex work", "classification": "research-chronicle-candidate"})
    receipt["ledger"] = str(ledger)
    receipt["activityCount"] = sum(1 for _ in ledger.open(encoding="utf-8"))
    plan["brief"]["activityLedger"]["recordCount"] = receipt["activityCount"]
    write_receipt(MONDAY_KNOWLEDGE, plan["date"], receipt)
    atomic_json(Path(args.output), plan)
    atomic_json(ARCHIVE_ROOT / f"{plan['date']}.json", plan)
    print(f"Built MONDAY Command Brief for {plan['date']} at {args.output}")


if __name__ == "__main__":
    main()
