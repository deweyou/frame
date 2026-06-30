# Scrolling Screenshot Design

## Goal

Ship the first scrolling screenshot workflow for Frame. Users select a fixed
screen region, start a scrolling capture session, manually scroll the content
inside that region, then finish the session to receive one stitched long PNG in
the existing Quick Access, history, copy, save, and editing flows.

This version deliberately favors reliability over automation. Frame captures and
stitches the selected pixels; the user remains in control of scrolling the
underlying app.

## Confirmed Product Decisions

- The first version is manual scrolling by default, with an optional small-step
  automatic scrolling assist inside the session.
- The first version supports vertical scrolling only.
- The user starts from the existing screenshot selection overlay, chooses a new
  scrolling screenshot action, then scrolls the underlying content by hand.
- Frame does not try to identify or control the app's internal scroll view in
  this version.
- Frame does not need to identify the target app's internal scroll view. When
  the user enables automatic scrolling assist, Frame posts small generic scroll
  wheel events at the selected region center and keeps the user in control of
  finishing or cancelling.
- Frame keeps the selected rectangle fixed during capture. The user scrolls the
  content underneath that fixed rectangle.
- The active scrolling session exposes visible controls for Finish and Cancel.
  Finish stitches captured frames into one screenshot. Cancel discards the
  session without showing Quick Access.
- The output is a normal `CapturedScreenshot`, so it uses existing Quick Access,
  capture history, copy, save, image workspace, annotation, and pin behavior.
- Horizontal scrolling, bidirectional scrolling, full-page browser DOM capture,
  and app-specific scroll view introspection are reserved for later versions.

## Scope

This iteration includes:

- A scrolling screenshot action in the screenshot HUD.
- A scrolling capture mode that keeps the selected region visible but lets the
  underlying app receive mouse and keyboard input.
- Periodic sampling of the fixed selected region while the user scrolls.
- Deterministic vertical stitching in `FrameCore`.
- Clear Finish and Cancel controls during the session.
- Failure handling for too few usable frames, no detected scroll progress, and
  image encoding failures.
- Reuse of normal screenshot output surfaces after successful stitching.
- Unit tests for stitching and AppKit component tests for the HUD/session
  routing that do not require live Screen Recording permission.

This iteration excludes:

- Automatic scrolling as the default path.
- Horizontal scrolling.
- Capturing multiple displays in one scrolling screenshot.
- Capturing more than one selected region at a time.
- DOM-based full-page browser capture.
- Accessibility-based scroll view discovery.
- App-specific integrations for browsers, chat apps, editors, or PDFs.
- Background capture while another Frame capture or recording flow is active.
- An intermediate wait/resume control. The user chooses the range with Start and
  Finish instead.

## User Flow

1. The user triggers Frame's screenshot shortcut or menu action.
2. The user draws or adjusts a rectangular selection over scrollable content.
3. The screenshot HUD shows a scrolling screenshot action beside the existing
   screenshot actions.
4. The user clicks the scrolling screenshot action.
5. Frame dismisses or passivates the interactive selection overlay enough that
   the underlying app can receive scrolling input, while keeping a lightweight
   visible boundary around the fixed capture region.
6. Frame shows a compact scrolling session HUD near the selection. The HUD
   exposes Finish, Cancel, and an automatic scrolling assist toggle.
7. Frame periodically captures the same fixed region while keeping only the
   boundary and compact session HUD visible during capture.
8. The user scrolls the content manually with a mouse, trackpad, keyboard, or
   app-specific scroll controls. If desired, the user can enable automatic
   scrolling assist; it scrolls with small steps close to manual scrolling and
   does not change the selected capture region.
9. The user clicks Finish when enough content has been captured.
10. Frame stitches the sampled frames vertically, stores the result in capture
    history, restores any temporarily hidden Quick Access previews, and shows
    the stitched image as a normal screenshot card.
11. If the user clicks Cancel, Frame closes the boundary and HUD, restores
    temporarily hidden Quick Access previews, and does not create output.

## Interaction Design

The scrolling session should feel like the recording boundary flow rather than a
new modal editor.

- Use the existing screenshot selection visual language: dim outside the region
  before start, then keep a visible non-interactive boundary once capture starts.
- The boundary must not block the app underneath from receiving scroll input.
- The session HUD should be compact, icon-first, and styled with the existing
  HUD chrome.
- Finish is the primary action because it creates the long screenshot.
- Automatic scrolling assist is secondary. It can be toggled while the session
  is running, but Finish and Cancel remain the reliable control surfaces.
- Cancel discards the session immediately after user intent is clear. If the
  implementation needs confirmation later, it should be HUD-local rather than a
  blocking modal alert.
- Escape cancels the active scrolling session when focus is still owned by
  Frame; the visible Cancel control remains the reliable surface.
- The session should not auto-finish on scroll inactivity in this version. Some
  pages pause for lazy loading, animations, or user reading time, so user intent
  is safer than inactivity inference.
- Frame does not show an in-progress stitched preview. This keeps capture
  responsive and avoids presenting stale partial results while the user scrolls.
- If several captured frames are effectively identical, Frame can keep sampling
  but should avoid appending duplicates to the stitch input.

## Stitching Semantics

The stitcher accepts a vertical sequence of captured region images. It produces
one long image by finding overlap between adjacent frames and appending only the
new content from later frames.

