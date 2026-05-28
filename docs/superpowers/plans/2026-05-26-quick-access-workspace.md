# Quick Access Workspace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build fixed Quick Access previews with drag-to-app support and a larger movable Image Workspace for preview, pinning, and future editing.

**Architecture:** Keep Quick Access and Image Workspace as separate AppKit controllers with different lifecycle rules. Put deterministic workspace policy and selected editing tool state in `FrameCore` so the close semantics and tool selection can be tested without AppKit.

**Tech Stack:** Swift 6.1, AppKit, Swift Testing, macOS pasteboard and dragging APIs, existing `ClipboardWriter` and `ScreenshotFileWriter`.

---

## File Structure

- Modify `Sources/FrameApp/AppDelegate.swift`: create and own the workspace controller, wire Quick Access callbacks for copy, save, open workspace, and pin.
- Modify `Sources/FrameApp/QuickAccessPanelController.swift`: fixed panel behavior, icon-only hover controls, drag source view, open workspace and pin callbacks.
- Create `Sources/FrameApp/ImageWorkspacePanelController.swift`: movable/resizable image workspace windows, toolbar, context menu, close behavior, copy/save callbacks.
- Create `Sources/FrameApp/ScreenshotDragItemProvider.swift`: create image and file drag representations for captured screenshots.
- Create `Sources/FrameCore/ImageWorkspaceState.swift`: testable workspace kind, close policy, editing tools, and state transition helpers.
- Modify `Tests/FrameCoreTests/FrameCoreTests.swift`: unit tests for workspace state and close policy.
- Modify `docs/architecture.md`: durable note about Quick Access versus Image Workspace boundaries.
- Keep `docs/superpowers/specs/2026-05-26-quick-access-workspace-design.md` as the source spec for this work.

---

### Task 1: Add Testable Workspace State

**Files:**
- Create: `Sources/FrameCore/ImageWorkspaceState.swift`
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`

- [ ] **Step 1: Write the failing workspace state tests**

Add these tests to `Tests/FrameCoreTests/FrameCoreTests.swift` before implementation:

```swift
@Test
func testImageWorkspaceDefaultsToViewWithoutActiveTool() {
    let state = ImageWorkspaceState(kind: .temporaryPreview)

    #expect(state.kind == .temporaryPreview)
    #expect(state.selectedTool == nil)
    #expect(state.closePolicy == .escapeOrFocusLoss)
}

@Test
func testPinnedWorkspaceOnlyClosesExplicitly() {
    let state = ImageWorkspaceState(kind: .pinned)

    #expect(state.kind == .pinned)
    #expect(state.closePolicy == .explicitCloseOnly)
}

