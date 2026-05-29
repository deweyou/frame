# HUD OCR Action Design

## Goal

Let users run OCR directly from the screenshot selection HUD after choosing a region, without first completing a normal capture and then using Quick Access.

## Product Decisions

- The selection HUD shows an OCR icon when a valid selection exists.
- Clicking the HUD OCR action captures the current selection and opens the existing OCR text panel.
- The normal capture confirmation path still opens Quick Access.
- The existing Quick Access OCR action remains available for screenshots that were captured normally.
- If OCR from the HUD finds no text or fails, Frame shows the same short user-facing feedback pattern as existing OCR failures and keeps the app recoverable.

## Scope

This iteration includes:

- A new OCR icon button in the selection HUD.
- A selection overlay completion path that distinguishes normal capture from direct OCR.
- AppDelegate wiring that captures the selected region, runs OCR, and opens the OCR text panel.
- Reuse of the existing `CaptureService`, `OCRService`, `OCRTextPanelController`, and OCR language settings.
- Tests for HUD button presence/action routing and overlay completion mode where practical.

This iteration excludes:

- OCR progress UI inside the selection overlay after it dismisses.
- Image-overlay text selection.
- Automatic OCR on every selection.
- Per-selection OCR language switching.

## UX

When a selection exists, the HUD includes a text-recognition icon next to the existing region action and size controls. The tooltip/accessibility label uses the existing localized OCR action string. Clicking it dismisses the overlay, captures the selected area, recognizes text, and opens the selectable OCR text panel. Return/Enter keeps the current behavior: normal capture into Quick Access.

## Architecture

- Introduce a selection completion mode in `FrameApp`, such as `.capture(selection)` and `.ocr(selection)`.
- `SelectionOverlayWindow` owns the HUD OCR button and calls completion with the OCR mode.
- `SelectionOverlayController` remains responsible for closing overlay windows and preserving selection history, independent of which completion mode was chosen.
- `AppDelegate.startCaptureFlow` switches on the completion mode:
  - `.capture`: current capture -> Quick Access behavior.
  - `.ocr`: capture -> OCR service -> OCR panel behavior.

## Error Handling

- Invalid selections beep and stay in the overlay.
- Capture failures from HUD OCR show the existing capture failure alert.
- OCR failures from HUD OCR show the existing OCR failure alert.
- No-text results show a lightweight no-text alert because there is no Quick Access status surface in this path.

## Acceptance Criteria

- Users can click OCR in the HUD after selecting an area.
- HUD OCR opens a non-empty OCR text panel when text is recognized.
- Normal capture behavior remains unchanged.
- Quick Access OCR remains unchanged.
- The local GUI test handoff uses `Frame Local Dev CLI` stable signing.
