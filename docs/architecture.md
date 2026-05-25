# Architecture

Frame is a native macOS menu bar app. AppKit owns the runtime because the product depends on system-level behavior: status items, global hotkeys, Screen Recording permission, full-screen overlay windows, pasteboard access, and local file output.

## Targets

- `Frame`: executable entry point.
- `FrameApp`: AppKit adapters and user-facing capture flow.
- `FrameCore`: deterministic helpers that can be tested without AppKit.
- `FrameCoreTests`: unit tests for core behavior.

## Runtime Flow

See `DESIGN.md` for interface principles, including the native glass HUD,
background-aware contrast, and direct-manipulation capture behavior.

1. `FrameApplication` starts `NSApplication` with accessory activation policy.
2. `AppDelegate` creates the menu bar item, hotkey controller, overlay controller, capture service, active-screen resolver, and output writers.
3. `StatusItemController` exposes menu commands for screenshot, settings, and quit.
4. `SettingsWindowController` hosts the SwiftUI settings window, including screenshot shortcut selection, Screen Recording permission checks, and about/version details.
5. `SettingsStore` persists user-facing app settings in `UserDefaults`.
6. `HotKeyController` registers the selected screenshot shortcut through Carbon and routes it to the screenshot flow.
7. `ScreenRecordingPermission` checks and requests macOS Screen Recording access.
8. `SelectionOverlayController` creates one overlay per connected `NSScreen`, owns automatic window-hover timing, and disables automatic window hover once the user starts region editing in the current session.
9. `SelectionOverlayWindow` shows a single active editable selection across displays, supports drag adjustment, can temporarily display an eligible hovered application window as a candidate, follows the active rectangle with a compact native glass HUD, and returns a global Cocoa screen rectangle after keyboard confirmation.
10. `WindowCandidateProvider` adapts CoreGraphics window-list metadata into eligible ordinary application window candidates while excluding Frame's own windows and obvious non-application surfaces.
11. `CaptureService` converts the selected Cocoa rectangle into a Quartz capture rectangle and returns PNG data plus `NSImage`.
12. `ActiveScreenResolver` resolves the active window rectangle, falling back to the mouse screen or main screen.
13. `QuickAccessPanelController` presents fixed-size screenshot previews at the active screen's bottom-left corner, stacks multiple previews upward, follows active-screen changes while previews are visible, and exposes hover actions for copy, save, and close.
14. `ClipboardWriter` writes the captured image to `NSPasteboard`.
15. `ScreenshotFileWriter` saves PNG data to Desktop using `ScreenshotNaming`.

## Boundaries

`FrameCore` contains code that should stay independent from AppKit side effects:

- shortcut defaults
- screenshot filename generation
- Desktop save URL composition
- selection rectangle normalization and validation
- automatic window-hover state and timing

AppKit-specific code stays in `FrameApp`. Keep permission, capture, pasteboard, panels, window metadata, and window behavior behind narrow adapters so future ScreenCaptureKit migration or UI changes are local.

## Current Tradeoffs

- `CaptureService` uses `CGWindowListCreateImage`, which is deprecated on macOS 14+. It is isolated in one adapter so a future ScreenCaptureKit migration is contained.
- Local development should use a stable self-signed Code Signing identity through `FRAME_CODESIGN_IDENTITY` to reduce TCC permission churn.
- Screen Recording permission is sensitive to bundle identity, path, and signature. Keep local testing on a stable app path such as `~/Applications/Frame.app`.
