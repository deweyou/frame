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
    static func showMissingPermissionAlert(strings: AppStrings = .current()) {
        let alert = NSAlert()
        alert.messageText = strings.screenRecordingPermissionRequiredTitle
        alert.informativeText = strings.screenRecordingPermissionRequiredMessage
        alert.addButton(withTitle: strings.screenRecordingPermissionContinue)
        alert.addButton(withTitle: strings.cancel)

        if alert.runModal() == .alertFirstButtonReturn {
            requestAccessAndOpenSettingsIfNeeded(strings: strings)
        }
    }

    @MainActor
    private static func requestAccessAndOpenSettingsIfNeeded(strings: AppStrings) {
        NSLog("Frame 正在请求屏幕录制权限")
        let didGrantAccess = requestAccess()
        NSLog("Frame 屏幕录制权限请求结果: \(didGrantAccess)")

        if hasAccess {
            showRestartRequiredAlert(strings: strings)
        } else {
            openSettings()
        }
    }

    @MainActor
    private static func showRestartRequiredAlert(strings: AppStrings) {
        let alert = NSAlert()
        alert.messageText = strings.screenRecordingPermissionGrantedTitle
        alert.informativeText = strings.screenRecordingPermissionRestartMessage
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }
}
