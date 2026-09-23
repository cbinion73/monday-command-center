# Scheduling ownership

Command Center is a read-only consumer of the versioned MONDAY projection at
`~/.codex/monday-planner/daily-plan.json`.

The installed primary `monday` plugin owns source collection, planning,
publication, and source-health semantics. Command Center validates schema 3,
displays the plan, and writes a matching readback receipt. It does not run a
second planning engine.

The retired Command Center launch agent, `calendar-feed.json` input, and copied
planning engine under `~/Library/Application Support/MondayCommandCenter` must
not be restored. They could overwrite a current plugin-produced plan with stale
or differently sourced Calendar data.

For recovery, reinstall the primary MONDAY plugin, regenerate a current plan,
then open Command Center and verify that its readback uses the same `planID` and
schema version.
