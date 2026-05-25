# Size HUD Ratio Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add fixed-width HUD size controls with numeric width/height editing, ratio locking, preset ratios, and Shift temporary ratio drag behavior.

**Architecture:** Put deterministic sizing math in `FrameCore` so center resizing, ratio fitting, and default preset creation can be unit tested without AppKit. Add a focused AppKit HUD control in `FrameApp` for the fixed-width size UI, then integrate it into `SelectionOverlayWindow` while keeping capture and Quick Access unchanged.

**Tech Stack:** Swift 6.1, AppKit, CoreGraphics, Swift Testing, existing `FrameCore` and `FrameApp` package targets.

---

## File Structure

- Create `Sources/FrameCore/SelectionSizing.swift` for `SelectionAspectRatio`, `SelectionSizingMode`, and deterministic rectangle sizing helpers.
- Modify `Tests/FrameCoreTests/FrameCoreTests.swift` with unit tests for center resize, ratio fitting, default preset selection, and clamping.
- Create `Sources/FrameApp/HUDSizeControl.swift` for the fixed-width width/lock/height/chevron HUD control.
- Modify `Sources/FrameApp/SelectionOverlayWindow.swift` to replace `sizeLabel` with `HUDSizeControl`, remove corner resize hit-testing for ordinary drag, apply numeric sizing and presets, and implement Shift temporary ratio lock during drag.
- Modify `docs/architecture.md` after implementation to record the durable sizing boundary.

## Tasks

### Task 1: Add Deterministic Sizing Helpers

**Files:**
- Create: `Sources/FrameCore/SelectionSizing.swift`
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`

- [ ] **Step 1: Write failing tests for center resize, locked dimensions, preset fitting, and default creation**

Add these tests to `Tests/FrameCoreTests/FrameCoreTests.swift`:

```swift
@Test
func testCenterResizePreservesCenter() {
    let original = CGRect(x: 100, y: 120, width: 200, height: 100)
    let resized = SelectionSizing.centeredRect(
        around: original.center,
        size: CGSize(width: 120, height: 80),
        inside: CGRect(x: 0, y: 0, width: 500, height: 400)
    )

    #expect(resized.midX == original.midX)
    #expect(resized.midY == original.midY)
    #expect(resized.size == CGSize(width: 120, height: 80))
}

@Test
func testLockedWidthEditDerivesHeight() {
    let size = SelectionSizing.size(
        editing: .width,
        value: 160,
        currentSize: CGSize(width: 100, height: 50),
        mode: .locked(SelectionAspectRatio(width: 16, height: 9))
    )

    #expect(size == CGSize(width: 160, height: 90))
}

@Test
func testLockedHeightEditDerivesWidth() {
    let size = SelectionSizing.size(
        editing: .height,
        value: 90,
        currentSize: CGSize(width: 100, height: 50),
        mode: .locked(SelectionAspectRatio(width: 16, height: 9))
    )

    #expect(size == CGSize(width: 160, height: 90))
}

@Test
func testPresetFitDoesNotEnlargeCurrentSelection() {
    let current = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let fitted = SelectionSizing.fit(
        aspectRatio: SelectionAspectRatio(width: 16, height: 9),
        inside: current
    )

    #expect(fitted.width == 1200)
    #expect(fitted.height == 675)
    #expect(fitted.midX == current.midX)
    #expect(fitted.midY == current.midY)
}

@Test
func testTallPresetFitDoesNotEnlargeCurrentSelection() {
    let current = CGRect(x: 0, y: 0, width: 800, height: 1200)
    let fitted = SelectionSizing.fit(
        aspectRatio: SelectionAspectRatio(width: 16, height: 9),
        inside: current
    )

    #expect(fitted.width == 800)
    #expect(fitted.height == 450)
    #expect(fitted.midX == current.midX)
    #expect(fitted.midY == current.midY)
}

