## Project Context

Frame is a native macOS screenshot utility. The current implemented scope focuses on the local screenshot loop:

- menu bar app with no main window
- `Command+Shift+A` default region screenshot shortcut, configurable in Settings
- Screen Recording permission guidance
- multi-display selection overlay
- PNG capture
- Quick Access actions for copy, save, and close

Recording, annotation, OCR, history, cloud sync, and scrolling capture are future product areas unless a task explicitly brings them into scope.

## Commands

Run these before claiming a change is ready:

```sh
swift test
swift build
scripts/package-app.sh
```

The packaging script creates `.build/app/Frame.app` and signs it for local testing. It uses ad-hoc signing by default, or `FRAME_CODESIGN_IDENTITY` when a stable local Code Signing identity is available.

For user-facing GUI changes, final handoff must explicitly ask whether to replace the local test app unless the user already declined or replacement was already completed in the same turn.

When replacing the user's local app or preparing a repeat GUI test build, do not use the default ad-hoc package. Always run this exact stable-signing flow:

```sh
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
```

After replacement, verify `codesign -dv --verbose=2 ~/Applications/Frame.app` reports `Authority=Frame Local Dev CLI` before telling the user it is ready.

## Knowledge Base

Use `docs/` as the project knowledge base:

- `docs/architecture.md` explains runtime boundaries and core components.
- `docs/development.md` explains local setup, verification, packaging, and CI expectations.
- `docs/overlay-interactions.md` explains screenshot overlay drag, cursor, handle, and HUD tooltip behavior.
- `docs/testing.md` explains automated test layers, AppKit component e2e boundaries, and the expectation to cover new interactive requirements with e2e tests.
- `docs/permissions.md` explains macOS Screen Recording/TCC behavior.
- `DESIGN.md` explains durable interface principles and HUD/Quick Access behavior.
- `docs/superpowers/specs/` stores approved product specs.
- `docs/superpowers/plans/` stores implementation plans.

Keep durable implementation decisions in docs when they affect future agent work.

## Product README

`README.md` is the English product overview and `README_ZH.md` is the Chinese product overview. Keep them aligned. Whenever adding, removing, or materially changing a user-facing feature, check whether both README files need updates.

## macOS Permission Notes

Screen Recording permission is tied to the app identity and code signature. Local ad-hoc builds can require re-authorization after rebuilding because the binary signature changes. For repeat manual testing, prefer a stable local Code Signing identity such as `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI"`, copy the packaged app to a stable path such as `~/Applications/Frame.app`, and authorize that exact app. Keep this as the default local development path even after Apple signing certificates exist; reserve Apple Development or Developer ID identities for explicit signing-path or distribution tests.

## Git Hygiene

- Do not commit `.build/`, `.superpowers/`, Xcode user state, or local app bundles.
- Do not stage unrelated user files.
- Keep feature work on `codex/*` branches unless the user asks otherwise.
