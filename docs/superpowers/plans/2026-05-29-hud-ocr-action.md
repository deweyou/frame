# HUD OCR Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a selection HUD OCR action that captures the current selection and opens the OCR text panel directly.

**Architecture:** Add a project-owned `SelectionOverlayCompletion` mode so the overlay can distinguish normal capture from OCR. Keep capture and OCR execution in `AppDelegate`; keep the HUD button inside `SelectionOverlayWindow`.

**Tech Stack:** Swift 6.1, AppKit, Vision, XCTest.

---

## Tasks

- [ ] Add `SelectionOverlayCompletion` and update `SelectionOverlayController.startSelection` completion signatures.
- [ ] Add an OCR icon button to `SelectionOverlayWindow` and route it to `.ocr(selection)`.
- [ ] Update `AppDelegate.startCaptureFlow` to handle `.capture` and `.ocr`.
- [ ] Add/update focused tests for completion mode and HUD button behavior where AppKit exposes stable hooks.
- [ ] Run `swift test`, `swift build`, stable-sign package, replace `~/Applications/Frame.app`.

## Notes

- Return/Enter and the existing region HUD button keep normal capture behavior.
- HUD OCR has no Quick Access status surface; use alert feedback for no-text/failure.
- Quick Access OCR remains unchanged.
