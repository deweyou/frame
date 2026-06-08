# Recording HUD Interaction Refinement

Date: 2026-06-07

## Problem

The current recording flow asks the user to click the last button in the
screenshot HUD to enter recording setup, then find and click the first button in
the setup HUD to start recording. This works functionally, but the interaction
feels indirect because the user's focus moves from the selected region back to a
toolbar edge twice.

During active recording, pause is less important than fast recovery from a bad
take. Users are more likely to want to stop, discard, or restart immediately
after a mistake.

## Direction

Use a centered recording setup HUD after the user enters recording mode.

The first screenshot HUD keeps the existing recording entry point. After clicking
recording, Frame switches to recording setup but places that setup HUD in the
center of the selected region. The setup HUD is not a new full modal; it is the
same lightweight HUD concept with stronger action hierarchy.

## Recording Setup HUD

The setup HUD appears centered inside the selected region.

Controls:

- Primary: `开始录制`
- Secondary: format toggle (`MP4` / `GIF`)
- Secondary: cursor visibility
- Secondary: keyboard hint visibility

Behavior:

- `开始录制` is a red primary pill/button, not a plain icon button.
- Secondary controls stay compact and icon-like.
- Clicking `开始录制` enters the existing short loading state before frames are
  written.
- The selected region remains visible while the setup HUD is shown.
- The setup HUD should fit inside small selections when practical. If the
  selection is too small, position it just below or above the selection using the
  existing HUD placement constraints.

## Active Recording HUD

The active recording HUD focuses on completion and recovery rather than pause.

Controls:

- Red elapsed time
- Red stop/finish button
- Restart button
- Delete/discard button

Behavior:

- Stop/finish finalizes the recording and shows the normal video Quick Access
  card.
- Restart discards the current in-progress recording and starts a new recording
  for the same selected region after the short loading state.
- Delete/discard cancels the current recording and exits recording without
  showing Quick Access.
- Delete/discard should require protection against accidental clicks. The first
  implementation should use a two-step confirmation in the HUD rather than a
  modal alert, so the user can recover without leaving the recording context.
- Pause/resume is removed from the first refined version.

## Visual Treatment

- Red is reserved for recording status and the main stop/finish action.
- The active HUD should make elapsed time and stop feel like one recording
  cluster.
- Restart and delete remain visually secondary, with delete allowed to become
  red only during its confirmation state.
- The HUD stays compact and uses the same glass/chrome language as the current
  HUD.

## Non-Goals

- Live keyboard hint visualization.
- Audio controls.
- A global stop-recording keyboard shortcut.
- Full recording preferences UI.
- Reworking screenshot HUD behavior beyond the recording entry point.

## Testing

Add focused tests for:

- Recording setup HUD is centered relative to the selected region when entering
  recording setup.
- Setup HUD exposes a primary start action plus compact option controls.
- Active recording HUD exposes stop, restart, and delete, and no pause/resume.
- Stop remains red alongside elapsed time.
- Restart cancels the current session and starts a new one using the same
  selection and options.
- Delete/discard cancels the session and does not show Quick Access.
- Delete confirmation requires a second action before discarding.
