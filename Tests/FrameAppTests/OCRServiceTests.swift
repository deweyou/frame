import XCTest
import Vision
@testable import FrameApp
@testable import FrameCore

final class OCRServiceTests: XCTestCase {
    func testConfigureTextRecognitionRequestIncludesChineseAndEnglish() {
        let request = VNRecognizeTextRequest()

        configureTextRecognitionRequest(request)

        XCTAssertEqual(request.recognitionLevel, .accurate)
        XCTAssertTrue(request.usesLanguageCorrection)
        XCTAssertEqual(request.recognitionLanguages, SettingsStore.ocrRecognitionLanguages())
    }

    func testConfigureTextRecognitionRequestUsesProvidedLanguages() {
        let request = VNRecognizeTextRequest()

        configureTextRecognitionRequest(request, recognitionLanguages: ["fr-FR", "en-US"])

        XCTAssertEqual(request.recognitionLanguages, ["fr-FR", "en-US"])
    }

    func testConfigureTextRecognitionRequestFallsBackForInvalidProvidedLanguages() {
        let request = VNRecognizeTextRequest()

        configureTextRecognitionRequest(request, recognitionLanguages: ["bad-language"])

        XCTAssertEqual(request.recognitionLanguages, OCRLanguageOption.defaultIdentifiers)
    }

    func testMakeLineConvertsVisionRectIntoCoreModel() {
        let line = makeRecognizedTextLine(
            text: "Frame",
            normalizedBounds: CGRect(x: 0.2, y: 0.7, width: 0.3, height: 0.1),
            confidence: 0.81
        )

        XCTAssertEqual(line.text, "Frame")
        XCTAssertEqual(line.bounds, NormalizedImageRect(x: 0.2, y: 0.7, width: 0.3, height: 0.1))
        XCTAssertEqual(line.confidence ?? 0, 0.81, accuracy: 0.001)
    }

    func testMakeLayoutDropsEmptyLines() {
        let layout = makeRecognizedTextLayout(lines: [
            makeRecognizedTextLine(text: "", normalizedBounds: .zero, confidence: nil),
            makeRecognizedTextLine(text: "Visible", normalizedBounds: CGRect(x: 0, y: 0.5, width: 1, height: 0.2), confidence: 0.9),
        ])

        XCTAssertEqual(layout.fullText, "Visible")
    }
}
