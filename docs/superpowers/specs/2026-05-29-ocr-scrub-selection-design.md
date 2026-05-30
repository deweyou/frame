# OCR Scrub Selection Design

## Goal

Make OCR output feel closer to WeChat's "涂抹选择文字" interaction: users can inspect the source screenshot, scrub across recognized text cuts, and copy only the selected cuts instead of copying the whole OCR result.

## Product Decisions

- OCR opens a scrub-selection panel instead of a plain text-only panel.
- The panel keeps the screenshot visible as context and renders recognized text as selectable cuts below it.
- Users can click a cut to toggle it and drag across cuts to select multiple cuts.
- The first version supports two actions: select all and copy selected text.
- Copy all remains available through select all plus copy.
- The existing Quick Access OCR button and HUD OCR button both route into this panel.

## Scope

This iteration includes:

- A token/cut model derived from recognized OCR lines.
- A lightweight tokenizer:
  - Chinese, Japanese, and Korean characters become single-character cuts.
  - Latin letters and digits are grouped into continuous word-like cuts.
  - Whitespace separates cuts.
  - Punctuation becomes its own cut unless it is part of a code-like run.
- A native AppKit OCR selection panel with:
  - screenshot preview at the top,
  - cut grid/list below,
  - click-to-toggle selection,
  - drag-to-select selection,
  - select-all and copy-selected actions.
- Tests for tokenizer behavior, selected text joining, and panel controls where practical.
- Stable local GUI handoff using `Frame Local Dev CLI`.

This iteration excludes:

- Selecting text directly on top of the screenshot image.
- Cross-line drag handles or platform Live Text style selection handles.
- NLP-grade Chinese word segmentation.
- WeChat-only actions such as forward, favorite, and search.
- Re-running OCR when cuts are selected.

## UX

The panel title remains OCR-oriented, but the content changes from a plain text box to a two-part selection experience.

The screenshot preview sits at the top with a bounded height so users can confirm where the text came from. Below it, recognized text appears as rows of rounded light-gray cuts. Rows follow the same visual order as OCR layout: top-to-bottom, left-to-right. Each selected cut uses a clear active fill and foreground color.

Users can:

- click a cut to toggle selection,
- press and drag over cuts to add them to the selection,
- choose select all,
- copy the currently selected cuts.

The copy button is disabled when no cuts are selected. After a successful copy, the app uses the existing OCR copied status behavior when there is a Quick Access preview; HUD OCR panels can simply keep the selection in place.

## Text Joining

Selected cuts should copy into readable text rather than a raw UI dump.

- Cuts from the same OCR row are joined without spaces for CJK-only sequences.
- Latin/digit word cuts in the same row use a space between adjacent word cuts when the original OCR line had whitespace between them.
- Punctuation cuts preserve their original relationship as much as the tokenizer can infer.
- Multiple selected rows are joined with newlines.
- Selection order follows visual OCR order, not the order in which the user scrubbed.

## Architecture

- `FrameCore` owns project-level OCR cut models and deterministic ordering:
  - `RecognizedTextCut`
  - `RecognizedTextCutLayout`
  - tokenizer and selected-text formatter
- `FrameApp.OCRService` continues to own Vision integration.
- The first implementation can derive cut bounds from line-level bounds if range-specific Vision bounds are not stored yet.
- If practical, `OCRService` should use `VNRecognizedText.boundingBox(for:)` to attach normalized bounds to each cut. This keeps the model ready for a later image-overlay selection mode.
- `OCRTextPanelController` becomes the owner of the scrub-selection panel UI and copy-selected callback.
- `AppDelegate` continues to own clipboard output and Quick Access status updates.

## Error Handling

- If tokenization produces no cuts but OCR has text, fall back to one cut per non-empty line.
- Copy selected is disabled when nothing is selected.
- Copy failure follows the existing OCR copy failure behavior.
- Panel reuse for the same screenshot replaces the cut layout and clears stale selection.

## Acceptance Criteria

- OCR output is shown as selectable cuts with the screenshot visible above it.
- Chinese text can be selected at single-character granularity.
- English and number runs can be selected as word-like cuts.
- Dragging across cuts selects multiple cuts.
- Select all selects every cut.
- Copy selected writes only selected cuts in visual order.
- Quick Access OCR and HUD OCR both open the scrub-selection panel.
- Existing no-text and OCR failure paths still work.
