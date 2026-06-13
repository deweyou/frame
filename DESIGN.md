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
- Screenshot shortcut editing uses a compact inline recorder in the General
  section. Validate simple local format rules before applying, but do not
  proactively inspect system-wide shortcut conflicts.
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
- The HUD is a transparent hub, not a solid toolbar.
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
- Adapt HUD content contrast to the background below it. Use light content on
  dark backgrounds and dark content on light backgrounds.

## Recording HUD

- Recording HUD states inherit the screenshot HUD chrome: native glass,
  icon-only buttons, stable sizing, delayed tooltips, and background-aware
  contrast.
- The screenshot HUD may switch into recording setup without closing the
  selection overlay. Setup controls stay compact and cover start recording,
  MP4/GIF format, cursor visibility, and keyboard hint visibility.
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
- Glass containers use HUD material, a fine translucent border, and capsule
  geometry when the control row is short. For fixed-height toolbars, the left
  and right ends should read as large rounded caps rather than square panels.
- Icon buttons are icon-only. Their default state is quiet; hover shows a
  circular background behind the icon instead of changing the whole toolbar or
  adding text.
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
  changes and closes through Escape or the native close control; pin behavior is
  handled separately as an image-only pinned window.
- Opening workspace again for the same captured screenshot activates the existing
  preview/edit window instead of creating duplicates.
- Workspace Copy and Download are active output actions. On success they close
  the workspace and the originating Quick Access preview. Workspace Save is a
  separate disabled action reserved for future edited-image persistence.
- It should stay lightweight and dismissible, without blocking normal system
  usage.
- Screenshots and recordings share one Quick Access stack and one visual
  language. Recording cards expose Download, Copy, Preview, disabled Edit, and
  Close. Preview opens a playable video window; Edit remains pending. Use the
  first decodable recording frame as the thumbnail, with a lightweight video
  placeholder as the fallback. Preserve the recording's pixel aspect ratio while
  sharing the screenshot Quick Access width baseline. Keep the rendered content
  size asserted so the preview cannot collapse into a thin strip.

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
- Keep history actions hidden until the tile is hovered. Metadata should remain
  one compact line below the preview and must not reintroduce table columns.
