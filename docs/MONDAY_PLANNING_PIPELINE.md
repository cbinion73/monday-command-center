# MONDAY Planning Pipeline

The Planning Pipeline is owned by the consolidated `monday` plugin. It reads only authorized, local records, creates append-only activity and operations receipts, and atomically publishes a bounded daily Command Brief for Command Center.

Its calendar input is a separate, privacy-minimized source artifact. A scheduled Codex run may refresh that source using only the local date, event title, start time, and end time. Schedule times are normalized to 24-hour `HH:mm` strings for Command Center. The published Command Center plan is never reused as tomorrow's calendar input. If the source manifest is missing, stale, blocked, partial, or malformed, the plan remains usable but Calendar coverage stays explicitly limited.

## Record boundaries

| Record | Location | Authority |
| --- | --- | --- |
| Captain's Log | `Chris Knowledge/500 Personal Journal` | Chris's reflective journal. Read-only to the engine and saved only with Chris's approval. |
| Research Chronicle | `Monday Knowledge/500 Research Journal` | Source-bound app-building and research record. The engine can identify candidates but does not silently publish an entry. |
| Activity Ledger | `Monday Knowledge/100 Activity Ledger` | Append-only, local, source-labeled observed activity. |
| MONDAY Operations | `Monday Knowledge/400 MONDAY Operations` | Planning receipts, open loops, and bounded MONDAY reflections. |
| Work portfolio | `Project Knowledge/03 Projects` | Authoritative evidence-linked work project status. |
| Personal Projects | `Personal Project Knowledge` | Dedicated private portfolio. It is never reported to JARVIS or substituted with historical project artifacts. |

## Safety contract

- The engine never writes the Captain's Log, calendar, external tasks, messages, or project source records.
- It does not collect raw calendar bodies, attendees, credentials, private communications, or hidden reasoning.
- Every recommendation identifies source availability. Missing data becomes a visible limitation, not a fabricated conclusion.
- The app reads the resulting plan. It does not hold source credentials or execute actions.

Command Center does not run a second planning engine. It consumes the plugin's
schema-v3 projection and verifies display through a plan-bound readback receipt.
