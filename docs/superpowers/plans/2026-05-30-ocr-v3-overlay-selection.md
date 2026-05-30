# OCR V3 Overlay Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add automatic OCR-backed text selection to the temporary image workspace preview without changing existing Quick Access OCR or OCR panel behavior.

**Architecture:** Extend core OCR token data with optional real token bounds, keep Vision details inside `OCRService`, and add a transparent text-selection overlay above the image workspace preview. The overlay owns selection and copy-text behavior while existing image output controls remain unchanged.

**Tech Stack:** Swift, AppKit, Vision, XCTest, FrameCore OCR models.

---

### Task 1: OCR Token Bounds Data

**Files:**
- Modify: `Sources/FrameCore/RecognizedTextLayout.swift`
- Modify: `Sources/FrameCore/RecognizedTextCutLayout.swift`
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`

- [x] Add `RecognizedTextToken` with text, bounds, and spacing metadata.
- [x] Add optional `[RecognizedTextToken]` to `RecognizedTextLine` with a default empty array.
- [x] Add tokenizer candidates that preserve `Range<String.Index>` for Vision range lookup.
- [x] Update `RecognizedTextCutLayout` to use line tokens when present and fall back to the existing tokenizer when absent.
- [x] Add tests proving token bounds are preferred and selected text remains stable.
- [x] Run `swift test --filter FrameCoreTests`.

### Task 2: Vision Token Bounds

**Files:**
- Modify: `Sources/FrameApp/OCRService.swift`
- Modify: `Tests/FrameAppTests/OCRServiceTests.swift`

- [x] Use tokenizer candidates from FrameCore inside `OCRService`.
- [x] For each candidate range, ask `VNRecognizedText.boundingBox(for:)`.
- [x] Store token bounds in `RecognizedTextLine`.
- [x] Fall back to line bounds when Vision cannot return token bounds.
- [x] Add focused tests for `makeRecognizedTextLine` carrying tokens.
- [x] Run `swift test --filter OCRServiceTests`.

### Task 3: Image Text Selection Overlay

**Files:**
- Create: `Sources/FrameApp/ImageWorkspaceTextSelectionOverlayView.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Create an AppKit overlay view that accepts `RecognizedTextCutLayout`.
- [x] Convert normalized image bounds into the fitted image rect used by `ImageWorkspaceImageView`.
- [x] Implement click, drag range selection, Shift range selection, clear, and `Command+C`.
- [x] Draw selected OCR cuts with a subtle accent highlight.
- [x] Add right-click Copy for selected OCR text.
- [x] Add direct overlay tests for hit selection and copied text.
- [x] Run `swift test --filter ImageWorkspacePanelControllerTests`.

### Task 4: Workspace Integration

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [x] Add optional OCR and copy-text dependencies to `ImageWorkspacePanelController.show`.
- [x] Add the overlay above the temporary preview image.
- [x] Start automatic OCR only for `.temporaryPreview`.
- [x] Ignore OCR completion after the workspace closes.
- [x] Keep pinned image-only windows unchanged.
- [x] Wire `AppDelegate.openWorkspace` to `OCRService` and `copyRecognizedText`.
- [x] Add tests for temporary overlay presence and pinned overlay absence.
- [x] Run `swift test --filter ImageWorkspacePanelControllerTests`.

### Task 4.5: OCR Workflow Polish

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Sources/FrameApp/OCRTextPanelController.swift`
- Modify: `Tests/FrameAppTests/OCRTextPanelControllerTests.swift`

- [x] Combine capture and OCR controls into one HUD group.
- [x] Make OCR panel cuts more compact.
- [x] Hide OCR panel scrollbars while preserving scroll behavior.
- [x] Keep OCR panel selection and copy controls covered by tests.

### Task 5: Verification And Local Handoff

**Files:**
- No additional source files expected.

- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Run `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh`.
- [x] Replace `~/Applications/Frame.app`, verify `Authority=Frame Local Dev CLI`, and launch it.
