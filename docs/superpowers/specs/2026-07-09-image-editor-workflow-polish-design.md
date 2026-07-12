# Image Editor Workflow Polish Design

## Goal

Make Frame's screenshot editor feel faster for repeated annotation work. The
current editor can draw, select, move, resize, and save annotations, but frequent
work still has too much mode friction: style changes live in toolbar menus,
objects do not fully pull the user back into their editing context, tool
shortcuts are incomplete, and Save Current asks the same replace-or-new question
every time.

This design updates the editor interaction model while keeping the existing
Image Workspace and object-based annotation document.

## Product Decisions

- Replace the old separate Color and Thickness/Font Size toolbar menus with a
  compact header style control when the selected object or active tool has a
  style context. It is a lightweight style control, not a full inspector or
  layer panel.
- The header style control edits the selected object when an object is selected.
  When no object is selected, it edits the current tool defaults.
- Single-clicking an annotation selects it and can start moving it, regardless of
  the currently active drawing tool.
- Double-clicking an annotation enters that annotation's editing context:
  text enters text editing, arrow selects the arrow subtype, rectangle/ellipse/
  line select their matching subtype, and mosaic/highlight/brush select their
  matching tool.
- Add single-key tool shortcuts while the canvas is focused and no text editor is
  active.
- Save Current should use a configurable default action instead of always opening
  a replace-or-new menu.
- Replace Current continues to mean replacing Frame's current in-memory edited
  screenshot and refreshing active previews. It must not overwrite a user-saved
  external file.

## Scope

This iteration includes:

- A visual-system pass for the Image Workspace toolbar: stable dark glass,
  semantic tool groups, consistent selected/disabled states, and normalized
  primary-symbol rendering.
- Header style control UI with a compact color dropdown palette and one
  contextual size control.
- Size semantics by context:
  - shape, brush, and highlight: stroke width
  - text: font size from 12 through 96 pt
  - mosaic: mosaic brush/block size when supported by the current mode
- Synchronization between selected annotation style, current tool defaults, top
  toolbar state, and the header style control state.
- Object double-click context switching for text, shape subtypes, brush,
  highlight, and mosaic.
- Canvas-only tool shortcuts:
  - `V` Select
  - `R` Rectangle
  - `O` Oval
  - `L` Line
  - `A` Arrow
  - `B` Brush
  - `T` Text
  - `H` Highlight
  - `M` Mosaic
  - `[` decrease contextual size
  - `]` increase contextual size
- Preserve native text editing shortcuts while editing text: Command-A, Command-C,
  Command-X, Command-V, Command-Z, and Shift-Command-Z continue to route to the
  active text editor.
- A new Settings preference for Save Current behavior:
  - Ask Every Time
  - Replace Current
  - Save As New
- Save Current primary click executes the configured default. A menu path remains
  available for one-off Replace Current / Save As New choices.
- Closing unsaved edits uses Save, Don't Save, and Cancel when a direct Save
  Current default is configured; only Ask Every Time exposes the explicit
  Replace Current / Save As New choices.
- The image canvas backdrop is fully opaque black. A passive delay countdown
  hides the selection HUD, and the last confirmed screenshot selection is
  persisted for ten minutes, including across Frame restarts. Remembered windows
  follow their resolved IDs while remembered regions restore their saved bounds;
  either skips hover preselection.
- Updates to `DESIGN.md` and `docs/development.md` so future work follows the
  new behavior.

This iteration excludes:

- A full layer list, property inspector, alignment panel, grouping, snapping,
  crop, numbered callouts, or persistent editable project files.
- Custom user-defined keyboard shortcuts for editor tools.
- Replacing user-saved external files.
- Reworking Quick Access, capture, recording, or history workflows outside the
  save-preview refresh needed by Save Current.

## Interaction Model

### Header Style Control

The header style control appears in the Image Workspace toolbar only when the
selected object or active tool supports color and contextual size edits. It
replaces the old separate Color and Thickness/Font Size toolbar menu buttons and
keeps style editing in the same header row as the tool picker.

The control shows:

- a chevron-free icon-only color swatch selector and tiled icon-only color
  dropdown palette for the supported annotation
  colors
- an icon and slider for the current size context, without a visible numeric
  value
- an accessibility label and tooltip for each control

When an annotation is selected, the control reflects and edits that annotation's
style. When no annotation is selected, it reflects and edits the active tool
defaults. Select, mosaic, and other contexts without color/size controls hide
the control. Changing style while a text editor is active updates the live text
object and the text editor view.

The existing top toolbar remains the main tool entry point. The control should
not remove the user's ability to see the current style.

### Toolbar Visual System

The Image Workspace toolbar remains edge-to-edge behind the native traffic-light
row, but its visual treatment must be stable regardless of the pixels behind the
window. Use a dark HUD material with a dark translucent backing layer and a
quiet border. Primary toolbar glyphs use a light system tint, disabled actions
use a visibly dimmer system tint, and the selected tool uses a compact accent
circle with a light glyph.

Toolbar controls are organized as four semantic groups:

1. History: Undo and Redo.
2. Tools: selection, shapes, drawing, text, highlight, and mosaic.
3. Contextual style: the existing color and size control, shown only when the
   current context supports it.
4. Output: Save Current, Copy, and Download, anchored at the trailing edge.

