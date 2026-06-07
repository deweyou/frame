# Recording Input Overlays Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add recorded mouse click rings and keyboard hints to MP4/GIF recordings.

**Architecture:** Add a small event timeline and renderer that turns global mouse/key events into time-bounded drawing commands. ScreenCaptureKit still captures the base frames and system cursor; encoders receive rendered pixel buffers when overlays are enabled. Event monitors live for the recording session lifetime and are removed on stop/cancel.

**Tech Stack:** Swift, AppKit global event monitors, CoreGraphics/CoreImage, CoreVideo pixel buffers, ScreenCaptureKit sample buffers, XCTest.

---

### Task 1: Overlay Timeline And Renderer

**Files:**
- Create: `Sources/FrameApp/RecordingOverlayRenderer.swift`
- Test: `Tests/FrameAppTests/RecordingOverlayRendererTests.swift`

- [ ] Add tests for click coordinate mapping, key label formatting, active event filtering, and visible pixel changes after rendering.
- [ ] Implement `RecordingOverlayEvent`, `RecordingOverlayEventStore`, and `RecordingOverlayRenderer`.
- [ ] Verify `swift test --filter RecordingOverlayRendererTests`.

### Task 2: Encoder Integration

**Files:**
- Modify: `Sources/FrameApp/RecordingFrameEncoder.swift`
- Test: `Tests/FrameAppTests/RecordingOverlayRendererTests.swift`

- [ ] Add tests proving overlay rendering returns the original buffer when disabled and a new composited buffer when events are active.
- [ ] Add an optional renderer parameter to `RecordingFrameEncoding.append`.
- [ ] Render into a fresh BGRA `CVPixelBuffer` before MP4/GIF encoding.
- [ ] Verify encoder-related tests.

### Task 3: Recording Session Event Monitors

**Files:**
- Modify: `Sources/FrameApp/RecordingService.swift`
- Test: `Tests/FrameAppTests/RecordingServiceTests.swift`

- [ ] Add tests for monitor enablement from `RecordingOptions`.
- [ ] Install global mouse/key monitors during active recording.
- [ ] Convert mouse screen points into recording pixel coordinates.
- [ ] Remove monitors on stop/cancel/failure.
- [ ] Verify `swift test --filter RecordingServiceTests`.

### Task 4: Final Verification

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Package with `FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh`.
- [ ] Replace and launch `~/Applications/Frame.app`.
