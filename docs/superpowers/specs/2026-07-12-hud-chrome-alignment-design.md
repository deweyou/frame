# HUD Chrome Alignment Design

## Goal

Make Frame's screenshot editor, video preview, video editor, and Quick Access
controls feel like one native macOS tool by sharing stable deep-glass chrome.
The captured image or video remains the visual focus; only control surfaces,
status affordances, and media placeholders adopt the dark treatment.

## Scope

- Add a small shared AppKit `FrameHUDChrome` boundary for dark HUD material,
  backing colors, borders, icon tints, disabled tints, hover fills, and compact
  accessory chips.
- Apply the shared toolbar treatment to the Image Workspace and Video Preview
  output headers.
- Apply a deeper editor surface to the Video Editor Bar while retaining its
  timeline-first layout and separate playback/speed controls.
- Apply deep glass to Quick Access action overlays, close/status/duration
  accessories, no-thumbnail placeholders, and right-side hover previews.
- Keep screenshot thumbnails, recording thumbnails, and video playback pixels
  unmodified by chrome overlays until the user explicitly hovers the card.

## Surface Rules

### Shared Chrome

- HUD toolbar surfaces use `hudWindow` material in a vibrant dark appearance,
  a stable black translucent backing, and a quiet translucent border.
- Primary icons are light, disabled icons are visibly dimmer, hover fills are
  compact and low contrast, and selected controls use the existing accent color
  plus a light glyph.
- Icon-only actions keep tooltips and accessibility labels.

### Video Preview

- The top output row aligns with the Image Workspace: native traffic-light safe
  area, trailing output group, 28 pt button cells, compact internal spacing, and
  dark toolbar chrome.
- The MP4 editor bar is an editing workbench, not a second toolbar. Its deep
  background carries the timeline, play/pause, duration, and speed controls
  without turning each row into a floating capsule.
- Timeline labels, speed token text, and transport icons use light high-contrast
  tints. Accent color remains reserved for playback, trim selection, and active
  manipulation.

### Quick Access

- The card's media stays visually true to the captured content.
- Hover action overlays use deep glass with light icon buttons.
- Close buttons, OCR status, and recording duration badges use compact deep
  accessory chips rather than light system-background pills.
- Placeholder surfaces and right-side hover previews use deep glass so they do
  not pick up arbitrary wallpaper or thumbnail luminance.

## Architecture

`FrameHUDChrome` lives in FrameApp and owns only reusable AppKit presentation
tokens and application helpers. It does not own media layout, playback state,
capture state, or action routing. Image Workspace, Video Preview, Video Editor,
and Quick Access retain their existing component-specific layouts and behaviors.

## Testing Strategy

- Add unit coverage proving each control surface uses the shared dark appearance,
  stable backing, and light primary icon treatment.
- Preserve existing geometry, playback, export, Quick Access card, and media
  behavior tests.
- Verify Video Preview output cells match the Image Workspace density.
- Verify Quick Access media views remain separate from their dark action overlay.

## Acceptance Criteria

- Bright wallpapers, screenshots, and videos cannot reduce control icon
  legibility.
- Video Preview and Image Workspace headers read as one product family without
  becoming identical layouts.
- Video Editor remains a clear timeline workbench.
- Quick Access keeps captured media inspectable while controls, badges, and
  hover previews use stable deep glass.