Core behavior:

- Compare adjacent frames using a bottom band from the previous frame and a top
  band from the next frame.
- Search a bounded vertical offset range for the best overlap.
- Accept an overlap only when its similarity is above a conservative threshold.
- When overlap is accepted, crop the duplicate top part from the next frame and
  append the remaining pixels.
- When a later frame is nearly identical to the previous accepted frame, treat it
  as no scroll progress and skip it.
- When no usable overlap can be found for an adjacent frame, fail the stitching
  request with a user-facing error instead of producing a visibly broken long
  image.
- Preserve image scale and color data consistently with normal PNG screenshots.

The first implementation should optimize for slow manual vertical scrolling. The
HUD copy or tooltip should encourage scrolling slowly if needed, but the feature
must not depend on a tutorial-like instruction screen.

## Architecture

Keep side effects in `FrameApp` and deterministic image analysis in `FrameCore`.

`FrameCore` should own:

- `ScrollingScreenshotFrame`: deterministic frame metadata for one sample.
- `ScrollingScreenshotStitcher`: overlap detection, duplicate-frame skipping,
  crop calculation, and final canvas composition.
- `ScrollingScreenshotStitchingError`: invalid input, insufficient progress, no
  reliable overlap, and output encoding failure.

`FrameApp` should own:

- A new `SelectionOverlayCompletion` case for starting a scrolling screenshot
  from a selected region.
- A scrolling session controller that owns timers, sampled screenshots,
  automatic scrolling assist, Finish, Cancel, final stitching, and lifecycle
  cleanup.
- A non-interactive boundary overlay around the fixed region. It may reuse or
  generalize existing recording boundary behavior if doing so keeps the boundary
  clear and does not leak recording-specific semantics into screenshot code.
- AppDelegate routing from overlay completion to scrolling session start and
  from session finish to existing screenshot output handling.
- Localized strings in `AppStrings` for the HUD action, Finish, Cancel, failure
  title, and concise failure messages.

`CaptureService` should remain the screen-pixel capture adapter. The scrolling
session can repeatedly call the same rectangular capture path used by normal
region screenshots.

## Error Handling

User-facing failures should restore the app to the normal idle state and show a
concise alert through the existing capture failure pattern.

Expected failure cases:

- The selection rectangle is invalid before the session starts.
- The user finishes before enough distinct frames are available.
- The frames do not contain a reliable vertical overlap.
- PNG encoding fails for the stitched output.
- Screen capture fails while sampling.

Sampling failures during an active session should stop the session and restore
temporarily hidden previews. Silent partial output is worse than a clear failure
because a broken long screenshot may look credible at a glance.

## Testing

`FrameCoreTests` should cover deterministic stitching:

- Stitch two images with a known vertical overlap.
- Stitch multiple images with repeated overlap.
- Skip identical frames as no progress.
- Fail when there are fewer than two distinct frames.
- Fail when adjacent frames do not have a reliable overlap.
- Preserve expected final image dimensions after cropping duplicates.

`FrameAppTests` should cover stable AppKit routing without requiring live Screen
Recording permission:

- The screenshot HUD exposes a scrolling screenshot action.
- Triggering the action emits the new scrolling completion with the current
  selection.
- AppDelegate starts a scrolling session from the new completion.
- Finish routes the stitched screenshot through the same Quick Access path as a
  normal screenshot.
- Cancel restores temporarily hidden Quick Access previews without creating a
  screenshot.

Full manual smoke remains necessary because live desktop scrolling and TCC
behavior depend on the user's current apps and macOS environment:

- Capture a long web page by manually scrolling a selected browser region.
- Capture a long code editor pane by manually scrolling a selected editor
  region.
- Cancel a scrolling session and confirm no Quick Access card appears.
- Finish without scrolling and confirm Frame reports insufficient progress.
- Confirm Frame's boundary and HUD are not present in the stitched output.
- Enable automatic scrolling assist and confirm it moves slowly enough to keep
  adjacent samples overlapping.

## Documentation

Update `docs/architecture.md` after implementation to record the durable
boundary:

- `FrameCore` owns deterministic scrolling stitch logic.
- `FrameApp` owns sampling, HUD/session lifecycle, and screen capture side
  effects.
- Scrolling screenshots produce normal `CapturedScreenshot` output.

Update `README.md` and `README_ZH.md` because scrolling screenshot moves from a
future product area into implemented scope. Keep the English and Chinese product
overviews aligned.

## Acceptance Criteria

- A user can start a manual vertical scrolling screenshot from a selected region.
- During capture, the selected app can still receive manual scrolling input.
- During capture, Frame shows only the fixed boundary and compact session HUD;
  the stitched result appears after Finish.
- Automatic scrolling assist is available as an optional small-step toggle, not
  the default behavior.
- Finish produces one long PNG when there is reliable vertical scroll progress.
- Cancel exits without creating output.
- The resulting image appears in Quick Access and capture history as a normal
  screenshot.
- The stitcher rejects unreliable inputs instead of returning a broken image.
- `swift test`, `swift build`, and `scripts/package-app.sh` pass before the
  implementation is claimed ready.

---
*Last updated: 2026-06-22 | Reason: define manual vertical scrolling screenshot v1*
