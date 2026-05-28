import Foundation

public enum ImageWorkspaceKind: Sendable, Equatable {
    case temporaryPreview
    case pinned
}

public enum ImageWorkspaceClosePolicy: Sendable, Equatable {
    case escapeOrExplicitClose
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
            .escapeOrExplicitClose
        case .pinned:
            .explicitCloseOnly
        }
    }

    public mutating func select(_ tool: ImageEditingTool) {
        selectedTool = tool
    }
}
