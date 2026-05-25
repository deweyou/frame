import AppKit
import CoreGraphics

@MainActor
enum ActiveScreenResolver {
    static func preferredQuickAccessAnchor() -> CGRect? {
        frontmostWindowRect()
            ?? mouseScreen()?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
    }

    static func preferredQuickAccessFollowAnchor() -> CGRect? {
        mouseScreen()?.visibleFrame
            ?? frontmostWindowRect()
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
    }

    private static func frontmostWindowRect() -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return nil
        }

        let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
        let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let layerZeroWindows = windowList.filter { windowInfo in
            guard let ownerProcessID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerProcessID != currentProcessID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat else {
                return false
            }

            return width > 1 && height > 1
        }

        if let frontmostProcessID,
           let frontmostWindow = layerZeroWindows
               .first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == frontmostProcessID }),
           let rect = cocoaRect(forWindowInfo: frontmostWindow) {
            return rect
        }

        return layerZeroWindows.compactMap(cocoaRect(forWindowInfo:)).first
    }

    private static func cocoaRect(forWindowInfo windowInfo: [String: Any]) -> CGRect? {
        guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat else {
            return nil
        }

        let quartzRect = CGRect(x: x, y: y, width: width, height: height)
        return cocoaRect(fromQuartzWindowRect: quartzRect)
    }

    private static func cocoaRect(fromQuartzWindowRect quartzRect: CGRect) -> CGRect {
        let screenUnion = NSScreen.screens.reduce(CGRect.null) { union, screen in
            union.union(screen.frame)
        }

        guard !screenUnion.isNull else {
            return quartzRect
        }

        return CGRect(
            x: quartzRect.minX,
            y: screenUnion.maxY - quartzRect.maxY + screenUnion.minY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    private static func mouseScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}
