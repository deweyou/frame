# Frame

[中文](README_ZH.md)

Frame is a native macOS screenshot utility for a faster local capture loop: press a shortcut, select an area, then copy or save the result as a PNG.

It is intentionally small. Frame is not a full screenshot workspace, a cloud library, or an annotation suite. Its first job is to make the everyday screenshot path feel short, reliable, and quiet.

## Why Frame

Screenshots are often a tiny step inside a larger workflow: explaining an idea, reporting a bug, saving a visual state, or sending context to someone else. Frame keeps that step out of the way:

- Lives in the menu bar without a main window.
- Starts region capture with `Command+Shift+A`.
- Works across multiple displays.
- Shows a small Quick Access preview after capture.
- Lets you copy, save, or close from hover actions.
- Keeps a local Capture History so recent captures can be recovered.

## What Frame Does

- Region capture: drag to select part of the screen, then press Enter to capture.
- PNG output: saved files use the `Frame yyyy-MM-dd HH.mm.ss.png` filename format.
- Clipboard copy: copy the captured image for pasting into chat, docs, or other apps.
- Desktop save: save the PNG to the current user's Desktop.
- Local capture history: recover recent captures from the menu bar. History is enabled by default, keeps captures for 7 days, and uses a 2 GB local cache limit.
- Multi-display selection: show capture overlays across connected displays and account for Retina scale and screen coordinates.
- Permission guidance: explain missing Screen Recording permission and open the relevant system settings.

## Privacy And Permissions

Frame uses macOS screen capture APIs, so it needs Screen Recording permission.

The capture flow runs locally. Frame does not upload screenshots, require an account, or sync captures to a cloud service. Capture History stores recent captures only in Frame's local Application Support cache and can be disabled or cleared from Settings. Save writes a separate PNG only when you choose to save. Copy writes the image only to the system clipboard.

If macOS says Frame can directly access screen content, that is the standard system wording for screenshot utilities. See [macOS Permissions](docs/permissions.md) for details.

## Not Included Yet

Frame currently does not include:

- screen recording
- annotation tools
- cloud sync or share links
- scrolling capture

These can be considered after the core local screenshot experience is stable.

## Project Status

Frame is in MVP development. Current work prioritizes menu bar lifecycle, global shortcuts, Screen Recording permission handling, multi-display coordinates, PNG output, and Quick Access interactions.

## Developer Notes

This README is a product overview. Development, architecture, and verification details live in:

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [macOS Permissions](docs/permissions.md)
- [Design](DESIGN.md)
- [Local Screenshot Loop Spec](docs/superpowers/specs/2026-05-18-local-screenshot-loop-design.md)
- [Local Screenshot Loop Implementation Plan](docs/superpowers/plans/2026-05-18-local-screenshot-loop.md)
