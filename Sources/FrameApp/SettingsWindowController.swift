import AppKit
import FrameCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var settingsViewController: SettingsContentViewController?
    private weak var centeredTitleField: NSTextField?

    func show(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onRecordingShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool = { _ in true },
        onShortcutRecordingChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onCheckPermission: @escaping @MainActor () -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () throws -> Void
    ) {
        if let window {
            settingsViewController?.update(strings: strings)
            centerOnActiveScreen(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsViewController = SettingsContentViewController(
            strings: strings,
            onShortcutChange: onShortcutChange,
            onRecordingShortcutChange: onRecordingShortcutChange,
            onShortcutRecordingChange: onShortcutRecordingChange,
            onCheckPermission: onCheckPermission,
            onLanguageChange: onLanguageChange,
            onChooseScreenshotDirectory: onChooseScreenshotDirectory,
            onResetScreenshotDirectory: onResetScreenshotDirectory,
            onClearCaptureHistory: onClearCaptureHistory
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowLayout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = strings.settingsTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .automatic
        window.minSize = SettingsWindowLayout.minimumSize
        window.isReleasedWhenClosed = false
        window.contentViewController = settingsViewController
        installCenteredTitle(in: window, title: strings.settingsTitle)
        window.minSize = SettingsWindowLayout.minimumSize
        window.setFrame(NSRect(origin: window.frame.origin, size: SettingsWindowLayout.defaultSize), display: false)
        centerOnActiveScreen(window)

        self.window = window
        self.settingsViewController = settingsViewController
        window.makeKeyAndOrderFront(nil)
        window.minSize = SettingsWindowLayout.minimumSize
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(strings: AppStrings) {
        window?.title = strings.settingsTitle
        centeredTitleField?.stringValue = strings.settingsTitle
        settingsViewController?.update(strings: strings)
    }

    private func installCenteredTitle(in window: NSWindow, title: String) {
        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview,
              let closeButton = window.standardWindowButton(.closeButton) else {
            return
        }

        let titleField = NSTextField(labelWithString: title)
        titleField.identifier = SettingsWindowLayout.centeredTitlebarTitleIdentifier
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.alignment = .center
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleField.setContentHuggingPriority(.required, for: .horizontal)

        titlebarView.addSubview(titleField)
        NSLayoutConstraint.activate([
            titleField.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleField.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])

        centeredTitleField = titleField
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? window.screen

        guard let visibleFrame = targetScreen?.visibleFrame else {
            window.center()
            return
        }

        window.setFrame(SettingsWindowLayout.centeredFrame(
            windowSize: window.frame.size,
            visibleFrame: visibleFrame
        ), display: false)
    }
}

enum SettingsWindowLayout {
    static let defaultSize = CGSize(width: 620, height: 600)
    static let minimumSize = CGSize(width: 560, height: 460)
    static let usesSidebar = false
    static let usesCenteredTitlebarLabel = true
    static let centeredTitlebarTitleIdentifier = NSUserInterfaceItemIdentifier("FrameSettingsCenteredTitle")

    static func centeredFrame(windowSize: CGSize, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }
}

enum SettingsSection: Int, CaseIterable {
    case general
    case screenshot
    case recording
    case textRecognition
    case history
    case permissions

    func title(strings: AppStrings) -> String {
        switch self {
        case .general:
            strings.settingsGeneral
        case .screenshot:
            strings.settingsScreenshot
        case .recording:
            strings.settingsRecording
        case .textRecognition:
            strings.settingsTextRecognition
        case .history:
            strings.settingsHistory
        case .permissions:
            strings.settingsPermissions
        }
    }
}

@MainActor
private final class SettingsContentViewController: NSHostingController<AnyView> {
    private let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    private let onRecordingShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    private let onShortcutRecordingChange: @MainActor (Bool) -> Void
    private let onCheckPermission: @MainActor () -> Void
    private let onLanguageChange: @MainActor (AppLanguage) -> Void
    private let onChooseScreenshotDirectory: @MainActor () -> URL?
    private let onResetScreenshotDirectory: @MainActor () -> Void
    private let onClearCaptureHistory: @MainActor () throws -> Void
    private var strings: AppStrings

    init(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onRecordingShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onShortcutRecordingChange: @escaping @MainActor (Bool) -> Void,
        onCheckPermission: @escaping @MainActor () -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () throws -> Void
    ) {
        self.strings = strings
        self.onShortcutChange = onShortcutChange
        self.onRecordingShortcutChange = onRecordingShortcutChange
        self.onShortcutRecordingChange = onShortcutRecordingChange
        self.onCheckPermission = onCheckPermission
        self.onLanguageChange = onLanguageChange
        self.onChooseScreenshotDirectory = onChooseScreenshotDirectory
        self.onResetScreenshotDirectory = onResetScreenshotDirectory
        self.onClearCaptureHistory = onClearCaptureHistory
        super.init(rootView: AnyView(EmptyView()))
        updateRootView()
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    func update(strings: AppStrings) {
        self.strings = strings
        updateRootView()
    }

    private func updateRootView() {
        rootView = AnyView(
            SettingsListView(
                strings: strings,
                onShortcutChange: onShortcutChange,
                onRecordingShortcutChange: onRecordingShortcutChange,
                onShortcutRecordingChange: onShortcutRecordingChange,
                onCheckPermission: onCheckPermission,
                onLanguageChange: onLanguageChange,
                onChooseScreenshotDirectory: onChooseScreenshotDirectory,
                onResetScreenshotDirectory: onResetScreenshotDirectory,
                onClearCaptureHistory: onClearCaptureHistory
            )
        )
    }
}

private struct SettingsListView: View {
    let strings: AppStrings
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onRecordingShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onShortcutRecordingChange: @MainActor (Bool) -> Void
    let onCheckPermission: @MainActor () -> Void
    let onLanguageChange: @MainActor (AppLanguage) -> Void
    let onChooseScreenshotDirectory: @MainActor () -> URL?
    let onResetScreenshotDirectory: @MainActor () -> Void
    let onClearCaptureHistory: @MainActor () throws -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsListMetrics.sectionSpacing) {
                GeneralSettingsView(
                    strings: strings,
                    onShortcutChange: onShortcutChange,
                    onRecordingShortcutChange: onRecordingShortcutChange,
                    onShortcutRecordingChange: onShortcutRecordingChange,
                    onChooseScreenshotDirectory: onChooseScreenshotDirectory,
                    onResetScreenshotDirectory: onResetScreenshotDirectory,
                    onLanguageChange: onLanguageChange
                )

                ScreenshotSettingsView(strings: strings)

                RecordingSettingsView(strings: strings)
                TextRecognitionSettingsView(strings: strings)

                HistorySettingsView(
                    strings: strings,
                    onClearCaptureHistory: onClearCaptureHistory
                )

                PermissionsSettingsView(
                    strings: strings,
                    onCheckPermission: onCheckPermission
                )

                SettingsAboutFooterView()
            }
            .padding(SettingsListMetrics.contentPadding)
            .frame(maxWidth: SettingsListMetrics.maxContentWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct GeneralSettingsView: View {
    let strings: AppStrings
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onRecordingShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onShortcutRecordingChange: @MainActor (Bool) -> Void
    let onChooseScreenshotDirectory: @MainActor () -> URL?
    let onResetScreenshotDirectory: @MainActor () -> Void
    let onLanguageChange: @MainActor (AppLanguage) -> Void

    @State private var selectedLanguage = SettingsStore.appLanguage()
    @State private var selectedShortcut = SettingsStore.screenshotShortcut()
    @State private var selectedRecordingShortcut = SettingsStore.recordingShortcut()
    @State private var shortcutErrorText: String?
    @State private var recordingShortcutErrorText: String?
    @State private var screenshotDirectoryURL = GeneralSettingsView.currentScreenshotDirectory()

    var body: some View {
        SettingsSectionGroup(title: strings.settingsGeneral) {
            SettingsControlGroup {
                SettingsControlRow(strings.settingsLanguage) {
                    Picker("", selection: $selectedLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName(strings: strings))
                                .tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel(strings.settingsLanguage)
                    .onChange(of: selectedLanguage) { _, newLanguage in
                        SettingsStore.setAppLanguage(newLanguage)
                        onLanguageChange(newLanguage)
                    }
                }

                SettingsControlDivider()

                SettingsControlRow(
                    strings.settingsScreenshotShortcut,
                    verticalAlignment: .top,
                    verticalPadding: 5
                ) {
                    VStack(alignment: .trailing, spacing: 5) {
                        ShortcutRecorderControl(
                            strings: strings,
                            accessibilityLabel: strings.settingsScreenshotShortcut,
                            shortcut: selectedShortcut,
                            reservedShortcuts: [.defaultRecording],
                            duplicateShortcut: selectedRecordingShortcut,
                            onShortcutChange: changeShortcut,
                            onValidationFailure: updateShortcutValidationFailure,
                            onRecordingChange: onShortcutRecordingChange
                        )

                        if let shortcutErrorText {
                            Text(shortcutErrorText)
                                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                                .foregroundStyle(Color(nsColor: .systemRed))
                        }
                    }
                }

                SettingsControlDivider()

                SettingsControlRow(
                    strings.settingsRecordingShortcut,
                    verticalAlignment: .top,
                    verticalPadding: 5
                ) {
                    VStack(alignment: .trailing, spacing: 5) {
                        ShortcutRecorderControl(
                            strings: strings,
                            accessibilityLabel: strings.settingsRecordingShortcut,
                            shortcut: selectedRecordingShortcut,
                            reservedShortcuts: [],
                            duplicateShortcut: selectedShortcut,
                            onShortcutChange: changeRecordingShortcut,
                            onValidationFailure: updateRecordingShortcutValidationFailure,
                            onRecordingChange: onShortcutRecordingChange
                        )

                        if let recordingShortcutErrorText {
                            Text(recordingShortcutErrorText)
                                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                                .foregroundStyle(Color(nsColor: .systemRed))
                        }
                    }
                }

                SettingsControlDivider()

                SettingsControlRow(
                    strings.settingsSaveLocation,
                    verticalAlignment: .center,
                    verticalPadding: 7
                ) {
                    SettingsSaveLocationControl(
                        summary: SettingsSaveLocationSummary(url: screenshotDirectoryURL),
                        strings: strings,
                        onChoose: chooseScreenshotDirectory,
                        onReset: resetScreenshotDirectory
                    )
                }
            }
        }
    }

    private func changeShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        selectedShortcut = shortcut
        guard onShortcutChange(shortcut) else {
            selectedShortcut = SettingsStore.screenshotShortcut()
            return false
        }
        shortcutErrorText = nil
        return true
    }

    private func changeRecordingShortcut(_ shortcut: ScreenshotShortcut) -> Bool {
        selectedRecordingShortcut = shortcut
        guard onRecordingShortcutChange(shortcut) else {
            selectedRecordingShortcut = SettingsStore.recordingShortcut()
            return false
        }
        recordingShortcutErrorText = nil
        return true
    }

    private func updateShortcutValidationFailure(_ failure: ScreenshotShortcutValidationFailure?) {
        shortcutErrorText = failure.map { strings.settingsShortcutRecorderError($0) }
    }

    private func updateRecordingShortcutValidationFailure(_ failure: ScreenshotShortcutValidationFailure?) {
        recordingShortcutErrorText = failure.map { strings.settingsShortcutRecorderError($0) }
    }

    private func chooseScreenshotDirectory() {
        guard let directory = onChooseScreenshotDirectory() else {
            return
        }

        SettingsStore.setScreenshotDirectory(directory)
        screenshotDirectoryURL = directory
    }

    private func resetScreenshotDirectory() {
        onResetScreenshotDirectory()
        screenshotDirectoryURL = Self.currentScreenshotDirectory()
    }

    private static func currentScreenshotDirectory() -> URL {
        (try? SettingsStore.screenshotDirectory()) ?? FileManager.default.homeDirectoryForCurrentUser
    }
}

enum SettingsListMetrics {
    static let maxContentWidth: CGFloat = 540
    static let contentPadding: CGFloat = 30
    static let sectionSpacing: CGFloat = 14
    static let showsAboutAsSection = false
    static let showsAboutFooter = true
}

enum SettingsGeneralMetrics {
    static let containsScreenshotShortcut = true
    static let containsRecordingShortcut = true
    static let containsSaveLocation = true
}

enum SettingsScreenshotMetrics {
    static let containsShortcut = false
    static let containsSaveLocation = false
}

enum SettingsGroupMetrics {
    static let usesVisibleGroupBackground = true
    static let cornerRadius: CGFloat = 10
    static let rowMinHeight: CGFloat = 36
    static let containerPadding: CGFloat = 10
    static let labelColumnWidth: CGFloat = 120
    static let horizontalPadding: CGFloat = 12
    static let controlSpacing: CGFloat = 14
    static let borderOpacity: CGFloat = 0.38
}

enum SettingsTypographyMetrics {
    static let usesSystemFont = true
    static let usesQuietSectionTitles = true
    static let usesMediumRowLabels = true
    static let sectionFontSize: CGFloat = 13
    static let rowFontSize: CGFloat = 14
    static let secondaryFontSize: CGFloat = 13
    static let footerFontSize: CGFloat = 11
}

enum SettingsSectionGroupMetrics {
    static let titleSpacing: CGFloat = 6
}

enum SettingsShortcutRecorderMetrics {
    static let usesInlineRecorder = true
    static let width: CGFloat = 118
    static let minHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 7
}

enum SettingsSaveLocationMetrics {
    static let usesSummaryRow = true
    static let opensChooserFromSummary = false
    static let showsFinderAction = false
    static let showsFolderName = false
    static let showsResetOnlyForCustomLocation = true
    static let usesNestedControlBackground = false
    static let usesSeparateRevealBox = false
    static let summaryWidth: CGFloat = 180
}

enum SettingsOCRLanguageMetrics {
    static let usesDisclosure = false
    static let usesSheet = true
    static let opensFromWholeRow = true
    static let sheetWidth: CGFloat = 420
    static let sheetHeight: CGFloat = 460
    static let gridMinimumItemWidth: CGFloat = 180
    static let gridSpacing: CGFloat = 8
}

enum SettingsMouseHintColorMetrics {
    static let usesSwatchPicker = true
    static let usesPresetOnlyPicker = true
    static let usesSelectedCheckmark = true
    static let showsCustomColorPicker = false
    static let showsResetAction = false
    static let swatchSize: CGFloat = 24
    static let controlSpacing: CGFloat = 8
}

struct SettingsSaveLocationSummary: Equatable {
    let path: String
    let isDefaultLocation: Bool

    init(
        url: URL,
        desktopURL: URL = SettingsSaveLocationSummary.defaultDesktopURL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        let standardizedURL = url.standardizedFileURL
        let standardizedDesktopURL = desktopURL.standardizedFileURL

        isDefaultLocation = standardizedURL.path == standardizedDesktopURL.path
        path = Self.abbreviatedPath(for: standardizedURL, homeURL: homeURL)
    }

    private static let defaultDesktopURL = FileManager.default
        .urls(for: .desktopDirectory, in: .userDomainMask)
        .first ?? FileManager.default.homeDirectoryForCurrentUser

    private static func abbreviatedPath(for url: URL, homeURL: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = homeURL.standardizedFileURL.path

        guard path != homePath else {
            return "~"
        }

        let homePrefix = homePath + "/"
        guard path.hasPrefix(homePrefix) else {
            return path
        }

        return "~/" + String(path.dropFirst(homePrefix.count))
    }
}

private struct SettingsControlGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(SettingsGroupMetrics.containerPadding)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: SettingsGroupMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: SettingsGroupMetrics.cornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(SettingsGroupMetrics.borderOpacity), lineWidth: 0.5)
        }
    }
}