Use short, low-contrast vertical dividers between groups, never a divider
between every tool. The contextual-style divider is hidden with its control.
Output controls retain their compact internal spacing.

All primary toolbar symbols share the same 28 pt control cell, 22 pt hover or
selected circle, and a common visual glyph box. Define visual metrics in one
toolbar-symbol catalog rather than applying point-size or baseline overrides at
individual button call sites. The catalog may normalize symbols whose native SF
Symbol ink bounds differ, including the trailing output actions. This is an
optical alignment rule, not a layout offset rule. The mosaic chevron remains the
only visible tool dropdown, with at least a 20 pt-wide target while keeping the
chevron glyph secondary to the primary icon. Its primary action and chevron form
one attached split control with an inner divider and shared hover/selected
background, while keeping their click actions independent.

### Selection And Double-Click

Single click selects an object and can begin dragging it. This should work even
when a drawing tool is active. The user should not need to switch to Select just
to move an object.

Double click enters context:

- text: enter inline text edit mode
- arrow: select Shape tool and Arrow subtype
- rectangle: select Shape tool and Rectangle subtype
- ellipse: select Shape tool and Oval subtype
- line: select Shape tool and Line subtype
- brush: select Brush tool
- highlight: select Highlight tool
- mosaic rectangle or brush: select Mosaic tool and matching mosaic mode

After context switching, the selected object stays selected and the header style
control shows that object's style.

### Keyboard

Tool shortcuts are active only when the canvas or workspace is focused and no
inline text editor is active. They must not interfere with normal text input.

Shortcut handling should not require a global hotkey. It belongs to the Image
Workspace responder chain. Tooltips and menus should show the shortcut where it
helps discovery.

`Escape` should keep the existing behavior: exit text editing or clear/cancel the
current editing state before closing the workspace.

## Save Current Behavior

Save Current has two levels:

- Primary click: execute the configured default action.
- Menu: choose Replace Current or Save As New for a one-off action and optionally
  change the default preference.

The Settings preference is stored with other annotation/editor preferences:

- Ask Every Time: primary click opens the existing choice menu.
- Replace Current: primary click replaces the current in-memory screenshot.
- Save As New: primary click creates another Quick Access preview.

The recommended default for new installs is Replace Current because Save Current
semantically means applying edits to the current screenshot, and it does not
overwrite external files.

Closing with unsaved edits follows the same setting. Replace Current and Save As
New show a compact Save / Don't Save / Cancel prompt; Ask Every Time preserves
the explicit Replace Current / Save As New branch for users who chose it.

If rendering fails, the workspace remains open and the annotation document is
unchanged. If the default action cannot complete because its handler is missing,
the UI falls back to asking every time.

## Architecture

FrameCore should own any new durable state enums:

- `ImageWorkspaceSaveCurrentBehavior`
- any style-size stepping helpers that are pure and easy to test

FrameApp owns AppKit surfaces:

- `ImageWorkspacePanelController` wires the header style control, toolbar state,
  save menu/default behavior, and SettingsStore persistence.
- `ImageAnnotationCanvasView` handles hit testing, double-click context switching,
  and canvas-only tool shortcuts.
- `SettingsWindowController` exposes the Save Current default under screenshot
  editing settings.

The existing `ImageAnnotationDocument` remains the source of truth for selected
elements, active tool, editing options, and undo/redo. Header style control
changes should use existing document style update paths where possible.

## Testing Strategy

- Add FrameCore tests for Save Current behavior storage/defaults and any size
  stepping helpers.
- Add AppKit tests in `ImageWorkspacePanelControllerTests` for:
  - header style control is visible only for style contexts and reflects
    selected object style
  - changing header style control color/size updates selected object style
  - changing header style control color/size with no selection updates tool
    defaults
  - double-clicking each object family switches to the expected tool context
  - tool shortcuts select the expected tools when no text editor is active
  - tool shortcuts are ignored by the canvas while text editing is active
  - Save Current primary click obeys Ask Every Time, Replace Current, and Save As
    New defaults
  - one-off Save Current menu actions still work
  - toolbar group dividers, selected-state contrast, dark appearance, and the
    wider mosaic option target
  - primary toolbar symbols resolving through the shared visual-metrics catalog
- Add Selection Overlay tests for hidden HUD countdown state and remembered
  window preselection/expiration.
- Update manual development smoke steps for the header style control, object
  double-click, tool shortcuts, and Save Current default preference.

## Acceptance Criteria

- Users can change color and contextual size from a lightweight header control
  when the active editing context supports those properties.
- Users can move selected annotations without first switching to Select.
- Double-clicking an object switches the editor into that object's editing
  context without losing selection.
- Tool shortcuts work from the canvas and do not break text entry.
- Save Current can run without prompting when a default behavior is configured.
- Ask Every Time remains available for users who prefer the old confirmation
  behavior.
- Replace Current never overwrites user-saved external files.
- The canvas backdrop is opaque, countdown controls do not block the desktop,
  and remembered screenshot selection expires after ten minutes.
- `DESIGN.md`, `docs/development.md`, and tests reflect the new behavior.
- The Image Workspace toolbar remains readable over bright and saturated captured
  pixels, groups history/tools/style/output without extra panel chrome, and
  presents all primary icons as one visually aligned system.
