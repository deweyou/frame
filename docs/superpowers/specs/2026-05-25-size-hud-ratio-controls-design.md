# Size HUD Ratio Controls Design

## Goal

Frame should keep the screenshot HUD compact while allowing precise selection sizing. Users can drag to create, move, and corner-resize a selection, and can also enter exact width and height values through the HUD size controls. Ratio locking and common ratio presets should be available without making the HUD wider or visually busy.

## Product Decisions

- The HUD width must stay fixed across read, edit, lock, unlock, and ratio menu states.
- Dragging still creates a new region, moves an existing region, and resizes from corner handles.
- Corner resizing anchors the opposite corner. For example, dragging the top-right handle keeps the bottom-left corner fixed.
- The size readout replaces the `x` separator with a link-style ratio icon that can be clicked.
- A fixed chevron icon sits after the height value and opens a ratio preset menu.
- Ratio presets are concrete ratios only: `1:1`, `4:3`, `3:2`, `16:9`, and `9:16`.
- The ratio menu does not include `Free` or `Current ratio`; the lock icon already owns those concepts.
- Selecting a preset immediately applies it and turns ratio locking on.
- Holding Shift during drag is a temporary ratio lock. Releasing Shift restores the previous persistent lock state.

## Scope

This feature includes:

- A fixed-width HUD size control with width input, link-style ratio icon, height input, and ratio chevron.
- Width and height editing by clicking a numeric value.
- Applying numeric edits on Enter or focus loss.
- Esc canceling an in-progress numeric edit and restoring the displayed value.
- Center-anchored numeric size application that expands or shrinks equally around the current center.
- Opposite-corner anchored drag resizing.
- Persistent ratio lock toggled by the lock icon.
- Ratio preset selection from the chevron menu.
- Empty-selection ratio preset behavior that creates a centered default selection on the active screen.
- Shift-drag temporary ratio locking.
- Unit tests for deterministic ratio and rectangle sizing rules where practical.

This feature excludes:

- A larger floating inspector or separate preferences panel.
- User-defined custom ratio presets.
- Pixel-size presets such as `1920 x 1080`.
- Aspect ratio labels shown persistently in the HUD.
- Annotation, guides, snapping, or alignment tools.

## HUD Layout

The HUD remains two fixed segments:

```text
[mode icon] [1280 link 720 chevron]
```

The size segment has a fixed width and enough internal padding to keep the controls from feeling cramped. Width and height are fixed-width text fields sized for four digits, rendered with monospaced digits, and clipped if needed rather than expanding the HUD. The link icon and chevron occupy fixed positions. The link icon replaces the previous `x` separator. The chevron is an icon button at the trailing edge of the size segment. HUD icon buttons use a pointing-hand cursor on hover.

The HUD has two size display states:

- Read state: width and height are editable numeric controls, the link icon shows persistent or temporary lock state, and the chevron opens the ratio menu.
- Numeric edit state: clicking width or height lets that number receive keyboard input without changing the HUD's outer width. Enter or focus loss applies the value. Esc cancels the edit.

## Ratio State

Frame tracks a persistent sizing mode:

- Unlocked: width and height edits are independent.
- Locked to current ratio: toggled by clicking the lock icon when a selection exists. The ratio is captured from the current selection at the moment locking is enabled.
- Locked from an empty or `0 x 0` HUD state: toggled by clicking the lock icon and defaults to `1:1`.
- Locked to preset ratio: set by choosing a preset from the chevron menu.

The link icon reflects persistent lock state when Shift is not pressed. During Shift-drag, the icon temporarily shows locked. When Shift is released, the icon returns to the persistent state.

Choosing a ratio preset always turns persistent lock on and stores the chosen ratio.

## Size Editing

Clicking a width or height value starts numeric editing for that value.

When the user applies an edit:

- Empty, non-numeric, zero, negative, or below-minimum values are rejected and the display returns to the previous value.
- Non-digit characters are blocked during text entry.
- Numeric entry is capped during typing to four digits and the active overlay screen's matching dimension.
- Leading zeroes are normalized during typing, so entering `1` into `0` becomes `1`, not `01`.
- Values larger than the active overlay screen's width or height are rejected for the corresponding dimension.
- In locked mode, edits that would derive an opposite dimension larger than the active overlay screen are rejected.
- Opening the ratio menu or toggling the lock ends any active numeric edit first.
- Unlocked mode changes only the edited dimension.
- Locked mode changes the edited dimension and derives the other dimension from the active ratio.
- The updated rectangle keeps the previous center fixed.
- If the requested size would extend outside the active screen, Frame first repositions the rectangle to keep the requested size inside the screen.
- If the requested size is larger than the active screen can contain, Frame clamps it to the largest valid size that preserves the requested ratio when locked.

