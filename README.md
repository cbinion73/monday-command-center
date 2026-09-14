# MONDAY Command Center

The native visual companion for MONDAY, Chris Binion's ChatGPT plugin.

Command Center is an interface, not MONDAY itself. It renders a user's approved
MONDAY context—projects, planner, journal library, weather, and other rooms—
without recreating the intelligence, personality, or private data held by the
MONDAY plugin.

## Current status

This repository is public so the Command Center interface can be shared and
reviewed. Command Center v1 is a read-oriented companion for a person who has
already installed the MONDAY Thermo plugin. It ships no credentials, personal
data, tokens, or user-specific file paths.

On first launch, Command Center looks only in Codex's local plugin cache and
MONDAY's documented vault locations. When it finds a valid installed plugin and
recipient-owned Project Knowledge vault, it pairs automatically. If either is
missing or nonstandard, Settings opens with its best verified suggestions:

- their installed `monday-thermo` plugin folder;
- their recipient-owned Project Knowledge vault, containing `03 Projects`;
- their Captain's Log at `Chris Knowledge/500 Personal Journal`;
- MONDAY's Research Journal at `Monday Knowledge/500 Research Journal`;
- optionally, a local JSON file exported by the Codex Planner skill.

The app verifies the plugin manifest and vault layout before saving local
settings. It does not search arbitrary user folders, infer access to ChatGPT,
or display fallback project data.

## Local development

Requirements: macOS, Xcode, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project MondayCommandCenter.xcodeproj \
  -scheme MondayCommandCenter \
  -configuration Debug build
```

`project.yml` is the source of truth; the Xcode project is generated locally.

## Recipient setup

1. Install the MONDAY Thermo plugin and create a recipient-owned Project
   Knowledge vault. The plugin's `docs/recipient-vault-setup.md` documents the
   non-destructive vault bootstrap.
2. Install Command Center from a signed release when one is published, then
   open it from Applications.
3. On first launch, Command Center pairs automatically when it finds the
   standard installed plugin and vault. Otherwise, choose the suggested paths
   in **Settings**. The two journal locations are separate read-only settings.
4. Connect the calendar in Codex, then have the Planner skill export the
   bounded daily plan to a local JSON file. Run the local MONDAY Planning
   Pipeline to reconcile it with authorized project and operations records.
   Select that file in
   **Settings → Planner shared plan**. The same file drives both Planner and
   today's calendar card. The exact [shared-plan contract](docs/PLANNER_SHARED_PLAN.md)
   is versioned with the app.

The settings are stored locally in the app's preferences and can be removed
with **Settings → Forget this Mac**. Removing them changes no MONDAY data.

## Release boundary

A shareable build must be archived with an Apple Developer ID Application
certificate, notarized, and distributed as a signed DMG. Those credentials are
intentionally not present in this repository. Until that release gate is
completed, this repository supports source review and local development, not a
claim of one-click public installation.

The repeatable release command is `scripts/release-notarized-dmg.sh`. It takes
the Developer ID identity, team ID, and `notarytool` Keychain profile from the
release environment, verifies the signed app, notarizes both the app archive
and DMG, staples the result, and runs Gatekeeper assessment before reporting
the DMG path.

## Boundaries

- MONDAY remains a ChatGPT plugin.
- Command Center is a read-oriented companion interface.
- Codex owns calendar authorization. Command Center never stores or receives
  calendar credentials, and only reads the selected Planner JSON export.
- The Planner connection is a local, user-selected file contract. It is not a
  hidden localhost service or a direct bridge into a Codex conversation.
- The Planning Pipeline creates local activity and MONDAY Operations receipts;
  it never writes a Captain's Log, calendar, external task, or message.
- Vault and Codex access are opt-in and user-owned.
- Tokens, private records, local build products, and generated projects do not
  belong in this repository.