@Test
func testDefaultPresetSelectionFitsInsideSixtyPercentScreenBox() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let selection = SelectionSizing.defaultSelection(
        aspectRatio: SelectionAspectRatio(width: 16, height: 9),
        screenBounds: screen
    )

    #expect(selection.width == 864)
    #expect(selection.height == 486)
    #expect(selection.midX == screen.midX)
    #expect(selection.midY == screen.midY)
}

@Test
func testLockedOversizedSelectionClampsWhilePreservingRatio() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    let selection = SelectionSizing.centeredRect(
        around: screen.center,
        size: CGSize(width: 2000, height: 1125),
        inside: screen,
        preserving: SelectionAspectRatio(width: 16, height: 9)
    )

    #expect(selection.width == 1000)
    #expect(selection.height == 562.5)
    #expect(selection.midX == screen.midX)
    #expect(selection.midY == screen.midY)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```sh
swift test
```

Expected: compile failure because `SelectionSizing`, `SelectionAspectRatio`, and related APIs do not exist.

- [ ] **Step 3: Implement the minimal sizing helper**

Create `Sources/FrameCore/SelectionSizing.swift`:

```swift
import CoreGraphics

public struct SelectionAspectRatio: Equatable, Sendable {
    public let width: CGFloat
    public let height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    public var value: CGFloat {
        width / height
    }

    public static let square = SelectionAspectRatio(width: 1, height: 1)
    public static let fourThree = SelectionAspectRatio(width: 4, height: 3)
    public static let threeTwo = SelectionAspectRatio(width: 3, height: 2)
    public static let sixteenNine = SelectionAspectRatio(width: 16, height: 9)
    public static let nineSixteen = SelectionAspectRatio(width: 9, height: 16)
}

public enum SelectionSizingMode: Equatable, Sendable {
    case unlocked
    case locked(SelectionAspectRatio)
}

public enum SelectionSizeDimension: Equatable, Sendable {
    case width
    case height
}

public enum SelectionSizing {
    public static let defaultScreenFraction: CGFloat = 0.6

    public static func size(
        editing dimension: SelectionSizeDimension,
        value: CGFloat,
        currentSize: CGSize,
        mode: SelectionSizingMode
    ) -> CGSize {
        switch (dimension, mode) {
        case (.width, .unlocked):
            return CGSize(width: value, height: currentSize.height)
        case (.height, .unlocked):
            return CGSize(width: currentSize.width, height: value)
        case let (.width, .locked(ratio)):
            return CGSize(width: value, height: value / ratio.value)
        case let (.height, .locked(ratio)):
            return CGSize(width: value * ratio.value, height: value)
        }
    }

    public static func centeredRect(
        around center: CGPoint,
        size: CGSize,
        inside bounds: CGRect,
        preserving aspectRatio: SelectionAspectRatio? = nil
    ) -> CGRect {
        let clampedSize: CGSize
        if let aspectRatio,
           (size.width > bounds.width || size.height > bounds.height) {
            clampedSize = sizeThatFits(aspectRatio: aspectRatio, inside: bounds.size)
        } else {
            clampedSize = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        }

        let width = clampedSize.width
        let height = clampedSize.height
        let origin = CGPoint(
            x: min(max(center.x - width / 2, bounds.minX), bounds.maxX - width),
            y: min(max(center.y - height / 2, bounds.minY), bounds.maxY - height)
        )
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }

    public static func sizeThatFits(
        aspectRatio: SelectionAspectRatio,
        inside size: CGSize
    ) -> CGSize {
        let heightFromWidth = size.width / aspectRatio.value
        if heightFromWidth <= size.height {
            return CGSize(width: size.width, height: heightFromWidth)
        }

        return CGSize(width: size.height * aspectRatio.value, height: size.height)
    }

    public static func fit(
        aspectRatio: SelectionAspectRatio,
        inside rect: CGRect
    ) -> CGRect {
        let size = sizeThatFits(aspectRatio: aspectRatio, inside: rect.size)
        return centeredRect(around: rect.center, size: size, inside: rect)
    }

