import AppKit
import CoreGraphics

enum ScreenRecordingPermission {
    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }

    @MainActor
    static func showMissingPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Frame 需要屏幕录制权限"
        alert.informativeText = "macOS 要求截图工具获得屏幕录制授权。点击继续后，Frame 会向系统请求权限；如果系统没有弹窗，请在系统设置的“屏幕与系统音频录制”或“屏幕录制”里允许 Frame，授权后重启 Frame。"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessAndOpenSettingsIfNeeded()
        }
    }

    @MainActor
    private static func requestAccessAndOpenSettingsIfNeeded() {
        NSLog("Frame 正在请求屏幕录制权限")
        let didGrantAccess = requestAccess()
        NSLog("Frame 屏幕录制权限请求结果: \(didGrantAccess)")

        if hasAccess {
            showRestartRequiredAlert()
        } else {
            openSettings()
        }
    }

    @MainActor
    private static func showRestartRequiredAlert() {
        let alert = NSAlert()
        alert.messageText = "Frame 屏幕录制权限已开启"
        alert.informativeText = "请重启 Frame 后再使用区域截图。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
