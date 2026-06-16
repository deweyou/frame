# Recording Video Editing Design

## Goal

Ship the first recording editing workflow for Frame's completed MP4 recordings.
Users keep the current Quick Access-first recording loop, open the existing video
preview window, trim the recording to a custom start and end time, choose a fixed
playback speed preset, then save the edited result back into Frame or download it
as a new MP4 file.

This version deliberately keeps video editing lightweight. The video preview
window remains the only user-facing video window; there is no separate Video
Workspace window.

## Confirmed Product Decisions

- Editing is MP4-only in this version.
- GIF recordings keep preview, copy, and download behavior, but do not expose
  editing controls. GIF Edit remains disabled with a short tooltip or disabled
  explanation.
- Quick Access Preview and Edit open the same video preview window. Edit should
  focus the always-visible MP4 editing controls, but it must not open another
  window.
- MP4 editing controls are visible by default in the video preview window. A user
  can ignore them and use the same window for preview-only playback.
- The first editable operations are trim start time, trim end time, and playback
  speed.
- Trim time display, input, snapping, and validation use `0.01s` precision.
  Export uses the quantized start and end times as the requested AVFoundation
  time range; tests may allow a small tolerance for source track time-scale and
  keyframe behavior.
- Playback is clipped to the selected trim range. Pressing Play starts at the
  selected start time, never plays outside the selected range, and stops at the
  selected end time. It does not loop automatically.
- Speed is preset-only: `0.5x`, `1x`, `1.25x`, `1.5x`, `2x`, `4x`, and `8x`.
  There is no custom speed input in this version.
- Save Current asks the user whether to Replace Current or Save As New, matching
  screenshot editing semantics.
- Replace Current updates Frame's current in-memory/history-backed recording and
  any active Quick Access preview, but never overwrites external files the user
  already downloaded.
- Save As New creates a new Quick Access recording card and keeps the original
  recording available.
- Download directly exports the current edited result to the configured save
  directory without asking Replace Current versus Save As New.
- Closing the video preview window with unsaved MP4 edits prompts for Replace
  Current, Save As New, Don't Save, or Cancel.

## Scope

This iteration includes:

- Enabling editing for MP4 recording cards in Quick Access and the video preview
  window.
- Keeping GIF editing unavailable while preserving GIF preview, copy, and
  download.
- A deterministic video editing state model in `FrameCore`.
- An always-visible MP4 editor bar in the existing video preview window.
- Start and end time controls with `0.01s` precision.
- A trim range timeline with start and end handles.
- Fixed speed presets up to `8x`.
- Preview playback constrained to the selected trim range and selected speed.
- Exporting edited MP4 output using AVFoundation.
- Save Current, Replace Current, Save As New, Download, Copy, and dirty-close
  behavior consistent with screenshot editing where applicable.

This iteration excludes:

- GIF editing.
- Audio recording or audio time stretching.
- Custom speed input.
- Frame-accurate editor UI.
- Cropping, annotation, blur, watermarking, captions, or multi-segment cutting.
- Persistent editable project files.
- Overwriting user-saved external files.

## User Flow

1. The user completes an MP4 recording.
2. Quick Access shows the recording card with Download, Copy, Preview, Edit, and
   Close.
3. Preview opens the existing video preview window. The MP4 editor bar is visible
   by default.
4. Edit opens or activates the same window and focuses the editor bar.
5. The editor initializes to the full source duration, `1x` speed, and clean
   state.
6. The user drags trim handles or edits start/end time fields. Values snap to
   `0.01s`.
7. The user chooses one speed preset.
8. Playback starts at the selected start time, uses the selected speed, and stops
   at the selected end time.
9. Save Current opens a choice between Replace Current and Save As New.
10. Download directly writes the edited MP4 to the configured save directory.
11. Closing with unsaved edits opens the same four-way decision pattern used by
    screenshot editing: Replace Current, Save As New, Don't Save, or Cancel.

For GIF recordings:

1. Quick Access keeps Download, Copy, Preview, disabled Edit, and Close.
2. Preview opens the same video preview window path used today for animated GIFs.
3. The MP4 editor bar is not active for GIF files.

## UI Design

The video preview window should keep native macOS window behavior and the current
compact toolbar direction. Avoid creating a separate editor surface or adding a
large side inspector.

Toolbar actions:

- Copy: copies the current visible recording result. For a clean recording it
  writes the current recording file URL to pasteboard. For unsaved MP4 edits it
  first exports a temporary edited MP4, then writes that edited file URL to
  pasteboard. Export failure keeps the window open and leaves the pasteboard
  unchanged.
- Save Current: available for MP4 when the current edit state differs from the
  source rendition. It opens Replace Current and Save As New choices.
- Download: exports the current edited MP4 directly for MP4 recordings; for clean
  MP4 or GIF recordings it can keep the current source-copy download behavior.

MP4 editor bar:

- Place it below the media preview, not over the recorded pixels.
- Show a trim range timeline with start and end handles.
- Show editable start and end time fields in `mm:ss.xx` style.
- Show selected duration and output duration when space allows.
- Show speed presets as compact segmented or button controls.
- Keep controls stable in size during edits to avoid layout jumps.

GIF behavior:

- Do not show active editing controls.
- Keep disabled Edit in Quick Access with a concise tooltip such as "MP4 editing
  only in this version."

## Output Semantics

The source recording file is treated as immutable. Editing creates a new
temporary MP4 file first, then the chosen product action decides where that file
goes.

Replace Current:

- Exports the edited MP4.
- Updates the current `CapturedRecording` reference used by the video preview
  window.
- Refreshes any active Quick Access recording preview and hover preview media.
- Updates the corresponding Frame-owned history/cache record when the recording
  came from history-backed output.
- Does not touch any external file previously downloaded by the user.

