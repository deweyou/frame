import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
enum AccessibilityPermission {
    static var hasAccess: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
}

enum InputMonitoringPermission {
    static var hasAccess: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        CGRequestListenEventAccess()
    }

    static func openSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        ) else {
            return
        }

        NSWorkspace.shared.open(settingsURL)
    }
}
