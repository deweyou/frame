# Quick Access Workspace Design

## Goal

Improve the post-capture experience so Frame can keep the lightweight Quick Access flow while adding drag-to-app output and a larger image workspace for preview, pinning, and future editing.

## Product Decisions

- Quick Access remains the immediate post-capture surface.
- Quick Access previews stay anchored to the active screen's bottom-left corner and cannot be moved by dragging the panel.
- Dragging the screenshot image body from Quick Access starts an external drag operation instead of moving the panel.
- Quick Access can open an Image Workspace for larger preview and future editing.
- Pinning converts the Quick Access preview into a persistent image-only pin window and closes the original Quick Access preview.
- Preview and editing are one workspace feature. The workspace opens as a large image viewer with editing tools visible in a lightweight, non-blocking toolbar.
- The Image Workspace uses native macOS window controls for close/minimize/zoom. It should not add a second custom close button inside the content area.
- The editing toolbar sits at the top of the workspace, outside the image preview, edge-to-edge with the image area and vertically aligned to the native traffic-light row.
- The toolbar is always visible because it does not block the image. Hover should only add subtle button feedback.
- Full annotation behavior can be implemented incrementally after the workspace shell and tool state model exist.

## Scope

This iteration includes:

- Fixed-position Quick Access previews that do not move when dragged.
- External drag support from Quick Access to apps and input fields that accept image files or image pasteboard data.
- Quick Access hover controls with icon-only buttons:
  - top-right close
  - top-left pin
  - bottom HUD actions for save, copy, and open workspace
- An Image Workspace window that can be moved and resized while preserving the screenshot aspect ratio.
- Preview workspace behavior: stays open across focus changes and closes on Escape or native close.
- Opening workspace again for the same captured screenshot activates the existing preview workspace instead of creating another copy.
- Persistent pin behavior: image-only pin windows close through the native window close control.
- Pin windows expose a context menu with copy, download, and edit. These actions keep the pin window open.
- A preview/edit workspace context menu with copy and download enabled, while edit-related actions and edited-image save stay disabled until their behavior exists.
- A top workspace toolbar with disabled editing tool placeholders for mosaic, shape box, brush, text, arrow, and highlight.
- Copy and download actions available from the workspace toolbar and context menu.
- A disabled workspace Save action is visible for future edited-image persistence and is separate from download.

This iteration excludes:

- Completed annotation rendering for every editing tool.
- Screenshot history.
- OCR, cloud sync, scrolling capture, or sharing links.
- Persistent remembered positions for Quick Access.
- Moving the Quick Access panel itself.

## Architecture

Keep Quick Access and the workspace as separate AppKit adapters because they have different lifecycle and positioning rules.

- `QuickAccessPanelController` owns the fixed bottom-left preview stack, hover controls, close/copy/save actions, pin action, drag source behavior, and screenshot-id based closing when workspace output succeeds.
- A new workspace controller owns larger preview/edit windows, image-only pin windows, resize/move behavior, close semantics, context menus, and editing toolbar state.
- The workspace controller owns native-titlebar layout decisions: traffic-light safe area, top toolbar row, and image content area below the toolbar.
- `AppDelegate` wires captured screenshot output into Quick Access and delegates workspace opening to the workspace controller.
- Existing `ClipboardWriter` and `ScreenshotFileWriter` remain the output adapters for copy and save.
- A small deterministic core model defines workspace mode and selected editing tool so unit tests can cover behavior without AppKit.

The workspace should receive captured PNG data and an image reference from `CapturedScreenshot`. It should not recapture the screen or depend on selection overlay state.

## Quick Access Flow

1. User captures a region.
2. Frame shows a Quick Access preview at the active screen's bottom-left corner.
3. The preview cannot be repositioned by dragging the panel background.
4. Hovering reveals icon-only actions.
5. Clicking close removes only that preview.
6. Clicking save writes the PNG to Desktop and closes that preview on success.
7. Clicking copy writes the image to the system clipboard and closes that preview on success.
8. Dragging the image body starts a drag session using image data and, when practical, a temporary PNG file representation for target apps.
9. Clicking open workspace opens a temporary Image Workspace while keeping the Quick Access preview available.
10. Clicking pin opens a persistent image-only pin window and closes the Quick Access preview that created it.

## Image Workspace Flow

1. The workspace opens with the captured image scaled to fit.
2. The window can be moved and resized using normal macOS window behavior, with resize constrained to keep the image area at the screenshot aspect ratio.
3. The native red traffic-light close control closes the workspace.
4. The top toolbar remains outside the image bounds and never overlays captured pixels.
5. The toolbar is always visible. Hover only changes individual button affordance.
6. Editing tools are visible but disabled until annotation behavior ships:
   - mosaic
   - shape box
   - brush
   - text
   - arrow
   - highlight
7. Right-clicking the preview/edit workspace opens a context menu with copy and download enabled; edited-image save and edit-related actions are disabled until annotation behavior ships.
8. Clicking preview/edit workspace copy or download closes the workspace and also closes the originating Quick Access preview when it is still visible.
9. Preview workspaces remain open across focus changes and close on Escape or through the native red traffic-light close control.
10. Pinned image windows remain open across focus changes and close through the native red traffic-light close control.
11. Pinned image windows do not show the preview/edit toolbar, output actions, or edit placeholders.

## UI Design

Quick Access should stay compact and operational:

