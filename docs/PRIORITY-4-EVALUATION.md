# Priority 4 Evaluation and Pilot

Command Center 0.4.2 provides a read-only inspection room for MONDAY's
governed evaluation system. The plugin remains responsible for executing test
suites, deciding gates, governing connector decisions, and recording pilot
evidence. The app only validates and renders the resulting projection.

## Projection and receipt

- Input: `~/.codex/monday-evaluation/inspection.json`
- Projection schema: `1`
- Producer: `monday-evaluation`
- Audience: `Chris-private-local`
- Readback: `~/.codex/monday-evaluation/readback.json`

The input has an exact top-level shape. Command Center recomputes the SHA-256
digest after removing `contentDigest` and the digest-derived `projectionID`.
It rejects unsupported or unknown fields, stale projections, denominator
mismatches, duplicate identifiers, prohibited material, unsupported plugin or
app versions, invalid gate states, and inconsistent enterprise claims.

## Inspection views

Each rendered tab has one view ID and produces a receipt only for that tab:

- `evaluation-overview`
- `evaluation-coverage`
- `evaluation-release-gates`
- `evaluation-connectors`
- `evaluation-pilot`
- `evaluation-enterprise-claim`

Planner, Digital Twin, Runtime Operations, and Evaluation receipts are not
interchangeable.

## Safety and claim boundaries

Connector lifecycle, authentication, and content coverage remain separate.
An `active` connector may still have unknown, blocked, or partial content
coverage. A successful sign-in is not a collection denominator.

The enterprise claim defaults to `BLOCKED`. An accepted single-user pilot can
support only a bounded local validation statement. It cannot enable an
enterprise-readiness claim. That claim requires a passing machine enterprise
gate, representative enterprise scope, an accepted pilot, and no remaining
requirements.

If the newest projection fails validation, the room can retain its last valid
in-memory projection for context. It labels that projection stale and does not
write a display receipt for it.
