# Recording And Capture Polish Design

## Goal

Fix the screenshot delay, recording shortcut, capture history, window selection,
recording startup, Quick Access media preview, and related copy/visual issues in
one focused polish pass.

## Scope

In scope:

- Delay screenshot countdown should not block normal desktop interaction.
- Delay countdown should appear near the current screen's bottom center and use
  a semi-transparent red treatment without a white outline.
- Recording should have a configurable global shortcut. The default is
  `Command+Shift+R`. It must not duplicate the screenshot shortcut.
- The recording shortcut should enter the same selected-area recording flow as
  the current HUD recording entry point.
- Capture History should show recording thumbnails from the first decodable MP4
  or GIF frame.
- Capture History and Settings copy should describe screenshots and recordings
  as captures, not only screenshots.
- Settings and Capture History windows should remain eligible for window
  screenshot double-click selection while Frame-owned overlays, HUDs, Quick
  Access, and transient panels stay excluded.
- Recording startup should avoid a visible overlay swap flash.
- The MP4/GIF setup control should make the currently selected format obvious,
  especially GIF.
- Quick Access screenshot and recording cards should share the same visual
  dimensions.
- Hovering a Quick Access screenshot or recording card for two seconds should
  show a right-side popover preview. Recordings should auto-play muted inside
  that popover.

Out of scope:

- Audio recording.
- Recording editing.
- Full capture history search, tagging, or grouping.
- Proactive system-wide shortcut conflict detection beyond Frame's two capture
  shortcuts.

## Product Decisions

The recording shortcut uses the same local shortcut model as the screenshot
shortcut: one letter or number key with at least two modifiers, including at
least one of Command, Option, or Control. `Command+Shift+R` is no longer just a
reserved screenshot shortcut; it is the default recording shortcut.

Settings keeps shortcuts compact. The General section shows both Screenshot and
Recording shortcut rows. Each row uses the existing inline recorder style and
returns a duplicate-shortcut error when it matches the other row.

The recording shortcut starts the overlay directly in recording setup mode. If
there is a restored selection, the centered setup HUD appears immediately; if
there is no selection, the user can draw or double-click a window, then starts
recording from the setup HUD. This preserves the existing selection-first
recording model and avoids inventing a separate recorder-only overlay.

Delay countdown becomes a passive overlay state. The selected region is snapped
when the user clicks Delay. The full-screen selection windows should stop
receiving mouse events while the countdown is active, letting underlying apps
respond. The countdown appears near the current screen's bottom center and uses
a semi-transparent red treatment without a white outline. Escape cancellation is
not guaranteed once the window is passive, so the countdown is intentionally
short and completes with the snapped selection.

The hover preview popover is owned by Quick Access, not by the workspace or
video preview windows. It is a transient, non-activating panel to the right of
the hovered card after two seconds. It uses a rounded popover without an arrow
and aspect-fits the original image or recording so the full media is visible. It
closes immediately when hover leaves the card or popover.

## Architecture

`FrameCore` gains a generic capture shortcut value that can represent screenshot
and recording shortcuts. Existing screenshot shortcut APIs stay available through
type aliases or wrappers to keep call sites focused. Validation receives a
reserved or duplicate shortcut set so Settings can reject conflicts between the
two configured actions.

`SettingsStore` persists the recording shortcut under a new key and continues to
migrate existing screenshot shortcut values. `HotKeyController` registers two
Carbon hot keys and routes them through separate screenshot and recording
callbacks.

`SelectionOverlayController` accepts an initial mode. The normal screenshot
shortcut opens screenshot mode. The recording shortcut opens recording setup mode
while keeping the same selection, window picking, and recording start path.

`SelectionOverlayWindow` owns the delay countdown visuals, but exposes a small
window-level method so the controller can switch overlay windows to passive mouse
handling during countdown. The countdown view positions itself near the current
screen's bottom center and uses a semi-transparent red recording-style accent
without a white outline.

`WindowCandidateProvider` continues to exclude Frame-owned overlay, HUD, Quick
Access, OCR, and preview surfaces, but it should not exclude ordinary Settings
or Capture History windows.

`CaptureHistoryWindowController` uses `RecordingThumbnailProvider` for recording
records. If thumbnail extraction fails, it keeps the lightweight video fallback.

`QuickAccessPanelController` keeps one shared card size from
`CapturePreviewMetrics`. Recording start temporarily hides existing managed
previews instead of closing them, then restores them when recording completion or
failure leaves recording mode. It adds a hover-preview popover that can render
an image or an `AVPlayerView` for recordings using aspect-fit media sizing. The
player is muted when shown.

## Testing

Add tests before implementation for:

- Recording shortcut defaults, persistence, duplicate validation, and Carbon
  routing.
- Settings exposes two shortcut rows and reports duplicate shortcut errors.
- Recording shortcut starts selection in recording setup mode.
- Delay countdown uses bottom-center placement, prominent styling, and passive
  overlay mouse behavior.
- Window candidate filtering includes Settings and Capture History windows while
  excluding transient Frame overlays.
- Capture History recording tiles use a thumbnail when one is decodable.
- User-facing copy uses capture-history language for mixed screenshot/recording
  history.
- Quick Access screenshot and recording card sizes match.
- Quick Access hover preview appears only after the configured delay and uses a
  muted video surface for recordings.

Full verification:

```sh
swift test
swift build
scripts/package-app.sh
```

For GUI handoff builds, use the stable local signing flow from `AGENTS.md`.
