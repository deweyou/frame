# Selection Recording Design

## Goal

Add a first recording workflow that grows out of the existing screenshot
selection overlay. Users select one area, optionally the full visible screen,
switch the HUD into recording mode, choose recording options, record, pause or
resume, stop, and then receive a video Quick Access card aligned with the
current screenshot experience.

This version records a single selected region on one display. It does not record
multiple displays at once.

## Scope

In scope:

- Entry from the existing screenshot overlay and HUD.
- Region recording, including full-screen recording by selecting the full
  screen.
- One display per recording.
- Recording setup controls for format, cursor visibility, and keyboard hints.
- Five-second start countdown, followed by active recording HUD with elapsed
  recording time, pause or resume, and stop.
- Non-interactive recording overlay that keeps the mask and selected region
  visible while the desktop remains usable.
- Status item recording state with a red recording icon and stop action.
- MP4 and GIF output.
- Recording cards in the shared Quick Access stack at the active screen
  bottom-left corner, using the first frame as the preview thumbnail when
  available.
- Copying the recorded file to the pasteboard.
- A playable video preview window.
- A visible but disabled/pending editing entry.
- Local capture history records for recordings.

Out of scope for this version:

- Recording multiple displays into one recording session.
- Audio recording.
- A stop-recording keyboard shortcut.
- Active video editing.
- Cloud sync, sharing, annotation, OCR on video, or scrolling capture.

## User Flow

1. The user invokes the existing screenshot shortcut or menu capture item.
2. The current selection overlay opens across displays.
3. The user creates or adjusts one selection. Dragging the selection to cover a
   whole screen is the first full-screen recording behavior.
4. The HUD includes a recording action beside the existing screenshot actions.
5. Clicking the recording action switches the HUD into recording setup mode.
6. Setup mode keeps the selected region active and shows icon-only controls for:
   start recording, MP4/GIF format, show cursor, and keyboard hints.
7. Clicking start enters a five-second countdown so the user can prepare the
   desktop before captured frames are written.
8. Countdown completion begins recording that selected region.
9. The HUD switches to active recording mode and shows elapsed recording time,
   pause/resume, and stop.
10. The status item switches to a red recording icon. Opening or clicking the
   recording status item exposes a stop action.
11. Stopping gives immediate disabled/loading feedback, finalizes the recording,
    and shows a video Quick Access card at the
    active screen bottom-left corner.
12. The video Quick Access card offers download, copy, preview, and edit. Edit
    is present but disabled/pending in this version.

## HUD Behavior

The recording HUD must follow the existing screenshot HUD design language:

- native HUD/glass material
- compact icon-only buttons
- delayed tooltips and accessibility labels
- stable dimensions across mode switches where practical
- background-aware light/dark content contrast
- actions on the left and measurements/state on the right where the layout fits

The screenshot HUD gains a recording button. Selecting it changes the HUD mode
instead of ending the overlay immediately.

Recording setup mode uses the same selected rectangle and disables unrelated
completion actions that would conflict with recording setup. The selected region
remains editable until recording starts.

Active recording mode freezes the recorded rectangle. The user cannot move or
resize the selection while recording is active or paused. Pause pauses the
recording for real: paused time is not written to the output and does not
increase the displayed elapsed recording time. Resume continues into the same
final recording file.

While recording is active, the full selection overlay should stop intercepting
desktop interaction. Frame should keep a visible non-interactive mask and
selected region around the recorded rectangle so users can see what is being
captured without blocking other apps. The active recording overlay is Frame-owned
chrome and must be excluded from captured pixels. It should follow the screenshot
selection visual language and avoid a red recording border.

Before recording starts, the same passive recording overlay displays a five
second countdown. The countdown is visible to the user, and capture begins only
after it completes.

The recording HUD should sit outside the selection when there is enough room. If
the selected region covers the full screen, the HUD may be visually inside the
selected screen so the user can still stop recording. In every placement, the
HUD and keyboard hint overlay must be excluded from captured pixels.

Stop should acknowledge input immediately. After the user clicks stop, disable
the stop affordance and show a busy/stopping state while finalization runs.

The app should not provide a stop-recording keyboard shortcut in this version.
Recorded demos can trigger the same shortcuts being demonstrated, so stop must
be available through visible controls instead.

## Recording Options

Recording options are explicit user choices surfaced in setup mode:

- Format: MP4 or GIF.
- Show cursor: include or omit the pointer from the recording.
- Keyboard hints: show or hide pressed key and shortcut hints as a Frame overlay.

Keyboard hints are visible to the user but are not part of the output video.
Their visual treatment should follow Frame HUD chrome and should remain compact
enough not to compete with the recorded content.

Audio is not implemented in this version, but the recording configuration should
leave room for future audio source choices:

- no audio
- microphone
- system audio
- possible future combinations of microphone and system audio

The first implementation should store or model the audio choice as no audio
rather than scattering assumptions that recordings can never have audio.

## Output

The recording output format is selected before recording starts.

MP4 recordings should use a user-facing `.mp4` file. If the platform encoder
requires an intermediate movie container, conversion and cleanup should stay
behind the recording service boundary.

GIF recordings should produce a `.gif` file. GIF generation may be slower than
MP4 finalization, so the UI should keep a clear finishing state while encoding.

Recording filenames should align with screenshot naming while using the selected
extension, for example:

- `Frame 2026-06-03 18.42.10.mp4`
- `Frame 2026-06-03 18.42.10.gif`

Finalization writes the completed recording into Frame-managed local storage so
Quick Access and Capture History can refer to a stable file. Download then
copies that file into the same configured save location used by screenshots.
Copy writes the recorded file URL to `NSPasteboard`, so pasting into Finder,
chat, or document targets behaves like pasting a movie or GIF file.

