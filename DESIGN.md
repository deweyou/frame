# Frame Design

Frame is a quiet native macOS utility. Its interface should feel like a small
system tool, not a branded dashboard.

## Product Feel

- Prefer native macOS behavior and system materials over custom-drawn controls.
- Keep permanent UI minimal. Show state and direct manipulation before adding
  buttons.
- Use SF Symbols for compact actions and always provide accessibility labels or
  tooltips.
- Keep copy short, factual, and Chinese-first for user-facing controls.

## Settings

- Settings is a compact single-page preference list, not a multi-column dashboard.
  Do not introduce a sidebar unless the number of settings grows enough that
  scrolling becomes materially harder than category navigation.
- Use quiet grouped rows with short section labels, fixed label columns, native
  controls aligned to the trailing edge, and subtle separators. Avoid large
  empty detail panes, nested cards, or decorative section chrome.
- The default Settings window should show multiple groups at once and scroll for
  longer preference sets such as OCR languages. Use a roughly 620 x 600 default
  window, a 560 x 460 minimum, and about 540 px of content width so the page
  feels like a preference pane instead of a narrow form. Preserve a resizable
  native window with a standard centered titlebar and system traffic-light
  controls.
- The native window titlebar owns the centered Settings title. Do not duplicate
  a large "Settings" / "设置" heading inside the content area.
- Section containers need enough inner padding that row dividers never visually
  collide with the rounded border. Keep section gaps compact, around 14 px, and
  use subtle borders instead of heavy card outlines.
- Settings typography uses the macOS system font throughout. Prefer hierarchy
  through size, weight, spacing, and grouping rather than custom Chinese display
  fonts. Section titles and row labels should stay medium-weight; avoid large
  bold labels that make simple preferences feel oversized.
- Screenshot and recording shortcut editing use compact inline recorders in the
  General section. Validate simple local format rules and prevent duplicate
  Frame capture shortcuts before applying, but do not proactively inspect
  system-wide shortcut conflicts.
- Save location settings belong in the General section and use a quiet inline
  summary: show only a folder icon plus the abbreviated path without repeating
  the folder name or adding a nested card background, keep folder choosing as a
  small native action, avoid secondary Finder reveal buttons in the row, and
  show reset only for custom locations.
- About/version/build metadata belongs in a small secondary English footer, not
  a primary settings section.
- Long option collections such as OCR language toggles should stay out of the
  main settings scroll. Use a whole-row entry with a selected-count summary that
  opens an attached sheet for detailed editing.

## Screenshot Overlay

- The selected region stays undimmed; the area outside the selection is dimmed.
- Selection chrome is border-first: a subtle white outline plus clear corner
  handles.
- Use recognizable resize affordances: L-shaped corner handles and small
  mid-edge handles, kept in the black/white system rather than introducing an
  accent color.
- Cursor shape should explain the next action: crosshair outside the selection,
  move inside a non-fullscreen selection, edge resize on edges, and diagonal
  resize on corners.
- Avoid filling the selected area with color. Users need to inspect the content
  they are selecting.

## Capture HUD

- Use native glass/material effects first. In AppKit, prefer
  `NSVisualEffectView` with a HUD-appropriate material before drawing custom
  backgrounds. In future SwiftUI surfaces, prefer Liquid Glass APIs such as
  `glassEffect` and glass button styles when the deployment target allows them.
- The HUD is a compact dark glass hub, not a heavy solid toolbar.
- Keep the HUD small and low-priority. It should not compete with the selected
  content.
- Keep HUD width stable while users edit size, toggle ratio lock, or open ratio
  presets. Avoid adding extra persistent buttons when an inline icon can carry
  the interaction.
- Place mode/actions on the left and the size readout on the right.
- Size is persistent in screenshot modes. If a mode cannot edit size, disable
  editing rather than hiding or moving the size position.
- Size editing uses fixed-width numeric fields. Commit edited dimensions on
  Enter, blur, or related control actions; do not apply partial input while the
  user is typing.
- The ratio lock belongs between width and height, replacing the visual `x`
  separator. Ratio presets live behind a compact chevron after the size fields.
- Shift-drag temporarily behaves like ratio lock, then restores the prior lock
  state when Shift is released.
- Do not show a persistent confirmation button. Enter confirms; Esc cancels.
- Prefer direct manipulation. Window capture should primarily use hover
  highlight plus click/Enter, not a heavy button workflow.
- Hover state is a circular background behind the icon, not a full cell or
  whole-toolbar highlight.
- Tooltips should be delayed and owned above the overlay/HUD layer. Default
  placement is below the hovered control, flipping above only when there is not
  enough space.
- HUD icon content uses fixed white on a deliberately deep glass background.
  Do not reintroduce background-aware black/white icon switching or
  appearance-dependent dynamic icon colors for the capture HUD; keep contrast
  stable with a dark glass fill that is less transparent than system chrome, a
  quiet hairline border, and subtle hover fill instead.
- Delay screenshot countdowns are passive: after the user starts the countdown,
  keep a prominent semi-transparent red countdown near the current screen's
  bottom center while letting underlying apps receive mouse interaction. Avoid a
  white outline around the countdown.

