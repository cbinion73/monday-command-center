# Planner shared-plan contract

Command Center does not connect directly to a calendar provider, Codex
conversation, or localhost service. Codex owns the calendar connection and an
authorized Planner skill can create a bounded, local JSON export. The user
selects that file in **Settings → Planner shared plan**.

The app accepts either this object directly or this object wrapped as
`{ "status": "ok", "plan": ... }`.

```json
{
  "schemaVersion": 3,
  "planID": "plan-2026-09-23-example",
  "date": "2026-09-11",
  "generatedAt": "2026-09-11T08:00:00Z",
  "validUntil": "2026-09-12T00:00:00-04:00",
  "timezone": "America/New_York",
  "sources": [
    {
      "kind": "calendar",
      "name": "Connected calendar",
      "status": "available",
      "fetchedAt": "2026-09-11T08:00:00Z"
    }
  ],
  "primaryFocus": "Complete the customer decision brief",
  "schedule": [
    { "time": "09:00", "end": "09:30", "title": "Team check-in" }
  ],
  "priorities": {
    "a": ["Complete the decision brief"],
    "b": ["Review portfolio updates"],
    "c": []
  },
  "notes": ["Calendar titles and times are intentionally bounded."],
  "compass": [
    { "role": "Leader", "goal": "Make the next decision clear" }
  ]
}
```

The Planner skill should atomically replace the selected file after it has
prepared the complete JSON, rather than writing directly into the live file.
It must never export OAuth tokens, meeting bodies, attendees, descriptions, or
other calendar details that are not needed for the day view.

The Command Center is read-only. It does not alter the calendar, create tasks,
or write to the selected plan file.

## Schema version 3 and display verification

Schema version 3 is the current MONDAY contract. It requires `planID`, adds an
explicit freshness boundary in `validUntil`, carries bounded coverage and
source-health details, and identifies the publication producer. Command Center
rejects unsupported, wrong-date, expired, or identifier-free v3 projections.

After displaying a current schema-v3 plan, Command Center atomically writes
`~/.codex/monday-planner/readback.json`. The receipt binds the consumer, app
version, plan schema, and exact `planID`. A published plan without a matching
readback remains published, not display-verified.

## MONDAY Command Brief extension

Schema versions 2 and 3 may include a `brief` object beside the bounded day-plan
fields. It is generated locally by the consolidated MONDAY plugin and
contains only recommendation text, project titles/status, pull-forwards, and
source-health labels. The app uses it to render the Command Brief; older apps
safely ignore the extension.

The extension must not contain raw calendar bodies, attendees, credentials,
private communications, hidden reasoning, or a substitute for Chris's Captain's
Log. Missing sources must remain visible as `unknown`, `partial`, `stale`,
`blocked`, or `unavailable`. An empty schedule is not evidence that the day is
clear when Calendar coverage is not `available`.
