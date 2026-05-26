# Testing

```mermaid
flowchart TD
    Change["Interactive AppKit change"] --> E2E["Add or update component E2E"]
    E2E --> Unit["Keep deterministic logic in unit tests"]
    E2E --> CI["Run on macOS CI"]
    CI --> Manual["Use manual smoke only for permissions and full desktop flows"]
```

Frame uses two automated test layers:

- `FrameCoreTests` cover deterministic helpers that do not need AppKit.
- `FrameAppTests` cover AppKit component behavior that is stable in a macOS test process.

## Component E2E

AppKit component E2E tests live in `Tests/FrameAppTests/` and use XCTest. They should exercise real controls and field editors inside a test window, but avoid full desktop automation, Screen Recording permission, and modal AppKit APIs.

New HUD or interactive AppKit features should add component E2E coverage for the user-visible cases they change:

- ordinary typing and deletion before commit
- intermediate invalid input states that should not beep or commit early
- commit behavior through Enter, blur, or control actions
- keyboard shortcuts such as Command-A when they are stable in a test window
- model refreshes while a field editor is active
- button or menu-trigger callbacks that must commit active input first
- locked-ratio or preset behavior at the component boundary when it does not require a modal menu

Do not call modal menu presentation such as `NSMenu.popUp` from CI tests. Prefer testing the callback seam or the control state before presentation; keep a manual smoke note for the actual popover/menu if needed.

## CI Expectations

GitHub Actions runs on a fixed `macos-15` runner and records the AppKit component E2E local-only requirement:

```sh
swift test --filter HUDSizeControlTests
```

Run AppKit HUD component E2E locally before shipping interactive HUD changes. GitHub hosted macOS runners crash real `NSWindow`/field-editor tests before assertions run, so hosted CI skips this suite and keeps the stable lower-level test/build/package path green.

Avoid `macos-latest` because it can silently move to newer hosted images. Keep the runner pinned to a Swift 6.1-capable macOS image and keep real AppKit window e2e local-only until a self-hosted runner or a stable UI automation environment is available.

The workflow also runs the rest of the verification sequence:

```sh
swift test --skip HUDSizeControlTests
swift build
scripts/package-app.sh
```

Component E2E tests must remain deterministic without Screen Recording permission. Full screenshot capture, TCC prompts, and multi-display manual checks stay in the local smoke test flow documented in `docs/development.md`.

## Feature Iteration Rule

When a new requirement changes an interactive AppKit behavior, update the matching component E2E tests in the same change. If the behavior cannot be automated safely, document the reason and add the smallest stable lower-level coverage instead.

---
*Last updated: 2026-05-26 | Reason: document hosted CI boundary for HUD AppKit E2E*
