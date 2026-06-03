# HUD Full-Screen And Delay Capture Design

## Goal

Add two screenshot HUD actions:

- Full-screen capture captures every attached screen as its own screenshot.
- Delay capture locks the current selection, counts down for five seconds, then captures that selection.

## User Experience

The selection HUD adds two icon actions beside the existing region and OCR actions.

- Full-screen capture is always available while the overlay is open. Clicking it ends the overlay and captures each `NSScreen` frame separately. Multi-display setups produce multiple Quick Access previews and multiple history records.
- Delay capture requires a valid active region or window selection. Clicking it freezes that selection and shows a visible countdown from 5 to 1. Esc cancels the countdown and closes the overlay. At the end of the countdown, the overlay closes and the captured selection follows the existing screenshot flow.
- Region capture, OCR, Return, and Esc keep their current behavior outside an active delay countdown.

## Architecture

`SelectionOverlayCompletion` gains a full-screen completion case. Region, window, and OCR completions continue to carry `SelectionCapture`.

`SelectionOverlayWindow` owns the HUD controls and delay countdown because it already owns selection interaction state. Delay capture snapshots `activeSelection` when clicked, disables further selection interaction during the countdown, updates a HUD countdown label, and emits a normal `.capture(selection)` completion when the timer finishes.

`AppDelegate` handles full-screen completion by asking `CaptureService` for one screenshot per screen frame. Each screenshot is stored in capture history and shown through the existing Quick Access controller.

`CaptureService` exposes a small `captureFullScreens()` API that maps over `NSScreen.screens` and reuses the existing rectangular capture path for each screen frame. It does not combine displays into one image.

## Testing

Add tests before implementation for:

- `SelectionOverlayCompletion.fullScreen` does not require a selection.
- `CaptureService.fullScreenRects(from:)` preserves one rect per screen rather than making a union rect.
- HUD content includes accessible buttons for full-screen and delay capture.
- Delay capture freezes the selected capture and completes only after the injected countdown interval.

Full verification remains:

```sh
swift test
swift build
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
```