private struct SettingsControlRow<Content: View>: View {
    let title: String
    let verticalAlignment: VerticalAlignment
    let verticalPadding: CGFloat
    let controlAlignment: Alignment
    @ViewBuilder let content: Content

    init(
        _ title: String,
        verticalAlignment: VerticalAlignment = .center,
        verticalPadding: CGFloat = 0,
        controlAlignment: Alignment = .trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.verticalAlignment = verticalAlignment
        self.verticalPadding = verticalPadding
        self.controlAlignment = controlAlignment
        self.content = content()
    }

    var body: some View {
        HStack(alignment: verticalAlignment, spacing: SettingsGroupMetrics.controlSpacing) {
            Text(title)
                .font(.system(size: SettingsTypographyMetrics.rowFontSize, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: SettingsGroupMetrics.labelColumnWidth, alignment: .leading)

            content
                .font(.system(size: SettingsTypographyMetrics.rowFontSize))
                .frame(maxWidth: .infinity, alignment: controlAlignment)
        }
        .padding(.horizontal, SettingsGroupMetrics.horizontalPadding)
        .padding(.vertical, verticalPadding)
        .frame(minHeight: SettingsGroupMetrics.rowMinHeight)
    }
}

private struct SettingsButtonRow: View {
    let title: String
    let value: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SettingsGroupMetrics.controlSpacing) {
                Text(title)
                    .font(.system(size: SettingsTypographyMetrics.rowFontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: SettingsGroupMetrics.labelColumnWidth, alignment: .leading)

                Text(value)
                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, SettingsGroupMetrics.horizontalPadding)
            .frame(minHeight: SettingsGroupMetrics.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct SettingsControlDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, SettingsGroupMetrics.horizontalPadding)
    }
}