If there is no active selection and the user enters width or height, Frame creates a centered selection on the active screen. In unlocked mode, the missing dimension uses the current displayed value when available or the default-selection height. In locked mode, the missing dimension is derived from the active ratio.

## Ratio Presets

The chevron menu contains only:

- `1:1`
- `4:3`
- `3:2`
- `16:9`
- `9:16`

Selecting a preset has immediate effect.

With an existing selection:

- The current selection center is preserved.
- The new rectangle is fitted inside the current selection's bounds and does not grow outside that current selection.
- If preserving current width would exceed current height for the chosen ratio, Frame preserves current height and derives width instead.
- The result is then clamped to the active screen.

Without an existing selection:

- Frame creates a centered selection on the active screen.
- The default selection is fitted inside a box equal to 60% of the active screen width and 60% of the active screen height.
- The selected preset determines the final width and height inside that box.
- The selection is never smaller than the minimum selection size unless the screen itself cannot fit that minimum.

## Shift Drag

Shift is a temporary ratio lock for drag interactions.

- If a selection exists when drag starts, Shift-drag uses that selection's ratio captured at drag start.
- If no selection exists when drag starts, Shift creation uses the first valid drag rectangle's ratio as the temporary ratio.
- Shift does not mutate the persistent lock setting.
- Releasing Shift restores the lock icon to the persistent state.
- Moving a selection with Shift held behaves like ordinary movement; ratio locking only affects create or resize operations.
- Resizing a selection with a persistent ratio lock or temporary Shift lock keeps the opposite corner fixed while constraining the moving corner to the active ratio.

## Error Handling

- Invalid numeric edits leave the selection unchanged and restore the previous display value.
- If applying a preset cannot create a valid rectangle because the screen is too small, Frame keeps the previous selection if one exists; otherwise it leaves the overlay empty and beeps.
- If ratio menu selection occurs while another screen owns the active selection, the active overlay receives the created or adjusted rectangle.
- Esc during numeric editing cancels the edit but does not cancel the whole screenshot session.
- Esc outside numeric editing keeps the existing screenshot-session cancel behavior.

## Testing Strategy

Unit tests should cover deterministic core geometry:

- Center-anchored resizing preserves center.
- Locked width edits derive height from ratio.
- Locked height edits derive width from ratio.
- Ratio preset fitting never enlarges beyond the current selection.
- Empty-selection preset creation fits inside the 60% active-screen box.
- Oversized requested dimensions clamp to the active screen while preserving ratio when locked.

Manual smoke tests should cover AppKit behavior:

- HUD width does not change when toggling lock, opening the ratio menu, or editing numbers.
- Clicking width or height allows numeric entry, Enter applies, and Esc cancels.
- The lock icon toggles persistent ratio locking.
- Preset selection immediately adjusts the selection and turns lock on.
- Empty-selection preset selection creates a centered selection.
- Holding Shift during drag shows temporary lock state and restores the previous state after release.
- Dragging a corner with ratio lock enabled keeps the opposite corner fixed.

## Acceptance Criteria

- The HUD remains fixed width in all new size-control states.
- Users can create, move, and corner-resize selections by dragging.
- Users change selection width and height through HUD numeric input.
- Center-fixed numeric sizing works with and without ratio locking.
- The lock icon replaces the `x` separator and toggles current-ratio locking.
- The chevron menu contains only concrete ratio presets.
- Preset selection applies immediately and does not enlarge an existing selection.
- Empty-state preset selection creates a centered default selection.
- Shift-drag temporarily locks ratio without changing persistent lock state.
- Ratio-constrained resize keeps the opposite corner anchored.

## Open Follow-Ups

- Consider user-defined custom ratios after the fixed HUD interaction has proven comfortable.
- Consider pixel-size presets in a separate command surface rather than the compact HUD.
