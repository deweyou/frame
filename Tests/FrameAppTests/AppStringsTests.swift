import XCTest
@testable import FrameApp

final class AppStringsTests: XCTestCase {
    func testExplicitEnglishStrings() {
        let strings = AppStrings(language: .en)

        XCTAssertEqual(strings.menuCapture, "Capture")
        XCTAssertEqual(strings.menuCaptureHistory, "Capture History")
        XCTAssertEqual(strings.settingsTitle, "Settings")
        XCTAssertEqual(strings.settingsScreenshot, "Screenshots")
        XCTAssertEqual(strings.settingsRecording, "Recording")
        XCTAssertEqual(strings.settingsTextRecognition, "Text Recognition")
        XCTAssertEqual(strings.settingsPermissions, "Permissions")
        XCTAssertEqual(strings.settingsSaveLocation, "Save location")
        XCTAssertEqual(strings.settingsRestoreDefaultFolder, "Restore Default")
        XCTAssertEqual(strings.settingsCaptureHistory, "Local history")
        XCTAssertEqual(strings.settingsWindowScreenshotDecorationStyle, "Window screenshot style")
        XCTAssertEqual(strings.settingsCaptureHistoryClearConfirmationTitle, "Clear local history?")
        XCTAssertEqual(
            strings.settingsCaptureHistoryClearConfirmationMessage,
            "This removes Frame's cached screenshots and recordings. Files you saved elsewhere are not affected."
        )
        XCTAssertEqual(strings.settingsCaptureHistoryCleared, "Local history cleared")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.softBackdrop), "Soft Backdrop")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.canvasGlow), "Canvas Glow")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.transparentShadow), "Transparent Shadow")
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
        XCTAssertEqual(strings.settingsScreenshot, "截图")
        XCTAssertEqual(strings.settingsRecording, "录屏")
        XCTAssertEqual(strings.settingsTextRecognition, "文字识别")
        XCTAssertEqual(strings.settingsPermissions, "权限")
        XCTAssertEqual(strings.settingsSaveLocation, "保存位置")
        XCTAssertEqual(strings.settingsRestoreDefaultFolder, "恢复默认")
        XCTAssertEqual(strings.settingsCaptureHistory, "本地历史")
        XCTAssertEqual(strings.settingsWindowScreenshotDecorationStyle, "窗口截图样式")
        XCTAssertEqual(strings.settingsCaptureHistoryClearConfirmationTitle, "清空本地历史？")
        XCTAssertEqual(
            strings.settingsCaptureHistoryClearConfirmationMessage,
            "这会移除 Frame 缓存的截图和录屏。你已另存到其他位置的文件不受影响。"
        )
        XCTAssertEqual(strings.settingsCaptureHistoryCleared, "本地历史已清空")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.softBackdrop), "柔和背景")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.canvasGlow), "画布光影")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.transparentShadow), "透明投影")
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
        XCTAssertEqual(english.settingsChooseOCRLanguages, "Select Languages...")
        XCTAssertEqual(english.ocrLanguageDisplayName(.simplifiedChinese), "Simplified Chinese")
        XCTAssertEqual(english.ocrLanguageDisplayName(.japanese), "Japanese")
        XCTAssertEqual(english.done, "Done")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.quickAccessOCR, "识别文字")
        XCTAssertEqual(chinese.ocrCopyAll, "复制全部")
        XCTAssertEqual(chinese.ocrNoTextFound, "未识别到文字")
        XCTAssertEqual(chinese.settingsOCRLanguages, "OCR 识别语言")
        XCTAssertEqual(chinese.settingsChooseOCRLanguages, "选择语言...")
        XCTAssertEqual(chinese.ocrLanguageDisplayName(.simplifiedChinese), "简体中文")
        XCTAssertEqual(chinese.ocrLanguageDisplayName(.japanese), "日文")
        XCTAssertEqual(chinese.done, "完成")
    }

    func testRecordingMouseHintColorStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.settingsRecordingMouseHintColor, "Mouse hint color")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.settingsRecordingMouseHintColor, "鼠标提示颜色")
    }

    func testShortcutRecorderStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.settingsShortcutRecorderPrompt, "Press shortcut")
        XCTAssertEqual(english.settingsShortcutRecorderInsufficientModifiers, "Use at least two modifier keys")
        XCTAssertEqual(english.settingsShortcutRecorderUnsupportedKey, "Use a letter or number key")
        XCTAssertEqual(english.settingsShortcutRecorderReservedShortcut, "This shortcut is reserved by Frame")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.settingsShortcutRecorderPrompt, "按下快捷键")
        XCTAssertEqual(chinese.settingsShortcutRecorderInsufficientModifiers, "请按下至少两个修饰键")
        XCTAssertEqual(chinese.settingsShortcutRecorderUnsupportedKey, "只支持字母或数字")
        XCTAssertEqual(chinese.settingsShortcutRecorderReservedShortcut, "这个快捷键已由 Frame 保留")
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
