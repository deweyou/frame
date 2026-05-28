# Image Workspace Top Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the Image Workspace editing controls into a native-feeling top toolbar that leaves room for macOS traffic-light controls and never overlays the screenshot.

**Architecture:** Keep the change local to `ImageWorkspacePanelController`: the window remains a native titled/resizable `NSPanel`, while the content view removes the custom close button and lays out toolbar then image. AppKit tests assert the window uses native close controls, the toolbar is above the image, and the first editing tool starts after the traffic-light safe area.

**Tech Stack:** Swift 6.1, AppKit `NSPanel`/Auto Layout, XCTest AppKit component tests, existing Frame workspace model.

---

### Task 1: Add Workspace Top Toolbar Layout Regression Test

**Files:**
- Create: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`
- Modify: none
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift` with this content:

```swift
import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class ImageWorkspacePanelControllerTests: XCTestCase {
    private var retainedControllers: [ImageWorkspacePanelController] = []

    func testWorkspaceUsesNativeCloseAndTopToolbarOutsideImage() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }

        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertNotNil(panel.standardWindowButton(.closeButton))

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Close"))

        let toolbar = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        let imageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Preview Container"))
        let mosaicButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic"))
        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy"))
        let saveButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save"))

        XCTAssertEqual(toolbar.alphaValue, 1, accuracy: 0.01)
        XCTAssertGreaterThan(toolbar.frame.minX, contentView.bounds.minX + 80)
        XCTAssertGreaterThanOrEqual(mosaicButton.convert(mosaicButton.bounds, to: contentView).minX, contentView.bounds.minX + 92)
        XCTAssertLessThanOrEqual(imageContainer.frame.maxY, toolbar.frame.minY - 8)
        XCTAssertEqual(imageContainer.frame.minX, contentView.bounds.minX + 16, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minY, contentView.bounds.minY + 16, accuracy: 0.5)
        XCTAssertGreaterThan(copyButton.frame.minX, mosaicButton.frame.maxX)
        XCTAssertGreaterThan(saveButton.frame.minX, copyButton.frame.maxX)
    }

    private func makeScreenshot() throws -> CapturedScreenshot {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 6,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return CapturedScreenshot(
            pngData: pngData,
            image: NSImage(size: NSSize(width: 320, height: 240)),
            rect: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
    }

    private func findButton(in view: NSView, accessibilityLabel: String) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == accessibilityLabel {
            return button
        }

        for subview in view.subviews {
            if let button = findButton(in: subview, accessibilityLabel: accessibilityLabel) {
                return button
            }
        }

        return nil
    }

    private func findView(in view: NSView, accessibilityLabel: String) -> NSView? {
        if view.accessibilityLabel() == accessibilityLabel {
            return view
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, accessibilityLabel: accessibilityLabel) {
                return matchingView
            }
        }

        return nil
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter ImageWorkspacePanelControllerTests/testWorkspaceUsesNativeCloseAndTopToolbarOutsideImage
```

Expected: FAIL because the content still contains a custom `Close` button, the toolbar has no `"Image Workspace Toolbar"` accessibility label, and the toolbar is currently below the image.

- [ ] **Step 3: Commit test red state when working in a commit-per-task flow**

Run only when the delivery flow for this branch is committing each task:

```bash
git add Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift
git commit -m "test: cover image workspace top toolbar layout"
```

Expected: commit succeeds with only the new test staged.

### Task 2: Move Workspace Toolbar To Top And Remove Custom Close

**Files:**
- Modify: `Sources/FrameApp/ImageWorkspacePanelController.swift`
- Test: `Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift`

- [ ] **Step 1: Remove the custom close button from content construction**

In `makeContentView(for:)`, delete the `closeButton` creation block:

```swift
let closeButton = makeIconButton(
    title: "Close",
    symbolName: "xmark",
    action: #selector(closeButtonClicked),
    buttonType: .momentaryPushIn
)
closeButton.translatesAutoresizingMaskIntoConstraints = false
closeButton.wantsLayer = true
closeButton.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.34).cgColor
closeButton.layer?.cornerRadius = 14
```

Also delete these lines:

```swift
imageContainer.addSubview(closeButton)
```

```swift
closeButton.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -10),
closeButton.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 10),
closeButton.widthAnchor.constraint(equalToConstant: 28),
closeButton.heightAnchor.constraint(equalToConstant: 28),
```

- [ ] **Step 2: Label toolbar and image container for tests and accessibility**

After creating `imageContainer`, add:

```swift
imageContainer.setAccessibilityLabel("Image Preview Container")
```

After creating `toolbar`, add:

```swift
toolbar.setAccessibilityLabel("Image Workspace Toolbar")
```

- [ ] **Step 3: Move toolbar constraints above the image**

Replace the current `imageContainer` and `toolbar` layout constraints with:

```swift
imageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
imageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
imageContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
imageContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 88),
toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
toolbar.heightAnchor.constraint(equalToConstant: 40),
```

Keep the `imageView` constraints pinned to `imageContainer` as they are.

- [ ] **Step 4: Keep toolbar controls visible at normal opacity**

In `ImageWorkspaceToolbarView.init()`, replace:

```swift
alphaValue = 0.72
```

with:

```swift
alphaValue = 1
```

Remove the tracking-area property and hover alpha behavior from `ImageWorkspaceToolbarView`:

```swift
private var trackingArea: NSTrackingArea?

override func updateTrackingAreas() { ... }
override func mouseEntered(with event: NSEvent) { ... }
override func mouseExited(with event: NSEvent) { ... }
```

