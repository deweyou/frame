# Changelog

## Unreleased

- Improve the screenshot editor with a context-aware header style control, an
  icon-only color swatch selector and tiled palette dropdown, canvas tool
  shortcuts, and double-click object context switching.
- Add a setting for the Save Current default behavior so edited screenshots can
  replace the current preview or save as a new preview without prompting every
  time.
- Refine editor close prompts, expand text sizing through 96 pt, use an opaque
  canvas backdrop, hide selection HUD controls during delayed capture, and
  persist the last confirmed screenshot selection for ten minutes across Frame
  restarts.
- Remove the visible blue resize anchor from selected image annotations while
  retaining the top-right resize target.
- Make the image editor's Save Current, Copy, and Download controls a compact,
  evenly sized group, with Save and Copy / Save and Download tooltips.
- Rework the image editor toolbar with stable dark glass, clearer semantic
  groups, centered normalized icon rendering, and an attached Mosaic split
  control with a larger menu target.
- Align image editing, video preview/editing, and Quick Access control chrome
  around stable deep glass while keeping captured image and video pixels
  unmodified.
- Reduce the recording Quick Access duration badge so it stays legible without
  competing with the preview.

## 0.1.1 - 2026-07-06

- Add manual beta release tooling for version bumps, changelog rollover, DMG/ZIP
  artifacts, and SHA-256 checksums.
- Align recording Quick Access copy/download behavior with screenshot actions by
  dismissing the corner preview after successful actions.

## 0.1.0 - 2026-07-02

- Add the menu bar app shell, first-run Screen Recording permission guidance,
  and configurable screenshot and recording shortcuts.
- Add region, window, full-screen, delayed, and manual scrolling screenshot
  capture, including multi-display selection support and per-display full-screen
  output.
- Add the corner Quick Access preview stack with copy, save, close, drag-out,
  pin, larger preview, and edit entry points for recent captures.
- Add image annotation and editing tools for text, arrows, shapes, highlights,
  brush marks, mosaics, undo/redo, pinning, and saving edited results.
- Add local OCR flows for recognizing text from captures, reviewing recognized
  text, and copying selected text.
- Add selected-area recording as MP4 or GIF with cursor, click, and keyboard
  hint overlays, a visible recording boundary, and active recording controls for
  stop, restart, and delete.
- Add recording Quick Access previews with first-frame thumbnails, larger video
  preview playback, MP4 trim controls, speed export, copy, and download actions.
- Add local capture history for screenshots and recordings, including restore to
  Quick Access and configurable retention/storage cleanup.
- Add English and Simplified Chinese app strings for the primary capture,
  settings, history, OCR, editing, and recording surfaces.