private struct SettingsSaveLocationControl: View {
    let summary: SettingsSaveLocationSummary
    let strings: AppStrings
    let onChoose: () -> Void
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                locationSummary
                Button(strings.settingsChooseFolder, action: onChoose)
                    .controlSize(.small)
                    .help(strings.settingsChooseFolder)
                    .accessibilityLabel(strings.settingsChooseFolder)
            }

            if !summary.isDefaultLocation {
                Button(strings.settingsRestoreDefaultFolder, action: onReset)
                    .buttonStyle(.plain)
                    .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                    .foregroundStyle(.secondary)
                    .help(strings.settingsRestoreDefaultFolder)
                    .accessibilityLabel(strings.settingsRestoreDefaultFolder)
            }
        }
    }

    private var locationSummary: some View {
        HStack(spacing: 7) {
            Image(systemName: "folder")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            Text(summary.path)
                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: SettingsSaveLocationMetrics.summaryWidth, alignment: .leading)
        .accessibilityLabel("\(strings.settingsSaveLocation), \(summary.path)")
    }
}

private struct ScreenshotSettingsView: View {
    let strings: AppStrings

    @State private var selectedWindowScreenshotDecorationStyle = SettingsStore.windowScreenshotDecorationStyle()

    var body: some View {
        SettingsSectionGroup(title: strings.settingsScreenshot) {
            SettingsControlGroup {
                SettingsControlRow(strings.settingsWindowScreenshotDecorationStyle) {
                    Picker("", selection: $selectedWindowScreenshotDecorationStyle) {
                        ForEach(WindowScreenshotDecorationStyle.allCases) { style in
                            Text(style.displayName(strings: strings))
                                .tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .accessibilityLabel(strings.settingsWindowScreenshotDecorationStyle)
                    .onChange(of: selectedWindowScreenshotDecorationStyle) { _, style in
                        SettingsStore.setWindowScreenshotDecorationStyle(style)
                    }
                }
            }
        }
    }
}

private struct ShortcutRecorderControl: NSViewRepresentable {
    let strings: AppStrings
    let accessibilityLabel: String
    let shortcut: ScreenshotShortcut
    let reservedShortcuts: Set<ScreenshotShortcut>
    let duplicateShortcut: ScreenshotShortcut?
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onValidationFailure: @MainActor (ScreenshotShortcutValidationFailure?) -> Void
    let onRecordingChange: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onShortcutChange: onShortcutChange,
            onValidationFailure: onValidationFailure,
            onRecordingChange: onRecordingChange
        )
    }

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.target = context.coordinator
        button.action = #selector(Coordinator.startRecording(_:))
        configure(button, context: context)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        context.coordinator.onShortcutChange = onShortcutChange
        context.coordinator.onValidationFailure = onValidationFailure
        context.coordinator.onRecordingChange = onRecordingChange
        configure(button, context: context)
    }

    private func configure(_ button: ShortcutRecorderButton, context: Context) {
        button.update(
            strings: strings,
            accessibilityLabel: accessibilityLabel,
            shortcut: shortcut,
            reservedShortcuts: reservedShortcuts,
            duplicateShortcut: duplicateShortcut,
            onShortcutChange: context.coordinator.onShortcutChange,
            onValidationFailure: context.coordinator.onValidationFailure,
            onRecordingChange: context.coordinator.onRecordingChange
        )
    }

    @MainActor
    final class Coordinator: NSObject {
        var onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
        var onValidationFailure: @MainActor (ScreenshotShortcutValidationFailure?) -> Void
        var onRecordingChange: @MainActor (Bool) -> Void

        init(
            onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
            onValidationFailure: @escaping @MainActor (ScreenshotShortcutValidationFailure?) -> Void,
            onRecordingChange: @escaping @MainActor (Bool) -> Void
        ) {
            self.onShortcutChange = onShortcutChange
            self.onValidationFailure = onValidationFailure
            self.onRecordingChange = onRecordingChange
        }

        @objc func startRecording(_ sender: ShortcutRecorderButton) {
            sender.startRecording()
        }
    }
}

