import CoreGraphics
import Foundation

public enum ImageAnnotationTool: CaseIterable, Sendable, Equatable {
    case select
    case shape
    case brush
    case text
    case mosaic
    case highlight
}

public enum ImageAnnotationShapeKind: CaseIterable, Sendable, Equatable {
    case rectangle
    case ellipse
    case line
    case arrow
}

public enum ImageAnnotationMosaicMode: CaseIterable, Sendable, Equatable {
    case rectangle
    case brush
}

public enum ImageAnnotationFontWeight: Sendable, Equatable {
    case regular
    case bold
}

public struct ImageAnnotationColor: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = ImageAnnotationColor(red: 1, green: 0.231, blue: 0.188)
    public static let yellow = ImageAnnotationColor(red: 1, green: 0.8, blue: 0)
    public static let blue = ImageAnnotationColor(red: 0.039, green: 0.518, blue: 1)
    public static let green = ImageAnnotationColor(red: 0.204, green: 0.78, blue: 0.349)
    public static let white = ImageAnnotationColor(red: 1, green: 1, blue: 1)
    public static let black = ImageAnnotationColor(red: 0, green: 0, blue: 0)

    public func withAlpha(_ alpha: Double) -> ImageAnnotationColor {
        ImageAnnotationColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public struct ImageAnnotationStyle: Sendable, Equatable {
    public var strokeColor: ImageAnnotationColor
    public var fillColor: ImageAnnotationColor?
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    public var fontWeight: ImageAnnotationFontWeight
    public var mosaicBlockSize: CGFloat
    public var mosaicStrength: CGFloat

    public init(
        strokeColor: ImageAnnotationColor,
        fillColor: ImageAnnotationColor? = nil,
        lineWidth: CGFloat,
        fontSize: CGFloat,
        fontWeight: ImageAnnotationFontWeight,
        mosaicBlockSize: CGFloat,
        mosaicStrength: CGFloat
    ) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.mosaicBlockSize = mosaicBlockSize
        self.mosaicStrength = mosaicStrength
    }

    public static let `default` = ImageAnnotationStyle(
        strokeColor: .red,
        fillColor: nil,
        lineWidth: 4,
        fontSize: 16,
        fontWeight: .regular,
        mosaicBlockSize: 20,
        mosaicStrength: 0.82
    )
}

public enum ImageAnnotationElementKind: Sendable, Equatable {
    case shape(ImageAnnotationShapeKind)
    case brush
    case text(String)
    case mosaic(ImageAnnotationMosaicMode)
    case highlight
}

public struct ImageAnnotationElement: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var kind: ImageAnnotationElementKind
    public var bounds: CGRect
    public var points: [CGPoint]
    public var style: ImageAnnotationStyle

    public init(
        id: UUID = UUID(),
        kind: ImageAnnotationElementKind,
        bounds: CGRect,
        points: [CGPoint] = [],
        style: ImageAnnotationStyle
    ) {
        self.id = id
        self.kind = kind
        self.bounds = bounds.standardized
        self.points = points
        self.style = style
    }
}

public struct ImageAnnotationEditingOptions: Sendable, Equatable {
    public var shapeKind: ImageAnnotationShapeKind
    public var mosaicMode: ImageAnnotationMosaicMode
    public var style: ImageAnnotationStyle

    public init(
        shapeKind: ImageAnnotationShapeKind = .rectangle,
        mosaicMode: ImageAnnotationMosaicMode = .rectangle,
        style: ImageAnnotationStyle = .default
    ) {
        self.shapeKind = shapeKind
        self.mosaicMode = mosaicMode
        self.style = style
    }
}

public struct ImageAnnotationDocument: Sendable, Equatable {
    public private(set) var elements: [ImageAnnotationElement]
    public private(set) var selectedElementID: UUID?
    public private(set) var selectedTool: ImageAnnotationTool
    public private(set) var editingOptions: ImageAnnotationEditingOptions
    public private(set) var hasUncommittedEdits: Bool

    private var undoStack: [ImageAnnotationSnapshot]
    private var redoStack: [ImageAnnotationSnapshot]

    public init(
        elements: [ImageAnnotationElement] = [],
        selectedElementID: UUID? = nil,
        selectedTool: ImageAnnotationTool = .select,
        editingOptions: ImageAnnotationEditingOptions = ImageAnnotationEditingOptions(),
        hasUncommittedEdits: Bool = false
    ) {
        self.elements = elements
        self.selectedElementID = selectedElementID
        self.selectedTool = selectedTool
        self.editingOptions = editingOptions
        self.hasUncommittedEdits = hasUncommittedEdits
        undoStack = []
        redoStack = []
    }

    public var canUndo: Bool {
        !undoStack.isEmpty
    }

    public var canRedo: Bool {
        !redoStack.isEmpty
    }

    public mutating func selectTool(_ tool: ImageAnnotationTool) {
        selectedTool = tool
    }

    public mutating func setShapeKind(_ shapeKind: ImageAnnotationShapeKind) {
        editingOptions.shapeKind = shapeKind
    }

