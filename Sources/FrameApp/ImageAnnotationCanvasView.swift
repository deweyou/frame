import AppKit
import FrameCore

@MainActor
final class ImageAnnotationCanvasView: NSView, NSTextViewDelegate {
    private var image: NSImage
    private var baseScreenshot: CapturedScreenshot?
    private var document: ImageAnnotationDocument
    private let onDocumentChange: (ImageAnnotationDocument) -> Void
    private var interaction: AnnotationInteraction?
    private var activeTextEditor: ImageAnnotationTextEditorView?
    private var activeTextElementID: UUID?
    private var activeTextOrigin: CGPoint?
    private var activeTextDidBeginMutation = false
    private var mosaicDrawingSource: ImageMosaicDrawingSource?
    var menuProvider: (() -> NSMenu)?

    init(
        image: NSImage,
        document: ImageAnnotationDocument,
        onDocumentChange: @escaping (ImageAnnotationDocument) -> Void = { _ in }
    ) {
        self.image = image
        self.document = document
        self.onDocumentChange = onDocumentChange
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var documentForTesting: ImageAnnotationDocument {
        document
    }

    var isEditingTextForTesting: Bool {
        activeTextEditor != nil
    }

    var activeTextEditorFontSizeForTesting: CGFloat? {
        activeTextEditor?.font?.pointSize
    }

    var currentScreenshotForTesting: CapturedScreenshot {
        baseScreenshot ?? CapturedScreenshot(
            pngData: image.pngData() ?? Data(),
            image: image,
            rect: CGRect(origin: .zero, size: image.size)
        )
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?() ?? super.menu(for: event)
    }

    func setDocument(_ document: ImageAnnotationDocument) {
        self.document = document
        needsDisplay = true
        notifyDocumentChanged()
    }

    func setBaseScreenshot(_ screenshot: CapturedScreenshot) {
        baseScreenshot = screenshot
        image = screenshot.image
        mosaicDrawingSource = nil
        needsDisplay = true
    }

    func selectTool(_ tool: ImageAnnotationTool) {
        document.selectTool(tool)
        needsDisplay = true
        notifyDocumentChanged()
    }

    func setShapeKind(_ shapeKind: ImageAnnotationShapeKind) {
        document.setShapeKind(shapeKind)
        notifyDocumentChanged()
    }

    func setMosaicMode(_ mosaicMode: ImageAnnotationMosaicMode) {
        document.setMosaicMode(mosaicMode)
        notifyDocumentChanged()
    }

    func setStyle(_ style: ImageAnnotationStyle) {
        document.setStyle(style)
        updateSelectedElementStyleIfNeeded(style)
        notifyDocumentChanged()
    }

    func undo() {
        document.undo()
        needsDisplay = true
        notifyDocumentChanged()
    }

    func redo() {
        document.redo()
        needsDisplay = true
        notifyDocumentChanged()
    }

    func markCurrentRenditionSaved() {
        document.markCurrentRenditionSaved()
        needsDisplay = true
        notifyDocumentChanged()
    }

    func commitActiveTextForTesting(_ text: String) {
        activeTextEditor?.string = text
        updateActiveTextElement(text)
        commitActiveText(text)
    }

    func editActiveTextForTesting(_ text: String) {
        activeTextEditor?.string = text
        updateActiveTextElement(text)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let drawRect = imageDrawRect
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        let mosaicSource = mosaicSourceIfNeeded()

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        let scaleX = drawRect.width / max(1, image.size.width)
        let scaleY = drawRect.height / max(1, image.size.height)
        transform.translateX(by: drawRect.minX, yBy: drawRect.minY)
        transform.scaleX(by: scaleX, yBy: scaleY)
        transform.concat()
        ImageAnnotationViewRenderer.draw(
            document: document,
            mosaicSource: mosaicSource,
            imageSize: image.size,
            excluding: activeTextEditor == nil ? nil : activeTextElementID
        )
        drawDraftIfNeeded(mosaicSource: mosaicSource)
        drawSelectionHandleIfNeeded()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if let activeTextEditor {
            let viewPoint = convert(event.locationInWindow, from: nil)
            if activeTextEditor.frame.contains(viewPoint) {
                return
            }
            commitActiveText(activeTextEditor.string)
        }

        guard let imagePoint = imagePoint(for: event) else {
            return
        }

        if document.selectedTool == .text {
            handleTextToolMouseDown(at: imagePoint, clickCount: event.clickCount)
            needsDisplay = true
            return
        }

        if shouldBeginSelectedElementInteraction(at: imagePoint) {
            beginSelectionInteraction(at: imagePoint, clickCount: event.clickCount)
            needsDisplay = true
            return
        }

        if shouldSelectExistingShapeOrMosaic(with: event, at: imagePoint) {
            beginSelectionInteraction(at: imagePoint, clickCount: event.clickCount)
            needsDisplay = true
            return
        }

        if shouldBeginPendingCreation {
            interaction = .pendingCreation(start: imagePoint)
            needsDisplay = true
            return
        }

        switch document.selectedTool {
        case .select:
            beginSelectionInteraction(at: imagePoint, clickCount: event.clickCount)
        case .shape:
            interaction = .creatingShape(start: imagePoint, current: imagePoint)
        case .brush:
            interaction = .drawingPoints(kind: .brush, points: [imagePoint])
        case .highlight:
            interaction = .drawingPoints(kind: .highlight, points: [imagePoint])
        case .mosaic:
            switch document.editingOptions.mosaicMode {
            case .rectangle:
                interaction = .creatingMosaic(start: imagePoint, current: imagePoint)
            case .brush:
                interaction = .drawingPoints(kind: .mosaic(.brush), points: [imagePoint])
            }
        case .text:
            break
        }

        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let imagePoint = imagePoint(for: event),
              let interaction else {
            return
        }

        switch interaction {
        case let .creatingShape(start, _):
            self.interaction = .creatingShape(
                start: start,
                current: constrainedShapePoint(start: start, current: imagePoint, modifierFlags: event.modifierFlags)
            )
        case let .creatingMosaic(start, _):
            self.interaction = .creatingMosaic(start: start, current: imagePoint)
        case let .drawingPoints(kind, points):
            self.interaction = .drawingPoints(kind: kind, points: points + [imagePoint])
        case let .moving(lastPoint, hasStartedMutation):
            if !hasStartedMutation {
                document.beginEditingSelectedElement()
            }
            document.moveSelected(
                by: CGSize(width: imagePoint.x - lastPoint.x, height: imagePoint.y - lastPoint.y),
                recordingUndo: false
            )
            self.interaction = .moving(lastPoint: imagePoint, hasStartedMutation: true)
            notifyDocumentChanged()
        case let .resizing(anchor, hasStartedMutation):
            if !hasStartedMutation {
                document.beginEditingSelectedElement()
            }
            let bounds = CGRect(
                x: anchor.x,
                y: anchor.y,
                width: imagePoint.x - anchor.x,
                height: imagePoint.y - anchor.y
            ).standardized
            document.resizeSelected(to: minimumAnnotationBounds(bounds), recordingUndo: false)
            self.interaction = .resizing(anchor: anchor, hasStartedMutation: true)
            notifyDocumentChanged()
        case let .pendingCreation(start):
            self.interaction = creationInteraction(start: start, current: imagePoint)
        }

        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let interaction else {
            return
        }

        switch interaction {
        case let .creatingShape(start, current):
            let shapeKind = document.editingOptions.shapeKind
            let finalPoint = constrainedShapePoint(start: start, current: current, modifierFlags: event.modifierFlags)
            addElement(
                kind: .shape(shapeKind),
                bounds: minimumAnnotationBounds(CGRect(
                    x: start.x,
                    y: start.y,
                    width: finalPoint.x - start.x,
                    height: finalPoint.y - start.y
                ).standardized),
                points: shapePoints(for: shapeKind, start: start, current: finalPoint)
            )
        case let .creatingMosaic(start, current):
            addElement(
                kind: .mosaic(.rectangle),
                bounds: minimumAnnotationBounds(CGRect(
                    x: start.x,
                    y: start.y,
                    width: current.x - start.x,
                    height: current.y - start.y
                ).standardized)
            )
        case let .drawingPoints(kind, points):
            guard !points.isEmpty else {
                break
            }

            let bounds = pointsBounds(points, radius: max(2, document.editingOptions.style.lineWidth))
            document.add(ImageAnnotationElement(
                kind: kind,
                bounds: bounds,
                points: points,
                style: document.editingOptions.style
            ))
            notifyDocumentChanged()
        case .moving, .resizing:
            break
        case .pendingCreation:
            document.selectElement(id: nil)
            notifyDocumentChanged()
            break
        }

        self.interaction = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "z" {
            if event.modifierFlags.contains(.shift) {
                redo()
            } else {
                undo()
            }
            return
        }

        if event.keyCode == 51 || event.keyCode == 117 || (event.keyCode == 53 && selectedElement != nil) {
            document.deleteSelected()
            needsDisplay = true
            notifyDocumentChanged()
            return
        }

        super.keyDown(with: event)
    }

    private var imageDrawRect: CGRect {
        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private var imageDisplayScale: CGFloat {
        imageDrawRect.width / max(1, image.size.width)
    }

    private func imagePoint(for event: NSEvent) -> CGPoint? {
        let point = convert(event.locationInWindow, from: nil)
        let drawRect = imageDrawRect
        guard drawRect.contains(point), drawRect.width > 0, drawRect.height > 0 else {
            return nil
        }

        let scaleX = image.size.width / drawRect.width
        let scaleY = image.size.height / drawRect.height
        return CGPoint(
            x: clamp((point.x - drawRect.minX) * scaleX, min: 0, max: image.size.width),
            y: clamp((point.y - drawRect.minY) * scaleY, min: 0, max: image.size.height)
        )
    }

    private func beginSelectionInteraction(at point: CGPoint, clickCount: Int) {
        document.selectTopmostElement(at: point, tolerance: 6)
        notifyDocumentChanged()

        if clickCount >= 2,
           let selectedElement = selectedElement,
           case let .text(text) = selectedElement.kind {
            beginTextEditing(elementID: selectedElement.id, origin: selectedElement.bounds.origin, initialText: text)
            return
        }

        guard let selectedElement else {
            interaction = nil
            return
        }

        if resizeHandleRect(for: selectedElement.bounds).contains(point) {
            interaction = .resizing(anchor: selectedElement.bounds.origin, hasStartedMutation: false)
        } else {
            interaction = .moving(lastPoint: point, hasStartedMutation: false)
        }
    }

    private var selectedElement: ImageAnnotationElement? {
        guard let selectedElementID = document.selectedElementID else {
            return nil
        }

        return document.elements.first { $0.id == selectedElementID }
    }

    private func shouldBeginSelectedElementInteraction(at point: CGPoint) -> Bool {
        switch document.selectedTool {
        case .select, .text:
            return false
        case .shape, .brush, .highlight, .mosaic:
            break
        }

        guard let selectedElement else {
            return false
        }

        return resizeHandleRect(for: selectedElement.bounds).contains(point)
            || document.topmostElementID(at: point, tolerance: 6) == selectedElement.id
    }

    private func shouldSelectExistingShapeOrMosaic(with event: NSEvent, at point: CGPoint) -> Bool {
        event.clickCount >= 2 && topmostShapeOrMosaicID(at: point) != nil
    }

    private var shouldBeginPendingCreation: Bool {
        switch document.selectedTool {
        case .shape, .brush, .highlight, .mosaic:
            return true
        case .select, .text:
            return false
        }
    }

    private func topmostShapeOrMosaicID(at point: CGPoint) -> UUID? {
        guard let elementID = document.topmostElementID(at: point, tolerance: 6),
              let element = document.elements.first(where: { $0.id == elementID }) else {
            return nil
        }

        switch element.kind {
        case .shape, .mosaic:
            return elementID
        case .brush, .highlight, .text:
            return nil
        }
    }

    private func handleTextToolMouseDown(at point: CGPoint, clickCount: Int) {
        if let textElementID = topmostTextElementID(at: point) {
            document.selectElement(id: textElementID)
            notifyDocumentChanged()

            if clickCount >= 2,
               let selectedElement,
               case let .text(text) = selectedElement.kind {
                beginTextEditing(elementID: selectedElement.id, origin: selectedElement.bounds.origin, initialText: text)
            }
            return
        }

        if selectedElementIsText {
            document.selectElement(id: nil)
            notifyDocumentChanged()
            return
        }

        beginTextEditing(elementID: nil, origin: point, initialText: "")
    }

    private var selectedElementIsText: Bool {
        guard let selectedElement else {
            return false
        }

        if case .text = selectedElement.kind {
            return true
        }

        return false
    }

    private func topmostTextElementID(at point: CGPoint) -> UUID? {
        guard let elementID = document.topmostElementID(at: point, tolerance: 6),
              let element = document.elements.first(where: { $0.id == elementID }) else {
            return nil
        }

        if case .text = element.kind {
            return elementID
        }

        return nil
    }

    private func creationInteraction(start: CGPoint, current: CGPoint) -> AnnotationInteraction {
        switch document.selectedTool {
        case .shape:
            return .creatingShape(start: start, current: current)
        case .mosaic:
            switch document.editingOptions.mosaicMode {
            case .rectangle:
                return .creatingMosaic(start: start, current: current)
            case .brush:
                return .drawingPoints(kind: .mosaic(.brush), points: [start, current])
            }
        case .brush:
            return .drawingPoints(kind: .brush, points: [start, current])
        case .highlight:
            return .drawingPoints(kind: .highlight, points: [start, current])
        case .select, .text:
            return .pendingCreation(start: start)
        }
    }

    private func beginTextEditing(elementID: UUID?, origin: CGPoint, initialText: String) {
        removeActiveTextEditor()

        let style: ImageAnnotationStyle
        let textBounds: CGRect
        let editingElementID: UUID
        if let elementID,
           let element = document.elements.first(where: { $0.id == elementID }) {
            document.selectElement(id: elementID)
            editingElementID = elementID
            style = element.style
            textBounds = element.bounds
            activeTextDidBeginMutation = false
        } else {
            style = document.editingOptions.style
            textBounds = ImageAnnotationTextStyle.bounds(for: initialText, origin: origin, style: style)
            let element = ImageAnnotationElement(
                kind: .text(initialText),
                bounds: textBounds,
                style: style
            )
            document.add(element)
            editingElementID = element.id
            activeTextDidBeginMutation = true
            notifyDocumentChanged()
        }

        activeTextElementID = editingElementID
        activeTextOrigin = textBounds.origin

        let editor = ImageAnnotationTextEditorView()
        editor.string = initialText
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
        editor.textColor = ImageAnnotationTextStyle.foregroundColor(for: style)
        editor.drawsBackground = false
        editor.backgroundColor = .clear
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = true
        editor.isRichText = false
        editor.allowsUndo = true
        editor.delegate = self
        editor.onCommit = { [weak self, weak editor] in
            guard let editor else {
                return
            }
            self?.commitActiveText(editor.string)
        }
        editor.onCancel = { [weak self] in
            self?.deleteActiveTextElement()
        }
        activeTextEditor = editor
        addSubview(editor)

        let frame = viewRect(forImageRect: textBounds)
        editor.frame = frame
        editor.textContainer?.containerSize = frame.size
        window?.makeFirstResponder(editor)
        needsDisplay = true
    }

    private func textEditingStyle(for elementID: UUID?) -> ImageAnnotationStyle {
        guard let elementID,
              let element = document.elements.first(where: { $0.id == elementID }) else {
            return document.editingOptions.style
        }

        return element.style
    }

    private func updateSelectedElementStyleIfNeeded(_ style: ImageAnnotationStyle) {
        if let activeTextElementID {
            document.selectElement(id: activeTextElementID)
        }

        guard let selectedElement else {
            activeTextEditor?.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
            activeTextEditor?.textColor = ImageAnnotationTextStyle.foregroundColor(for: style)
            needsDisplay = true
            return
        }

        let updatedBounds: CGRect?
        if case let .text(text) = selectedElement.kind {
            updatedBounds = ImageAnnotationTextStyle.bounds(
                for: text,
                origin: selectedElement.bounds.origin,
                style: style
            )
        } else {
            updatedBounds = nil
        }

        document.updateSelectedStyle(style, bounds: updatedBounds)

        if let activeTextEditor,
           selectedElement.id == activeTextElementID,
           let updatedBounds {
            activeTextEditor.font = ImageAnnotationTextStyle.font(for: style, scale: imageDisplayScale)
            activeTextEditor.textColor = ImageAnnotationTextStyle.foregroundColor(for: style)
            let frame = viewRect(forImageRect: updatedBounds)
            activeTextEditor.frame = frame
            activeTextEditor.textContainer?.containerSize = frame.size
            activeTextOrigin = updatedBounds.origin
            activeTextDidBeginMutation = true
        }

        needsDisplay = true
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === activeTextEditor else {
            return
        }

        updateActiveTextElement(activeTextEditor?.string ?? "")
    }

    private func commitActiveText(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedText.isEmpty {
            deleteActiveTextElement()
            return
        }

        if let textElementID = activeTextElementID {
            document.selectElement(id: textElementID)
            updateActiveTextElement(trimmedText)
            notifyDocumentChanged()
        }

        removeActiveTextEditor()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func updateActiveTextElement(_ text: String) {
        guard let textElementID = activeTextElementID,
              let origin = activeTextOrigin else {
            return
        }

        document.selectElement(id: textElementID)
        if !activeTextDidBeginMutation {
            document.beginEditingSelectedElement()
            activeTextDidBeginMutation = true
        }

        let style = textEditingStyle(for: textElementID)
        let bounds = ImageAnnotationTextStyle.bounds(for: text, origin: origin, style: style)
        document.updateSelectedText(text, bounds: bounds, recordingUndo: false)
        if let activeTextEditor {
            let frame = viewRect(forImageRect: bounds)
            activeTextEditor.frame = frame
            activeTextEditor.textContainer?.containerSize = frame.size
        }
        needsDisplay = true
        notifyDocumentChanged()
    }

    private func deleteActiveTextElement() {
        if let textElementID = activeTextElementID {
            document.selectElement(id: textElementID)
            document.deleteSelected()
            notifyDocumentChanged()
        }

        removeActiveTextEditor()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    private func removeActiveTextEditor() {
        activeTextEditor?.delegate = nil
        activeTextEditor?.onCommit = nil
        activeTextEditor?.onCancel = nil
        activeTextEditor?.removeFromSuperview()
        activeTextEditor = nil
        activeTextElementID = nil
        activeTextOrigin = nil
        activeTextDidBeginMutation = false
    }

    private func addElement(kind: ImageAnnotationElementKind, bounds: CGRect, points: [CGPoint] = []) {
        guard bounds.width >= 2, bounds.height >= 2 else {
            return
        }

        document.add(ImageAnnotationElement(
            kind: kind,
            bounds: bounds,
            points: points,
            style: document.editingOptions.style
        ))
        notifyDocumentChanged()
    }

    private func drawDraftIfNeeded(mosaicSource: ImageMosaicDrawingSource?) {
        guard let interaction else {
            return
        }

        switch interaction {
        case let .creatingShape(start, current):
            let shapeKind = document.editingOptions.shapeKind
            let element = ImageAnnotationElement(
                kind: .shape(shapeKind),
                bounds: minimumAnnotationBounds(CGRect(
                    x: start.x,
                    y: start.y,
                    width: current.x - start.x,
                    height: current.y - start.y
                ).standardized),
                points: shapePoints(for: shapeKind, start: start, current: current),
                style: document.editingOptions.style
            )
            ImageAnnotationViewRenderer.draw(element, mosaicSource: mosaicSource, imageSize: image.size)
        case let .creatingMosaic(start, current):
            drawMosaicSelectionDraft(in: minimumAnnotationBounds(CGRect(
                x: start.x,
                y: start.y,
                width: current.x - start.x,
                height: current.y - start.y
            ).standardized))
        case let .drawingPoints(kind, points):
            let element = ImageAnnotationElement(
                kind: kind,
                bounds: pointsBounds(points, radius: document.editingOptions.style.lineWidth),
                points: points,
                style: document.editingOptions.style
            )
            ImageAnnotationViewRenderer.draw(element, mosaicSource: mosaicSource, imageSize: image.size)
        case .moving, .resizing, .pendingCreation:
            break
        }
    }

    private func drawSelectionHandleIfNeeded() {
        guard let selectedElement else {
            return
        }

        let bounds = selectedElement.bounds
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: bounds)
        path.lineWidth = 1
        path.stroke()

        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: resizeHandleRect(for: bounds), xRadius: 2, yRadius: 2).fill()
    }

    private func drawMosaicSelectionDraft(in bounds: CGRect) {
        let path = NSBezierPath(rect: bounds.standardized)
        path.lineWidth = 1.5
        path.setLineDash([5, 3], count: 2, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()

        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        NSBezierPath(rect: bounds.standardized).fill()
    }

    private func resizeHandleRect(for bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - 5, y: bounds.maxY - 5, width: 10, height: 10)
    }

    private func viewRect(forImageRect imageRect: CGRect) -> CGRect {
        let drawRect = imageDrawRect
        let scaleX = drawRect.width / max(1, image.size.width)
        let scaleY = drawRect.height / max(1, image.size.height)
        return CGRect(
            x: drawRect.minX + imageRect.minX * scaleX,
            y: drawRect.minY + imageRect.minY * scaleY,
            width: imageRect.width * scaleX,
            height: imageRect.height * scaleY
        )
    }

    private func pointsBounds(_ points: [CGPoint], radius: CGFloat) -> CGRect {
        guard let first = points.first else {
            return .zero
        }

        let rect = points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { partialResult, point in
            partialResult.union(CGRect(origin: point, size: .zero))
        }
        return rect.insetBy(dx: -radius, dy: -radius).standardized
    }

    private func shapePoints(for shapeKind: ImageAnnotationShapeKind, start: CGPoint, current: CGPoint) -> [CGPoint] {
        switch shapeKind {
        case .line, .arrow:
            return [start, current]
        case .rectangle, .ellipse:
            return []
        }
    }

    private func constrainedShapePoint(
        start: CGPoint,
        current: CGPoint,
        modifierFlags: NSEvent.ModifierFlags
    ) -> CGPoint {
        guard modifierFlags.contains(.shift) else {
            return current
        }

        switch document.editingOptions.shapeKind {
        case .rectangle, .ellipse:
            let deltaX = current.x - start.x
            let deltaY = current.y - start.y
            let side = max(abs(deltaX), abs(deltaY))
            return CGPoint(
                x: start.x + (deltaX < 0 ? -side : side),
                y: start.y + (deltaY < 0 ? -side : side)
            )
        case .line, .arrow:
            return snappedLinePoint(start: start, current: current)
        }
    }

    private func snappedLinePoint(start: CGPoint, current: CGPoint) -> CGPoint {
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y
        let absoluteX = abs(deltaX)
        let absoluteY = abs(deltaY)
        guard absoluteX > 0 || absoluteY > 0 else {
            return current
        }

        let axisThreshold = CGFloat(tan(Double.pi / 8))
        if absoluteY <= absoluteX * axisThreshold {
            return CGPoint(x: current.x, y: start.y)
        }
        if absoluteX <= absoluteY * axisThreshold {
            return CGPoint(x: start.x, y: current.y)
        }

        let side = max(absoluteX, absoluteY)
        return CGPoint(
            x: start.x + (deltaX < 0 ? -side : side),
            y: start.y + (deltaY < 0 ? -side : side)
        )
    }

    private func minimumAnnotationBounds(_ bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(2, bounds.width),
            height: max(2, bounds.height)
        )
    }

    private func notifyDocumentChanged() {
        onDocumentChange(document)
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private func mosaicSourceIfNeeded() -> ImageMosaicDrawingSource? {
        guard document.containsMosaicElements || interaction?.requiresMosaicRendering == true else {
            return nil
        }

        if let mosaicDrawingSource {
            return mosaicDrawingSource
        }

        let source = ImageMosaicDrawingSource(sourceImage: image, imageSize: image.size)
        mosaicDrawingSource = source
        return source
    }
}

private enum AnnotationInteraction {
    case creatingShape(start: CGPoint, current: CGPoint)
    case creatingMosaic(start: CGPoint, current: CGPoint)
    case drawingPoints(kind: ImageAnnotationElementKind, points: [CGPoint])
    case moving(lastPoint: CGPoint, hasStartedMutation: Bool)
    case resizing(anchor: CGPoint, hasStartedMutation: Bool)
    case pendingCreation(start: CGPoint)

    var requiresMosaicRendering: Bool {
        switch self {
        case .creatingMosaic:
            return false
        case let .drawingPoints(kind, _):
            if case .mosaic = kind {
                return true
            }

            return false
        case .creatingShape, .moving, .resizing, .pendingCreation:
            return false
        }
    }
}

private final class ImageAnnotationTextEditorView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        if event.keyCode == 36, event.modifierFlags.contains(.command) {
            onCommit?()
            return
        }

        super.keyDown(with: event)
    }
}

