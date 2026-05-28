import Foundation

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
        case .zhHans: "截图保存位置"
        case .en: "Screenshot save location"
        }
    }

    var settingsChooseFolder: String {
        switch language {
        case .zhHans: "选择..."
        case .en: "Choose..."
        }
    }

    var settingsResetFolder: String {
        switch language {
        case .zhHans: "重置"
        case .en: "Reset"
        }
    }

    var settingsLanguage: String {
        switch language {
        case .zhHans: "语言"
        case .en: "Language"
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

    var quickAccessPin: String {
        switch language {
        case .zhHans: "固定到预览窗口"
        case .en: "Pin to Preview Window"
        }
    }

    var ok: String {
        switch language {
        case .zhHans: "好"
        case .en: "OK"
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
