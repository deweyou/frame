import CoreGraphics

public enum SelectionGeometry {
    public static let minimumSelectionSize: CGFloat = 8

    public static func normalizedRect(from startPoint: CGPoint, to endPoint: CGPoint) -> CGRect {
        let minX = min(startPoint.x, endPoint.x)
        let minY = min(startPoint.y, endPoint.y)
        let width = abs(endPoint.x - startPoint.x)
        let height = abs(endPoint.y - startPoint.y)

        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    public static func isValidSelection(_ rect: CGRect) -> Bool {
        rect.width >= minimumSelectionSize && rect.height >= minimumSelectionSize
    }
}