## Recording Quick Access And Preview

After finalization, recordings appear as cards in the same bottom-left Quick
Access stack used by screenshots:

- anchor to the active screen bottom-left with the same padding model
- stack upward with screenshot and recording Quick Access cards mixed together
- stay lightweight and dismissible
- use the recording's first frame as the thumbnail when it can be decoded
- preserve the recording pixel aspect ratio inside a compact preview bound, so
  wide recordings show as wide video cards instead of screenshot-shaped cards
- keep the borderless preview panel's rendered content size equal to the
  expected preview size so the card cannot collapse into a thin strip
- show hover actions as icon-only controls

The video card actions are:

- Download: save or reveal the generated recording through the configured save
  flow.
- Copy: copy the recording file to the pasteboard.
- Preview: open a playable video preview window.
- Edit: visible but disabled/pending in this version.

Preview and Edit route to the same playable video preview surface for now. The
preview should use native macOS window behavior and follow the existing
workspace chrome principles. Editing tools should remain disabled until active
video editing ships.

Capture History already has a recording kind. Recording records should preserve
enough metadata to list, open, copy, save, and delete local recordings without
conflating them with screenshots.

## Architecture

Keep ScreenCaptureKit and encoding details behind a project-owned recording
boundary in `FrameApp`.

Proposed components:

- `RecordingService`: owns ScreenCaptureKit capture, pause/resume, stop,
  finalization, and format-specific output.
- `RecordingSession`: represents one active or paused recording and exposes a
  small state API for HUD and status item coordination.
- `RecordingOptions`: stores selected format, cursor visibility, keyboard hints,
  and future audio source.
- `RecordingFileWriter`: writes or copies finalized recording files using the
  configured save directory and recording filename generation.
- `RecordingBoundaryOverlayController`: shows the recorded rectangle during an
  active recording without taking focus, blocking mouse events, or being shared
  into captured output.
- `RecordingThumbnailProvider`: extracts a first-frame thumbnail for completed
  MP4 and GIF files when the output can be decoded.
- `QuickAccessPanelController`: owns the shared bottom-left stack for screenshots
  and recordings while keeping media-specific actions on each card type.
- `VideoPreviewWindowController`: opens playable video previews and keeps edit
  controls pending/disabled.

`SelectionOverlayWindow` should own the HUD mode transitions because it already
owns selection interaction, HUD placement, and delayed HUD tooltips.
`AppDelegate` should remain the coordinator: it starts selection, receives a
recording start request, asks the recording service to run, updates the status
item, and routes completed output to history and Quick Access.

Status item behavior should stay in `StatusItemController`. It should expose a
recording state that changes the icon to a red recording affordance and makes
stop recording available while a session is active.

Recording output should not reuse `CapturedScreenshot` directly. A dedicated
recording value avoids mixing image-only data, pixel dimensions, and pasteboard
behavior with file-backed video/GIF data.

## Permissions And Capture Exclusion

Frame already requires macOS Screen Recording permission. Recording uses the
same broad permission area, but platform prompts may mention screen and audio
access on newer macOS versions. Since audio is out of scope, no microphone
permission should be requested in this version.

Recording HUD windows, keyboard hint overlays, recording boundary overlays, and
Frame-owned transient surfaces must be excluded from captured content. The
implementation should use the appropriate AppKit/ScreenCaptureKit window-sharing
and content-filtering mechanisms so visual controls remain visible to the user
without entering the recording.

If exclusion cannot be guaranteed for a platform path, that path should fail
with a clear error instead of producing recordings that include Frame controls.

## Errors And States

The user-facing states are:

- selecting
- recording setup
- recording
- paused
- finishing
- completed
- failed
- canceled

Errors should restore the app to a non-recording state, reset the status item
icon, and present localized failure copy.

Likely failure cases:

- Screen Recording permission is missing.
- The selected rectangle is invalid or spans multiple displays in a way the
  recording service cannot support.
- ScreenCaptureKit content cannot be resolved for the selected display.
- MP4 or GIF finalization fails.
- Writing to the configured save directory fails.
- Pasteboard copy fails.

Recording start validates that the selected rectangle belongs to one display. If
the selection intersects multiple displays, this version rejects the start action
with localized guidance to choose one display. It must not silently crop,
normalize, or record multiple displays.

## Testing

Automated tests should cover stable boundaries that do not require live desktop
capture:

- Recording options default values and persistence, including future no-audio
  modeling.
- HUD mode transitions: screenshot mode to recording setup, setup to active
  recording, recording to paused/resumed/stopped.
- Active recording freezes selection edits.
- Pause/resume elapsed-time accounting excludes paused duration.
- Status item recording state changes menu/icon behavior and exposes stop.
- Recording filename generation for MP4 and GIF.
- Capture history can store and list recording records separately from
  screenshots.
- File pasteboard writing uses file URLs for recordings.
- Recording Quick Access cards expose download, copy, preview, disabled edit,
  and close actions in the shared stack.

Manual smoke testing is required for:

- Screen Recording permission behavior.
- Region recording on a real desktop.
- Full-screen selection recording.
- HUD exclusion from output, including full-screen selection where the HUD is
  visually over the selected screen.
- Cursor visibility on/off.
- Keyboard hint visibility on/off and exclusion from output.
- Pause/resume output continuity.
- MP4 and GIF finalization.
- Status item red recording icon and stop action.

Local GUI verification should use the stable signing flow documented in
`AGENTS.md` and `docs/development.md`.
