# Command Center 0.4.3 release record

Command Center `0.4.3 (18)` closes the immutable-plugin rollover gap.

## Changes

- Automatically advances a managed Codex cache pairing to the newest valid installed MONDAY release.
- Preserves explicitly selected plugin folders outside the managed cache.
- Orders immutable builds by their `+codex.<timestamp>` metadata rather than filesystem modification time.
- Adds regression coverage for release ordering and managed-plugin selection.

The app remains a read-only projection. Updating the paired plugin path does not grant new connector access, write to a vault, or relax projection compatibility checks.
