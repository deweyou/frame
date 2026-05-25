<!-- deweyou-agent:start -->
## Dewey Workflow

This repository uses Dewey's personal agent workflow. Inspect `.agents/` before making changes, then run `deweyou-cli agent context --format markdown` and follow the returned rules, skill index, asset paths, and runtime notices.
<!-- deweyou-agent:end -->

## Project Context

Frame is a native macOS screenshot utility. The current implemented scope focuses on the local screenshot loop:

- menu bar app with no main window
- `Command+Shift+A` region screenshot shortcut
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

## Knowledge Base

Use `docs/` as the project knowledge base:

- `docs/architecture.md` explains runtime boundaries and core components.
- `docs/development.md` explains local setup, verification, packaging, and CI expectations.
- `docs/permissions.md` explains macOS Screen Recording/TCC behavior.
- `DESIGN.md` explains durable interface principles and HUD/Quick Access behavior.
- `docs/superpowers/specs/` stores approved product specs.
- `docs/superpowers/plans/` stores implementation plans.

Keep durable implementation decisions in docs when they affect future agent work.

## macOS Permission Notes

Screen Recording permission is tied to the app identity and code signature. Local ad-hoc builds can require re-authorization after rebuilding because the binary signature changes. For repeat manual testing, prefer a stable local Code Signing identity such as `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI"`, copy the packaged app to a stable path such as `~/Applications/Frame.app`, and authorize that exact app. Keep this as the default local development path even after Apple signing certificates exist; reserve Apple Development or Developer ID identities for explicit signing-path or distribution tests.

## Git Hygiene

- Do not commit `.build/`, `.superpowers/`, Xcode user state, or local app bundles.
- Do not stage unrelated user files.
- Keep feature work on `codex/*` branches unless the user asks otherwise.