Save As New:

- Exports the edited MP4.
- Adds it to Frame's local capture history as a new recording record.
- Shows a new Quick Access recording card.
- Leaves the original recording and current window state intact. Like screenshot
  editing, Save As New does not replace the current window's recording identity.
  The current window can continue editing the same source state after creating
  the new Quick Access recording.

Download:

- Exports a dirty MP4 edit before copying it. For a clean MP4 or GIF, it may
  copy the current recording file directly.
- Copies the edited MP4 to the configured save directory with normal recording
  naming.
- Does not ask Replace Current versus Save As New.

Copy:

- Existing clean recording copy behavior writes a file URL to pasteboard.
- With unsaved MP4 edits, Copy materializes an edited temporary MP4 first, then
  writes that edited file URL to pasteboard. It does not Replace Current or Save
  As New.

## Architecture

Use one user-facing video window with internal boundaries.

`FrameCore` owns deterministic editing rules:

- `VideoEditingState`: source duration, selected start, selected end, selected
  speed, dirty calculation, output duration, and validation.
- `VideoPlaybackSpeed`: fixed presets `0.5x`, `1x`, `1.25x`, `1.5x`, `2x`,
  `4x`, and `8x`.
- Time quantization helpers for `0.01s` precision.

`FrameApp` owns AppKit behavior and side effects:

- `VideoPreviewWindowController`: owns window lifecycle, media view, toolbar
  actions, dirty-close prompt, and delegates edit-specific behavior to smaller
  helpers.
- Video editor bar view/controller: owns trim handles, time fields, speed preset
  controls, and player synchronization.
- Video playback coordinator: constrains player playback to the selected range,
  applies the selected rate, stops at end, and restarts from start on the next
  play.
- `VideoEditingExporter`: uses AVFoundation to export an edited MP4 from a source
  MP4 URL, trim range, and speed preset.
- `AppDelegate`: keeps product routing for Replace Current, Save As New,
  Download, Quick Access refresh, clipboard, and history.

`VideoPreviewWindowController` should not become the exporter or deterministic
editing model. It may coordinate these objects, but the time math and export side
effects should stay behind narrow APIs.

## Export Notes

Use AVFoundation rather than shelling out to external tools. For silent MP4
recordings, the first implementation can focus on video tracks. If future audio
recording ships, video editing must revisit audio handling, because high speed
presets make audio output nontrivial.

The exporter should:

- Reject non-MP4 input.
- Reject invalid or effectively empty ranges.
- Use the selected trim range.
- Apply the selected speed by scaling the output time range.
- Preserve source pixel dimensions and orientation. If AVFoundation cannot
  create an output that preserves those properties, export fails rather than
  silently changing the recording geometry.
- Write to a temporary Frame-owned URL first.
- Return a `CapturedRecording`-compatible file URL and metadata only after
  export succeeds.

## Error Handling

- Invalid start/end ranges are prevented by controls and rejected by
  `VideoEditingState`.
- Start must be before end after `0.01s` quantization.
- The implementation should enforce a small minimum selected duration to avoid
  near-zero output files.
- Export failures keep the video window open and preserve edit state.
- Replace Current and Save As New update Frame state only after export succeeds.
- Download failure keeps the window open and reports the existing save failure
  copy.
- Closing with unsaved edits uses Replace Current, Save As New, Don't Save, and
  Cancel. Cancel keeps editing; Don't Save closes without exporting.
- GIF edit requests are ignored or disabled before they reach the editor state.

## Testing Strategy

Automated tests should cover boundaries that do not need live screen recording:

- `FrameCoreTests` for speed presets, `0.01s` time quantization, range
  validation, minimum duration, dirty calculation, selected duration, and output
  duration.
- `FrameAppTests` for MP4 windows showing the editor bar by default.
- `FrameAppTests` for GIF windows keeping editing disabled.
- `FrameAppTests` for Quick Access Preview and Edit opening or activating the
  same video window.
- `FrameAppTests` for playback coordination: play starts at trim start, stops at
  trim end, and does not loop.
- `FrameAppTests` for Save Current choice routing, Download direct routing, and
  dirty-close decisions.
- Exporter tests using a small generated or checked-in MP4 fixture to verify
  trim range, speed scaling, and approximate output duration.

Manual smoke testing should cover:

- Opening an MP4 recording from Quick Access Preview and Edit.
- Adjusting trim handles and time fields to `0.01s`.
- Each speed preset.
- Playback limited to the selected range and stopping at end.
- Replace Current refreshing the active Quick Access card.
- Save As New creating a second Quick Access recording card.
- Download writing an edited MP4 to the configured save directory.
- GIF Edit staying unavailable.

Full verification before claiming implementation ready:

```sh
swift test
swift build
scripts/package-app.sh
```

For GUI handoff builds, use the stable local signing flow documented in
`AGENTS.md`.

## Documentation And README Impact

Implementation will materially change user-facing recording output behavior, so
the implementation plan should update `README.md`, `README_ZH.md`,
`docs/architecture.md`, and `DESIGN.md` after the feature ships. This design spec
does not update those product docs yet because the behavior is not implemented.

## Acceptance Criteria

- MP4 recording cards expose enabled Edit.
- GIF recording cards keep Edit disabled.
- Preview and Edit open the same video preview window.
- MP4 video preview windows show editing controls by default.
- Users can set start and end times with `0.01s` precision.
- Users can select only the approved speed presets up to `8x`.
- Playback is constrained to the selected trim range.
- Playback stops at end and does not auto-loop.
- Save Current asks Replace Current or Save As New.
- Download directly writes the current edited result to the configured save
  directory.
- Closing with unsaved edits prompts for Replace Current, Save As New, Don't
  Save, or Cancel.
- Export failures do not mutate the source recording or close the window.
