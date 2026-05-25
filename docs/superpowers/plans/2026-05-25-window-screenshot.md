# Window Screenshot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add double-click window screenshot selection while preserving the current region screenshot flow and last-selection memory.

**Architecture:** Keep CoreGraphics window-list parsing in `FrameApp/WindowCandidateProvider`, add `SelectionCapture` metadata in `FrameCore`, and let `SelectionOverlayWindow` switch between region and window selection on double-click. Confirmation still flows through the existing rectangular capture service.

**Tech Stack:** Swift 6.1, AppKit, CoreGraphics, Swift Testing, existing `FrameCore` and `FrameApp` package targets.

---

## File Structure

- Create `Sources/FrameCore/SelectionCapture.swift` for `.region` / `.window` selection metadata.
- Keep `Sources/FrameCore/WindowCandidate.swift` for lightweight candidate identity and bounds.
- Keep `Sources/FrameApp/WindowCandidateProvider.swift` for `CGWindowListCopyWindowInfo` parsing, filtering, and coordinate conversion.
- Modify `Tests/FrameCoreTests/FrameCoreTests.swift` to cover marked window selection metadata.
- Modify `Sources/FrameApp/SelectionOverlayController.swift` to return `SelectionCapture` and provide double-click window lookup.
- Modify `Sources/FrameApp/SelectionOverlayWindow.swift` to select a window candidate on double-click, ignore HUD/empty/ineligible double-clicks, and confirm marked selections.
- Modify `docs/architecture.md` after implementation to record the durable double-click window-selection boundary.

## Tasks

- [x] Add `SelectionCaptureKind` and `SelectionCapture` in `FrameCore`.
- [x] Remove automatic hover state and tests.
- [x] Keep window candidate filtering behind `WindowCandidateProvider`.
- [x] Wire overlay double-click to query a candidate at the clicked global point.
- [x] Ignore double-clicks on HUD or ineligible surfaces.
- [x] Confirm window selections as `.window` and region selections as `.region`.
- [x] Update specs and architecture docs.
- [ ] Run `swift test`, `swift build`, and `scripts/package-app.sh`.
- [ ] Replace the local app bundle signed with `Frame Local Dev CLI`.

## Manual Smoke

- Start screenshot with a previous region and confirm it is still visible.
- Double-click a normal app window and confirm the active selection changes to that window bounds.
- Press Enter after window selection and confirm the captured image uses that window's full bounds.
- Double-click HUD, desktop, and common system UI surfaces and confirm selection remains unchanged.
- Drag or resize a region after selecting a window and confirm region editing takes over.

