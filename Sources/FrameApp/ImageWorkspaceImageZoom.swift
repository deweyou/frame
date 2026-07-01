import AppKit

@MainActor
final class ImageWorkspaceImageZoom {
    private static let minimumScale: CGFloat = 1
    private static let maximumScale: CGFloat = 6

    var onViewportChange: (() -> Void)?
    private(set) var scale: CGFloat = 1
    private var contentOffset: CGPoint = .zero

    @discardableResult
    func applyMagnification(
        _ magnification: CGFloat,
        imageSize: CGSize,
        bounds: CGRect
    ) -> Bool {
        let factor = max(0.05, 1 + magnification)
        let updatedScale = Self.clamp(scale * factor, min: Self.minimumScale, max: Self.maximumScale)
        guard abs(updatedScale - scale) > 0.0001 else {
            return false
        }

        scale = updatedScale
        contentOffset = clampedOffset(contentOffset, imageSize: imageSize, bounds: bounds)
        onViewportChange?()
        return true
    }

    @discardableResult
    func applyScroll(
        delta: CGSize,
        imageSize: CGSize,
        bounds: CGRect
    ) -> Bool {
        guard scale > Self.minimumScale else {
            return false
        }

        let updatedOffset = clampedOffset(
            CGPoint(
                x: contentOffset.x + delta.width,
                y: contentOffset.y - delta.height
            ),
            imageSize: imageSize,
            bounds: bounds
        )
        guard distance(from: updatedOffset, to: contentOffset) > 0.0001 else {
            return false
        }

        contentOffset = updatedOffset
        onViewportChange?()
        return true
    }

    func drawRect(imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return bounds
        }

        let baseScale = baseScale(imageSize: imageSize, bounds: bounds)
        let drawSize = CGSize(
            width: imageSize.width * baseScale * scale,
            height: imageSize.height * baseScale * scale
        )
        let offset = clampedOffset(contentOffset, imageSize: imageSize, bounds: bounds)
        return CGRect(
            x: bounds.midX - drawSize.width / 2 + offset.x,
            y: bounds.midY - drawSize.height / 2 + offset.y,
            width: drawSize.width,
            height: drawSize.height
        )
    }

    private func clampedOffset(_ offset: CGPoint, imageSize: CGSize, bounds: CGRect) -> CGPoint {
        let drawSize = scaledImageSize(imageSize: imageSize, bounds: bounds)
        let maximumHorizontalOffset = max(0, (drawSize.width - bounds.width) / 2)
        let maximumVerticalOffset = max(0, (drawSize.height - bounds.height) / 2)
        return CGPoint(
            x: Self.clamp(offset.x, min: -maximumHorizontalOffset, max: maximumHorizontalOffset),
            y: Self.clamp(offset.y, min: -maximumVerticalOffset, max: maximumVerticalOffset)
        )
    }

    private func scaledImageSize(imageSize: CGSize, bounds: CGRect) -> CGSize {
        guard imageSize.width > 0,
              imageSize.height > 0,
              bounds.width > 0,
              bounds.height > 0 else {
            return .zero
        }

        let baseScale = baseScale(imageSize: imageSize, bounds: bounds)
        return CGSize(
            width: imageSize.width * baseScale * scale,
            height: imageSize.height * baseScale * scale
        )
    }

    private func baseScale(imageSize: CGSize, bounds: CGRect) -> CGFloat {
        min(1, bounds.width / imageSize.width, bounds.height / imageSize.height)
    }

    private func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        Swift.max(minValue, Swift.min(maxValue, value))
    }
}

@MainActor
protocol ImageWorkspaceZoomableImageSurfaceForTesting: AnyObject {
    var lastDrawRectForTesting: CGRect { get }
}
