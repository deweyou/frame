# Frame

[中文](README_ZH.md)

Frame is a native macOS capture utility for a faster local screenshot and recording loop: press a shortcut, select an area, then copy, save, preview, or recover the result locally.

It is intentionally small. Frame is not a cloud library or a heavyweight media suite. Its first job is to make the everyday screenshot path feel short, reliable, and quiet.

## Why Frame

Screenshots are often a tiny step inside a larger workflow: explaining an idea, reporting a bug, saving a visual state, or sending context to someone else. Frame keeps that step out of the way:

- Lives in the menu bar without a main window.
- Starts region capture with `Command+Shift+A`; the recording shortcut is unset
  by default and can be configured in Settings.
- Works across multiple displays.
- Shows a small Quick Access preview after screenshots and recordings, with a
  larger hover preview after a short pause.
- Lets you copy, save, edit, download, or close from contextual actions.
- Keeps a local Capture History so recent screenshots and recordings can be
  recovered.

## What Frame Does

- Region capture: drag to select part of the screen, then press Enter to capture.
- Window capture: hover an eligible app window to preselect it, then capture the original window image by default or choose another window screenshot style in Settings.
- PNG output: saved files use the `Frame yyyy-MM-dd HH.mm.ss.png` filename format.
- Clipboard copy: copy the captured image for pasting into chat, docs, or other apps.
- Save location: save PNG files to the configured screenshot folder, defaulting to Desktop.
- Scrolling screenshot: select a fixed region, scroll manually by default, or
  enable a small-step auto-scroll assist before finishing one vertical PNG.
- Screenshot editing: open the Image Workspace from Quick Access to add text,
  shapes, brush strokes, highlight, and mosaic annotations. The toolbar opens in
  pointer mode, lays shape tools out directly, keeps only mosaic behind a tool
  dropdown, and uses shared color plus contextual Thickness or Font Size menus.
  Menus mark the current choice and remember the last color, thickness, font
  size, mosaic mode, and shape type while reopening in pointer mode. Shift
  constrains rectangles/ovals to squares/circles and lines/arrows to horizontal,
  vertical, or 45-degree angles. Edited screenshots can update the current
  workspace image and its active Quick Access preview, or create another Quick
  Access preview without closing the editor; closing with unsaved edits can
  replace, save new, close without saving, or be cancelled to keep editing.
- Selection recording: set a recording shortcut or switch the selection HUD
  into recording mode, choose MP4 or GIF, show or hide mouse cursor and click
  highlights together, customize mouse hint color in Settings, record held-key
  hints, and stop, restart, or delete from the recording HUD or red menu bar
  recording item.
- Recording output: copy the recorded file, download it to the configured save
  folder, or open the video preview. MP4 recordings can be trimmed to custom
  start/end times and exported at preset speeds up to 8x from the same preview
  window. GIF recordings remain preview/copy/download only.
- Local capture history: recover recent captures from the menu bar, including
  recording thumbnails when a first frame can be decoded. History is enabled by
  default, keeps captures for 7 days, and uses a 2 GB local cache limit.
- Multi-display selection: show capture overlays across connected displays and account for Retina scale and screen coordinates.
- Window screenshot styles: choose Original, Soft Backdrop, Canvas Glow, or Transparent Shadow for window captures. Original is the default.
- Permission guidance: explain missing Screen Recording permission and open the relevant system settings.

## Privacy And Permissions

Frame uses macOS screen capture APIs, so it needs Screen Recording permission.

The capture flow runs locally. Frame does not upload screenshots or recordings, require an account, or sync captures to a cloud service. Capture History stores recent captures only in Frame's local Application Support cache and can be disabled or cleared from Settings. Save or Download writes a separate file only when you choose to save. Copy writes either image content or a recording file URL to the system clipboard.

If macOS says Frame can directly access screen content, that is the standard system wording for screenshot utilities. See [macOS Permissions](docs/permissions.md) for details.

## Not Included Yet

Frame currently does not include:

- audio recording
- cloud sync or share links

These can be considered after the core local capture experience is stable.

## Project Status

Frame is in MVP development. Current work prioritizes menu bar lifecycle, global shortcuts, Screen Recording permission handling, single-display selection recording, PNG/MP4/GIF output, and Quick Access interactions.

## Developer Notes

This README is a product overview. Development, architecture, and verification details live in:

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [macOS Permissions](docs/permissions.md)
- [Design](DESIGN.md)
- [Local Screenshot Loop Spec](docs/superpowers/specs/2026-05-18-local-screenshot-loop-design.md)
- [Local Screenshot Loop Implementation Plan](docs/superpowers/plans/2026-05-18-local-screenshot-loop.md)