final class ShortcutRecorderButton: NSButton {
    private var strings = AppStrings(language: .system)
    private var shortcutAccessibilityLabel = ""
    private var shortcut = ScreenshotShortcut.default
    private var reservedShortcuts: Set<ScreenshotShortcut> = [.defaultRecording]
    private var duplicateShortcut: ScreenshotShortcut?
    private var isRecording = false
    private var recordingPreviewTitle: String?
    private var onShortcutChange: (@MainActor (ScreenshotShortcut) -> Bool)?
    private var onValidationFailure: (@MainActor (ScreenshotShortcutValidationFailure?) -> Void)?
    private var onRecordingChange: (@MainActor (Bool) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryChange)
        isBordered = false
        focusRingType = .none
        alignment = .center
        lineBreakMode = .byTruncatingTail
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: SettingsShortcutRecorderMetrics.width).isActive = true
        heightAnchor.constraint(greaterThanOrEqualToConstant: SettingsShortcutRecorderMetrics.minHeight).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        strings: AppStrings,
        accessibilityLabel: String = "",
        shortcut: ScreenshotShortcut,
        reservedShortcuts: Set<ScreenshotShortcut> = [.defaultRecording],
        duplicateShortcut: ScreenshotShortcut? = nil,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onValidationFailure: @escaping @MainActor (ScreenshotShortcutValidationFailure?) -> Void,
        onRecordingChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.strings = strings
        shortcutAccessibilityLabel = accessibilityLabel.isEmpty ? strings.settingsScreenshotShortcut : accessibilityLabel
        self.shortcut = shortcut
        self.reservedShortcuts = reservedShortcuts
        self.duplicateShortcut = duplicateShortcut
        self.onShortcutChange = onShortcutChange
        self.onValidationFailure = onValidationFailure
        self.onRecordingChange = onRecordingChange

        if isRecording {
            title = recordingTitle
        } else {
            title = shortcut.displayName
        }
        updateAccessibilityLabel()
        updateAppearance()
    }

    func startRecording() {
        guard !isRecording else {
            return
        }

        isRecording = true
        recordingPreviewTitle = nil
        title = recordingTitle
        onValidationFailure?(nil)
        onRecordingChange?(true)
        window?.makeFirstResponder(self)
        updateAccessibilityLabel()
        updateAppearance()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        if event.keyCode == shortcutRecorderEscapeKeyCode {
            stopRecording()
            return
        }

        let key = ScreenshotShortcutKey(event: event)
        let modifiers = ScreenshotShortcutModifier.modifiers(event: event)
        updateRecordingPreview(key: key, modifiers: modifiers)

        let result = ScreenshotShortcut.validate(
            key: key,
            modifiers: modifiers,
            reservedShortcuts: reservedShortcuts,
            duplicateShortcut: duplicateShortcut
        )

        switch result {
        case let .valid(shortcut):
            let didApply = onShortcutChange?(shortcut) ?? false
            if didApply {
                self.shortcut = shortcut
            }
            stopRecording()
        case let .invalid(failure):
            onValidationFailure?(failure)
            updateAppearance()
        }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }

        updateRecordingPreview(key: nil, modifiers: ScreenshotShortcutModifier.modifiers(event: event))
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil && isRecording {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func stopRecording() {
        guard isRecording else {
            return
        }

        isRecording = false
        recordingPreviewTitle = nil
        title = shortcut.displayName
        onValidationFailure?(nil)
        onRecordingChange?(false)
        window?.makeFirstResponder(nil)
        updateAccessibilityLabel()
        updateAppearance()
    }

    private func updateRecordingPreview(
        key: ScreenshotShortcutKey?,
        modifiers: Set<ScreenshotShortcutModifier>
    ) {
        let preview = ShortcutRecorderPreview.title(key: key, modifiers: modifiers)
        recordingPreviewTitle = preview.isEmpty ? nil : preview
        title = recordingTitle
        updateAccessibilityLabel()
        updateAppearance()
    }

    private var recordingTitle: String {
        recordingPreviewTitle ?? strings.settingsShortcutRecorderPrompt
    }

    private func updateAccessibilityLabel() {
        setAccessibilityLabel("\(shortcutAccessibilityLabel), \(title)")
    }

    private func updateAppearance() {
        font = .systemFont(ofSize: 13, weight: .semibold)
        contentTintColor = .labelColor
        wantsLayer = true
        layer?.cornerRadius = SettingsShortcutRecorderMetrics.cornerRadius
        layer?.backgroundColor = shortcutRecorderBackgroundColor.cgColor
        layer?.borderWidth = isRecording ? 1 : 0.5
        layer?.borderColor = shortcutRecorderBorderColor.cgColor
    }

    private var shortcutRecorderBackgroundColor: NSColor {
        if isRecording {
            return NSColor.controlAccentColor.withAlphaComponent(0.12)
        }

        return .controlBackgroundColor
    }

    private var shortcutRecorderBorderColor: NSColor {
        if isRecording {
            return NSColor.controlAccentColor.withAlphaComponent(0.8)
        }

        return NSColor.separatorColor.withAlphaComponent(0.65)
    }
}