    public static func defaultSelection(
        aspectRatio: SelectionAspectRatio,
        screenBounds: CGRect
    ) -> CGRect {
        let defaultBox = CGRect(
            x: screenBounds.midX - screenBounds.width * defaultScreenFraction / 2,
            y: screenBounds.midY - screenBounds.height * defaultScreenFraction / 2,
            width: screenBounds.width * defaultScreenFraction,
            height: screenBounds.height * defaultScreenFraction
        )
        return fit(aspectRatio: aspectRatio, inside: defaultBox)
    }
}

public extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```sh
swift test
```

Expected: all `FrameCoreTests` pass.

### Task 2: Add Fixed-Width HUD Size Control

**Files:**
- Create: `Sources/FrameApp/HUDSizeControl.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`

- [ ] **Step 1: Create `HUDSizeControl` with callbacks and fixed layout**

Create `Sources/FrameApp/HUDSizeControl.swift`:

```swift
import AppKit
import FrameCore

@MainActor
final class HUDSizeControl: NSView {
    var onWidthCommit: ((Int) -> Void)?
    var onHeightCommit: ((Int) -> Void)?
    var onLockToggle: (() -> Void)?
    var onRatioPreset: ((SelectionAspectRatio) -> Void)?

    private let widthButton = NSButton(title: "0", target: nil, action: nil)
    private let lockButton = NSButton()
    private let heightButton = NSButton(title: "0", target: nil, action: nil)
    private let menuButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let editor = NSTextField()
    private var editingDimension: SelectionSizeDimension?
    private var isLocked = false
    private var foregroundColor = NSColor.white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(width: Int, height: Int, isLocked: Bool, foregroundColor: NSColor) {
        self.isLocked = isLocked
        self.foregroundColor = foregroundColor
        widthButton.title = "\(width)"
        heightButton.title = "\(height)"
        lockButton.image = NSImage(
            systemSymbolName: isLocked ? "lock.fill" : "lock.open",
            accessibilityDescription: isLocked ? "锁定比例" : "自由比例"
        )
        [widthButton, lockButton, heightButton, menuButton].forEach {
            $0.contentTintColor = foregroundColor
        }
    }

    private func configure() {
        wantsLayer = true

        [widthButton, lockButton, heightButton].forEach { button in
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        widthButton.target = self
        widthButton.action = #selector(editWidth)
        widthButton.alignment = .right

        lockButton.target = self
        lockButton.action = #selector(toggleLock)
        lockButton.toolTip = "锁定比例"

        heightButton.target = self
        heightButton.action = #selector(editHeight)
        heightButton.alignment = .left

        configureMenu()
        configureEditor()

        NSLayoutConstraint.activate([
            widthButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            widthButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthButton.widthAnchor.constraint(equalToConstant: 34),

            lockButton.leadingAnchor.constraint(equalTo: widthButton.trailingAnchor, constant: 2),
            lockButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 22),
            lockButton.heightAnchor.constraint(equalToConstant: 30),

            heightButton.leadingAnchor.constraint(equalTo: lockButton.trailingAnchor, constant: 2),
            heightButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightButton.widthAnchor.constraint(equalToConstant: 34),

            menuButton.leadingAnchor.constraint(equalTo: heightButton.trailingAnchor, constant: 2),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func configureMenu() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isBordered = false
        menuButton.menu?.removeAllItems()
        menuButton.addItem(withTitle: "")
        addRatioItem(title: "1:1", ratio: .square)
        addRatioItem(title: "4:3", ratio: .fourThree)
        addRatioItem(title: "3:2", ratio: .threeTwo)
        addRatioItem(title: "16:9", ratio: .sixteenNine)
        addRatioItem(title: "9:16", ratio: .nineSixteen)
        addSubview(menuButton)
    }

    private func addRatioItem(title: String, ratio: SelectionAspectRatio) {
        let item = NSMenuItem(title: title, action: #selector(selectRatio(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ratio
        menuButton.menu?.addItem(item)
    }

    private func configureEditor() {
        editor.isHidden = true
        editor.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        editor.alignment = .center
        editor.target = self
        editor.action = #selector(commitEditor)
        editor.translatesAutoresizingMaskIntoConstraints = false
        addSubview(editor)
    }

    @objc private func editWidth() {
        startEditing(.width, from: widthButton)
    }

    @objc private func editHeight() {
        startEditing(.height, from: heightButton)
    }

    @objc private func toggleLock() {
        onLockToggle?()
    }

    @objc private func selectRatio(_ sender: NSMenuItem) {
        guard let ratio = sender.representedObject as? SelectionAspectRatio else {
            return
        }
        onRatioPreset?(ratio)
    }

    private func startEditing(_ dimension: SelectionSizeDimension, from button: NSButton) {
        editingDimension = dimension
        editor.stringValue = button.title
        editor.frame = button.frame
        editor.textColor = foregroundColor
        editor.isHidden = false
        window?.makeFirstResponder(editor)
        editor.selectText(nil)
    }

    @objc private func commitEditor() {
        guard let editingDimension,
              let value = Int(editor.stringValue) else {
            cancelEditing()
            return
        }

        editor.isHidden = true
        self.editingDimension = nil

        switch editingDimension {
        case .width:
            onWidthCommit?(value)
        case .height:
            onHeightCommit?(value)
        }
    }

    func cancelEditing() {
        editor.isHidden = true
        editingDimension = nil
    }
}
```

