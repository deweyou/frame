# Recording Input Hints Design

## Goal

Align Frame recording input hints with the CleanShot X style of lightweight
recording enhancements: users can record the cursor, highlight mouse clicks in
the output, and show keyboard shortcuts during recording without reopening the
selection flow by accident.

This extends the selection recording workflow from
`2026-06-03-selection-recording-design.md`; it does not change recording setup,
output formats, Quick Access, or active recording stop surfaces.

## Scope

In scope:

- Prevent screenshot shortcut re-entry while Frame is selecting, counting down,
  actively recording, paused, or finalizing a recording.
- Keep the existing cursor visibility option and make it part of the same input
  hints model.
- Add mouse click highlights that are visible in the recorded output.
- Add real keyboard shortcut hints during recording.
- Keep input hint controls compact and compatible with the existing recording
  setup HUD.

Out of scope:

- Post-recording editing of cursor tracks, click tracks, or keyboard callouts.
- Recording all typed text by default.
- A keyboard shortcut for stopping recordings.
- New annotation or drawing tools during recording.

## Product Behavior

Frame recording setup should expose input hints as separate choices:

- Show cursor: include or omit the system pointer in the recorded video.
- Highlight clicks: render a short click ripple at the click location and include
  it in the recorded video.
- Show keyboard shortcuts: show compact keycaps for shortcut-style input while
  recording.

The defaults should favor useful demos without surprising sensitive capture:

- Show cursor defaults to on.
- Highlight clicks defaults to on.
- Keyboard shortcuts default to on, but only shortcut-style keys are shown by
  default: keys with Command, Control, Option, Shift, or named non-text keys such
  as Escape, Return, Tab, arrows, Space, and Delete.
- Plain text typing is not shown in this version.

Keyboard hints can appear in the recorded output when enabled because CleanShot X
positions keystrokes as an output enhancement. Frame should still avoid exposing
plain typed text. The hint surface should be compact, bottom-centered inside the
recorded region when space allows, and omitted when the key event occurs outside
the active recording state.

Mouse click highlights should appear only when the click lands inside the
recorded selection. Left and right clicks may share the same first version style:
a short circular ripple centered at the click point. The effect should be visible
in MP4 and GIF output.

## Shortcut Re-Entry Guard

Pressing the screenshot shortcut while Frame is already in a capture or recording
flow must not create a second overlay.

Busy states:

- Selection overlay is visible.
- Delayed screenshot countdown is active.
- Recording countdown is active.
- Recording is active.
- Recording is paused.
- Recording is stopping or finalizing.

In these states, the shortcut is ignored with a light system beep. The current
flow remains unchanged.

Once a screenshot flow is cancelled or completed, or once a recording is fully
finished and Quick Access is shown, the shortcut can start a new selection flow.

## Architecture

Add a small recording input-hints boundary instead of mixing event-monitoring
code into `AppDelegate`.

Proposed components:

- `RecordingInputHintOptions` in `FrameCore`, or an extension to
  `RecordingOptions`, for cursor, click highlight, and keyboard hint choices.
- `RecordingInputMonitor` in `FrameApp`, responsible for local/global mouse and
  keyboard event observation during active recording only.
- `RecordingClickHighlightOverlayController`, responsible for drawing click
  ripples in a capture-visible overlay limited to the recorded selection.
- `RecordingKeyboardHintOverlayController`, either replacing or expanding the
  existing `KeyboardHintOverlayController`, responsible for keycap rendering and
  placement.
- `AppDelegate` remains the coordinator: start monitors after recording begins,
  pause visual updates while recording is paused, and stop monitors when
  recording finishes or fails.

Click highlights need to be captured into the video. The first implementation
should use a dedicated capture-visible overlay that only contains click effects.
Frame-owned HUDs, recording boundaries, and stop controls must remain excluded
from output.

Keyboard hints should be included in the recorded output when enabled. A
capture-visible overlay is acceptable only when it can include shortcut callouts
without also capturing Frame controls. If platform capture exclusion makes that
unreliable, keyboard hints should be composited into encoded frames behind the
recording service boundary rather than weakening HUD exclusion.

## Event Handling

Mouse monitoring should observe left and right mouse-down events. Events outside
the recorded selection are ignored. Events inside the selection create a ripple
using the click location converted into the recording overlay's coordinate
space.

Keyboard monitoring should observe key-down events during active recording. It
should build a display string from modifiers and the key:

- Command: `⌘`
- Shift: `⇧`
- Option: `⌥`
- Control: `⌃`
- Escape: `Esc`
- Return: `Return`
- Space: `Space`
- Delete: `Delete`
- Arrow keys: `↑`, `↓`, `←`, `→`

Repeated key-down events from key repeat should refresh the same hint rather
than stacking duplicates.

## Visual Design

Click highlight:

- Circular ripple centered on the click.
- Short duration, roughly 350 to 500 ms.
- CleanShot-like high-contrast outline style, with no persistent cursor halo.
- Subtle enough not to hide UI controls being clicked.

Keyboard hint:

- HUD-style rounded keycaps or a compact pill.
- Monospaced or system semibold text.
- Bottom-center placement inside the recorded selection when possible.
- Short hold time, roughly 900 to 1200 ms after the last shortcut event.

Both surfaces must scale with display backing scale so output looks crisp on
Retina displays.

## Testing

Automated coverage should include:

- Screenshot shortcut guard returns busy while selection, recording countdown,
  active recording, paused recording, and stopping states are active.
- Recording options persist click highlight and keyboard hint choices.
- Mouse events outside the recorded selection do not create click effects.
- Mouse events inside the selection create a click effect at the expected local
  point.
- Keyboard event formatting for common modifier combinations and named keys.
- Frame-owned recording HUD and boundary overlays remain capture-excluded.

Manual verification should include:

- Start selection, press `Command+Shift+A` again, and confirm no duplicate
  overlay appears.
- Start recording, click inside the selected region, and confirm the click
  highlight appears in the saved MP4/GIF.
- Click outside the selected region and confirm no highlight appears in the
  output.
- Press shortcuts during recording and confirm only shortcut-style input is
  shown.
- Confirm stop controls and recording boundary are not recorded into the output.
