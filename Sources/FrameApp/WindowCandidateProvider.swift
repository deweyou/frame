import AppKit
import CoreGraphics
import FrameCore

@MainActor
struct WindowCandidateProvider {
    private let currentProcessID = pid_t(ProcessInfo.processInfo.processIdentifier)
    private let minimumCandidateSize = CGSize(width: 48, height: 48)

    func candidate(at point: CGPoint) -> WindowCandidate? {
        windowInfos()
            .compactMap(candidate(from:))
            .first { $0.bounds.contains(point) }
    }

    private func windowInfos() -> [[String: Any]] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        return windowList
    }

    private func candidate(from windowInfo: [String: Any]) -> WindowCandidate? {
        guard let ownerProcessID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              ownerProcessID != currentProcessID,
              let layer = windowInfo[kCGWindowLayer as String] as? Int,
              layer == 0,
              let windowID = windowInfo[kCGWindowNumber as String] as? UInt32,
              let alpha = windowInfo[kCGWindowAlpha as String] as? Double,
              alpha > 0,
              let sharingState = windowInfo[kCGWindowSharingState as String] as? Int,
              sharingState != 0,
              let rect = Self.cocoaRect(forWindowInfo: windowInfo),
              rect.width >= minimumCandidateSize.width,
              rect.height >= minimumCandidateSize.height else {
            return nil
        }

        return WindowCandidate(id: windowID, ownerProcessID: ownerProcessID, bounds: rect)
    }

    static func cocoaRect(forWindowInfo windowInfo: [String: Any]) -> CGRect? {
        guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat,
              width > 0,
              height > 0 else {
            return nil
        }

        return cocoaRect(fromQuartzWindowRect: CGRect(x: x, y: y, width: width, height: height))
    }

    static func cocoaRect(fromQuartzWindowRect quartzRect: CGRect) -> CGRect {
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
}