The class should keep only its visual-effect setup and `required init?(coder:)`.

- [ ] **Step 5: Remove the unused close action**

Delete this method from `ImageWorkspacePanelController`:

```swift
@objc private func closeButtonClicked(_ sender: NSButton) {
    guard let item = workspaceItem(for: sender.window) else {
        return
    }

    closeWorkspace(item)
}
```

Native traffic-light close still flows through `ImageWorkspacePanel.close()` and `onClose`.

- [ ] **Step 6: Run layout test to verify it passes**

Run:

```bash
swift test --filter ImageWorkspacePanelControllerTests/testWorkspaceUsesNativeCloseAndTopToolbarOutsideImage
```

Expected: PASS.

- [ ] **Step 7: Run existing workspace and drag AppKit tests**

Run:

```bash
swift test --filter 'ImageWorkspacePanelControllerTests|ScreenshotDragItemProviderTests'
```

Expected: PASS. If `ScreenshotDragItemProviderTests` exits with AppKit signal 11, rerun the same command once; the known crash is a transient AppKit test-runner issue when synthetic panel events are mixed with other AppKit tests, not a product assertion failure.

- [ ] **Step 8: Commit implementation when working in a commit-per-task flow**

Run only when the delivery flow for this branch is committing each task:

```bash
git add Sources/FrameApp/ImageWorkspacePanelController.swift Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift
git commit -m "feat: use native top toolbar for image workspace"
```

Expected: commit succeeds with only the workspace layout implementation and tests staged.

### Task 3: Update Durable Documentation And Verify Package

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/superpowers/specs/2026-05-26-quick-access-workspace-design.md` if implementation reveals wording drift
- Test: full repository verification commands

- [ ] **Step 1: Update architecture workspace summary**

In `docs/architecture.md`, update the Image Workspace bullet to say it uses native close controls and a top toolbar. Replace the current item:

```markdown
14. `ImageWorkspacePanelController` presents movable and resizable preview/edit workspace windows for temporary preview sessions and pinned screenshots.
```

with:

```markdown
14. `ImageWorkspacePanelController` presents movable and resizable preview/edit workspace windows for temporary preview sessions and pinned screenshots, using native macOS close controls plus a top toolbar that leaves captured pixels unobstructed.
```

- [ ] **Step 2: Scan spec for stale bottom-toolbar or custom-close wording**

Run:

```bash
rg -n "bottom external|bottom HUD toolbar|custom close|top-right close button|low opacity|focus loss and closes through the top-right" docs/superpowers/specs/2026-05-26-quick-access-workspace-design.md docs/architecture.md
```

Expected: no output for Image Workspace wording. Mentions of Quick Access bottom HUD or top-right close are acceptable only when the line explicitly says Quick Access.

- [ ] **Step 3: Run full verification**

Run:

```bash
swift test
swift build
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
```

Expected:
- `swift test`: PASS. If the full AppKit suite exits once with signal 11 inside `ScreenshotDragItemProviderTests`, rerun `swift test` once and require a PASS before handoff.
- `swift build`: PASS.
- `scripts/package-app.sh`: PASS and prints `Signed with identity: Frame Local Dev CLI`.

- [ ] **Step 4: Replace local app for manual verification**

Run:

```bash
osascript -e 'tell application "Frame" to quit' || true
ditto .build/app/Frame.app /Users/bytedance/Applications/Frame.app
open /Users/bytedance/Applications/Frame.app
sleep 1
codesign --verify --deep --strict --verbose=2 /Users/bytedance/Applications/Frame.app
pgrep -fl '/Users/bytedance/Applications/Frame.app/Contents/MacOS/Frame'
```

Expected:
- Codesign reports the app is valid and satisfies its designated requirement.
- `pgrep` prints the running Frame process.

- [ ] **Step 5: Manual smoke check**

Use Frame locally:

1. Capture a screenshot.
2. Click Quick Access open workspace.
3. Confirm the Image Workspace has native traffic-light controls at top-left.
4. Confirm no custom close button appears inside the content.
5. Confirm the toolbar is top-aligned to the right of the traffic lights.
6. Confirm the screenshot image starts below the toolbar and no tool overlays image pixels.
7. Confirm copy/save still work from the toolbar and right-click menu.
8. Confirm pinned windows stay open on focus loss and close with the native red close control.

- [ ] **Step 6: Commit docs and verification-ready state when working in a commit-per-task flow**

Run only when the delivery flow for this branch is committing each task:

```bash
git add Sources/FrameApp/ImageWorkspacePanelController.swift Tests/FrameAppTests/ImageWorkspacePanelControllerTests.swift docs/architecture.md docs/superpowers/specs/2026-05-26-quick-access-workspace-design.md
git commit -m "docs: document native workspace toolbar"
```

Expected: commit succeeds with only workspace layout docs and implementation files staged.

---

## Self-Review

- **Spec coverage:** The plan covers native red traffic-light close, no custom close, top toolbar, traffic-light safe area, always-visible toolbar, image unobstructed below the toolbar, copy/save retained, and pinned close semantics.
- **Placeholder scan:** No `TBD`, `TODO`, or vague implementation steps remain. Each code change has exact files, snippets, and commands.
- **Type consistency:** The test uses existing public types `ImageWorkspacePanelController`, `CapturedScreenshot`, and `ImageWorkspaceKind`; accessibility labels are added in Task 2 before the test passes.
