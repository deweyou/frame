import XCTest
@testable import FrameApp

final class AppStringsTests: XCTestCase {
    func testExplicitEnglishStrings() {
        let strings = AppStrings(language: .en)

        XCTAssertEqual(strings.menuCapture, "Capture")
        XCTAssertEqual(strings.menuCaptureHistory, "Capture History")
        XCTAssertEqual(strings.settingsTitle, "Settings")
        XCTAssertEqual(strings.settingsCaptureHistory, "Local history")
        XCTAssertEqual(strings.capturePlaceholder, "Drag to select an area")
        XCTAssertEqual(strings.quickAccessSave, "Save")
        XCTAssertEqual(strings.captureHistoryTitle, "Capture History")
        XCTAssertEqual(strings.captureHistoryEmpty, "No local history yet")
        XCTAssertEqual(strings.captureHistoryRestore, "Restore")
    }

    func testExplicitChineseStrings() {
        let strings = AppStrings(language: .zhHans)

        XCTAssertEqual(strings.menuCapture, "截图")
        XCTAssertEqual(strings.menuCaptureHistory, "截图历史")
        XCTAssertEqual(strings.settingsTitle, "设置")
        XCTAssertEqual(strings.settingsCaptureHistory, "本地历史")
        XCTAssertEqual(strings.capturePlaceholder, "拖拽以选择截图区域")
        XCTAssertEqual(strings.quickAccessSave, "保存")
        XCTAssertEqual(strings.captureHistoryTitle, "截图历史")
        XCTAssertEqual(strings.captureHistoryEmpty, "暂无本地历史")
        XCTAssertEqual(strings.captureHistoryRestore, "恢复")
    }

    func testOCRStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.quickAccessOCR, "Recognize Text")
        XCTAssertEqual(english.ocrCopyAll, "Copy All")
        XCTAssertEqual(english.ocrNoTextFound, "No text found")
        XCTAssertEqual(english.settingsOCRLanguages, "OCR Languages")
        XCTAssertEqual(english.ocrLanguageDisplayName(.simplifiedChinese), "Simplified Chinese")
        XCTAssertEqual(english.ocrLanguageDisplayName(.japanese), "Japanese")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.quickAccessOCR, "识别文字")
        XCTAssertEqual(chinese.ocrCopyAll, "复制全部")
        XCTAssertEqual(chinese.ocrNoTextFound, "未识别到文字")
        XCTAssertEqual(chinese.settingsOCRLanguages, "OCR 识别语言")
        XCTAssertEqual(chinese.ocrLanguageDisplayName(.simplifiedChinese), "简体中文")
        XCTAssertEqual(chinese.ocrLanguageDisplayName(.japanese), "日文")
    }

    func testOCRScrubSelectionStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.ocrSelectAll, "Select All")
        XCTAssertEqual(english.ocrDeselectAll, "Clear")
        XCTAssertEqual(english.ocrCopySelected, "Copy Selected")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.ocrSelectAll, "全选")
        XCTAssertEqual(chinese.ocrDeselectAll, "清空")
        XCTAssertEqual(chinese.ocrCopySelected, "复制")
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