- [ ] **Step 2: Wire the control into `SelectionOverlayWindow` without changing behavior yet**

In `Sources/FrameApp/SelectionOverlayWindow.swift`, replace `sizeLabel` with:

```swift
private let sizeControl = HUDSizeControl()
```

In `configureHUD()`, replace `sizeView.addSubview(sizeLabel)` and `configureSizeLabel()` with:

```swift
sizeView.addSubview(sizeControl)
configureSizeControl()
```

Replace the size constraints with:

```swift
sizeControl.translatesAutoresizingMaskIntoConstraints = false
NSLayoutConstraint.activate([
    sizeControl.leadingAnchor.constraint(equalTo: sizeView.leadingAnchor),
    sizeControl.trailingAnchor.constraint(equalTo: sizeView.trailingAnchor),
    sizeControl.topAnchor.constraint(equalTo: sizeView.topAnchor),
    sizeControl.bottomAnchor.constraint(equalTo: sizeView.bottomAnchor),
])
```

Add:

```swift
private func configureSizeControl() {
    sizeControl.onWidthCommit = { [weak self] width in
        self?.applySizeEdit(.width, value: width)
    }
    sizeControl.onHeightCommit = { [weak self] height in
        self?.applySizeEdit(.height, value: height)
    }
    sizeControl.onLockToggle = { [weak self] in
        self?.toggleRatioLock()
    }
    sizeControl.onRatioPreset = { [weak self] ratio in
        self?.applyRatioPreset(ratio)
    }
}
```

Add temporary compile stubs that will be filled in Task 3:

```swift
private func applySizeEdit(_ dimension: SelectionSizeDimension, value: Int) {}
private func toggleRatioLock() {}
private func applyRatioPreset(_ ratio: SelectionAspectRatio) {}
```

In `updateMetrics()`, replace `sizeLabel.stringValue` assignments with:

```swift
updateSizeControl(width: 0, height: 0)
```

and:

```swift
updateSizeControl(
    width: Int(displayedLocalRect.width.rounded()),
    height: Int(displayedLocalRect.height.rounded())
)
```

Add:

```swift
private func updateSizeControl(width: Int, height: Int) {
    sizeControl.update(
        width: width,
        height: height,
        isLocked: effectiveSizingMode != .unlocked,
        foregroundColor: hudTheme.foregroundColor
    )
}
```

Add:

```swift
private var sizingMode: SelectionSizingMode = .unlocked
private var isShiftTemporarilyLocking = false

private var effectiveSizingMode: SelectionSizingMode {
    if isShiftTemporarilyLocking,
       let displayedLocalRect,
       displayedLocalRect.width > 0,
       displayedLocalRect.height > 0 {
        return .locked(SelectionAspectRatio(width: displayedLocalRect.width, height: displayedLocalRect.height))
    }

    return sizingMode
}
```

- [ ] **Step 3: Run build to catch integration errors**

Run:

```sh
swift build
```

Expected: build succeeds after resolving any naming/import issues introduced by the new control.

### Task 3: Implement Size Editing, Presets, and Drag Rules

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Sources/FrameApp/HUDSizeControl.swift` if AppKit focus handling needs a small adjustment

- [ ] **Step 1: Disable ordinary corner resize hit testing**

In `dragOperation(startingAt:)`, remove the `SelectionHandle.hitTest` branch so ordinary drags only create or move:

```swift
private func dragOperation(startingAt point: CGPoint, modifiers: NSEvent.ModifierFlags) -> SelectionDragOperation {
    guard let selectionRect else {
        return .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
    }

    if selectionRect.isNearlyEqual(to: bounds) {
        return .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
    }

    if selectionRect.contains(point) {
        return .move(startRect: selectionRect, startPoint: point)
    }

    return .create(startPoint: point, ratio: ratioForCreateDrag(modifiers: modifiers))
}
```

Change `SelectionDragOperation` to:

```swift
private enum SelectionDragOperation {
    case create(startPoint: CGPoint, ratio: SelectionAspectRatio?)
    case move(startRect: CGRect, startPoint: CGPoint)
}
```

- [ ] **Step 2: Capture Shift temporary lock during drag**

In `mouseDown(with:)`, call the new signature and update temporary lock state:

```swift
isShiftTemporarilyLocking = event.modifierFlags.contains(.shift)
dragOperation = dragOperation(startingAt: point, modifiers: event.modifierFlags)
```

Add `flagsChanged(with:)`:

```swift
override func flagsChanged(with event: NSEvent) {
    isShiftTemporarilyLocking = event.modifierFlags.contains(.shift)
    updateMetrics()
    super.flagsChanged(with: event)
}
```

In `mouseUp(with:)`, restore temporary state:

```swift
dragOperation = nil
isShiftTemporarilyLocking = false
updateMetrics()
```

Add:

```swift
private func ratioForCreateDrag(modifiers: NSEvent.ModifierFlags) -> SelectionAspectRatio? {
    guard modifiers.contains(.shift) else {
        return nil
    }

    if let displayedLocalRect,
       displayedLocalRect.width > 0,
       displayedLocalRect.height > 0 {
        return SelectionAspectRatio(width: displayedLocalRect.width, height: displayedLocalRect.height)
    }

    return nil
}
```

- [ ] **Step 3: Apply ratio to create drags**

Replace the `.create` branch in `updateSelection(for:currentPoint:)` with:

```swift
case let .create(startPoint, ratio):
    let proposed = SelectionGeometry.normalizedRect(from: startPoint, to: currentPoint)
    if let ratio,
       proposed.width > 0,
       proposed.height > 0 {
        selectionRect = SelectionSizing.fit(aspectRatio: ratio, inside: proposed)
    } else {
        selectionRect = proposed
    }
```

- [ ] **Step 4: Implement lock, size edits, and presets**

Replace the no-op methods with:

```swift
private func applySizeEdit(_ dimension: SelectionSizeDimension, value: Int) {
    guard value >= Int(SelectionGeometry.minimumSelectionSize) else {
        NSSound.beep()
        updateMetrics()
        return
    }

    let currentRect = displayedLocalRect ?? SelectionSizing.defaultSelection(
        aspectRatio: activeRatio ?? .sixteenNine,
        screenBounds: bounds
    )
    let requestedSize = SelectionSizing.size(
        editing: dimension,
        value: CGFloat(value),
        currentSize: currentRect.size,
        mode: sizingMode
    )

    selectionRect = SelectionSizing.centeredRect(
        around: currentRect.center,
        size: requestedSize,
        inside: bounds,
        preserving: activeRatio
    )
    windowCandidate = nil
    updateMetrics()
    needsDisplay = true
}

