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
3. `StatusItemController` exposes menu commands for screenshot, permission check, and quit.
4. `HotKeyController` registers `Command+Shift+A` through Carbon and routes it to the screenshot flow.
5. `ScreenRecordingPermission` checks and requests macOS Screen Recording access.
6. `SelectionOverlayController` creates one overlay per connected `NSScreen`.
7. `SelectionOverlayWindow` shows a single active editable selection across displays, supports drag adjustment, follows it with a compact native glass HUD for the active capture mode and size, and returns a global Cocoa screen rectangle after keyboard confirmation.
8. `CaptureService` converts the selected Cocoa rectangle into a Quartz capture rectangle and returns PNG data plus `NSImage`.
9. `ActiveScreenResolver` resolves the active window rectangle, falling back to the mouse screen or main screen.
10. `QuickAccessPanelController` presents fixed-size screenshot previews at the active screen's bottom-left corner, stacks multiple previews upward, follows active-screen changes while previews are visible, and exposes hover actions for copy, save, and close.
11. `ClipboardWriter` writes the captured image to `NSPasteboard`.
12. `ScreenshotFileWriter` saves PNG data to Desktop using `ScreenshotNaming`.

## Boundaries

`FrameCore` contains code that should stay independent from AppKit side effects:

- shortcut defaults
- screenshot filename generation
- Desktop save URL composition
- selection rectangle normalization and validation

AppKit-specific code stays in `FrameApp`. Keep permission, capture, pasteboard, panels, and window behavior behind narrow adapters so future ScreenCaptureKit migration or UI changes are local.

## Current Tradeoffs

- `CaptureService` uses `CGWindowListCreateImage`, which is deprecated on macOS 14+. It is isolated in one adapter so a future ScreenCaptureKit migration is contained.
- Local development should use a stable self-signed Code Signing identity through `FRAME_CODESIGN_IDENTITY` to reduce TCC permission churn.
- Screen Recording permission is sensitive to bundle identity, path, and signature. Keep local testing on a stable app path such as `~/Applications/Frame.app`.
