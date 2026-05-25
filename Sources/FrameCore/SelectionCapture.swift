import CoreGraphics

public enum SelectionCaptureKind: Equatable {
    case region
    case window(id: UInt32)
}

public struct SelectionCapture: Equatable {
    public let rect: CGRect
    public let kind: SelectionCaptureKind

    public init(rect: CGRect, kind: SelectionCaptureKind) {
        self.rect = rect
        self.kind = kind
    }
}