private extension ScreenshotShortcutKey {
    init(event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.uppercased().first,
              let scalar = String(character).unicodeScalars.first else {
            self = .unsupported
            return
        }

        switch scalar.value {
        case ShortcutRecorderScalar.capitalA...ShortcutRecorderScalar.capitalZ:
            self = .letter(String(character))
        case ShortcutRecorderScalar.zero...ShortcutRecorderScalar.nine:
            self = .number(String(character))
        default:
            self = .unsupported
        }
    }
}

private enum ShortcutRecorderPreview {
    static func title(
        key: ScreenshotShortcutKey?,
        modifiers: Set<ScreenshotShortcutModifier>
    ) -> String {
        orderedModifiers
            .filter { modifiers.contains($0) }
            .map(\.symbol)
            .joined() + (key?.displayName ?? "")
    }

    private static let orderedModifiers: [ScreenshotShortcutModifier] = [
        .command,
        .option,
        .control,
        .shift,
    ]
}

private extension ScreenshotShortcutModifier {
    static func modifiers(event: NSEvent) -> Set<ScreenshotShortcutModifier> {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Set<ScreenshotShortcutModifier>()
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }
}

private enum ShortcutRecorderScalar {
    static let zero = UnicodeScalar("0").value
    static let nine = UnicodeScalar("9").value
    static let capitalA = UnicodeScalar("A").value
    static let capitalZ = UnicodeScalar("Z").value
}

