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
        XCTAssertEqual(strings.settingsCaptureHistoryEnabled, "Keep recent captures")
        XCTAssertEqual(strings.settingsRecordingShortcut, "Recording shortcut")
        XCTAssertEqual(strings.settingsShortcutRecorderUnset, "Not set")
        XCTAssertEqual(strings.settingsShortcutRecorderDuplicateShortcut, "Already used by another Frame shortcut")
        XCTAssertEqual(strings.settingsWindowScreenshotDecorationStyle, "Window screenshot style")
        XCTAssertEqual(strings.settingsImageWorkspaceSaveCurrentBehavior, "Edited screenshot save")
        XCTAssertEqual(strings.settingsCaptureHistoryClearConfirmationTitle, "Clear local history?")
        XCTAssertEqual(
            strings.settingsCaptureHistoryClearConfirmationMessage,
            "This removes Frame's cached screenshots and recordings. Files you saved elsewhere are not affected."
        )
        XCTAssertEqual(strings.settingsCaptureHistoryCleared, "Local history cleared")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.softBackdrop), "Soft Backdrop")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.canvasGlow), "Canvas Glow")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.transparentShadow), "Transparent Shadow")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.original), "Original")
        XCTAssertEqual(strings.imageWorkspaceSaveCurrentBehaviorName(.askEveryTime), "Ask Every Time")
        XCTAssertEqual(strings.imageWorkspaceSaveCurrentBehaviorName(.replaceCurrent), "Replace Current")
        XCTAssertEqual(strings.imageWorkspaceSaveCurrentBehaviorName(.saveAsNew), "Save As New")
        XCTAssertEqual(strings.capturePlaceholder, "Drag to select an area")
        XCTAssertEqual(strings.quickAccessSave, "Save")
        XCTAssertEqual(strings.videoEditingMP4Only, "MP4 editing only in this version")
        XCTAssertEqual(strings.captureHistoryTitle, "Capture History")
        XCTAssertEqual(strings.captureHistoryEmpty, "No local history yet")
        XCTAssertEqual(strings.captureHistoryRestore, "Restore")
    }

    func testExplicitChineseStrings() {
        let strings = AppStrings(language: .zhHans)

        XCTAssertEqual(strings.menuCapture, "截图")
        XCTAssertEqual(strings.menuCaptureHistory, "捕获历史")
        XCTAssertEqual(strings.settingsTitle, "设置")
        XCTAssertEqual(strings.settingsScreenshot, "截图")
        XCTAssertEqual(strings.settingsRecording, "录屏")
        XCTAssertEqual(strings.settingsTextRecognition, "文字识别")
        XCTAssertEqual(strings.settingsPermissions, "权限")
        XCTAssertEqual(strings.settingsSaveLocation, "保存位置")
        XCTAssertEqual(strings.settingsRestoreDefaultFolder, "恢复默认")
        XCTAssertEqual(strings.settingsCaptureHistory, "本地历史")
        XCTAssertEqual(strings.settingsCaptureHistoryEnabled, "保存最近捕获")
        XCTAssertEqual(strings.settingsRecordingShortcut, "录屏快捷键")
        XCTAssertEqual(strings.settingsShortcutRecorderUnset, "未设置")
        XCTAssertEqual(strings.settingsShortcutRecorderDuplicateShortcut, "这个快捷键已被 Frame 的另一个操作使用")
        XCTAssertEqual(strings.settingsWindowScreenshotDecorationStyle, "窗口截图样式")
        XCTAssertEqual(strings.settingsImageWorkspaceSaveCurrentBehavior, "编辑保存方式")
        XCTAssertEqual(strings.settingsCaptureHistoryClearConfirmationTitle, "清空本地历史？")
        XCTAssertEqual(
            strings.settingsCaptureHistoryClearConfirmationMessage,
            "这会移除 Frame 缓存的截图和录屏。你已另存到其他位置的文件不受影响。"
        )
        XCTAssertEqual(strings.settingsCaptureHistoryCleared, "本地历史已清空")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.softBackdrop), "柔和背景")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.canvasGlow), "画布光影")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.transparentShadow), "透明投影")
        XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.original), "原图")
        XCTAssertEqual(strings.imageWorkspaceSaveCurrentBehaviorName(.askEveryTime), "每次询问")
        XCTAssertEqual(strings.imageWorkspaceSaveCurrentBehaviorName(.replaceCurrent), "替换当前图")
        XCTAssertEqual(strings.imageWorkspaceSaveCurrentBehaviorName(.saveAsNew), "另存新图")
        XCTAssertEqual(strings.capturePlaceholder, "拖拽以选择截图区域")
        XCTAssertEqual(strings.quickAccessSave, "保存")
        XCTAssertEqual(strings.videoEditingMP4Only, "此版本仅支持编辑 MP4")
        XCTAssertEqual(strings.captureHistoryTitle, "捕获历史")
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

    func testScrollingScreenshotStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.scrollingScreenshotAction, "Scrolling Screenshot")
        XCTAssertEqual(english.scrollingScreenshotStart, "Start")
        XCTAssertEqual(english.scrollingScreenshotFinish, "Finish")
        XCTAssertEqual(english.scrollingScreenshotAutoScroll, "Auto Scroll")
        XCTAssertEqual(english.scrollingScreenshotStopAutoScroll, "Stop Auto Scroll")
        XCTAssertEqual(english.scrollingScreenshotCancel, "Cancel")
        XCTAssertEqual(english.scrollingScreenshotFailedTitle, "Scrolling screenshot failed")
        XCTAssertEqual(
            english.scrollingScreenshotInsufficientProgress,
            "Frame did not detect scrollable content. Make sure the selection covers a scrollable area."
        )
        XCTAssertEqual(
            english.scrollingScreenshotNoReliableOverlap,
            "Frame could not match the captured frames. Scroll more slowly and keep the same region visible."
        )

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.scrollingScreenshotAction, "滚动长截图")
        XCTAssertEqual(chinese.scrollingScreenshotStart, "开始")
        XCTAssertEqual(chinese.scrollingScreenshotFinish, "完成")
        XCTAssertEqual(chinese.scrollingScreenshotAutoScroll, "自动滚动")
        XCTAssertEqual(chinese.scrollingScreenshotStopAutoScroll, "停止滚动")
        XCTAssertEqual(chinese.scrollingScreenshotCancel, "取消")
        XCTAssertEqual(chinese.scrollingScreenshotFailedTitle, "滚动截图失败")
        XCTAssertEqual(chinese.scrollingScreenshotInsufficientProgress, "没有检测到可滚动的内容。请确认选区覆盖可滚动区域。")
        XCTAssertEqual(chinese.scrollingScreenshotNoReliableOverlap, "没有找到可拼接的重叠区域。请慢一点滚动，并保持同一个区域可见。")
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

    func testWorkspaceAnnotationStringsAreLocalized() {
        let english = AppStrings(language: .en)
        XCTAssertEqual(english.workspaceToolTitle(.select), "Select")
        XCTAssertEqual(english.workspaceToolTitle(.shape), "Shape")
        XCTAssertEqual(english.workspaceToolOptionsTitle(.shape), "Shape Options")
        XCTAssertEqual(english.workspaceShapeKindTitle(.arrow), "Arrow")
        XCTAssertEqual(english.workspaceMosaicModeTitle(.rectangle), "Region")
        XCTAssertEqual(english.workspaceMosaicModeTitle(.brush), "Brush")
        XCTAssertEqual(english.workspaceColorTitle(.red), "Red")
        XCTAssertEqual(english.workspaceColorTitle(.white), "White")
        XCTAssertEqual(english.workspaceColorTitle(.black), "Black")
        XCTAssertEqual(english.workspaceColorOptions, "Color")
        XCTAssertEqual(english.workspaceThicknessOptions, "Thickness")
        XCTAssertEqual(english.workspaceFontSizeOptions, "Font Size")
        XCTAssertEqual(english.workspaceSaveCurrent, "Save Current")
        XCTAssertEqual(english.workspaceSaveAndCopy, "Save and Copy")
        XCTAssertEqual(english.workspaceSaveAndDownload, "Save and Download")
        XCTAssertEqual(english.workspaceReplaceCurrent, "Replace Current")
        XCTAssertEqual(english.workspaceSaveAsNew, "Save As New")
        XCTAssertEqual(english.workspaceDiscardEdits, "Don't Save")
        XCTAssertEqual(english.workspaceUnsavedChangesTitle, "Save edits?")
        XCTAssertEqual(
            english.workspaceUnsavedChangesMessage,
            "Before closing, replace the current image, save a new Quick Access preview, close without saving, or cancel and keep editing."
        )
        XCTAssertEqual(
            english.videoUnsavedChangesMessage,
            "Before closing, replace the current recording, save a new Quick Access recording, close without saving, or cancel and keep editing."
        )
        XCTAssertEqual(english.videoReplaceCurrent, "Replace Current")
        XCTAssertEqual(english.videoSaveAsNew, "Save As New")
        XCTAssertEqual(english.videoEditorPlayPause, "Play/Pause")
        XCTAssertEqual(english.videoEditorStartTime, "Start time")
        XCTAssertEqual(english.videoEditorEndTime, "End time")
        XCTAssertEqual(english.videoEditorStartShort, "Start")
        XCTAssertEqual(english.videoEditorEndShort, "End")
        XCTAssertEqual(english.videoEditorPlaybackSpeed, "Playback speed")
        XCTAssertEqual(english.videoEditorSpeedShort, "Speed")
        XCTAssertEqual(english.videoEditorOutputDurationShort, "Output")
        XCTAssertEqual(english.cancel, "Cancel")

        let chinese = AppStrings(language: .zhHans)
        XCTAssertEqual(chinese.workspaceToolTitle(.select), "选择")
        XCTAssertEqual(chinese.workspaceToolTitle(.shape), "形状")
        XCTAssertEqual(chinese.workspaceToolOptionsTitle(.shape), "形状选项")
        XCTAssertEqual(chinese.workspaceShapeKindTitle(.arrow), "箭头")
        XCTAssertEqual(chinese.workspaceMosaicModeTitle(.rectangle), "区域")
        XCTAssertEqual(chinese.workspaceMosaicModeTitle(.brush), "画笔")
        XCTAssertEqual(chinese.workspaceColorTitle(.red), "红色")
        XCTAssertEqual(chinese.workspaceColorTitle(.white), "白色")
        XCTAssertEqual(chinese.workspaceColorTitle(.black), "黑色")
        XCTAssertEqual(chinese.workspaceColorOptions, "颜色")
        XCTAssertEqual(chinese.workspaceThicknessOptions, "粗细")
        XCTAssertEqual(chinese.workspaceFontSizeOptions, "字号")
        XCTAssertEqual(chinese.workspaceSaveCurrent, "保存当前稿")
        XCTAssertEqual(chinese.workspaceSaveAndCopy, "保存并复制")
        XCTAssertEqual(chinese.workspaceSaveAndDownload, "保存并下载")
        XCTAssertEqual(chinese.workspaceReplaceCurrent, "替换当前图")
        XCTAssertEqual(chinese.workspaceSaveAsNew, "另存新图")
        XCTAssertEqual(chinese.workspaceDiscardEdits, "不保存")
        XCTAssertEqual(
            chinese.workspaceUnsavedChangesMessage,
            "关闭前选择替换当前图、保存为一张新的 Quick Access 预览、不保存并关闭，或取消并继续编辑。"
        )
        XCTAssertEqual(
            chinese.videoUnsavedChangesMessage,
            "关闭前选择替换当前录屏、保存为一条新的 Quick Access 录屏、不保存并关闭，或取消并继续编辑。"
        )
        XCTAssertEqual(chinese.videoReplaceCurrent, "替换当前录屏")
        XCTAssertEqual(chinese.videoSaveAsNew, "另存新录屏")
        XCTAssertEqual(chinese.videoEditorPlayPause, "播放/暂停")
        XCTAssertEqual(chinese.videoEditorStartTime, "开始时间")
        XCTAssertEqual(chinese.videoEditorEndTime, "结束时间")
        XCTAssertEqual(chinese.videoEditorStartShort, "开始")
        XCTAssertEqual(chinese.videoEditorEndShort, "结束")
        XCTAssertEqual(chinese.videoEditorPlaybackSpeed, "播放速度")
        XCTAssertEqual(chinese.videoEditorSpeedShort, "速度")
        XCTAssertEqual(chinese.videoEditorOutputDurationShort, "变速后")
        XCTAssertEqual(chinese.cancel, "取消")
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
