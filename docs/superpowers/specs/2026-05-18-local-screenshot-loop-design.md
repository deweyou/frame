# Frame Local Screenshot Loop Design

## Goal

Frame validates the core macOS local screenshot loop: a menu bar app can be invoked by a global shortcut, let the user adjust and confirm a region, capture that region as PNG, then offer copy, save, or close through a minimal preview panel.

## Product Decisions

- The app is a native macOS app.
- The app runs without a main window and stays available from the menu bar.
- The default screenshot shortcut is `Command+Shift+A`.
- The default recording shortcut is `Command+Shift+R`, but this local screenshot loop only reserves this setting and does not implement recording.
- Saved screenshots go to the user's Desktop by default.
- Saved screenshot filenames use `Frame yyyy-MM-dd HH.mm.ss.png`.
- UI is intentionally minimal. The local screenshot loop prioritizes system capability, permission reliability, coordinate correctness, and output correctness over visual richness.

## Scope

The local screenshot loop includes:

- macOS app target and app metadata.
- Menu bar status item with screenshot, permission, and quit actions.
- Global shortcut registration for the screenshot command.
- Screen Recording permission checking and system settings handoff.
- Full-screen selection overlay across all connected displays.
- Region capture that accounts for Retina scale and multi-display coordinates.
- PNG output for the selected region.
- Quick Access preview with hover actions for copy, save, and close.
- Clipboard image writing.
- Desktop file writing.
- Unit tests for deterministic core behavior.

The local screenshot loop excludes:

- Recording implementation.
- Annotation editor.
- Screenshot history.
- OCR.
- Cloud sync or share links.
- Scrolling screenshots.
- GIF or camera overlays.
- Rich preferences UI.

## Architecture

Use AppKit as the primary runtime because the local screenshot loop depends on macOS system behavior: menu bar lifecycle, global shortcuts, overlay windows, display coordinates, Screen Recording permission, pasteboard, and file output. SwiftUI can be used only for small local view content where it does not own system behavior.

The app is decomposed into system-facing adapters and deterministic core helpers:

- `FrameApp` starts the app and delegates lifecycle to `AppDelegate`.
- `AppDelegate` wires menu bar actions, shortcuts, permission checks, capture flow, and Quick Access presentation.
- `StatusItemController` owns the menu bar item and menu commands.
- `HotKeyController` owns global shortcut registration and exposes screenshot trigger callbacks. It reserves a recording shortcut value without invoking recording in the local screenshot loop.
- `ScreenRecordingPermission` wraps permission checks and opens System Settings when access is missing.
- `SelectionOverlayController` creates one borderless overlay window per screen, seeds the editable selection from the last session selection or the main screen, and reports the final selection after explicit confirmation.
- `CaptureService` captures the selected rectangle and returns PNG data plus an image suitable for preview and pasteboard use.
- `QuickAccessPanelController` presents a small bottom-left image preview after capture and dispatches hover actions for copy, save, and close.
- `ClipboardWriter` writes captured images to `NSPasteboard`.
- `ScreenshotFileWriter` writes PNG data to Desktop with the default Frame filename format.
- `FrameCore` contains testable helpers for shortcut defaults, filename formatting, desktop path resolution, and geometry normalization.

## Flow

1. User launches Frame.
2. Frame appears in the menu bar and does not show a main window.
3. User presses `Command+Shift+A` or chooses the screenshot menu item.
4. Frame checks Screen Recording permission.
5. If permission is missing, Frame shows a clear explanation and offers to open System Settings.
6. If permission exists, Frame shows full-screen selection overlays across connected displays.
7. The first invocation seeds the selection to the main screen. Later invocations reuse the last confirmed selection from the current app session.
8. User drags to create, move, or resize the selection.
9. User confirms with Enter.
10. Frame normalizes the confirmed region and captures PNG output.
11. Frame shows Quick Access as a bottom-left preview on the active screen.
12. User hovers the preview and chooses copy, save, or close.
13. Copy writes the captured image to the system clipboard.
14. Save writes PNG data to Desktop with the default Frame filename.
15. Close dismisses the Quick Access preview without deleting saved or copied output.

## UI Design

The local screenshot loop does not need a rich interface. The interface should feel native, quiet, and operational:

- Menu bar item: simple Frame label or symbol with Screenshot, Check Permission, and Quit menu actions.
- Selection overlay: dimmed transparent screen outside the selected region, an undimmed selected region, visible selection rectangle, and a compact native glass HUD with the active capture mode on the left and persistent size readout on the right. Enter confirms the capture; confirmation is not a persistent HUD button.
- Quick Access: fixed `180x120` image previews anchored to the active screen's bottom-left corner with equal left and bottom padding; multiple previews stack upward, follow active-screen changes, fill the preview proportionally, and reveal Save, Copy, and Close controls on hover.
- Permission prompt: plain language explaining that macOS Screen Recording access is required for screenshot capture, with buttons to open settings or cancel.

Use neutral surfaces, border-first separation, and emerald only for the primary action where useful. Avoid decorative views, landing screens, and onboarding.

## Error Handling

- If Screen Recording permission is missing, do not start capture silently. Show the permission prompt.
- If capture fails, dismiss selection overlays and show a short error alert with the reason.
- If saving fails, keep Quick Access open and show the failed path or error message.
- If copying fails, keep Quick Access open and show a short pasteboard error.
- If the selected rectangle is too small or empty, keep the overlay open and reject confirmation.

## Testing Strategy

Unit tests cover deterministic core behavior:

- Default screenshot shortcut is `Command+Shift+A`.
- Default recording shortcut is `Command+Shift+R` and is marked reserved for future recording support.
- Screenshot filenames follow `Frame yyyy-MM-dd HH.mm.ss.png`.
- Desktop save path is built from the user's Desktop directory and generated filename.
- Drag rectangles normalize correctly when dragged in any direction.
- Tiny or empty selections are rejected.

System behavior that cannot be fully automated in unit tests is verified by build and manual smoke instructions:

- Build the macOS app target.
- Launch the app.
- Confirm the menu bar item appears with no main window.
- Press `Command+Shift+A`.
- Confirm missing Screen Recording permission opens a clear prompt.
- After granting permission and relaunching, confirm the seeded selection appears before dragging.
- Confirm Enter captures the selected region.
- Confirm the post-capture preview appears at the active screen's bottom-left corner, follows active-screen changes, stacks upward for multiple captures, and reveals actions on hover.
- Confirm Copy places an image on the clipboard.
- Confirm Save writes a PNG to Desktop.

## Acceptance Criteria

- On a single-screen Retina Mac, Frame can complete region screenshot, copy, and save.
- In an external-display setup, selection and output are not visibly offset.
- Missing Screen Recording permission produces explicit guidance instead of silent failure.
- After permission is granted and the app is restarted, the screenshot flow works.
- Quick Access preview is small, dismissible, and does not block normal system usage after close.
- The codebase contains focused tests for deterministic core behavior.

## Open Follow-Ups

- A future preferences surface can expose shortcut customization.
- Recording can be implemented in a later iteration using the reserved `Command+Shift+R` shortcut.
- History, annotation, OCR, and scrolling capture remain out of scope until the base capture loop is stable.