private let shortcutRecorderEscapeKeyCode: UInt16 = 53

private struct RecordingSettingsView: View {
    let strings: AppStrings

    @State private var selectedRecordingMouseHintColor = SettingsStore.recordingOptions().mouseHintColor

    var body: some View {
        SettingsSectionGroup(title: strings.settingsRecording) {
            SettingsControlGroup {
                SettingsControlRow(strings.settingsRecordingMouseHintColor) {
                    RecordingMouseHintColorControl(
                        strings: strings,
                        selectedColor: $selectedRecordingMouseHintColor,
                        onChange: updateRecordingMouseHintColor
                    )
                }
            }
        }
        .onAppear(perform: normalizeRecordingMouseHintColor)
    }

    private func updateRecordingMouseHintColor(_ color: RecordingMouseHintColor) {
        selectedRecordingMouseHintColor = color
        let options = SettingsStore.recordingOptions()
        SettingsStore.setRecordingOptions(
            RecordingOptions(
                format: options.format,
                showsCursor: options.showsCursor,
                showsMouseClickHighlights: options.showsMouseClickHighlights,
                showsKeyboardHints: options.showsKeyboardHints,
                audioSource: options.audioSource,
                mouseHintColor: color
            )
        )
    }

    private func normalizeRecordingMouseHintColor() {
        let normalizedColor = RecordingMouseHintColorPreset.normalizedColor(selectedRecordingMouseHintColor)
        guard !selectedRecordingMouseHintColor.isApproximatelyEqual(to: normalizedColor) else {
            return
        }

        updateRecordingMouseHintColor(normalizedColor)
    }
}

private struct TextRecognitionSettingsView: View {
    let strings: AppStrings

    @State private var selectedOCRLanguageIdentifiers = Set(SettingsStore.ocrRecognitionLanguages())
    @State private var isShowingOCRLanguageSheet = false

