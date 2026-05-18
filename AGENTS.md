<!-- deweyou-agent:start -->
## Dewey Workflow

This repository uses Dewey's personal agent workflow. Inspect `.agents/` before making changes, then run `deweyou-cli agent context --format markdown` and follow the returned rules, skill index, asset paths, and runtime notices.
<!-- deweyou-agent:end -->

## Project Context

Frame is a native macOS screenshot utility. v0.1 focuses on the local screenshot loop:

- menu bar app with no main window
- `Command+Shift+A` region screenshot shortcut
- Screen Recording permission guidance
- multi-display selection overlay
- PNG capture
- Quick Access actions for copy, save, and close

Recording, annotation, OCR, history, cloud sync, and scrolling capture are intentionally out of scope for v0.1.

## Commands

Run these before claiming a change is ready:

```sh
swift test
swift build
scripts/package-app.sh
```

The packaging script creates `.build/app/Frame.app` and ad-hoc signs it for local testing.

## Knowledge Base

Use `docs/` as the project knowledge base:

- `docs/architecture.md` explains runtime boundaries and core components.
- `docs/development.md` explains local setup, verification, packaging, and CI expectations.
- `docs/permissions.md` explains macOS Screen Recording/TCC behavior.
- `docs/superpowers/specs/` stores approved product specs.
- `docs/superpowers/plans/` stores implementation plans.

Keep durable implementation decisions in docs when they affect future agent work.

## macOS Permission Notes

Screen Recording permission is tied to the app identity and code signature. Local ad-hoc builds can require re-authorization after rebuilding because the binary signature changes. For repeat manual testing, copy a packaged app to a stable path such as `~/Applications/Frame.app`, authorize that exact app, and avoid rebuilding between authorization and smoke testing.

## Git Hygiene

- Do not commit `.build/`, `.superpowers/`, Xcode user state, or local app bundles.
- Do not stage unrelated user files.
- Keep feature work on `codex/*` branches unless the user asks otherwise.
