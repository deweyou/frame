import AppKit
import CoreGraphics
import FrameCore

@MainActor
struct WindowCandidateProvider {
    private let currentProcessID: pid_t
    private let minimumCandidateSize = CGSize(width: 48, height: 48)
    private let windowInfoProvider: (CGWindowListOption, CGWindowID) -> [[String: Any]]

    init(
        currentProcessID: pid_t = pid_t(ProcessInfo.processInfo.processIdentifier),
        windowInfoProvider: @escaping (CGWindowListOption, CGWindowID) -> [[String: Any]] = { options, relativeToWindow in
            CGWindowListCopyWindowInfo(options, relativeToWindow) as? [[String: Any]] ?? []
        }
    ) {
        self.currentProcessID = currentProcessID
        self.windowInfoProvider = windowInfoProvider
    }

    func candidate(at point: CGPoint, belowWindowNumber: Int? = nil) -> WindowCandidate? {
        let preferredLookup = lookupCandidate(at: point, belowWindowNumber: belowWindowNumber)
        if let candidate = preferredLookup.candidate {
            return candidate
        }

        let fallbackLookup = belowWindowNumber == nil ? preferredLookup : lookupCandidate(at: point, belowWindowNumber: nil)
        return fallbackLookup.candidate
    }

    func candidate(id: UInt32) -> WindowCandidate? {
        windowInfos(belowWindowNumber: nil)
            .compactMap(candidate(from:))
            .first { $0.id == id }
    }

    private func lookupCandidate(
        at point: CGPoint,
        belowWindowNumber: Int?
    ) -> (rawCount: Int, candidates: [WindowCandidate], candidate: WindowCandidate?) {
        let infos = windowInfos(belowWindowNumber: belowWindowNumber)
        let candidates = infos.compactMap(candidate(from:))
        return (infos.count, candidates, candidates.first { $0.bounds.contains(point) })
    }

    private func windowInfos(belowWindowNumber: Int?) -> [[String: Any]] {
        if let belowWindowNumber,
           belowWindowNumber > 0 {
            return windowInfoProvider(.optionOnScreenBelowWindow, CGWindowID(belowWindowNumber))
        }

        return windowInfoProvider(.optionOnScreenOnly, kCGNullWindowID)
    }

    private func candidate(from windowInfo: [String: Any]) -> WindowCandidate? {
        guard let ownerProcessID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
              isSelectableWindow(ownerProcessID: ownerProcessID, windowInfo: windowInfo),
              let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue,
              layer == 0,
              let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
              alpha > 0,
              let sharingState = (windowInfo[kCGWindowSharingState as String] as? NSNumber)?.intValue,
              sharingState != 0,
              let rect = Self.cocoaRect(forWindowInfo: windowInfo),
              rect.width >= minimumCandidateSize.width,
              rect.height >= minimumCandidateSize.height else {
            return nil
        }

        return WindowCandidate(id: windowID, ownerProcessID: ownerProcessID, bounds: rect)
    }

    private func isSelectableWindow(ownerProcessID: pid_t, windowInfo: [String: Any]) -> Bool {
        guard ownerProcessID == currentProcessID else {
            return true
        }

        guard let windowName = windowInfo[kCGWindowName as String] as? String,
              !windowName.isEmpty else {
            return true
        }

        return !Self.transientCurrentProcessWindowNames.contains(windowName)
    }

    private static let transientCurrentProcessWindowNames: Set<String> = [
        QuickAccessPanelController.previewWindowTitle,
        QuickAccessPanelController.hoverPreviewWindowTitle,
    ]

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
        let screenMappings = NSScreen.screens.compactMap { screen -> ScreenCoordinateMapping? in
            guard let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            return ScreenCoordinateMapping(
                cocoaFrame: screen.frame,
                quartzFrame: CGDisplayBounds(CGDirectDisplayID(displayNumber.uint32Value))
            )
        }

        return cocoaRect(fromQuartzWindowRect: quartzRect, screenMappings: screenMappings)
    }

    static func cocoaRect(
        fromQuartzWindowRect quartzRect: CGRect,
        screenMappings: [ScreenCoordinateMapping]
    ) -> CGRect {
        guard let mapping = screenMappings
            .max(by: { first, second in
                intersectionArea(first.quartzFrame, quartzRect) < intersectionArea(second.quartzFrame, quartzRect)
            }) else {
            return quartzRect
        }

        let localMinX = quartzRect.minX - mapping.quartzFrame.minX
        let localMaxY = quartzRect.maxY - mapping.quartzFrame.minY
        return CGRect(
            x: mapping.cocoaFrame.minX + localMinX,
            y: mapping.cocoaFrame.maxY - localMaxY,
            width: quartzRect.width,
            height: quartzRect.height
        )
    }

    private static func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }
}

struct ScreenCoordinateMapping {
    let cocoaFrame: CGRect
    let quartzFrame: CGRect
}