    var body: some View {
        SettingsSectionGroup(title: strings.settingsTextRecognition) {
            SettingsControlGroup {
                SettingsButtonRow(
                    title: strings.settingsOCRLanguages,
                    value: summaryText,
                    accessibilityLabel: "\(strings.settingsOCRLanguages), \(summaryText), \(strings.settingsChooseOCRLanguages)",
                    action: {
                        isShowingOCRLanguageSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingOCRLanguageSheet) {
            OCRLanguageSelectionSheet(
                strings: strings,
                selectedOCRLanguageIdentifiers: $selectedOCRLanguageIdentifiers,
                onDone: {
                    isShowingOCRLanguageSheet = false
                }
            )
        }
    }

    private var summaryText: String {
        strings.settingsOCRLanguagesSelected(
            count: selectedOCRLanguageIdentifiers.count,
            total: OCRLanguageOption.allCases.count
        )
    }
}

private struct OCRLanguageSelectionSheet: View {
    let strings: AppStrings
    @Binding var selectedOCRLanguageIdentifiers: Set<String>
    let onDone: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: SettingsOCRLanguageMetrics.gridMinimumItemWidth), alignment: .leading),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(strings.settingsOCRLanguages)
                .font(.system(size: 18, weight: .semibold))

            Text(summaryText)
                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(
                    columns: columns,
                    alignment: .leading,
                    spacing: SettingsOCRLanguageMetrics.gridSpacing
                ) {
                    ForEach(OCRLanguageOption.allCases) { option in
                        Toggle(
                            strings.ocrLanguageDisplayName(option),
                            isOn: Binding(
                                get: {
                                    selectedOCRLanguageIdentifiers.contains(option.rawValue)
                                },
                                set: { isSelected in
                                    updateOCRLanguage(option, isSelected: isSelected)
                                }
                            )
                        )
                        .accessibilityLabel(strings.ocrLanguageDisplayName(option))
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Spacer()

                Button(strings.done, action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(
            width: SettingsOCRLanguageMetrics.sheetWidth,
            height: SettingsOCRLanguageMetrics.sheetHeight,
            alignment: .topLeading
        )
    }

    private var summaryText: String {
        strings.settingsOCRLanguagesSelected(
            count: selectedOCRLanguageIdentifiers.count,
            total: OCRLanguageOption.allCases.count
        )
    }

    private func updateOCRLanguage(_ option: OCRLanguageOption, isSelected: Bool) {
        var identifiers = selectedOCRLanguageIdentifiers
        if isSelected {
            identifiers.insert(option.rawValue)
        } else {
            identifiers.remove(option.rawValue)
        }

        let validatedIdentifiers = SettingsStore.setOCRRecognitionLanguages(Array(identifiers))
        selectedOCRLanguageIdentifiers = Set(validatedIdentifiers)
    }
}

private struct HistorySettingsView: View {
    let strings: AppStrings
    let onClearCaptureHistory: @MainActor () throws -> Void

    @State private var isCaptureHistoryEnabled = SettingsStore.isCaptureHistoryEnabled()
    @State private var selectedCaptureHistoryRetention = SettingsStore.captureHistoryRetention()
    @State private var selectedCaptureHistorySizeLimit = SettingsStore.captureHistorySizeLimit()
    @State private var isShowingClearConfirmation = false
    @State private var clearStatusMessage: String?
    @State private var clearStatusIsError = false

    var body: some View {
        SettingsSectionGroup(title: strings.settingsCaptureHistory) {
            SettingsControlGroup {
                SettingsControlRow(strings.settingsCaptureHistoryEnabled) {
                    Toggle("", isOn: $isCaptureHistoryEnabled)
                        .labelsHidden()
                        .accessibilityLabel(strings.settingsCaptureHistoryEnabled)
                        .onChange(of: isCaptureHistoryEnabled) { _, isEnabled in
                            SettingsStore.setCaptureHistoryEnabled(isEnabled)
                        }
                }

                SettingsControlDivider()

                SettingsControlRow(strings.settingsCaptureHistoryRetention) {
                    Picker("", selection: $selectedCaptureHistoryRetention) {
                        ForEach(CaptureHistoryRetention.allCases) { retention in
                            Text(retention.displayName(strings: strings))
                                .tag(retention)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!isCaptureHistoryEnabled)
                    .accessibilityLabel(strings.settingsCaptureHistoryRetention)
                    .onChange(of: selectedCaptureHistoryRetention) { _, retention in
                        SettingsStore.setCaptureHistoryRetention(retention)
                    }
                }

                SettingsControlDivider()

                SettingsControlRow(strings.settingsCaptureHistorySizeLimit) {
                    Picker("", selection: $selectedCaptureHistorySizeLimit) {
                        ForEach(CaptureHistorySizeLimit.settingsCases) { sizeLimit in
                            Text(sizeLimit.displayName(strings: strings))
                                .tag(sizeLimit)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!isCaptureHistoryEnabled)
                    .accessibilityLabel(strings.settingsCaptureHistorySizeLimit)
                    .onChange(of: selectedCaptureHistorySizeLimit) { _, sizeLimit in
                        SettingsStore.setCaptureHistorySizeLimit(sizeLimit)
                    }
                }

                SettingsControlDivider()

                SettingsControlRow(strings.settingsCaptureHistoryClear) {
                    Button(strings.settingsCaptureHistoryClear, role: .destructive) {
                        isShowingClearConfirmation = true
                    }
                }

                if let clearStatusMessage {
                    SettingsControlDivider()

                    SettingsControlRow("") {
                        Text(clearStatusMessage)
                            .foregroundStyle(clearStatusIsError ? .red : .secondary)
                    }
                }
            }
        }
        .alert(strings.settingsCaptureHistoryClearConfirmationTitle, isPresented: $isShowingClearConfirmation) {
            Button(strings.settingsCaptureHistoryClear, role: .destructive, action: clearCaptureHistory)
            Button(strings.cancel, role: .cancel) {}
        } message: {
            Text(strings.settingsCaptureHistoryClearConfirmationMessage)
        }
    }

    private func clearCaptureHistory() {
        do {
            try onClearCaptureHistory()
            clearStatusIsError = false
            clearStatusMessage = strings.settingsCaptureHistoryCleared
        } catch {
            clearStatusIsError = true
            clearStatusMessage = strings.settingsCaptureHistoryClearFailed(errorDescription: error.localizedDescription)
        }
    }
}

private struct PermissionsSettingsView: View {
    let strings: AppStrings
    let onCheckPermission: @MainActor () -> Void

    @State private var hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess

    var body: some View {
        SettingsSectionGroup(title: strings.settingsPermissions) {
            SettingsControlGroup {
                SettingsControlRow(
                    strings.settingsScreenRecordingPermission,
                    verticalAlignment: .top,
                    verticalPadding: 12
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        Text(hasScreenRecordingAccess ? strings.settingsPermissionGranted : strings.settingsPermissionMissing)
                            .foregroundStyle(hasScreenRecordingAccess ? .green : .secondary)

                        HStack(spacing: 8) {
                            Button(strings.settingsCheckPermission, action: checkPermission)
                                .accessibilityLabel(strings.settingsCheckPermission)
                            Button(strings.settingsOpenSystemSettings, action: ScreenRecordingPermission.openSettings)
                                .accessibilityLabel(strings.settingsOpenSystemSettings)
                        }
                    }
                }
            }
        }
    }

    private func checkPermission() {
        onCheckPermission()
        hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
    }
}

enum RecordingMouseHintColorPreset: String, CaseIterable, Identifiable {
    case coral
    case amber
    case sky
    case mint
    case violet

    var id: String {
        rawValue
    }

    static let defaultPreset = RecordingMouseHintColorPreset.coral
    static let standardPresets: [RecordingMouseHintColorPreset] = [.coral, .amber, .sky, .mint, .violet]

    static func normalizedColor(_ color: RecordingMouseHintColor) -> RecordingMouseHintColor {
        standardPresets.first { preset in
            color.isApproximatelyEqual(to: preset.color)
        }?.color ?? defaultPreset.color
    }

    var color: RecordingMouseHintColor {
        switch self {
        case .coral:
            RecordingMouseHintColor(red: 1, green: 0.32, blue: 0.36)
        case .amber:
            RecordingMouseHintColor(red: 1, green: 0.68, blue: 0.18)
        case .sky:
            RecordingMouseHintColor(red: 0.16, green: 0.56, blue: 1)
        case .mint:
            RecordingMouseHintColor(red: 0.2, green: 0.78, blue: 0.52)
        case .violet:
            RecordingMouseHintColor(red: 0.58, green: 0.42, blue: 1)
        }
    }

    func accessibilityLabel(strings: AppStrings) -> String {
        switch (strings.language, self) {
        case (.zhHans, .coral): "珊瑚色"
        case (.en, .coral): "Coral"
        case (.zhHans, .amber): "琥珀色"
        case (.en, .amber): "Amber"
        case (.zhHans, .sky): "天蓝色"
        case (.en, .sky): "Sky"
        case (.zhHans, .mint): "薄荷色"
        case (.en, .mint): "Mint"
        case (.zhHans, .violet): "紫色"
        case (.en, .violet): "Violet"
        }
    }
}

private struct RecordingMouseHintColorControl: View {
    let strings: AppStrings
    @Binding var selectedColor: RecordingMouseHintColor
    let onChange: (RecordingMouseHintColor) -> Void

    var body: some View {
        HStack(spacing: SettingsMouseHintColorMetrics.controlSpacing) {
            ForEach(RecordingMouseHintColorPreset.standardPresets) { preset in
                Button {
                    onChange(preset.color)
                } label: {
                    RecordingMouseHintColorSwatch(
                        color: preset.color,
                        isSelected: selectedColor.isApproximatelyEqual(to: preset.color)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.accessibilityLabel(strings: strings))
            }
        }
    }
}

private struct RecordingMouseHintColorSwatch: View {
    let color: RecordingMouseHintColor
    let isSelected: Bool

    var body: some View {
        Circle()
            .fill(Color(nsColor: color.nsColor))
            .overlay {
                Circle()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(1)
                }
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(nsColor: color.selectionGlyphColor))
                }
            }
            .frame(width: SettingsMouseHintColorMetrics.swatchSize, height: SettingsMouseHintColorMetrics.swatchSize)
            .contentShape(Circle())
    }
}

private struct SettingsAboutFooterView: View {
    var body: some View {
        Text(SettingsAboutFooterText.value(appName: appName, version: versionText, build: buildText))
            .font(.system(size: SettingsTypographyMetrics.footerFontSize))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 2)
            .accessibilityLabel(SettingsAboutFooterText.value(appName: appName, version: versionText, build: buildText))
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Frame"
    }

    private var versionText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? FrameVersion.shortVersion
    }

    private var buildText: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? FrameVersion.build
    }
}

enum SettingsAboutFooterText {
    static func value(appName: String, version: String, build: String) -> String {
        "\(appName) · Version \(version) · Build \(build)"
    }
}

private struct SettingsSectionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsSectionGroupMetrics.titleSpacing) {
            Text(title)
                .font(.system(size: SettingsTypographyMetrics.sectionFontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private extension RecordingMouseHintColor {
    func isApproximatelyEqual(to color: RecordingMouseHintColor) -> Bool {
        abs(red - color.red) < 0.001
            && abs(green - color.green) < 0.001
            && abs(blue - color.blue) < 0.001
            && abs(alpha - color.alpha) < 0.001
    }

    var selectionGlyphColor: NSColor {
        let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
        return luminance > 0.62 ? .black : .white
    }
}
