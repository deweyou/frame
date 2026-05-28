import AppKit

public enum FrameApplication {
    @MainActor
    private static var appDelegate: AppDelegate?

    @MainActor
    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()

        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination("Frame stays resident as a menu bar app.")
        app.run()
    }
}
