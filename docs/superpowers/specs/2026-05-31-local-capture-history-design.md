# Local Capture History Design

## Goal

Frame will keep a local, private capture history so users can recover recent screenshots after closing the Quick Access preview. The feature stays scoped to recent capture recovery, not long-term image management.

## Approval

The product scope was approved in-thread on 2026-05-31 after choosing the bounded local-history approach over a hidden cache-only version or a larger gallery/search feature.

The history window redesign was approved in-thread on 2026-05-31:

- The content model uses an adaptive preview grid instead of a table/list.
- The window chrome uses a native transparent titlebar with integrated traffic-light controls instead of a fully custom borderless window.

## Product Scope

- Local history is enabled by default.
- Captures are kept for 7 days by default.
- The default cache size limit is 2 GB.
- A single capture larger than the configured size limit is not added to history. It can still appear in the current Quick Access preview.
- When the total history cache exceeds the configured size limit, Frame deletes the oldest cached records until the cache is under the limit. The newest stored capture is preserved.
- Closing Quick Access does not delete history.
- Deleting a history item removes only Frame's cached copy and metadata.
- Files explicitly saved by the user to a screenshot directory are not owned by history cleanup.
- Search, tags, favorites, OCR indexing, cloud sync, and automatic classification are out of scope.

## UI

- The menu bar menu gets a Capture History item.
- The history window shows recent local captures as an adaptive preview grid, not as a table.
- The window uses a native macOS window with `fullSizeContentView`, a transparent titlebar, and system traffic-light controls. It must keep normal macOS window movement, resizing, focus, shadows, and close/minimize/zoom behavior.
- The titlebar area visually blends with the content background. The title and the All/Screenshots/Recordings segmented filter live in that top chrome without crowding the traffic-light safe area.
- The content background uses a subtle system material or native visual-effect surface. It should feel lighter than a file manager and quieter than a custom dark HUD window.
- Each capture appears as a preview tile aligned with the Quick Access visual language: rounded screenshot preview, fine translucent border, screenshot content as the primary surface, and low-priority metadata below.
- Tile metadata is limited to one compact line: relative or formatted capture time plus the most useful secondary detail, such as dimensions, file size, or recording type. It must not reintroduce table columns.
- Hovering a tile reveals a compact HUD over the bottom of the preview. The HUD uses icon-only actions for save, copy, open preview, and delete, with tooltips and accessibility labels.
- Actions are hidden when the tile is not hovered. Delete remains local-history deletion only and does not affect user-saved files.
- The grid adapts to the window width and falls back to one column at narrow sizes. It should preserve stable tile dimensions and avoid text or HUD overlap while resizing.
- The history window keeps a segmented type filter for All, Screenshots, and Recordings. Recording is reserved for future data and may be empty in this release.
- Empty states use short native text only.
- Search, grouping by day, tags, and favorites remain out of scope for this release.
- Settings get controls for enabling history, retention duration, cache size limit, and clearing history.

## Architecture

- `CaptureHistoryStore` owns disk layout, metadata index, writes, reads, deletion, and cleanup.
- History files live under `Application Support/Frame/History/Captures`.
- Metadata lives in `Application Support/Frame/History/index.json`.
- The store uses atomic JSON index writes and atomic file writes where practical.
- AppKit controllers depend on the store through small methods rather than reading files directly.
- `AppDelegate` records screenshots after successful capture and before showing Quick Access.
- Existing copy, save, and workspace preview adapters are reused for history actions.
- `CaptureHistoryWindowController` owns the native history window and uses a collection-style preview surface for records. It should not depend on table columns or row views for the primary UI.
- The preview tile/HUD implementation should share constants or small helper views with Quick Access when that keeps behavior consistent without coupling the two controllers tightly.

## Testing

- Store tests cover default settings, add/read/delete, retention cleanup, size cleanup, and oversized single-file rejection.
- Settings tests cover persistence and validation.
- History window tests cover filter controls, preview-grid presentation, tile action dispatch, and absence of table-column UI.
- Component tests cover hover visibility state for tile actions where practical.
- Full verification remains `swift test`, `swift build`, and `scripts/package-app.sh`.
