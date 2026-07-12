import Foundation

public enum ImageWorkspaceKind: Sendable, Equatable {
    case temporaryPreview
    case pinned
}

public enum ImageWorkspaceClosePolicy: Sendable, Equatable {
    case escapeOrExplicitClose
    case explicitCloseOnly
}

public enum ImageWorkspaceSaveCurrentBehavior: String, CaseIterable, Sendable, Equatable {
    case askEveryTime
    case replaceCurrent
    case saveAsNew

    public static let defaultBehavior: ImageWorkspaceSaveCurrentBehavior = .replaceCurrent
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
    public private(set) var selectedTool: ImageAnnotationTool?

    public init(kind: ImageWorkspaceKind, selectedTool: ImageAnnotationTool? = .select) {
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

    public mutating func select(_ tool: ImageAnnotationTool) {
        selectedTool = tool
    }
}