enum ImageAnnotationViewRenderer {
    static func draw(
        document: ImageAnnotationDocument,
        mosaicSource: ImageMosaicDrawingSource? = nil,
        imageSize: CGSize = .zero,
        excluding excludedElementID: UUID? = nil
    ) {
        for element in document.elements {
            if element.id == excludedElementID {
                continue
            }
            draw(element, mosaicSource: mosaicSource, imageSize: imageSize)
        }
    }

    static func draw(
        _ element: ImageAnnotationElement,
        mosaicSource: ImageMosaicDrawingSource? = nil,
        imageSize: CGSize = .zero
    ) {
        switch element.kind {
        case let .shape(kind):
            drawShape(element, kind: kind)
        case .brush:
            drawStroke(element.points, style: element.style, alpha: 1)
        case let .text(text):
            drawText(text, in: element.bounds, style: element.style)
        case let .mosaic(mode):
            ImageMosaicDrawing.draw(
                element,
                mode: mode,
                source: mosaicSource,
                imageSize: imageSize
            )
        case .highlight:
            drawStroke(element.points, style: element.style, alpha: 0.42)
        }
    }

    private static func drawShape(_ element: ImageAnnotationElement, kind: ImageAnnotationShapeKind) {
        ImageAnnotationShapeDrawing.draw(element, kind: kind)
    }

    private static func drawStroke(_ points: [CGPoint], style: ImageAnnotationStyle, alpha: Double) {
        guard let first = points.first else {
            return
        }

        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = max(1, style.lineWidth)
        path.move(to: first)
        for point in points.dropFirst() {
            path.line(to: point)
        }
        style.strokeColor.withAlpha(style.strokeColor.alpha * alpha).nsColor.setStroke()
        path.stroke()
    }

    private static func drawText(_ text: String, in bounds: CGRect, style: ImageAnnotationStyle) {
        text.draw(
            in: bounds.standardized,
            withAttributes: ImageAnnotationTextStyle.attributes(for: style)
        )
    }

}

extension ImageAnnotationColor {
    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
