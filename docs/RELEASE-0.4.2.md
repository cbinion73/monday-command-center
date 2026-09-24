# Command Center 0.4.2 release record

Command Center `0.4.2 (17)` is the verified read-only native companion for the
governed MONDAY plugin release `0.1.0+codex.20260924163918`.

## What changed

### Governed Digital Twin inspection

- Added separate professional and personal inspection surfaces.
- Added lifecycle labels for active, corrected, superseded, forgotten, and
  opted-out records.
- Added strict schema, content-digest, freshness, privacy, and compatibility
  validation before display.
- Added projection-specific readback receipts. Publication is not represented
  as display until the app returns the matching projection identifier, schema,
  digest, and view.
- Prevented withheld governance reasons and prohibited raw evidence from being
  rendered.

### Runtime Operations cockpit

- Added workflow, retry, dead-letter, replay, external-action, compatibility,
  migration, alert, and recovery inspection.
- Added deterministic room routing so a notification or recovery path opens the
  intended operational view.
- Kept external actions read-only in Command Center. The app reports state but
  does not bypass the plugin's confirmation and verification controls.

### Evaluation and Pilot room

- Added six independently receipted views:
  `evaluation-overview`, `evaluation-coverage`,
  `evaluation-release-gates`, `evaluation-connectors`, `evaluation-pilot`, and
  `evaluation-enterprise-claim`.
- Added exact test denominators, adversarial coverage, release-gate decisions,
  connector lifecycle, bounded pilot progress, and enterprise-claim limits.
- Added rejection for unknown fields, duplicate identifiers, denominator
  mismatches, stale payloads, unsupported versions, invalid gate states,
  privacy violations, and forged digests.
- Retained the last valid in-memory projection for context when a new payload is
  invalid, labels it stale, and withholds a display receipt.

### Compatibility and migration

- Added explicit plugin and app compatibility checks to the new projections.
- Kept Planner, Digital Twin, Runtime Operations, and Evaluation readbacks
  separate and non-interchangeable.
- Preserved the prior `0.4.1 (16)` application as the local rollback baseline.

## Verification

The release passed 36 native Command Center tests as part of the combined
145-test MONDAY release run. It was built as a universal macOS application,
installed locally, launched, paired with the immutable plugin build, and
verified against the exact current Evaluation projection and view-specific
readback contract.

The application source release is commit `3ec9026` plus this documentation
commit. The matching plugin source is commit `93c9eb8` on the `monday-plugin`
branch of `cbinion73/MONDAY`.

## Installation state versus distribution state

The verified local installation is `/Applications/Command Center.app`. It has
a valid local signing identity and works on this Mac. It is not yet a publicly
distributable release. External installation still requires:

1. Archive with a Developer ID Application certificate.
2. Submit the application and DMG for Apple notarization.
3. Staple the notarization ticket.
4. Verify Gatekeeper acceptance on the final DMG.
5. Test first install and automatic MONDAY plugin discovery on a second Mac.

The repository includes `scripts/release-notarized-dmg.sh` for that governed
release path. Credentials and notarization profiles are never committed.

## Known operational limits

- Restart Command Center after replacing the installed plugin so the app
  discovers the new immutable cache path.
- The unattended next-day planning proof and five-day bounded pilot remain open
  acceptance gates.
- A successful single-user pilot cannot be promoted to an enterprise-readiness
  claim.

## Rollback

The pre-release application is preserved locally as:

`~/Library/Application Support/MondayCommandCenter/Backups/Command Center-0.4.1-16-priority4-rollback.app`

Rollback replaces only the app bundle. It does not modify the user's vaults,
plugin records, or Command Center projections.
