# Architecture

Frame v0.1 is a native macOS menu bar app. AppKit owns the runtime because the product depends on system-level behavior: status items, global hotkeys, Screen Recording permission, full-screen overlay windows, pasteboard access, and local file output.

## Targets

- `Frame`: executable entry point.
- `FrameApp`: AppKit adapters and user-facing capture flow.
- `FrameCore`: deterministic helpers that can be tested without AppKit.
- `FrameCoreTests`: unit tests for core behavior.

## Runtime Flow

1. `FrameApplication` starts `NSApplication` with accessory activation policy.
2. `AppDelegate` creates the menu bar item, hotkey controller, overlay controller, capture service, and output writers.
3. `StatusItemController` exposes menu commands for screenshot, permission check, and quit.
4. `HotKeyController` registers `Command+Shift+A` through Carbon and routes it to the screenshot flow.
5. `ScreenRecordingPermission` checks and requests macOS Screen Recording access.
6. `SelectionOverlayController` creates one overlay per connected `NSScreen`.
7. `SelectionOverlayWindow` tracks drag selection and returns a global Cocoa screen rectangle.
8. `CaptureService` converts the selected Cocoa rectangle into a Quartz capture rectangle and returns PNG data plus `NSImage`.
9. `QuickAccessPanelController` presents copy, save, and close.
10. `ClipboardWriter` writes the captured image to `NSPasteboard`.
11. `ScreenshotFileWriter` saves PNG data to Desktop using `ScreenshotNaming`.

## Boundaries

`FrameCore` contains code that should stay independent from AppKit side effects:

- shortcut defaults
- screenshot filename generation
- Desktop save URL composition
- selection rectangle normalization and validation

AppKit-specific code stays in `FrameApp`. Keep permission, capture, pasteboard, panels, and window behavior behind narrow adapters so future ScreenCaptureKit migration or UI changes are local.

## Current Tradeoffs

- `CaptureService` uses `CGWindowListCreateImage`, which is deprecated on macOS 14+. It is isolated in one adapter so a future ScreenCaptureKit migration is contained.
- Local packaging uses ad-hoc signing because this development machine currently has no valid code-signing identity.
- Screen Recording permission is sensitive to bundle identity and signature. Rebuilt ad-hoc apps may need re-authorization.

