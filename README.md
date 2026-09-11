# MONDAY Command Center

The native visual companion for MONDAY, Chris Binion's ChatGPT plugin.

Command Center is an interface, not MONDAY itself. It renders a user's approved
MONDAY context—projects, planner, journal library, study, prayer, weather, and
other rooms—without recreating the intelligence, personality, or private data
held by the MONDAY plugin.

## Current status

This repository is public so the Command Center interface can be shared and
reviewed. It is not yet a self-service installation for other people. The
present build contains local-only integrations for a user's own MONDAY bridge,
vault, and project registry; it ships no credentials or personal data.

Before external distribution, Command Center needs a generic pairing contract
with each user's installed MONDAY plugin. The interface must show an honest
unpaired state rather than assume access to ChatGPT, Codex, a calendar, or a
personal vault.

## Local development

Requirements: macOS, Xcode, and XcodeGen.

```sh
xcodegen generate
xcodebuild -project MondayCommandCenter.xcodeproj \
  -scheme MondayCommandCenter \
  -configuration Debug build
```

`project.yml` is the source of truth; the Xcode project is generated locally.

## Boundaries

- MONDAY remains a ChatGPT plugin.
- Command Center is a read-oriented companion interface.
- Calendar, vault, and Codex access are opt-in and user-owned.
- Tokens, private records, local build products, and generated projects do not
  belong in this repository.