    public mutating func setMosaicMode(_ mosaicMode: ImageAnnotationMosaicMode) {
        editingOptions.mosaicMode = mosaicMode
    }

    public mutating func setStyle(_ style: ImageAnnotationStyle) {
        editingOptions.style = style
    }

    public mutating func add(_ element: ImageAnnotationElement) {
        pushUndoSnapshot()
        elements.append(element)
        selectedElementID = element.id
        markChanged()
    }

    public mutating func selectElement(id: UUID?) {
        selectedElementID = id
    }

    public mutating func selectTopmostElement(at point: CGPoint, tolerance: CGFloat = 4) {
        selectedElementID = topmostElementID(at: point, tolerance: tolerance)
    }

    public func topmostElementID(at point: CGPoint, tolerance: CGFloat = 4) -> UUID? {
        elements.reversed().first { element in
            element.contains(point, tolerance: tolerance)
        }?.id
    }

    public mutating func beginEditingSelectedElement() {
        guard selectedIndex != nil else {
            return
        }

        pushUndoSnapshot()
    }

    public mutating func moveSelected(by delta: CGSize, recordingUndo: Bool = true) {
        guard let selectedIndex else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        elements[selectedIndex].bounds = elements[selectedIndex].bounds.offsetBy(dx: delta.width, dy: delta.height)
        elements[selectedIndex].points = elements[selectedIndex].points.map {
            CGPoint(x: $0.x + delta.width, y: $0.y + delta.height)
        }
        markChanged()
    }

    public mutating func resizeSelected(to bounds: CGRect, recordingUndo: Bool = true) {
        guard let selectedIndex else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        elements[selectedIndex].bounds = bounds.standardized
        markChanged()
    }

    public mutating func replaceSelectedText(_ text: String) {
        guard let selectedIndex,
              case .text = elements[selectedIndex].kind else {
            return
        }

        pushUndoSnapshot()
        elements[selectedIndex].kind = .text(text)
        markChanged()
    }

    public mutating func updateSelectedText(_ text: String, bounds: CGRect, recordingUndo: Bool = true) {
        guard let selectedIndex,
              case .text = elements[selectedIndex].kind else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        elements[selectedIndex].kind = .text(text)
        elements[selectedIndex].bounds = bounds.standardized
        markChanged()
    }

    public mutating func updateSelectedStyle(
        _ style: ImageAnnotationStyle,
        bounds: CGRect? = nil,
        recordingUndo: Bool = true
    ) {
        guard let selectedIndex else {
            return
        }

        if recordingUndo {
            pushUndoSnapshot()
        }
        editingOptions.style = style
        elements[selectedIndex].style = style
        if let bounds {
            elements[selectedIndex].bounds = bounds.standardized
        }
        markChanged()
    }

    public mutating func deleteSelected() {
        guard let selectedElementID,
              elements.contains(where: { $0.id == selectedElementID }) else {
            return
        }

        pushUndoSnapshot()
        elements.removeAll { $0.id == selectedElementID }
        self.selectedElementID = nil
        markChanged()
    }

    public mutating func undo() {
        guard let snapshot = undoStack.popLast() else {
            return
        }

        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    public mutating func redo() {
        guard let snapshot = redoStack.popLast() else {
            return
        }

        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    public mutating func markCurrentRenditionSaved() {
        elements.removeAll()
        selectedElementID = nil
        undoStack.removeAll()
        redoStack.removeAll()
        hasUncommittedEdits = false
    }

    private var selectedIndex: Int? {
        guard let selectedElementID else {
            return nil
        }

        return elements.firstIndex { $0.id == selectedElementID }
    }

    private var currentSnapshot: ImageAnnotationSnapshot {
        ImageAnnotationSnapshot(
            elements: elements,
            selectedElementID: selectedElementID,
            hasUncommittedEdits: hasUncommittedEdits
        )
    }

    private mutating func pushUndoSnapshot() {
        undoStack.append(currentSnapshot)
        redoStack.removeAll()
    }

    private mutating func markChanged() {
        hasUncommittedEdits = true
    }

    private mutating func restore(_ snapshot: ImageAnnotationSnapshot) {
        elements = snapshot.elements
        selectedElementID = snapshot.selectedElementID
        hasUncommittedEdits = snapshot.hasUncommittedEdits
    }
}

private struct ImageAnnotationSnapshot: Sendable, Equatable {
    let elements: [ImageAnnotationElement]
    let selectedElementID: UUID?
    let hasUncommittedEdits: Bool
}

private extension ImageAnnotationElement {
    func contains(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch kind {
        case let .shape(shapeKind):
            if shapeKind == .line || shapeKind == .arrow {
                return bounds.insetBy(dx: -max(tolerance, style.lineWidth), dy: -max(tolerance, style.lineWidth))
                    .contains(point)
            }

            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .brush, .highlight:
            let hitRadius = max(tolerance, style.lineWidth / 2)
            return points.contains { $0.distance(to: point) <= hitRadius }
                || bounds.insetBy(dx: -hitRadius, dy: -hitRadius).contains(point)
        case .text, .mosaic:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
}

private extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        hypot(x - point.x, y - point.y)
    }
}