@Test
func testSelectingEditingToolsUpdatesWorkspaceState() {
    var state = ImageWorkspaceState(kind: .temporaryPreview)

    for tool in ImageEditingTool.allCases {
        state.select(tool)
        #expect(state.selectedTool == tool)
    }
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run:

```bash
swift test --filter FrameCoreTests
```

Expected: FAIL because `ImageWorkspaceState`, `ImageWorkspaceKind`, `ImageWorkspaceClosePolicy`, and `ImageEditingTool` do not exist.

- [ ] **Step 3: Add the minimal core model**

Create `Sources/FrameCore/ImageWorkspaceState.swift`:

```swift
import Foundation

public enum ImageWorkspaceKind: Sendable, Equatable {
    case temporaryPreview
    case pinned
}

public enum ImageWorkspaceClosePolicy: Sendable, Equatable {
    case escapeOrFocusLoss
    case explicitCloseOnly
}

public enum ImageEditingTool: CaseIterable, Sendable, Equatable {
    case mosaic
    case shapeBox
    case brush
    case text
    case arrow
    case highlight
}

public struct ImageWorkspaceState: Sendable, Equatable {
    public let kind: ImageWorkspaceKind
    public private(set) var selectedTool: ImageEditingTool?

    public init(kind: ImageWorkspaceKind, selectedTool: ImageEditingTool? = nil) {
        self.kind = kind
        self.selectedTool = selectedTool
    }

    public var closePolicy: ImageWorkspaceClosePolicy {
        switch kind {
        case .temporaryPreview:
            .escapeOrFocusLoss
        case .pinned:
            .explicitCloseOnly
        }
    }

    public mutating func select(_ tool: ImageEditingTool) {
        selectedTool = tool
    }
}
```

- [ ] **Step 4: Run the tests to verify GREEN**

Run:

```bash
swift test --filter FrameCoreTests
```

Expected: PASS.

---

### Task 2: Prepare Quick Access Actions And Fixed Panel Behavior

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [ ] **Step 1: Update the Quick Access API shape**

Change `QuickAccessPanelController.show` so callers provide `openWorkspace` and `pin` actions:

```swift
func show(
    for captured: CapturedScreenshot,
    preferredAnchor: CGRect?,
    copy: @escaping () -> Bool,
    save: @escaping () -> Bool,
    openWorkspace: @escaping () -> Bool,
    pin: @escaping () -> Bool,
    close: @escaping () -> Void
)
```

Update `QuickAccessPreviewItem` with matching stored closures:

```swift
let openWorkspace: () -> Bool
let pin: () -> Bool
```

- [ ] **Step 2: Update `AppDelegate` to compile against the new API with temporary stubs**

In `showQuickAccess(for:anchor:)`, pass temporary closures that log and return `true`:

```swift
openWorkspace: {
    NSLog("Frame workspace preview requested")
    return true
},
pin: {
    NSLog("Frame pin preview requested")
    return true
},
```

Keep existing copy, save, and close closures unchanged.

- [ ] **Step 3: Make the Quick Access panel non-movable**

In `makePanel(for:)`, set:

```swift
panel.isMovableByWindowBackground = false
```

Keep the panel position controlled only by `repositionPreviewStack`.

- [ ] **Step 4: Replace text buttons with icon-only controls**

Replace `makeButton(title:symbolName:action:)` with:

```swift
private func makeIconButton(title: String, symbolName: String, action: Selector) -> NSButton {
    let button = NSButton(image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(), target: self, action: action)
    button.isBordered = false
    button.bezelStyle = .regularSquare
    button.imagePosition = .imageOnly
    button.toolTip = title
    button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
    button.contentTintColor = .labelColor
    button.setButtonType(.momentaryPushIn)
    button.translatesAutoresizingMaskIntoConstraints = false
    return button
}
```

Use SF Symbols:

```swift
"square.and.arrow.down" // save
"doc.on.doc" // copy
"arrow.up.left.and.arrow.down.right" // open workspace
"pin" // pin
"xmark" // close
```

- [ ] **Step 5: Rebuild the Quick Access content layout**

In `makeContentView(for:)`, keep the image full bleed, add:

```swift
let closeButton = makeIconButton(title: "关闭", symbolName: "xmark", action: #selector(closeButtonClicked))
let pinButton = makeIconButton(title: "固定到预览窗口", symbolName: "pin", action: #selector(pinButtonClicked))
let overlayView = NSVisualEffectView()
let stackView = NSStackView()
```

Place close at top-right, pin at top-left, and save/copy/open workspace in the bottom HUD. Keep all controls hidden until hover by adding them to `ScreenshotPreviewView.actionsViews`.

- [ ] **Step 6: Add action handlers**

Add:

```swift
@objc private func openWorkspaceButtonClicked() {
    guard let item = previewItem(for: NSApp.currentEvent) else {
        return
    }

    _ = item.openWorkspace()
}

@objc private func pinButtonClicked() {
    guard let item = previewItem(for: NSApp.currentEvent) else {
        return
    }

    if item.pin() {
        closePreview(item, notify: false)
    }
}
```

Copy and save continue to close the item only on success. Close continues to notify.

- [ ] **Step 7: Build to verify GREEN for API and layout compile**

Run:

```bash
swift build
```

Expected: PASS.

---

### Task 3: Add Quick Access Drag Source Support

**Files:**
- Create: `Sources/FrameApp/ScreenshotDragItemProvider.swift`
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`

- [ ] **Step 1: Add the drag provider adapter**

Create `Sources/FrameApp/ScreenshotDragItemProvider.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotDragItemProvider {
    func draggingItem(for screenshot: CapturedScreenshot, sourceBounds: NSRect) -> NSDraggingItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(screenshot.pngData, forType: .png)
        pasteboardItem.setString("Frame Screenshot.png", forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        draggingItem.setDraggingFrame(sourceBounds, contents: screenshot.image)
        return draggingItem
    }
}
```

- [ ] **Step 2: Add screenshot ownership to the preview content view**

Change `makeContentView(for:)` to receive the full screenshot and drag provider:

```swift
private func makeContentView(for screenshot: CapturedScreenshot) -> NSView
```

Initialize:

```swift
let contentView = ScreenshotPreviewView(screenshot: screenshot, dragItemProvider: ScreenshotDragItemProvider())
```

- [ ] **Step 3: Implement drag start in `ScreenshotPreviewView`**

Add stored properties and initializer:

```swift
private let screenshot: CapturedScreenshot
private let dragItemProvider: ScreenshotDragItemProvider

init(screenshot: CapturedScreenshot, dragItemProvider: ScreenshotDragItemProvider) {
    self.screenshot = screenshot
    self.dragItemProvider = dragItemProvider
    super.init(frame: .zero)
}

@available(*, unavailable)
required init?(coder: NSCoder) {
    nil
}
```

Implement:

```swift
override func mouseDragged(with event: NSEvent) {
    guard !isPointInActions(convert(event.locationInWindow, from: nil)) else {
        return
    }

    let item = dragItemProvider.draggingItem(for: screenshot, sourceBounds: bounds)
    beginDraggingSession(with: [item], event: event, source: self)
}
```

Add a simple hit-test helper that treats visible action controls as non-draggable:

```swift
private func isPointInActions(_ point: NSPoint) -> Bool {
    actionsViews.contains { view in
        !view.isHidden && view.alphaValue > 0.01 && view.frame.contains(point)
    }
}
```

- [ ] **Step 4: Conform to `NSDraggingSource`**

Add:

```swift
extension ScreenshotPreviewView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
```

- [ ] **Step 5: Build to verify drag code compiles**

Run:

```bash
swift build
```

Expected: PASS.

---

### Task 4: Build Image Workspace Controller Shell

**Files:**
- Create: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [ ] **Step 1: Create the controller and public API**

Create `Sources/FrameApp/ImageWorkspacePanelController.swift`:

```swift
import AppKit
import FrameCore

@MainActor
final class ImageWorkspacePanelController: NSObject {
    private var workspaceItems: [ImageWorkspaceItem] = []

    func show(
        screenshot: CapturedScreenshot,
        kind: ImageWorkspaceKind,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool
    ) -> Bool {
        let item = ImageWorkspaceItem(
            state: ImageWorkspaceState(kind: kind),
            panel: makePanel(for: screenshot, kind: kind),
            screenshot: screenshot,
            copy: copy,
            save: save
        )
        item.panel.contentView = makeContentView(for: item)
        workspaceItems.append(item)
        item.panel.orderFrontRegardless()
        return true
    }
}
```

- [ ] **Step 2: Add the workspace panel**

Add:

```swift
private func makePanel(for screenshot: CapturedScreenshot, kind: ImageWorkspaceKind) -> NSPanel {
    let screenFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
    let panelSize = CGSize(width: min(720, screenFrame.width * 0.7), height: min(520, screenFrame.height * 0.7))
    let origin = CGPoint(x: screenFrame.midX - panelSize.width / 2, y: screenFrame.midY - panelSize.height / 2)
    let panel = NSPanel(
        contentRect: NSRect(origin: origin, size: panelSize),
        styleMask: [.nonactivatingPanel, .resizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.isReleasedWhenClosed = false
    panel.hidesOnDeactivate = kind == .temporaryPreview
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isOpaque = false
    return panel
}
```

- [ ] **Step 3: Add the workspace content view**

Add `ImageWorkspaceContentView` in the same file. It should contain:

```swift
private final class ImageWorkspaceContentView: NSView {
    let imageView: NSImageView
    let toolbarView: NSVisualEffectView

    init(image: NSImage) {
        imageView = NSImageView(image: image)
        toolbarView = NSVisualEffectView()
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
```

In `setup()`, use constraints so the toolbar is below the image:

```swift
imageView.imageScaling = .scaleProportionallyUpOrDown
imageView.translatesAutoresizingMaskIntoConstraints = false
toolbarView.material = .hudWindow
toolbarView.blendingMode = .withinWindow
toolbarView.state = .active
toolbarView.alphaValue = 0.72
toolbarView.translatesAutoresizingMaskIntoConstraints = false
addSubview(imageView)
addSubview(toolbarView)
NSLayoutConstraint.activate([
    imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
    imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
    imageView.topAnchor.constraint(equalTo: topAnchor),
    toolbarView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
    toolbarView.centerXAnchor.constraint(equalTo: centerXAnchor),
    toolbarView.heightAnchor.constraint(equalToConstant: 40),
    toolbarView.bottomAnchor.constraint(equalTo: bottomAnchor),
])
```

- [ ] **Step 4: Add toolbar and context menu actions**

Create icon buttons for:

```swift
ImageEditingTool.mosaic
ImageEditingTool.shapeBox
ImageEditingTool.brush
ImageEditingTool.text
ImageEditingTool.arrow
ImageEditingTool.highlight
```

Also add copy and save buttons at the right edge. Add `menu(for:)` on the content view or panel content to return an `NSMenu` with `复制`, `保存`, and editing tool items. Tool actions update `ImageWorkspaceItem.state`.

- [ ] **Step 5: Add close behavior**

Add a top-right close button over the image area. For temporary preview, close on Escape and focus loss:

```swift
override func cancelOperation(_ sender: Any?) {
    window?.close()
}
```

For focus loss, observe `NSWindow.didResignKeyNotification` only for `.temporaryPreview` and close that item. Pinned items must not register this observer.

- [ ] **Step 6: Remove workspace items when panels close**

Set the panel delegate and implement:

```swift
func windowWillClose(_ notification: Notification) {
    guard let panel = notification.object as? NSPanel else {
        return
    }
    workspaceItems.removeAll { $0.panel === panel }
}
```

- [ ] **Step 7: Build to verify workspace shell compiles**

Run:

```bash
swift build
```

Expected: PASS.

---

### Task 5: Wire Quick Access To Image Workspace

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`

- [ ] **Step 1: Own the workspace controller in `AppDelegate`**

Add:

```swift
private let imageWorkspacePanelController = ImageWorkspacePanelController()
```

- [ ] **Step 2: Add workspace helpers**

Add:

```swift
private func openWorkspace(_ screenshot: CapturedScreenshot, kind: ImageWorkspaceKind) -> Bool {
    imageWorkspacePanelController.show(
        screenshot: screenshot,
        kind: kind,
        copy: { [weak self] in
            self?.copyToClipboard(screenshot) ?? false
        },
        save: { [weak self] in
            self?.saveToDesktop(screenshot) ?? false
        }
    )
}
```

- [ ] **Step 3: Replace temporary Quick Access stubs**

In `showQuickAccess(for:anchor:)`, pass:

```swift
openWorkspace: { [weak self] in
    self?.openWorkspace(screenshot, kind: .temporaryPreview) ?? false
},
pin: { [weak self] in
    self?.openWorkspace(screenshot, kind: .pinned) ?? false
},
```

Confirm `pin` closes the originating Quick Access item because `pinButtonClicked` closes after success. Confirm `openWorkspace` keeps the Quick Access item open.

- [ ] **Step 4: Build and run core tests**

Run:

```bash
swift test --filter FrameCoreTests
swift build
```

Expected: both PASS.

---

### Task 6: Update Architecture Docs And Manual Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/development.md` if manual QA steps need new wording.

- [ ] **Step 1: Update architecture runtime flow**

In `docs/architecture.md`, replace the Quick Access line with:

```markdown
10. `QuickAccessPanelController` presents fixed-position screenshot previews at the active screen's bottom-left corner, stacks multiple previews upward, exposes icon-only hover actions, and acts as a drag source for captured image output.
11. `ImageWorkspacePanelController` presents movable and resizable preview/edit workspace windows for temporary preview and pinned screenshots.
12. `ClipboardWriter` writes the captured image to `NSPasteboard`.
13. `ScreenshotFileWriter` saves PNG data to Desktop using `ScreenshotNaming`.
```

- [ ] **Step 2: Update development smoke checks**

In `docs/development.md`, add manual checks after capture:

```markdown
- Confirm Quick Access cannot be moved by dragging its background.
- Confirm dragging the preview image can drop image content into a compatible target app.
- Confirm the workspace action opens a movable, resizable temporary workspace.
- Confirm Escape or focus loss closes the temporary workspace.
- Confirm pin closes the originating Quick Access card and opens a persistent workspace.
- Confirm the pinned workspace stays open after focus changes and closes with its top-right close button.
```

- [ ] **Step 3: Run full required verification**

Run:

```bash
swift test
swift build
scripts/package-app.sh
```

Expected: all PASS. Packaging creates `.build/app/Frame.app`.

- [ ] **Step 4: Manual smoke verification**

Launch the packaged app and verify:

```bash
open .build/app/Frame.app
```

Manual expected behavior:

- `Command+Shift+A` starts capture after permission exists.
- Quick Access appears bottom-left and stays fixed when dragged by background.
- Hover shows top-right close, top-left pin, and bottom icon-only save/copy/workspace controls.
- Save writes `Frame yyyy-MM-dd HH.mm.ss.png` to Desktop.
- Copy writes an image to the clipboard.
- Dragging the screenshot body starts a copy drag into at least one compatible app.
- Workspace opens as a large movable, resizable window.
- Workspace toolbar is below the image and does not obscure image pixels.
- Temporary workspace closes on Escape or focus loss.
- Pin closes the Quick Access card and opens a persistent workspace.

---

## Plan Self-Review

- Spec coverage: fixed Quick Access, drag-to-app, icon-only controls, temporary workspace, pinned workspace, external bottom toolbar, copy/save, context menu, and docs are covered by Tasks 1-6.
- Placeholder scan: no task uses TBD, TODO, or unspecified implementation steps.
- Type consistency: `ImageWorkspaceKind`, `ImageWorkspaceClosePolicy`, `ImageEditingTool`, and `ImageWorkspaceState` are introduced in Task 1 and reused consistently in later tasks.