private func toggleRatioLock() {
    switch sizingMode {
    case .unlocked:
        guard let displayedLocalRect,
              displayedLocalRect.width > 0,
              displayedLocalRect.height > 0 else {
            NSSound.beep()
            return
        }
        sizingMode = .locked(SelectionAspectRatio(width: displayedLocalRect.width, height: displayedLocalRect.height))
    case .locked:
        sizingMode = .unlocked
    }

    updateMetrics()
}

private func applyRatioPreset(_ ratio: SelectionAspectRatio) {
    sizingMode = .locked(ratio)

    let nextRect: CGRect
    if let displayedLocalRect {
        nextRect = SelectionSizing.fit(aspectRatio: ratio, inside: displayedLocalRect)
    } else {
        nextRect = SelectionSizing.defaultSelection(aspectRatio: ratio, screenBounds: bounds)
    }

    guard SelectionGeometry.isValidSelection(nextRect) else {
        NSSound.beep()
        updateMetrics()
        return
    }

    selectionRect = clampedRect(nextRect)
    windowCandidate = nil
    updateMetrics()
    needsDisplay = true
}

private var activeRatio: SelectionAspectRatio? {
    if case let .locked(ratio) = sizingMode {
        return ratio
    }

    return nil
}
```

- [ ] **Step 5: Update theme application for the new size control**

In `applyHUDTheme(_:)`, replace `sizeLabel.textColor = theme.foregroundColor` with:

```swift
if let displayedLocalRect {
    updateSizeControl(
        width: Int(displayedLocalRect.width.rounded()),
        height: Int(displayedLocalRect.height.rounded())
    )
} else {
    updateSizeControl(width: 0, height: 0)
}
```

- [ ] **Step 6: Run build and tests**

Run:

```sh
swift test
swift build
```

Expected: tests and build pass.

### Task 4: Documentation and Verification

**Files:**
- Modify: `docs/architecture.md`
- Optionally modify: `docs/development.md` if manual smoke instructions need to mention the size HUD

- [ ] **Step 1: Update architecture docs**

In `docs/architecture.md`, update the `SelectionOverlayWindow` runtime component description to mention:

```text
SelectionOverlayWindow shows a fixed-width HUD whose size segment supports numeric width and height input, ratio locking, preset ratios, and temporary Shift ratio locking while preserving the compact overlay shape.
```

- [ ] **Step 2: Run the required verification commands**

Run:

```sh
swift test
swift build
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
```

Expected: all commands exit 0. The packaging output must say:

```text
Signed with identity: Frame Local Dev CLI
```

- [ ] **Step 3: Replace the local app bundle for manual smoke testing**

Run:

```sh
osascript -e 'tell application id "dev.dewey.frame" to quit' || true
sleep 1
if pgrep -x Frame >/dev/null; then pkill -x Frame; fi
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
codesign -dv --verbose=2 ~/Applications/Frame.app 2>&1 | sed -n '1,24p'
open ~/Applications/Frame.app
```

Expected: the codesign output includes:

```text
Authority=Frame Local Dev CLI
```

## Manual Smoke Checklist

- [ ] Start screenshot and confirm the HUD width does not change from empty state to selected state.
- [ ] Drag to create a region and confirm the region can be moved by dragging inside it.
- [ ] Confirm corner/edge drag no longer resizes the region.
- [ ] Click width, enter a number, press Enter, and confirm the selection resizes around its center.
- [ ] Click height, enter a number, press Enter, and confirm the selection resizes around its center.
- [ ] Toggle the lock icon and confirm editing width derives height from the locked ratio.
- [ ] Open the chevron menu, select `16:9`, and confirm the selection immediately fits within the previous selection without enlarging.
- [ ] Clear selection, select a preset, and confirm a centered default selection appears.
- [ ] Hold Shift while creating a selection and confirm the lock icon appears locked only while Shift is held.
