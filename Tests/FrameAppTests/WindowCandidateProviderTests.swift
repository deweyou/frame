import CoreGraphics
import XCTest
@testable import FrameApp

@MainActor
final class WindowCandidateProviderTests: XCTestCase {
    func testCandidateLookupUsesBelowOverlayWindowWhenProvided() {
        var requestedOptions: CGWindowListOption?
        var requestedWindowID: CGWindowID?
        let quartzBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let expectedCocoaBounds = WindowCandidateProvider.cocoaRect(fromQuartzWindowRect: quartzBounds)
        let provider = WindowCandidateProvider(
            currentProcessID: 100,
            windowInfoProvider: { options, windowID in
                requestedOptions = options
                requestedWindowID = windowID
                return [Self.windowInfo(
                    windowID: 42,
                    ownerProcessID: 200,
                    bounds: quartzBounds
                )]
            }
        )

        let candidate = provider.candidate(at: CGPoint(x: expectedCocoaBounds.midX, y: expectedCocoaBounds.midY), belowWindowNumber: 99)

        XCTAssertEqual(candidate?.id, 42)
        XCTAssertEqual(requestedOptions, .optionOnScreenBelowWindow)
        XCTAssertEqual(requestedWindowID, 99)
    }

    func testCandidateLookupFallsBackToOnScreenWindowsWhenBelowOverlayMisses() {
        let quartzBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let expectedCocoaBounds = WindowCandidateProvider.cocoaRect(fromQuartzWindowRect: quartzBounds)
        var requests: [(CGWindowListOption, CGWindowID)] = []
        let provider = WindowCandidateProvider(
            currentProcessID: 100,
            windowInfoProvider: { options, windowID in
                requests.append((options, windowID))
                guard options == .optionOnScreenOnly else {
                    return []
                }

                return [Self.windowInfo(
                    windowID: 42,
                    ownerProcessID: 200,
                    bounds: quartzBounds
                )]
            }
        )

        let candidate = provider.candidate(at: CGPoint(x: expectedCocoaBounds.midX, y: expectedCocoaBounds.midY), belowWindowNumber: 99)

        XCTAssertEqual(candidate?.id, 42)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].0, .optionOnScreenBelowWindow)
        XCTAssertEqual(requests[0].1, 99)
        XCTAssertEqual(requests[1].0, .optionOnScreenOnly)
        XCTAssertEqual(requests[1].1, kCGNullWindowID)
    }

    func testCocoaRectConvertsMainDisplayQuartzCoordinates() {
        let rect = WindowCandidateProvider.cocoaRect(
            fromQuartzWindowRect: CGRect(x: 209, y: 81, width: 1479, height: 1081),
            screenMappings: [
                ScreenCoordinateMapping(
                    cocoaFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                    quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243)
                ),
                ScreenCoordinateMapping(
                    cocoaFrame: CGRect(x: -2055, y: 1243, width: 3008, height: 1692),
                    quartzFrame: CGRect(x: -2055, y: -1692, width: 3008, height: 1692)
                ),
            ]
        )

        XCTAssertEqual(rect, CGRect(x: 209, y: 81, width: 1479, height: 1081))
    }

    func testCocoaRectConvertsStackedExternalDisplayQuartzCoordinates() {
        let rect = WindowCandidateProvider.cocoaRect(
            fromQuartzWindowRect: CGRect(x: -2055, y: -1692, width: 3008, height: 1692),
            screenMappings: [
                ScreenCoordinateMapping(
                    cocoaFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243),
                    quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1243)
                ),
                ScreenCoordinateMapping(
                    cocoaFrame: CGRect(x: -2055, y: 1243, width: 3008, height: 1692),
                    quartzFrame: CGRect(x: -2055, y: -1692, width: 3008, height: 1692)
                ),
            ]
        )

        XCTAssertEqual(rect, CGRect(x: -2055, y: 1243, width: 3008, height: 1692))
    }

    func testCurrentProcessSettingsWindowIsEligibleForWindowSelection() {
        let quartzBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let expectedCocoaBounds = WindowCandidateProvider.cocoaRect(fromQuartzWindowRect: quartzBounds)
        let provider = WindowCandidateProvider(
            currentProcessID: 100,
            windowInfoProvider: { _, _ in
                [Self.windowInfo(
                    windowID: 42,
                    ownerProcessID: 100,
                    bounds: quartzBounds,
                    name: "Settings"
                )]
            }
        )

        let candidate = provider.candidate(at: CGPoint(x: expectedCocoaBounds.midX, y: expectedCocoaBounds.midY))

        XCTAssertEqual(candidate?.id, 42)
    }

    func testCurrentProcessCaptureHistoryWindowIsEligibleForWindowSelection() {
        let quartzBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let expectedCocoaBounds = WindowCandidateProvider.cocoaRect(fromQuartzWindowRect: quartzBounds)
        let provider = WindowCandidateProvider(
            currentProcessID: 100,
            windowInfoProvider: { _, _ in
                [Self.windowInfo(
                    windowID: 43,
                    ownerProcessID: 100,
                    bounds: quartzBounds,
                    name: "捕获历史"
                )]
            }
        )

        let candidate = provider.candidate(at: CGPoint(x: expectedCocoaBounds.midX, y: expectedCocoaBounds.midY))

        XCTAssertEqual(candidate?.id, 43)
    }

    func testCurrentProcessTransientQuickAccessWindowIsNotEligibleForWindowSelection() {
        let quartzBounds = CGRect(x: 10, y: 20, width: 300, height: 200)
        let expectedCocoaBounds = WindowCandidateProvider.cocoaRect(fromQuartzWindowRect: quartzBounds)
        let provider = WindowCandidateProvider(
            currentProcessID: 100,
            windowInfoProvider: { _, _ in
                [Self.windowInfo(
                    windowID: 44,
                    ownerProcessID: 100,
                    bounds: quartzBounds,
                    name: QuickAccessPanelController.previewWindowTitle
                )]
            }
        )

        let candidate = provider.candidate(at: CGPoint(x: expectedCocoaBounds.midX, y: expectedCocoaBounds.midY))

        XCTAssertNil(candidate)
    }

    private static func windowInfo(
        windowID: UInt32,
        ownerProcessID: pid_t,
        bounds: CGRect,
        name: String? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowOwnerPID as String: ownerProcessID,
            kCGWindowLayer as String: 0,
            kCGWindowNumber as String: windowID,
            kCGWindowAlpha as String: 1,
            kCGWindowSharingState as String: 1,
            kCGWindowBounds as String: [
                "X": bounds.minX,
                "Y": bounds.minY,
                "Width": bounds.width,
                "Height": bounds.height,
            ],
        ]
        if let name {
            info[kCGWindowName as String] = name
        }
        return info
    }
}