## Recording HUD

- Recording HUD states inherit the screenshot HUD chrome: native glass, compact
  buttons, stable sizing, delayed tooltips, less-transparent dark glass chrome,
  white icon contrast, and a quiet boundary.
- The screenshot HUD may switch into recording setup without closing the
  selection overlay. Setup controls stay compact and cover start recording,
  MP4/GIF format, cursor visibility, and keyboard hint visibility. The MP4/GIF
  format toggle shows the selected format as visible short text so GIF is not
  mistaken for MP4.
- Mouse hint color is a recording output preference in Settings. Keep the
  recording setup HUD focused on showing or hiding mouse hints, while Settings
  owns a small curated preset set. In Settings, present it as a quiet preset-only
  swatch picker with a checkmark selected state; avoid custom color wells and
  reset actions for this preference.
- Keyboard hint visibility is retained as a setup option, but recording start
  must not show a static placeholder hint. Reintroduce a keyboard hint overlay
  only when it reflects real key activity.
- Starting a recording enters a short preparation/loading state before frames
  are written, giving Frame time to settle transient HUD state without making
  the user wait through a visible countdown.
- Active recording freezes the selected rectangle and replaces size editing
  with elapsed recording time. The action group contains stop, restart, and
  delete; pause/resume is not shown in the first refined recording HUD.
- During active recording, keep a visible non-interactive mask and selected
  region around the recorded rectangle while allowing desktop apps below it to
  receive mouse and keyboard interaction. Follow the screenshot selection visual
  language instead of switching the selection chrome to red.
- The recording HUD should sit outside the selected region when space allows.
  For full-screen selections it may sit inside the screen so controls remain
  reachable, but Frame-owned HUDs, recording boundaries, and keyboard hint
  overlays must not be recorded into the output.
- Stop actions acknowledge immediately: disable the stop affordance, show a
  stopping state, and keep the app responsive while finalization runs.
- Do not add a stop-recording keyboard shortcut in this version. The HUD and
  red menu bar recording state are the stop surfaces.

## HUD And Workspace Chrome

- HUD-like controls share one visual language across capture, Quick Access, and
  Image Workspace surfaces.
- Glass containers use HUD material, a quiet translucent border, and capsule
  geometry when the control row is short. For fixed-height toolbars, the left
  and right ends should read as large rounded caps rather than square panels.
- Capture and recording HUD rows use a darker, less-transparent glass fill under
  that material so white icons stay readable without relying on background
  luminance detection.
- Icon buttons are icon-only except for compact state toggles such as the
  MP4/GIF recording format control. Their default state is quiet; hover shows a
  circular background behind the icon instead of changing the whole toolbar or
  adding explanatory text.
- Actions that are visible before their behavior is implemented stay disabled:
  no pointer cursor, no hover fill, and disabled tint.
- Selected tools keep the same circular affordance, using a subtle accent tint
  rather than a heavy filled segment.
- Toolbar chrome must not obscure the screenshot. Workspace toolbar rows align
  vertically with the native traffic-light row and extend behind the native
  traffic-light controls. The toolbar chrome and image preview run edge-to-edge
  inside the workspace content; editing actions start after the traffic-light
  safe area.
- Workspace toolbar and image preview keep a small vertical gap so the titlebar
  controls and preview surface read as separate layers without restoring outer
  padding.
- Workspace windows should open with the image area matching the screenshot
  aspect ratio so the initial preview does not show letterbox/pillarbox edges.
- Workspace resize keeps the image area at the screenshot aspect ratio while the
  top toolbar keeps a fixed height. This avoids empty preview fill during normal
  window resizing.
- During a live corner resize, keep the initial resize axis stable until the drag
  ends so AppKit and Frame do not alternate competing aspect-ratio corrections.
- Resizable workspace windows must set a minimum width that keeps the full
  toolbar visible at the smallest allowed size.
- Image Workspace panels use the native macOS window shadow because the surface
  behaves like a real movable and resizable window. Avoid custom shadow gutters
  unless the workspace becomes a borderless HUD-like surface again.
- Pinned image windows are image-only. They use native macOS traffic-light
  controls over the top-left of the image and do not show the workspace toolbar
  or visible output actions.
- Pinned image windows expose Copy, Download, and Edit through the context menu.
  These actions must not close the pinned window. Edit opens or activates the
  preview/edit workspace for the same screenshot.
- Every icon-only action must keep a tooltip and accessibility label.

## Quick Access

- Quick Access is a small fixed post-capture preview with icon-only hover
  actions for copy, save, workspace, pin, and close.
- It anchors to the active screen's bottom-left corner with equal left and
  bottom padding.
- While previews are visible, they follow active-screen changes.
- Multiple previews stack upward from the bottom-left corner.
- Dragging the preview image outputs image content to targets that accept PNG
  pasteboard drags.
- Workspace opens a movable preview/edit window that stays open across focus
  changes. If there are unsaved edits, Escape or the native close control asks
  whether to Replace Current, Save As New, Don't Save, or Cancel and continue
  editing; pin behavior is handled separately as an image-only pinned window.
