import AppKit
import FrameCore

enum ImageAnnotationShapeDrawing {
    static func draw(_ element: ImageAnnotationElement, kind: ImageAnnotationShapeKind) {
        switch kind {
        case .rectangle:
            drawRectangularShape(element, kind: kind)
        case .ellipse:
            drawRectangularShape(element, kind: kind)
        case .line:
            drawLine(element)
        case .arrow:
            drawArrow(element)
        }
    }

    private static func drawRectangularShape(_ element: ImageAnnotationElement, kind: ImageAnnotationShapeKind) {
        let bounds = element.bounds.standardized
        let path: NSBezierPath
        switch kind {
        case .rectangle:
            path = NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3)
        case .ellipse:
            path = NSBezierPath(ovalIn: bounds)
        case .line, .arrow:
            return
        }

        if let fillColor = element.style.fillColor {
            fillColor.nsColor.setFill()
            path.fill()
        }
        path.lineWidth = max(1, element.style.lineWidth)
        element.style.strokeColor.nsColor.setStroke()
        path.stroke()
    }

    private static func drawLine(_ element: ImageAnnotationElement) {
        let endpoints = lineEndpoints(for: element)
        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: endpoints.start)
        path.line(to: endpoints.end)
        path.lineWidth = max(1, element.style.lineWidth)
        element.style.strokeColor.nsColor.setStroke()
        path.stroke()
    }

    private static func drawArrow(_ element: ImageAnnotationElement) {
        let endpoints = lineEndpoints(for: element)
        guard let arrowPath = wedgeArrowPath(from: endpoints.start, to: endpoints.end, style: element.style) else {
            return
        }

        element.style.strokeColor.nsColor.setStroke()
        element.style.strokeColor.nsColor.setFill()
        arrowPath.fill()
    }

    private static func lineEndpoints(for element: ImageAnnotationElement) -> (start: CGPoint, end: CGPoint) {
        if element.points.count >= 2 {
            return (element.points[0], element.points[1])
        }

        let bounds = element.bounds.standardized
        return (bounds.origin, CGPoint(x: bounds.maxX, y: bounds.maxY))
    }

    private static func wedgeArrowPath(
        from start: CGPoint,
        to end: CGPoint,
        style: ImageAnnotationStyle
    ) -> NSBezierPath? {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let length = hypot(deltaX, deltaY)
        guard length > 1 else {
            return nil
        }

        let direction = CGVector(dx: deltaX / length, dy: deltaY / length)
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let styleWidth = max(1, style.lineWidth)
        let neckWidth = min(max(8, styleWidth * 3.2), max(8, length * 0.14))
        let headWidth = min(
            max(neckWidth + styleWidth * 3.6, styleWidth * 6.4),
            max(neckWidth + styleWidth * 1.8, length * 0.26)
        )
        let preferredHeadLength = max(max(18, styleWidth * 4.8), headWidth * 0.92)
        let headLength = min(preferredHeadLength, max(12, length * 0.26))
        let neckCenter = offset(end, direction: direction, normal: normal, forward: -headLength, side: 0)

        let neckLeft = offset(neckCenter, direction: direction, normal: normal, forward: 0, side: neckWidth / 2)
        let neckRight = offset(neckCenter, direction: direction, normal: normal, forward: 0, side: -neckWidth / 2)
        let wingLeft = offset(neckCenter, direction: direction, normal: normal, forward: 0, side: headWidth / 2)
        let wingRight = offset(neckCenter, direction: direction, normal: normal, forward: 0, side: -headWidth / 2)

        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: neckLeft)
        path.line(to: wingLeft)
        path.line(to: end)
        path.line(to: wingRight)
        path.line(to: neckRight)
        path.close()
        return path
    }

    private static func offset(
        _ point: CGPoint,
        direction: CGVector,
        normal: CGVector,
        forward: CGFloat,
        side: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: point.x + direction.dx * forward + normal.dx * side,
            y: point.y + direction.dy * forward + normal.dy * side
        )
    }
}
