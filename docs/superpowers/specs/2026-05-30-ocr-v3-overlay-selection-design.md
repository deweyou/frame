# OCR V3 Overlay Selection Design

## Goal

Add Live Text-like selection to the image preview editing window. Opening the temporary image workspace should automatically run OCR in the background, then let users select recognized text directly on the image and copy it, without changing the existing Quick Access OCR button or OCR text panel workflows.

## Product Decisions

- V3 is an additive preview-editing feature.
- V1/V2 remain unchanged:
  - Quick Access OCR still opens the OCR result panel.
  - The OCR panel still supports cuts, Shift range selection, clear, copy selected, and copy all.
- Automatic OCR starts only when a `.temporaryPreview` image workspace opens.
- The Quick Access thumbnail itself does not auto-OCR.
- Pinned image-only windows do not auto-OCR unless the user opens Edit, which creates the normal temporary preview.
- OCR results live only for the current workspace lifecycle.
- The first version targets selectable text blocks on the image, not full Apple Live Text parity such as insertion cursors, text editing, lookup, translation, or selection handles.

## User Flow

1. User captures a screenshot.
2. User opens the image preview editing window from Quick Access, or edits a pinned image.
3. Frame opens the current image workspace UI as before.
4. Frame starts OCR in the background for that workspace.
5. When OCR results arrive, a transparent overlay above the image becomes text-selectable.
6. User drags across recognized text on the image to select it.
7. User presses `Command+C` to copy selected text.
8. Existing image copy/download buttons continue to copy/download the image, not the selected OCR text.

## Architecture

- `OCRService` remains the only Vision boundary.
- `FrameCore` keeps deterministic OCR text/cut models.
- `RecognizedTextLine` gains optional token metadata so V3 can use token-level bounds when Vision provides them.
- `RecognizedTextCutLayout` uses token metadata when present and falls back to the existing line-bound tokenizer when not present.
- `ImageWorkspacePanelController` gets optional OCR dependencies:
  - async recognize closure for a `CapturedScreenshot`,
  - copy-text closure for selected OCR text.
- The preview image container receives an `ImageWorkspaceTextSelectionOverlayView` above `ImageWorkspaceImageView`.
- The overlay owns hit testing, drag selection, Shift range extension, selection drawing, and `Command+C`.

## Bounds Strategy

- OCR line bounds continue to use `VNRecognizedTextObservation.boundingBox`.
- Token bounds should use `VNRecognizedText.boundingBox(for:)` for tokenizer ranges.
- If Vision cannot return a token bounding box, the token falls back to the line bounds.
- Coordinate conversion maps normalized lower-left image rectangles into the actual fitted image rect drawn by `ImageWorkspaceImageView`.

## UI Behavior

- The overlay is transparent when nothing is selected.
- Dragging from one recognized cut through another selects the range in visual order.
- Shift-click extends from the previous anchor to the clicked cut.
- Selected text uses the same quiet accent highlight style as the OCR panel selection.
- `Command+C` copies OCR-selected text when the overlay has selection.
- Right-clicking selected OCR text in the image overlay shows a focused `Copy` menu item for the selected text.
- If no OCR text is available, the workspace behaves exactly as it does today.
- OCR failure in the workspace is non-blocking and does not show a modal alert.

## Testing Strategy

- Core tests:
  - tokenizer candidates expose text ranges and spacing.
  - `RecognizedTextCutLayout` prefers token bounds when provided.
- OCR service tests:
  - recognized lines can carry token bounds.
- Workspace tests:
  - temporary preview receives a text overlay.
  - pinned image-only workspace does not expose the overlay.
  - setting OCR layout on the overlay allows hit selection and `Command+C`.
  - image output Copy button still calls the image copy closure.

## Acceptance Criteria

- Opening image preview editing starts automatic OCR without user action.
- Users can select recognized text directly on the image preview.
- `Command+C` copies selected OCR text from the image overlay.
- Right-click Copy copies selected OCR text from the image overlay.
- Existing Quick Access OCR and OCR panel behavior still works.
- Existing image copy/download behavior still works.
- Pinned image-only windows stay image-only.
