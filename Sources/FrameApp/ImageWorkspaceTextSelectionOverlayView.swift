import AppKit
import FrameCore

private let imageWorkspaceEscapeKeyCode: UInt16 = 53

@MainActor
final class ImageWorkspaceTextSelectionOverlayView: NSView {
    private let imageSize: CGSize
    private let copyText: (String) -> Bool
    private var cutLayout: RecognizedTextCutLayout?
    private var selectedCutIDs: Set<UUID> = []
    private var selectionAnchorCutID: UUID?
    private var isDraggingSelection = false
    private var isTextSelectionEnabled = true
    private var trackingArea: NSTrackingArea?
    var menuProvider: (() -> NSMenu)?

    init(imageSize: CGSize, copyText: @escaping (String) -> Bool) {
        self.imageSize = imageSize
        self.copyText = copyText
        super.init(frame: .zero)
        isHidden = true
        setAccessibilityLabel("Image Text Selection Overlay")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden,
              isTextSelectionEnabled,
              cut(at: point) != nil else {
            return nil
        }

        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        super.resetCursorRects()

        guard let cutLayout else {
            return
        }

        guard isTextSelectionEnabled else {
            return
        }

        for cut in cutLayout.rows.flatMap(\.cuts) {
            addCursorRect(viewRect(for: cut.bounds).insetBy(dx: -3, dy: -3), cursor: .iBeam)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !isTextSelectionEnabled || cut(at: point) == nil {
            NSCursor.arrow.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    var hasRecognizedText: Bool {
        cutLayout?.rows.contains { !$0.cuts.isEmpty } == true
    }

    var selectedTextForTesting: String {
        cutLayout?.selectedText(for: selectedCutIDs) ?? ""
    }

    func setRecognizedTextLayout(_ textLayout: RecognizedTextLayout) {
        setCutLayout(RecognizedTextCutLayout(textLayout: textLayout))
    }

    func setCutLayout(_ cutLayout: RecognizedTextCutLayout) {
        self.cutLayout = cutLayout
        selectedCutIDs = []
        selectionAnchorCutID = nil
        updateVisibility()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func setTextSelectionEnabled(_ isEnabled: Bool) {
        guard isTextSelectionEnabled != isEnabled else {
            return
        }

        isTextSelectionEnabled = isEnabled
        if !isEnabled {
            clearSelection()
        }
        updateVisibility()
        window?.invalidateCursorRects(for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if hasSelectedText {
            return makeSelectedTextMenu()
        }

        return menuProvider?() ?? super.menu(for: event)
    }

    func clearSelection() {
        selectedCutIDs = []
        selectionAnchorCutID = nil
        needsDisplay = true
    }

    private func updateVisibility() {
        isHidden = !(isTextSelectionEnabled && hasRecognizedText)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let cutLayout else {
            return
        }

        for rect in selectedLineHighlightRects(in: cutLayout) {
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            NSColor.selectedTextBackgroundColor.withAlphaComponent(0.55).setFill()
            path.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let cut = cut(at: convert(event.locationInWindow, from: nil)) else {
            clearSelection()
            return
        }

        isDraggingSelection = true
        if event.modifierFlags.contains(.shift) {
            extendSelection(to: cut)
        } else {
            selectedCutIDs = [cut.id]
            selectionAnchorCutID = cut.id
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingSelection,
              let cut = cut(at: convert(event.locationInWindow, from: nil)) else {
            return
        }

        extendDragSelection(to: cut)
    }

    override func mouseUp(with event: NSEvent) {
        isDraggingSelection = false
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c",
           copySelectedText() {
            return
        }

        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a" {
            selectAll()
            return
        }

        if event.keyCode == imageWorkspaceEscapeKeyCode {
            clearSelection()
            return
        }

        super.keyDown(with: event)
    }

    private func copySelectedText() -> Bool {
        guard let text = cutLayout?.selectedText(for: selectedCutIDs),
              !text.isEmpty else {
            return false
        }

        return copyText(text)
    }

    @objc private func copySelectedMenuItemClicked(_ sender: NSMenuItem) {
        _ = copySelectedText()
    }

    private var hasSelectedText: Bool {
        cutLayout?.selectedText(for: selectedCutIDs).isEmpty == false
    }

    private func makeSelectedTextMenu() -> NSMenu {
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: "Copy",
            action: #selector(copySelectedMenuItemClicked),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)
        return menu
    }

    private func selectAll() {
        guard let cutLayout else {
            return
        }

        selectedCutIDs = cutLayout.allCutIDs
        selectionAnchorCutID = orderedCuts(in: cutLayout).last?.id
        needsDisplay = true
    }

    private func extendSelection(to cut: RecognizedTextCut) {
        selectRange(to: cut, updatesAnchor: true)
    }

    private func extendDragSelection(to cut: RecognizedTextCut) {
        selectRange(to: cut, updatesAnchor: false)
    }

    private func selectRange(to cut: RecognizedTextCut, updatesAnchor: Bool) {
        guard let cutLayout else {
            return
        }

        let cuts = orderedCuts(in: cutLayout)
        guard let targetIndex = cuts.firstIndex(where: { $0.id == cut.id }) else {
            return
        }

        if let anchorID = selectionAnchorCutID,
           let anchorIndex = cuts.firstIndex(where: { $0.id == anchorID }) {
            let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            selectedCutIDs = Set(cuts[bounds].map(\.id))
        } else {
            selectedCutIDs = [cut.id]
        }

        if updatesAnchor {
            selectionAnchorCutID = cut.id
        }
        needsDisplay = true
    }

    private func cut(at point: CGPoint) -> RecognizedTextCut? {
        guard let cutLayout else {
            return nil
        }

        return orderedCuts(in: cutLayout)
            .filter { viewRect(for: $0.bounds).insetBy(dx: -3, dy: -3).contains(point) }
            .min { first, second in
                let firstRect = viewRect(for: first.bounds)
                let secondRect = viewRect(for: second.bounds)
                return firstRect.width * firstRect.height < secondRect.width * secondRect.height
            }
    }

    private func orderedCuts(in cutLayout: RecognizedTextCutLayout) -> [RecognizedTextCut] {
        cutLayout.rows.flatMap(\.cuts)
    }

    private func selectedLineHighlightRects(in cutLayout: RecognizedTextCutLayout) -> [CGRect] {
        cutLayout.rows.flatMap { row -> [CGRect] in
            let selectedCuts = row.cuts.filter { selectedCutIDs.contains($0.id) }
            guard !selectedCuts.isEmpty else {
                return []
            }

            var rects: [CGRect] = []
            var currentRect: CGRect?
            var previousTokenIndex: Int?

            for cut in selectedCuts {
                let cutRect = viewRect(for: cut.bounds).insetBy(dx: -1, dy: -1)
                if let previousTokenIndex,
                   cut.tokenIndex == previousTokenIndex + 1,
                   let existingRect = currentRect {
                    currentRect = existingRect.union(cutRect)
                } else {
                    if let currentRect {
                        rects.append(currentRect)
                    }
                    currentRect = cutRect
                }
                previousTokenIndex = cut.tokenIndex
            }

            if let currentRect {
                rects.append(currentRect)
            }

            return rects
        }
    }

    private func viewRect(for normalizedRect: NormalizedImageRect) -> CGRect {
        let drawRect = imageDrawRect()
        return CGRect(
            x: drawRect.minX + normalizedRect.x * drawRect.width,
            y: drawRect.minY + normalizedRect.y * drawRect.height,
            width: normalizedRect.width * drawRect.width,
            height: normalizedRect.height * drawRect.height
        )
    }

    private func imageDrawRect() -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return .zero
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}
