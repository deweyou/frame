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

## Quick Access

- Quick Access is a small post-capture preview with copy, save, and close.
- It anchors to the active screen's bottom-left corner with equal left and
  bottom padding.
- While previews are visible, they follow active-screen changes.
- Multiple previews stack upward from the bottom-left corner.
- It should stay lightweight and dismissible, without blocking normal system
  usage.
