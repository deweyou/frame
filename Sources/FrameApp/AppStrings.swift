import CoreGraphics
import Foundation
import FrameCore

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case en

    var id: String {
        rawValue
    }
}

enum ResolvedAppLanguage: Equatable {
    case zhHans
    case en
}

struct AppStrings {
    let language: ResolvedAppLanguage

    init(
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) {
        self.language = Self.resolvedLanguage(
            for: language,
            preferredLanguages: preferredLanguages
        )
    }

    static func current(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppStrings {
        AppStrings(
            language: SettingsStore.appLanguage(defaults: defaults),
            preferredLanguages: preferredLanguages
        )
    }

    static func resolvedLanguage(
        for language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> ResolvedAppLanguage {
        switch language {
        case .zhHans:
            return .zhHans
        case .en:
            return .en
        case .system:
            return preferredLanguages.contains { identifier in
                identifier.lowercased().hasPrefix("zh")
            } ? .zhHans : .en
        }
    }

    var menuCapture: String {
        switch language {
        case .zhHans: "截图"
        case .en: "Capture"
        }
    }

    var menuSettings: String {
        switch language {
        case .zhHans: "设置..."
        case .en: "Settings..."
        }
    }

    var menuCaptureHistory: String {
        switch language {
        case .zhHans: "捕获历史"
        case .en: "Capture History"
        }
    }

    var menuStopRecording: String {
        switch language {
        case .zhHans: "停止录制"
        case .en: "Stop Recording"
        }
    }

    var menuQuit: String {
        switch language {
        case .zhHans: "退出"
        case .en: "Quit"
        }
    }

    var settingsTitle: String {
        switch language {
        case .zhHans: "设置"
        case .en: "Settings"
        }
    }

    var settingsGeneral: String {
        switch language {
        case .zhHans: "通用"
        case .en: "General"
        }
    }

    var settingsScreenshot: String {
        switch language {
        case .zhHans: "截图"
        case .en: "Screenshots"
        }
    }

    var settingsRecording: String {
        switch language {
        case .zhHans: "录屏"
        case .en: "Recording"
        }
    }

    var settingsTextRecognition: String {
        switch language {
        case .zhHans: "文字识别"
        case .en: "Text Recognition"
        }
    }

    var settingsPermissions: String {
        switch language {
        case .zhHans: "权限"
        case .en: "Permissions"
        }
    }

    var settingsHistory: String {
        switch language {
        case .zhHans: "历史"
        case .en: "History"
        }
    }

    var settingsAbout: String {
        switch language {
        case .zhHans: "关于"
        case .en: "About"
        }
    }

    var settingsScreenshotShortcut: String {
        switch language {
        case .zhHans: "截图快捷键"
        case .en: "Screenshot shortcut"
        }
    }

    var settingsRecordingShortcut: String {
        switch language {
        case .zhHans: "录屏快捷键"
        case .en: "Recording shortcut"
        }
    }

    var settingsShortcutRecorderPrompt: String {
        switch language {
        case .zhHans: "按下快捷键"
        case .en: "Press shortcut"
        }
    }

    var settingsShortcutRecorderInsufficientModifiers: String {
        switch language {
        case .zhHans: "请按下至少两个修饰键"
        case .en: "Use at least two modifier keys"
        }
    }

    var settingsShortcutRecorderUnsupportedKey: String {
        switch language {
        case .zhHans: "只支持字母或数字"
        case .en: "Use a letter or number key"
        }
    }

    var settingsShortcutRecorderReservedShortcut: String {
        switch language {
        case .zhHans: "这个快捷键已由 Frame 保留"
        case .en: "This shortcut is reserved by Frame"
        }
    }

    var settingsShortcutRecorderDuplicateShortcut: String {
        switch language {
        case .zhHans: "这个快捷键已被 Frame 的另一个操作使用"
        case .en: "Already used by another Frame shortcut"
        }
    }

    func settingsShortcutRecorderError(_ failure: ScreenshotShortcutValidationFailure) -> String {
        switch failure {
        case .insufficientModifiers:
            settingsShortcutRecorderInsufficientModifiers
        case .unsupportedKey:
            settingsShortcutRecorderUnsupportedKey
        case .reservedShortcut:
            settingsShortcutRecorderReservedShortcut
        case .duplicateShortcut:
            settingsShortcutRecorderDuplicateShortcut
        }
    }

    var settingsScreenRecordingPermission: String {
        switch language {
        case .zhHans: "屏幕录制权限"
        case .en: "Screen Recording permission"
        }
    }

    var settingsPermissionGranted: String {
        switch language {
        case .zhHans: "已开启"
        case .en: "Granted"
        }
    }

    var settingsPermissionMissing: String {
        switch language {
        case .zhHans: "未开启"
        case .en: "Missing"
        }
    }

    var settingsCheckPermission: String {
        switch language {
        case .zhHans: "检查权限"
        case .en: "Check Permission"
        }
    }

    var settingsOpenSystemSettings: String {
        switch language {
        case .zhHans: "打开系统设置"
        case .en: "Open System Settings"
        }
    }

    var settingsSaveLocation: String {
        switch language {
        case .zhHans: "保存位置"
        case .en: "Save location"
        }
    }

    var settingsRestoreDefaultFolder: String {
        switch language {
        case .zhHans: "恢复默认"
        case .en: "Restore Default"
        }
    }

    var settingsWindowScreenshotDecorationStyle: String {
        switch language {
        case .zhHans: "窗口截图样式"
        case .en: "Window screenshot style"
        }
    }

    func windowScreenshotDecorationStyleName(_ style: WindowScreenshotDecorationStyle) -> String {
        switch style {
        case .softBackdrop:
            switch language {
            case .zhHans: "柔和背景"
            case .en: "Soft Backdrop"
            }
        case .canvasGlow:
            switch language {
            case .zhHans: "画布光影"
            case .en: "Canvas Glow"
            }
        case .transparentShadow:
            switch language {
            case .zhHans: "透明投影"
            case .en: "Transparent Shadow"
            }
        case .original:
            switch language {
            case .zhHans: "原图"
            case .en: "Original"
            }
        }
    }

    var settingsChooseFolder: String {
        switch language {
        case .zhHans: "选择..."
        case .en: "Choose..."
        }
    }

    var settingsLanguage: String {
        switch language {
        case .zhHans: "语言"
        case .en: "Language"
        }
    }

    var settingsOCRLanguages: String {
        switch language {
        case .zhHans: "OCR 识别语言"
        case .en: "OCR Languages"
        }
    }

    var settingsChooseOCRLanguages: String {
        switch language {
        case .zhHans: "选择语言..."
        case .en: "Select Languages..."
        }
    }

    func settingsOCRLanguagesSelected(count: Int, total: Int) -> String {
        switch language {
        case .zhHans: "\(count) / \(total) 种语言已启用"
        case .en: "\(count) of \(total) languages enabled"
        }
    }

    var settingsRecordingMouseHintColor: String {
        switch language {
        case .zhHans: "鼠标提示颜色"
        case .en: "Mouse hint color"
        }
    }

    var settingsCaptureHistory: String {
        switch language {
        case .zhHans: "本地历史"
        case .en: "Local history"
        }
    }

    var settingsCaptureHistoryEnabled: String {
        switch language {
        case .zhHans: "保存最近捕获"
        case .en: "Keep recent captures"
        }
    }

    var settingsCaptureHistoryRetention: String {
        switch language {
        case .zhHans: "保留时间"
        case .en: "Retention"
        }
    }

    var settingsCaptureHistorySizeLimit: String {
        switch language {
        case .zhHans: "容量上限"
        case .en: "Size limit"
        }
    }

    var settingsCaptureHistoryClear: String {
        switch language {
        case .zhHans: "清空历史"
        case .en: "Clear History"
        }
    }

    var settingsCaptureHistoryClearConfirmationTitle: String {
        switch language {
        case .zhHans: "清空本地历史？"
        case .en: "Clear local history?"
        }
    }

    var settingsCaptureHistoryClearConfirmationMessage: String {
        switch language {
        case .zhHans: "这会移除 Frame 缓存的截图和录屏。你已另存到其他位置的文件不受影响。"
        case .en: "This removes Frame's cached screenshots and recordings. Files you saved elsewhere are not affected."
        }
    }

    var settingsCaptureHistoryCleared: String {
        switch language {
        case .zhHans: "本地历史已清空"
        case .en: "Local history cleared"
        }
    }

    func settingsCaptureHistoryClearFailed(errorDescription: String) -> String {
        switch language {
        case .zhHans: "清空失败：\(errorDescription)"
        case .en: "Could not clear history: \(errorDescription)"
        }
    }

    var settingsAppName: String {
        switch language {
        case .zhHans: "应用"
        case .en: "App"
        }
    }

    var settingsVersion: String {
        switch language {
        case .zhHans: "版本"
        case .en: "Version"
        }
    }

    var settingsBuild: String {
        switch language {
        case .zhHans: "构建"
        case .en: "Build"
        }
    }

    var capturePlaceholder: String {
        switch language {
        case .zhHans: "拖拽以选择截图区域"
        case .en: "Drag to select an area"
        }
    }

    var regionCapture: String {
        switch language {
        case .zhHans: "区域截图"
        case .en: "Region capture"
        }
    }

    var quickAccessSave: String {
        switch language {
        case .zhHans: "保存"
        case .en: "Save"
        }
    }

    var quickAccessCopy: String {
        switch language {
        case .zhHans: "复制"
        case .en: "Copy"
        }
    }

    var quickAccessOCR: String {
        switch language {
        case .zhHans: "识别文字"
        case .en: "Recognize Text"
        }
    }

    var quickAccessClose: String {
        switch language {
        case .zhHans: "关闭"
        case .en: "Close"
        }
    }

    var quickAccessOpen: String {
        switch language {
        case .zhHans: "打开预览"
        case .en: "Open Preview"
        }
    }

    var videoQuickAccessDownload: String {
        switch language {
        case .zhHans: "下载"
        case .en: "Download"
        }
    }

    var videoQuickAccessCopy: String {
        switch language {
        case .zhHans: "复制"
        case .en: "Copy"
        }
    }

    var videoQuickAccessPreview: String {
        switch language {
        case .zhHans: "预览"
        case .en: "Preview"
        }
    }

    var videoQuickAccessEdit: String {
        switch language {
        case .zhHans: "编辑"
        case .en: "Edit"
        }
    }

    var quickAccessPin: String {
        switch language {
        case .zhHans: "固定到预览窗口"
        case .en: "Pin to Preview Window"
        }
    }

    var workspaceUndo: String {
        switch language {
        case .zhHans: "撤销"
        case .en: "Undo"
        }
    }

    var workspaceRedo: String {
        switch language {
        case .zhHans: "重做"
        case .en: "Redo"
        }
    }

    var workspaceSaveCurrent: String {
        switch language {
        case .zhHans: "保存当前稿"
        case .en: "Save Current"
        }
    }

    var workspaceReplaceCurrent: String {
        switch language {
        case .zhHans: "替换当前图"
        case .en: "Replace Current"
        }
    }

    var workspaceSaveAsNew: String {
        switch language {
        case .zhHans: "另存新图"
        case .en: "Save As New"
        }
    }

    var workspaceDiscardEdits: String {
        switch language {
        case .zhHans: "不保存"
        case .en: "Don't Save"
        }
    }

    var workspaceUnsavedChangesTitle: String {
        switch language {
        case .zhHans: "保存编辑？"
        case .en: "Save edits?"
        }
    }

    var workspaceUnsavedChangesMessage: String {
        switch language {
        case .zhHans: "关闭前选择替换当前图、保存为一张新的 Quick Access 预览、不保存并关闭，或取消并继续编辑。"
        case .en: "Before closing, replace the current image, save a new Quick Access preview, close without saving, or cancel and keep editing."
        }
    }

    var workspaceCopy: String {
        switch language {
        case .zhHans: "复制"
        case .en: "Copy"
        }
    }

    var workspaceDownload: String {
        switch language {
        case .zhHans: "下载"
        case .en: "Download"
        }
    }

    var workspaceEdit: String {
        switch language {
        case .zhHans: "编辑"
        case .en: "Edit"
        }
    }

    var workspaceColorOptions: String {
        switch language {
        case .zhHans: "颜色"
        case .en: "Color"
        }
    }

    var workspaceThicknessOptions: String {
        switch language {
        case .zhHans: "粗细"
        case .en: "Thickness"
        }
    }

    var workspaceFontSizeOptions: String {
        switch language {
        case .zhHans: "字号"
        case .en: "Font Size"
        }
    }

    func workspaceToolTitle(_ tool: ImageAnnotationTool) -> String {
        switch (language, tool) {
        case (.zhHans, .select): "选择"
        case (.en, .select): "Select"
        case (.zhHans, .mosaic): "马赛克"
        case (.en, .mosaic): "Mosaic"
        case (.zhHans, .shape): "形状"
        case (.en, .shape): "Shape"
        case (.zhHans, .brush): "画笔"
        case (.en, .brush): "Brush"
        case (.zhHans, .text): "文本"
        case (.en, .text): "Text"
        case (.zhHans, .highlight): "高亮"
        case (.en, .highlight): "Highlight"
        }
    }

    func workspaceToolOptionsTitle(_ tool: ImageAnnotationTool) -> String {
        switch language {
        case .zhHans: "\(workspaceToolTitle(tool))选项"
        case .en: "\(workspaceToolTitle(tool)) Options"
        }
    }

    func workspaceShapeKindTitle(_ shapeKind: ImageAnnotationShapeKind) -> String {
        switch (language, shapeKind) {
        case (.zhHans, .rectangle): "矩形"
        case (.en, .rectangle): "Rectangle"
        case (.zhHans, .ellipse): "椭圆"
        case (.en, .ellipse): "Oval"
        case (.zhHans, .line): "直线"
        case (.en, .line): "Line"
        case (.zhHans, .arrow): "箭头"
        case (.en, .arrow): "Arrow"
        }
    }

    func workspaceMosaicModeTitle(_ mosaicMode: ImageAnnotationMosaicMode) -> String {
        switch (language, mosaicMode) {
        case (.zhHans, .rectangle): "区域"
        case (.en, .rectangle): "Region"
        case (.zhHans, .brush): "画笔"
        case (.en, .brush): "Brush"
        }
    }

    func workspaceColorTitle(_ color: ImageAnnotationColor) -> String {
        if color == .red {
            switch language {
            case .zhHans: return "红色"
            case .en: return "Red"
            }
        }

        if color == .yellow {
            switch language {
            case .zhHans: return "黄色"
            case .en: return "Yellow"
            }
        }

        if color == .blue {
            switch language {
            case .zhHans: return "蓝色"
            case .en: return "Blue"
            }
        }

        if color == .green {
            switch language {
            case .zhHans: return "绿色"
            case .en: return "Green"
            }
        }

        switch language {
        case .zhHans: return "颜色"
        case .en: return "Color"
        }
    }

    func workspaceLineWidth(_ width: CGFloat) -> String {
        "\(Int(width)) px"
    }

    func workspaceFontSize(_ size: CGFloat) -> String {
        "\(Int(size)) pt"
    }

    func workspaceFontWeightTitle(_ weight: ImageAnnotationFontWeight) -> String {
        switch (language, weight) {
        case (.zhHans, .regular): "常规"
        case (.en, .regular): "Regular"
        case (.zhHans, .bold): "粗体"
        case (.en, .bold): "Bold"
        }
    }

    var captureHistoryTitle: String {
        switch language {
        case .zhHans: "捕获历史"
        case .en: "Capture History"
        }
    }

    var captureHistoryOpen: String {
        switch language {
        case .zhHans: "打开预览"
        case .en: "Open Preview"
        }
    }

    var captureHistoryRestore: String {
        switch language {
        case .zhHans: "恢复"
        case .en: "Restore"
        }
    }

    var captureHistoryDelete: String {
        switch language {
        case .zhHans: "删除"
        case .en: "Delete"
        }
    }

    var captureHistoryEmpty: String {
        switch language {
        case .zhHans: "暂无本地历史"
        case .en: "No local history yet"
        }
    }

    var captureHistoryFilterAll: String {
        switch language {
        case .zhHans: "全部"
        case .en: "All"
        }
    }

    var captureHistoryFilterScreenshots: String {
        switch language {
        case .zhHans: "截图"
        case .en: "Screenshots"
        }
    }

    var captureHistoryFilterRecordings: String {
        switch language {
        case .zhHans: "录屏"
        case .en: "Recordings"
        }
    }

    var captureHistoryKindScreenshot: String {
        switch language {
        case .zhHans: "截图"
        case .en: "Screenshot"
        }
    }

    var captureHistoryKindRecording: String {
        switch language {
        case .zhHans: "录屏"
        case .en: "Recording"
        }
    }

    var ocrPanelTitle: String {
        switch language {
        case .zhHans: "识别文字"
        case .en: "Recognized Text"
        }
    }

    var ocrCopyAll: String {
        switch language {
        case .zhHans: "复制全部"
        case .en: "Copy All"
        }
    }

    var ocrSelectAll: String {
        switch language {
        case .zhHans: "全选"
        case .en: "Select All"
        }
    }

    var ocrDeselectAll: String {
        switch language {
        case .zhHans: "清空"
        case .en: "Clear"
        }
    }

    var ocrCopySelected: String {
        switch language {
        case .zhHans: "复制"
        case .en: "Copy Selected"
        }
    }

    var ocrRecognizing: String {
        switch language {
        case .zhHans: "正在识别..."
        case .en: "Recognizing..."
        }
    }

    var ocrNoTextFound: String {
        switch language {
        case .zhHans: "未识别到文字"
        case .en: "No text found"
        }
    }

    var ocrFailedTitle: String {
        switch language {
        case .zhHans: "文字识别失败"
        case .en: "Text recognition failed"
        }
    }

    var ocrCopied: String {
        switch language {
        case .zhHans: "已复制文字"
        case .en: "Text copied"
        }
    }

    func ocrLanguageDisplayName(_ option: OCRLanguageOption) -> String {
        switch (language, option) {
        case (.zhHans, .simplifiedChinese): "简体中文"
        case (.en, .simplifiedChinese): "Simplified Chinese"
        case (.zhHans, .traditionalChinese): "繁体中文"
        case (.en, .traditionalChinese): "Traditional Chinese"
        case (.zhHans, .english): "英文"
        case (.en, .english): "English"
        case (.zhHans, .japanese): "日文"
        case (.en, .japanese): "Japanese"
        case (.zhHans, .korean): "韩文"
        case (.en, .korean): "Korean"
        case (.zhHans, .french): "法文"
        case (.en, .french): "French"
        case (.zhHans, .italian): "意大利文"
        case (.en, .italian): "Italian"
        case (.zhHans, .german): "德文"
        case (.en, .german): "German"
        case (.zhHans, .spanish): "西班牙文"
        case (.en, .spanish): "Spanish"
        case (.zhHans, .portugueseBrazil): "葡萄牙文（巴西）"
        case (.en, .portugueseBrazil): "Portuguese (Brazil)"
        case (.zhHans, .russian): "俄文"
        case (.en, .russian): "Russian"
        case (.zhHans, .ukrainian): "乌克兰文"
        case (.en, .ukrainian): "Ukrainian"
        case (.zhHans, .thai): "泰文"
        case (.en, .thai): "Thai"
        case (.zhHans, .vietnamese): "越南文"
        case (.en, .vietnamese): "Vietnamese"
        case (.zhHans, .arabic): "阿拉伯文"
        case (.en, .arabic): "Arabic"
        case (.zhHans, .turkish): "土耳其文"
        case (.en, .turkish): "Turkish"
        case (.zhHans, .indonesian): "印度尼西亚文"
        case (.en, .indonesian): "Indonesian"
        case (.zhHans, .czech): "捷克文"
        case (.en, .czech): "Czech"
        case (.zhHans, .danish): "丹麦文"
        case (.en, .danish): "Danish"
        case (.zhHans, .dutch): "荷兰文"
        case (.en, .dutch): "Dutch"
        case (.zhHans, .norwegian): "挪威文"
        case (.en, .norwegian): "Norwegian"
        case (.zhHans, .malay): "马来文"
        case (.en, .malay): "Malay"
        case (.zhHans, .polish): "波兰文"
        case (.en, .polish): "Polish"
        case (.zhHans, .romanian): "罗马尼亚文"
        case (.en, .romanian): "Romanian"
        case (.zhHans, .swedish): "瑞典文"
        case (.en, .swedish): "Swedish"
        }
    }

    var ok: String {
        switch language {
        case .zhHans: "好"
        case .en: "OK"
        }
    }

    var done: String {
        switch language {
        case .zhHans: "完成"
        case .en: "Done"
        }
    }

    var cancel: String {
        switch language {
        case .zhHans: "取消"
        case .en: "Cancel"
        }
    }

    var hotKeyRegistrationFailedTitle: String {
        switch language {
        case .zhHans: "Frame 快捷键注册失败"
        case .en: "Frame shortcut registration failed"
        }
    }

    func hotKeyRegistrationFailedMessage(errorDescription: String) -> String {
        switch language {
        case .zhHans:
            "截图快捷键暂时无法使用。你仍然可以通过菜单栏使用截图功能。\n\n\(errorDescription)"
        case .en:
            "The screenshot shortcut is temporarily unavailable. You can still capture from the menu bar.\n\n\(errorDescription)"
        }
    }

    var captureFailedTitle: String {
        switch language {
        case .zhHans: "Frame 截图失败"
        case .en: "Frame capture failed"
        }
    }

    var permissionReadyTitle: String {
        switch language {
        case .zhHans: "Frame 屏幕录制权限已开启"
        case .en: "Frame Screen Recording permission is enabled"
        }
    }

    func permissionReadyMessage(shortcut: String) -> String {
        switch language {
        case .zhHans:
            "你可以使用 \(shortcut) 或菜单栏截图入口开始区域截图。"
        case .en:
            "Use \(shortcut) or the menu bar capture item to start a region screenshot."
        }
    }

    var copyFailedTitle: String {
        switch language {
        case .zhHans: "Frame 复制失败"
        case .en: "Frame copy failed"
        }
    }

    var saveFailedTitle: String {
        switch language {
        case .zhHans: "Frame 保存失败"
        case .en: "Frame save failed"
        }
    }

    func saveFailedMessage(path: String, errorDescription: String) -> String {
        switch language {
        case .zhHans:
            "无法保存截图到 \(path)：\(errorDescription)"
        case .en:
            "Could not save screenshot to \(path): \(errorDescription)"
        }
    }
}

extension AppLanguage {
    func displayName(strings: AppStrings) -> String {
        switch self {
        case .system:
            switch strings.language {
            case .zhHans: "跟随系统"
            case .en: "Follow System"
            }
        case .zhHans:
            "中文"
        case .en:
            "English"
        }
    }
}
