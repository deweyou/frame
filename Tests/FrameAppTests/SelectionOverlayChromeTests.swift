import CoreGraphics
import XCTest
@testable import FrameApp

final class SelectionOverlayChromeTests: XCTestCase {
    func testSelectionChromeDrawsInsetContinuousCornerPaths() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 80)
        let lineWidth: CGFloat = 2.5
        let paths = selectionChromeCornerPaths(in: rect, lineWidth: lineWidth)

        XCTAssertEqual(paths.count, 4)
        XCTAssertTrue(paths.allSatisfy { $0.points.count == 3 })
        XCTAssertTrue(paths.allSatisfy(\.isContinuousCorner))
        XCTAssertTrue(paths.flatMap(\.points).allSatisfy { $0.isInside(rect, inset: lineWidth / 2) })
    }

    func testSelectionChromePixelAlignmentSnapsEdgesToDevicePixels() {
        let rect = CGRect(x: 10.24, y: 20.24, width: 100.51, height: 80.51)
        let alignedRect = pixelAlignedSelectionRect(rect, scale: 2)

        XCTAssertEqual(alignedRect.minX * 2, (alignedRect.minX * 2).rounded())
        XCTAssertEqual(alignedRect.minY * 2, (alignedRect.minY * 2).rounded())
        XCTAssertEqual(alignedRect.maxX * 2, (alignedRect.maxX * 2).rounded())
        XCTAssertEqual(alignedRect.maxY * 2, (alignedRect.maxY * 2).rounded())
    }

    func testSelectionChromeUsesSoftAdaptiveSingleStroke() {
        let brightStyle = selectionChromeStrokeStyle(backgroundLuminance: 0.9, foregroundLineWidth: 2.5)
        let darkStyle = selectionChromeStrokeStyle(backgroundLuminance: 0.1, foregroundLineWidth: 2.5)

        XCTAssertEqual(brightStyle.role, .darkForeground)
        XCTAssertEqual(darkStyle.role, .lightForeground)
        XCTAssertEqual(brightStyle.lineWidth, 2.5)
        XCTAssertEqual(darkStyle.lineWidth, 2.5)
        XCTAssertGreaterThan(brightStyle.whiteComponent, 0.16)
        XCTAssertLessThan(brightStyle.whiteComponent, 0.32)
        XCTAssertLessThan(darkStyle.whiteComponent, 0.98)
        XCTAssertLessThanOrEqual(brightStyle.alpha, 0.72)
        XCTAssertLessThanOrEqual(darkStyle.alpha, 0.9)
    }

    func testHUDBackgroundEstimateIgnoresSparseDarkForegroundText() {
        let samples = Array(repeating: CGFloat(0.88), count: 80)
            + Array(repeating: CGFloat(0.08), count: 20)

        XCTAssertEqual(ScreenLuminanceSampler.estimatedBackgroundLuminance(from: samples), 0.88)
    }

    func testHUDBackgroundEstimateKeepsLightBackgroundWithSubstantialDarkForegroundLight() {
        let samples = Array(repeating: CGFloat(0.88), count: 92)
            + Array(repeating: CGFloat(0.08), count: 36)

        let luminance = ScreenLuminanceSampler.estimatedBackgroundLuminance(from: samples)

        XCTAssertEqual(luminance, 0.88)
        XCTAssertTrue(ScreenLuminanceSampler.prefersLightHUDContent(backgroundLuminance: luminance ?? 0))
    }

    func testHUDBackgroundEstimateKeepsMostlyDarkBackgroundDark() {
        let samples = Array(repeating: CGFloat(0.14), count: 80)
            + Array(repeating: CGFloat(0.78), count: 20)

        XCTAssertEqual(ScreenLuminanceSampler.estimatedBackgroundLuminance(from: samples), 0.14)
    }

    func testHUDBackgroundEstimateTreatsMixedGrayAndWhiteAsGrayBackground() {
        let samples = Array(repeating: CGFloat(0.46), count: 64)
            + Array(repeating: CGFloat(0.86), count: 64)

        XCTAssertEqual(ScreenLuminanceSampler.estimatedBackgroundLuminance(from: samples), 0.46)
    }

    func testHUDThemeAlwaysUsesLightContentForWhiteIcons() {
        XCTAssertTrue(ScreenLuminanceSampler.prefersLightHUDContent(backgroundLuminance: 0.10))
        XCTAssertTrue(ScreenLuminanceSampler.prefersLightHUDContent(backgroundLuminance: 0.54))
        XCTAssertTrue(ScreenLuminanceSampler.prefersLightHUDContent(backgroundLuminance: 0.70))
    }
}

private extension SelectionChromeCornerPath {
    var isContinuousCorner: Bool {
        guard points.count == 3 else {
            return false
        }

        let firstLegIsVertical = points[0].x == points[1].x
        let firstLegIsHorizontal = points[0].y == points[1].y
        let secondLegIsVertical = points[1].x == points[2].x
        let secondLegIsHorizontal = points[1].y == points[2].y
        return (firstLegIsVertical && secondLegIsHorizontal)
            || (firstLegIsHorizontal && secondLegIsVertical)
    }
}

private extension CGPoint {
    func isInside(_ rect: CGRect, inset: CGFloat) -> Bool {
        x >= rect.minX + inset
            && x <= rect.maxX - inset
            && y >= rect.minY + inset
            && y <= rect.maxY - inset
    }
}