- Preview size remains compact by default.
- Multiple previews stack upward from the bottom-left anchor.
- The panel should not be movable by its background.
- Close is a top-right icon-only button.
- Pin is a top-left icon-only button.
- Save, copy, and open workspace live in the bottom glass HUD as icon-only buttons.
- Buttons need accessibility labels and tooltips because visible text is removed.

The Image Workspace should feel like a native floating image surface:

- The screenshot itself is unobstructed.
- The editing toolbar appears above the image as native workspace chrome.
- The toolbar container runs edge-to-edge and extends behind the native traffic-light controls so the titlebar controls visually sit inside the toolbar chrome.
- The toolbar center aligns with the native traffic-light button centers so the titlebar row reads as one piece of chrome.
- The toolbar follows the shared HUD chrome language: translucent HUD material, fine border, capsule ends, icon-only controls, and circular icon hover/selected backgrounds.
- The toolbar and image preview keep a small vertical gap, while both remain horizontally edge-to-edge.
- Editing tools sit on the left side of the toolbar after the traffic-light safe area.
- Editing tools use disabled tint and should not show pointer or hover affordances until they are implemented.
- Disabled Save, Copy, and Download sit on the right side of the toolbar. Copy and Download are active output actions; Save is reserved for future edited-image persistence.
- Right-click keeps duplicate access to copy and download plus disabled save/edit placeholders.
- Toolbar buttons remain visible at normal opacity. Hover and selected states should be subtle, not a whole-toolbar glow.
- The workspace does not render a custom close button because the native traffic-light close control is the close affordance.
- The workspace uses neutral translucent surfaces and avoids decorative chrome.
- The workspace remains resizable, with a minimum width that keeps every toolbar action fully visible.
- The workspace opens with the image area matching the screenshot aspect ratio so the initial preview has no letterbox or pillarbox fill.
- Resizing the workspace keeps the image area at that screenshot aspect ratio while the top toolbar keeps a fixed height.
- The workspace uses native macOS window shadow because it behaves like a real movable and resizable window with traffic-light controls.

Pinned image windows are a simpler surface:

- The pinned screenshot fills the window content without a toolbar row.
- Native traffic-light controls sit over the top-left of the image.
- The window remains movable and aspect-preserving resizable.
- Pin exposes copy, download, and edit through right-click only; it does not show visible toolbar buttons.
- Pin right-click copy and download output the pinned image without closing the pin window.
- Pin right-click edit opens or activates the preview/edit workspace for the same screenshot without closing the pin window.

## Error Handling

- If copying from Quick Access or workspace fails, keep the source surface open and show a short pasteboard error.
- If saving from Quick Access or downloading from workspace fails, keep the source surface open and show the failed path or error message.
- If drag file materialization fails, fall back to image pasteboard data when possible.
- If neither drag representation can be provided, do not start the drag and keep Quick Access open.
- If opening a workspace fails, keep the Quick Access preview open and show a short error.

## Testing Strategy

Unit tests should cover deterministic behavior introduced for the workspace:

- Default workspace tool state is view/no active drawing operation.
- Disabled mosaic, shape box, brush, text, arrow, and highlight controls cannot update selected tool state.
- Temporary and pinned workspace policies report the correct close behavior.

AppKit behavior should be verified through focused build and manual smoke checks:

- Quick Access appears in the bottom-left corner and cannot be moved by dragging its background.
- Hover controls show close at top-right, pin at top-left, and icon-only bottom actions.
- Save and copy still work from Quick Access.
- Dragging the image body can drop into at least one compatible target app or input surface.
- Open workspace creates a movable, resizable preview workspace.
- Preview workspace stays open across focus changes and closes on Escape or native close.
- Re-clicking open workspace for the same Quick Access screenshot activates the existing preview workspace instead of opening a duplicate.
- Pin closes the originating Quick Access preview and opens a persistent image-only pin window.
- Pinned workspace does not close on focus loss, shows only the pinned image, and closes through the native red traffic-light close control.
- Workspace toolbar sits above the image, leaves room for traffic-light controls, and does not obscure captured pixels.
- Workspace opens with its image area at the screenshot aspect ratio.
- Workspace resize preserves the image area aspect ratio so normal resizing does not introduce empty preview fill.
- Preview/edit workspace context menu exposes copy and download, while edited-image save remains disabled.

## Acceptance Criteria

- Capturing a screenshot still ends in a Quick Access preview without requiring a main window.
- Quick Access preview location is fixed to the active screen's bottom-left stack and is not user-movable.
- Users can drag captured image content from Quick Access into compatible external apps.
- Quick Access hover actions are icon-only and match the new top-left/top-right/bottom HUD layout.
- Users can open a focus-persistent workspace for larger preview and future editing.
- Users can pin a screenshot into a persistent, movable, aspect-preserving resizable image-only window while removing the original Quick Access card.
- Workspace tools are visible in a top toolbar that does not cover the image and leaves space for native traffic-light controls.
- Quick Access keeps save and copy available. Preview/edit workspace keeps copy and download available, with edited-image save visible but disabled.

## Open Follow-Ups

- Implement full annotation rendering and export semantics for mosaic, shape box, brush, text, arrow, and highlight.
- Decide whether edited output overwrites the captured PNG data in-memory or creates a separate edited rendition.
- Decide whether workspace windows should support zoom controls beyond window resizing.
- Decide whether pinned workspace positions should be remembered across app launches.
