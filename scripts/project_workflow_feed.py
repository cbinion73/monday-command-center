#!/usr/bin/env python3
"""Build Command Center's read-only, evidence-linked project workflow feed.

The feed is a derived operating view.  Project records remain authoritative;
this program neither changes them nor advances a project state.  A planned
substep is explicitly labelled proposed until a governed project record carries
the evidence needed to accept it.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from datetime import datetime, timezone
from pathlib import Path


LINK = re.compile(r"\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]")


def front_matter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    _, _, remainder = text.partition("---\n")
    header, marker, _ = remainder.partition("\n---")
    if not marker:
        return {}
    values: dict[str, str] = {}
    for line in header.splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip().strip('"')
    return values


def evidence_refs(text: str, project_file: Path, status: str) -> list[dict[str, str]]:
    links: list[str] = []
    for match in LINK.finditer(text):
        value = match.group(1).strip()
        if value and value not in links:
            links.append(value)
    refs = [{
        "label": project_file.stem,
        "locator": str(project_file),
        "standing": status or "unknown",
        "kind": "governed project record",
    }]
    refs.extend({
        "label": link,
        "locator": f"[[{link}]]",
        "standing": status or "unknown",
        "kind": "linked evidence",
    } for link in links[:4])
    return refs


def station(key: str, title: str, purpose: str, evidence: list[dict[str, str]], *, state: str = "proposed") -> dict[str, object]:
    return {
        "id": key.lower().replace("_", "-"),
        "station": key,
        "title": title,
        "purpose": purpose,
        "state": state,
        "evidence_status": "not yet evidenced" if state == "proposed" else "recorded",
        "evidence": evidence if state != "proposed" else [],
    }


def workflow(project_file: Path) -> dict[str, object]:
    text = project_file.read_text(encoding="utf-8")
    meta = front_matter(text)
    status = meta.get("status", "unknown")
    evidence_status = meta.get("evidence_status", "unknown")
    source_refs = evidence_refs(text, project_file, evidence_status)
    lower = text.lower()

    # A closure state is a recorded portfolio outcome, not proof that every
    # claimed benefit was realized.  Its follow-on remains a decision gate.
    if status in {"complete", "closed", "inactive", "on-hold"}:
        steps = [
            station("CLOSURE_EVIDENCE", "Closure evidence review", "Confirm what completion, transition, or pause is actually supported.", source_refs, state="recorded"),
            station("PORTFOLIO_DECISION", "Portfolio decision", "Deliberately archive, monitor benefits, reopen, or create a successor only with evidence.", source_refs),
        ]
        current = "CLOSURE_EVIDENCE"
    else:
        steps = [
            station("ASSESSMENT", "Current-state assessment", "Classify the current stage, accountable owner, gate, and source freshness before advancing the plan.", source_refs, state="recorded"),
            station("STRATEGY", "Outcome and guardrails", "Record intended outcome, exclusions, decision rights, and success measure.", source_refs),
            station("BASELINE", "Evidence baseline", "Establish current state, known unknowns, and source freshness.", source_refs),
            station("SEQUENCE", "Sequencing and ownership", "Name accountable owner, dependencies, and the next bounded move.", source_refs),
            station("EXECUTE", "Execution evidence", "Perform the approved work and preserve its delivery evidence.", source_refs),
            station("REVIEW", "Operating review", "Compare plan and actual, then record a decision or escalation.", source_refs),
            station("PORTFOLIO_DECISION", "Portfolio decision", "Deliberately recommit, pause, archive, or redirect the work.", source_refs),
        ]
        current = "ASSESSMENT"

        # These additional gates are determined from the governed record's
        # language, not inferred as complete.  They make invisible assurance
        # and value work visible where the record says it matters.
        if any(word in lower for word in ("validation", "validate", "evaluation", "quality")):
            steps.insert(-2, station("VERIFY", "Validation and quality gate", "Define acceptance evidence, run the check, and record limitations or failures.", source_refs))
        if any(word in lower for word in ("benefit", "productivity", "adoption", "value", "outcome")):
            steps.insert(-1, station("BENEFITS", "Benefit follow-through", "Define the measurement, period, and realization mechanism before calling value achieved.", source_refs))

    fingerprint = hashlib.sha256(text.encode("utf-8")).hexdigest()
    return {
        "project_id": meta.get("id", project_file.stem.lower().replace(" ", "-")),
        "project_title": project_file.stem,
        "source_path": str(project_file),
        "source_modified_at": datetime.fromtimestamp(project_file.stat().st_mtime, tz=timezone.utc).isoformat(),
        "source_fingerprint": fingerprint,
        "project_status": status,
        "current_station": current,
        "decision_owner": meta.get("owner"),
        "steps": steps,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    projects = [workflow(path) for path in sorted(args.project_root.glob("*.md"))]
    payload = {
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "derivation": "Read-only Command Center operating view. Project records and linked evidence remain authoritative.",
        "projects": projects,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(".tmp")
    temporary.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    temporary.replace(args.output)


if __name__ == "__main__":
    main()
