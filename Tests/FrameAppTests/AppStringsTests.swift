import XCTest
@testable import FrameApp

final class AppStringsTests: XCTestCase {
    func testExplicitEnglishStrings() {
        let strings = AppStrings(language: .en)

        XCTAssertEqual(strings.menuCapture, "Capture")
        XCTAssertEqual(strings.settingsTitle, "Settings")
        XCTAssertEqual(strings.capturePlaceholder, "Drag to select an area")
        XCTAssertEqual(strings.quickAccessSave, "Save")
    }

    func testExplicitChineseStrings() {
        let strings = AppStrings(language: .zhHans)

        XCTAssertEqual(strings.menuCapture, "截图")
        XCTAssertEqual(strings.settingsTitle, "设置")
        XCTAssertEqual(strings.capturePlaceholder, "拖拽以选择截图区域")
        XCTAssertEqual(strings.quickAccessSave, "保存")
    }

    func testOCRStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.quickAccessOCR, "Recognize Text")
        XCTAssertEqual(english.ocrCopyAll, "Copy All")
        XCTAssertEqual(english.ocrNoTextFound, "No text found")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.quickAccessOCR, "识别文字")
        XCTAssertEqual(chinese.ocrCopyAll, "复制全部")
        XCTAssertEqual(chinese.ocrNoTextFound, "未识别到文字")
    }

    func testSystemChineseResolvesToSimplifiedChinese() {
        XCTAssertEqual(
            AppStrings.resolvedLanguage(for: .system, preferredLanguages: ["zh-Hans-CN"]),
            .zhHans
        )
    }

    func testSystemNonChineseResolvesToEnglish() {
        XCTAssertEqual(
            AppStrings.resolvedLanguage(for: .system, preferredLanguages: ["fr-FR", "en-US"]),
            .en
        )
    }
}
