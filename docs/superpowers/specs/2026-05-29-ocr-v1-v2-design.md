# OCR V1/V2 Design

## Goal

Add a local OCR experience to Frame so users can extract text from a captured screenshot without leaving the Quick Access flow. This iteration should make OCR useful immediately through whole-image recognition and a selectable text result panel, while preserving enough recognition layout data for a future image-overlay text selection experience.

## Product Decisions

- Apple Vision is the OCR engine for this iteration.
- OCR runs locally on the user's Mac and does not require network access.
- OCR is triggered from a captured screenshot after Quick Access appears.
- The first user-facing OCR result is text, not an editable image overlay.
- Users can copy all recognized text in one action.
- Users can open a text result panel, select a subset of recognized text, and copy it with normal text selection behavior.
- OCR results are scoped to the current captured screenshot preview lifecycle.
- The data model should retain line-level layout metadata so the future image-overlay selection experience can reuse the same OCR service boundary.

## Scope

This iteration includes:

- A Quick Access OCR action for captured screenshots.
- Local Apple Vision text recognition for the captured image.
- Asynchronous recognition so the Quick Access UI stays responsive.
- OCR states for idle, recognizing, recognized text, no text found, and failure.
- A lightweight OCR text panel associated with the captured screenshot.
- Normal text selection inside the OCR text panel.
- Copy all recognized text from the OCR panel.
- Copy selected text from the OCR panel through standard text selection.
- Basic deterministic text ordering and joining from recognized lines.
- A project-owned OCR result model that includes full text, line text, line bounds, confidence, and request metadata needed later by v3.

This iteration excludes:

- Direct text selection on top of the image.
- Word-level or character-level image hit testing.
- OCR highlights over the screenshot preview.
- Table structure reconstruction.
- Screenshot history persistence for OCR results.
- Cloud OCR, LLM OCR, or remote text extraction.
- Automatic OCR on every capture unless a later product decision explicitly enables it.
- Language preference UI.

## Architecture

Keep Vision and AppKit behavior in `FrameApp`; keep deterministic text assembly in `FrameCore`.

- `QuickAccessPanelController` exposes an OCR action for each captured screenshot and displays per-screenshot recognition state.
- A new `OCRService` in `FrameApp` wraps Apple Vision requests. It accepts the captured image or PNG data and returns a project-owned OCR result instead of leaking Vision observations to callers.
- A new core model, `RecognizedTextLayout`, represents recognized text independent of Vision. It stores:
  - `fullText`
  - ordered recognized lines
  - each line's normalized image-space bounding box
  - confidence when available
  - requested recognition level and language hints when configured
- A small deterministic formatter in `FrameCore` orders lines and joins them into `fullText`.
- A new OCR text panel controller in `FrameApp` owns the selectable text panel lifecycle, copy-all action, selected-text behavior, and status display.
- `AppDelegate` wires the OCR service and OCR panel controller into the existing captured screenshot flow.

The OCR service should be easy to replace or extend later. Callers should not depend on `VNRecognizedTextObservation`, Vision coordinate conventions, or Vision request lifecycle details.

## Quick Access Flow

1. User captures a screenshot.
2. Frame shows the normal Quick Access preview.
3. Quick Access hover controls include an OCR action.
4. Clicking OCR starts recognition for that captured screenshot if no result exists yet.
5. While recognition is running, the OCR action shows a busy state and cannot start duplicate requests for the same screenshot.
6. When recognition succeeds with text, Frame opens or activates the OCR text panel for that screenshot.
7. When recognition succeeds with no text, Frame keeps the screenshot preview open and shows a short no-text state.
8. When recognition fails, Frame keeps the screenshot preview open and shows a short failure state.
9. Re-clicking OCR after a successful recognition opens or activates the existing OCR text panel without re-running recognition.

## OCR Text Panel Flow

1. The OCR text panel opens near the related screenshot preview or active screen.
2. The panel displays recognized text in a selectable native text view.
3. Users can select any subset of text and copy through `Command+C` or the text view context menu.
4. A copy-all action copies the full recognized text to the system pasteboard.
5. The panel can be closed without closing the originating Quick Access preview.
6. If the originating Quick Access preview is closed, the OCR panel for that screenshot should close too.

## UI Design

Quick Access remains compact:

- OCR appears as an icon-only action alongside existing Quick Access actions.
- The OCR action needs an accessibility label and tooltip.
- Recognizing state should be visible without expanding Quick Access into a large surface.
- OCR status feedback should be short and operational: recognizing, copied, no text found, or failed.

The OCR text panel should feel like a small native utility surface:

- It is a focused text surface, not a document editor.
- Text should be selectable with standard macOS text behavior.
- Copy all should be visible as an action.
- The panel should not obscure the original screenshot more than necessary.
- It should support enough resizing or scrolling for long OCR output.
- It should use the same quiet native visual language as the existing workspace and Quick Access surfaces.

## Error Handling

- If the current macOS version cannot perform Vision text recognition, show a clear unsupported-state message and keep the screenshot preview open.
- If the image cannot be converted into a Vision input, report OCR failure and keep the screenshot preview open.
- If recognition fails, preserve the screenshot preview and allow retry.
- If no text is recognized, show a no-text state instead of treating it as a failure.
- If copying full text fails, keep the OCR panel open and show a pasteboard error.
- If recognition is already running for a screenshot, ignore duplicate starts and keep the visible busy state.

## Testing Strategy

Unit tests should cover deterministic core behavior:

- Recognized lines sort into expected reading order for simple top-to-bottom text.
- Lines on the same row sort left to right.
- Empty OCR results produce empty `fullText`.
- Multi-line OCR results join with line breaks.
- Confidence and normalized bounds survive conversion into the project-owned model.

AppKit and Vision behavior should be verified through focused build and manual smoke checks:

- Quick Access still appears after capture.
- OCR action starts recognition without blocking Quick Access hover behavior.
- Successful recognition opens a selectable text panel.
- `Command+C` copies selected text from the panel.
- Copy all copies the full recognized text.
- No-text and failure states keep the screenshot preview available.
- Re-clicking OCR after success reopens or activates the cached panel.
- Closing the screenshot preview closes its OCR panel.

## Acceptance Criteria

- Users can capture a screenshot and trigger OCR from Quick Access.
- OCR uses Apple Vision locally.
- Recognition runs asynchronously and does not freeze the post-capture UI.
- Users can copy all recognized text.
- Users can select and copy partial text from the OCR text panel.
- No-text and failure states are visible and recoverable.
- OCR implementation details are isolated behind project-owned types and services.
- The result model preserves line bounds for a future image-overlay text selection implementation.

## Open Follow-Ups

- Add v3 image-overlay text selection on top of the screenshot using recognized line or word bounds.
- Decide whether v3 needs word-level or character-level recognition metadata.
- Add OCR language preferences if user testing shows mixed-language recognition needs manual control.
- Decide whether OCR results should be persisted when screenshot history exists.
- Explore optional automatic OCR if manual triggering feels too slow in daily use.
