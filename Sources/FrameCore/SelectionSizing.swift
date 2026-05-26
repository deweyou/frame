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
           size.width > bounds.width || size.height > bounds.height {
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