- Opening workspace again for the same captured screenshot activates the existing
  preview/edit window instead of creating duplicates.
- Workspace Copy and Download are active output actions. On success they close
  the workspace and the originating Quick Access preview. The checkmark Save
  Current action opens a choice between replacing the current in-memory edited
  screenshot and creating a new Quick Access preview; replacing keeps the
  workspace open, refreshes any still-active Quick Access preview, and must not
  overwrite a user-saved external file. Save As New keeps the workspace open and
  adds another Quick Access preview instead of writing a file directly.
- Screenshot editing controls stay in the top workspace toolbar. Shape tools
  are flat top-level buttons for rectangle, oval, line, and arrow. Only mosaic
  uses a split button: the main icon activates the current mosaic mode, and the
  adjacent chevron opens Region/Brush mosaic options. Color is a standalone
  toolbar dropdown that shows the current color as its icon. The adjacent style
  dropdown is contextual: stroke Thickness for shape, brush, and highlight, and
  Font Size for text. Text does not expose a separate tool dropdown. The editor
  opens with the pointer/select tool active, while remembering the last selected
  color, thickness, font size, mosaic mode, and shape type. Thickness options
  include 1, 2, 4, 8, 12, 16, and 24 px. Dropdown menus mark the active option
  with the native menu selected state. The mosaic primary icon follows its
  selected subtool. Do not use a persistent side inspector or a floating property
  bar over the screenshot.
- Editing is object-based: annotations can be selected, moved, resized, deleted,
  undone, and redone. Selection handles should remain small and high-contrast.
- Text annotations support re-entering text edit mode after creation.
- Shape annotations include rectangle, oval, line, and arrow. Arrows should be
  straight-edged filled wedge arrows that grow from a fine tail into a wider
  body and filled head instead of stroked line arrows. Holding Shift while
  drawing constrains rectangles/ovals to squares/circles and line/arrow angles
  to horizontal, vertical, or 45 degrees. Mosaic supports both
  rectangular regions and brush strokes; rectangular mosaic should show a
  lightweight selection frame while dragging and apply pixelation after release.
- It should stay lightweight and dismissible, without blocking normal system
  usage.
- Starting a recording temporarily hides existing Quick Access cards; it must
  restore them after recording completes or fails, then stack the new recording
  card with the existing previews instead of clearing the stack.
- Screenshots and recordings share one Quick Access stack and one visual
  language. Recording cards use the centered play affordance to open Preview;
  hover actions expose Download, Copy, Edit, and Close so playback entry is not
  duplicated. Edit is enabled for MP4 and disabled for GIF. Preview and Edit
  open the same playable video window; MP4 windows hide the native AVPlayer
  playback controls and titlebar filename prominence, keep Save Current, Copy,
  and Download in the same right-aligned header row pattern as screenshot
  editing, and show Frame's compact grouped bottom media control strip by
  default. The strip uses a mini timeline for progress/seek, start/end trim
  handles, and read-only start/end time labels, with time labels placed inside
  wide selections, outside narrow selections when room allows, and clamped at
  crowded edges. The timeline strip and trim handles use a pointing-hand cursor.
  The bottom row stays minimal and aligned to the mini timeline's visible track:
  a neutral circular play/pause icon button with no native focus ring or blue
  accent fill, a current/selected duration summary that adds output duration
  when speed is not `1x`, and a speed dropdown sized so Chinese labels and the
  longest preset do not clip. Do not add a bottom Trim chip or make the controls
  read as a large form. Use the first decodable recording frame as the thumbnail,
  with a lightweight video placeholder as the fallback.
  Screenshots and recordings should render in the same fixed card size,
  preserving media aspect ratio inside that footprint. Keep the rendered content
  size asserted so the preview cannot collapse into a thin strip.
- Hovering a Quick Access card for two seconds opens a transient rounded
  right-side popover without an arrow. Image and recording previews render larger
  using the original media aspect ratio and aspect-fit scaling so the full image
  or video is visible; recording previews play muted and close with the hover
  state.

## Capture History

- Capture History is a recovery browser, not a file manager. Prefer preview
  tiles over table rows so screenshot content remains the primary surface.
- Use a native macOS window with system traffic-light controls, a transparent
  titlebar, and `fullSizeContentView`. Avoid a fully custom borderless window
  unless the product intentionally gives up standard window behavior.
- The titlebar chrome should blend with the content background. Keep the
  traffic-light safe area clear, and place compact filters in the titlebar
  rather than adding a separate toolbar band.
- History tiles follow the Quick Access visual language: rounded image preview,
  fine translucent border, compact metadata, and icon-only hover HUD actions.
- Restoring a history tile should return the capture to the bottom-left Quick
  Access stack instead of opening recordings directly in the system player.
  Restored recordings must keep enough media metadata, including duration, for
  the same Preview and Edit actions available after a fresh recording.
- Recording history tiles should use the first decodable recording frame as the
  preview image and fall back to a lightweight video placeholder only when
  decoding fails.
- Keep history actions hidden until the tile is hovered. Metadata should remain
  one compact line below the preview and must not reintroduce table columns.
