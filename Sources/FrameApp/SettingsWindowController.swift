import AppKit
import FrameCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private var splitViewController: SettingsSplitViewController?

    func show(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onCheckPermission: @escaping @MainActor () -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () -> Void
    ) {
        if let window {
            splitViewController?.update(strings: strings)
            centerOnActiveScreen(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let splitViewController = SettingsSplitViewController(
            strings: strings,
            onShortcutChange: onShortcutChange,
            onCheckPermission: onCheckPermission,
            onLanguageChange: onLanguageChange,
            onChooseScreenshotDirectory: onChooseScreenshotDirectory,
            onResetScreenshotDirectory: onResetScreenshotDirectory,
            onClearCaptureHistory: onClearCaptureHistory
        )

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsWindowLayout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = strings.settingsTitle
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = SettingsWindowLayout.minimumSize
        centerOnActiveScreen(window)
        window.isReleasedWhenClosed = false
        window.contentViewController = splitViewController

        self.window = window
        self.splitViewController = splitViewController
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(strings: AppStrings) {
        window?.title = strings.settingsTitle
        splitViewController?.update(strings: strings)
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
    static let defaultSize = CGSize(width: 900, height: 540)
    static let minimumSize = CGSize(width: 780, height: 480)

    static func centeredFrame(windowSize: CGSize, visibleFrame: CGRect) -> CGRect {
        CGRect(
            x: visibleFrame.midX - windowSize.width / 2,
            y: visibleFrame.midY - windowSize.height / 2,
            width: windowSize.width,
            height: windowSize.height
        )
    }
}

private enum SettingsSection: Int, CaseIterable {
    case general
    case about

    func title(strings: AppStrings) -> String {
        switch self {
        case .general:
            strings.settingsGeneral
        case .about:
            strings.settingsAbout
        }
    }

    var imageName: String {
        switch self {
        case .general:
            "gearshape"
        case .about:
            "info.circle"
        }
    }
}

@MainActor
private final class SettingsSplitViewController: NSSplitViewController {
    private let detailViewController: SettingsDetailViewController
    private let sidebarViewController: SettingsSidebarViewController

    init(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onCheckPermission: @escaping @MainActor () -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () -> Void
    ) {
        detailViewController = SettingsDetailViewController(
            strings: strings,
            onShortcutChange: onShortcutChange,
            onCheckPermission: onCheckPermission,
            onLanguageChange: onLanguageChange,
            onChooseScreenshotDirectory: onChooseScreenshotDirectory,
            onResetScreenshotDirectory: onResetScreenshotDirectory,
            onClearCaptureHistory: onClearCaptureHistory
        )

        sidebarViewController = SettingsSidebarViewController(strings: strings)

        super.init(nibName: nil, bundle: nil)

        splitView.isVertical = true
        splitView.dividerStyle = .thin

        sidebarViewController.onSelectSection = { [weak self] section in
            self?.detailViewController.show(section)
        }

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 172
        sidebarItem.maximumThickness = 220
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.minimumThickness = 420

        addSplitViewItem(sidebarItem)
        addSplitViewItem(detailItem)

        detailViewController.show(.general)
        NSLog("Frame 设置页 split view 已创建")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(strings: AppStrings) {
        sidebarViewController.update(strings: strings)
        detailViewController.update(strings: strings)
    }
}

@MainActor
private final class SettingsSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectSection: ((SettingsSection) -> Void)?

    private let tableView = NSTableView()
    private var strings: AppStrings

    init(strings: AppStrings) {
        self.strings = strings
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        let column = NSTableColumn(identifier: .settingsSidebarColumn)
        column.width = 172
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        view = scrollView
        tableView.reloadData()
        NSLog("Frame 设置页 sidebar 已加载: rows=\(SettingsSection.allCases.count)")
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if tableView.selectedRow == -1 {
            tableView.selectRowIndexes(IndexSet(integer: SettingsSection.general.rawValue), byExtendingSelection: false)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        SettingsSection.allCases.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = SettingsSection(rawValue: row) ?? .general
        let view = tableView.makeView(withIdentifier: .settingsSidebarCell, owner: self) as? NSTableCellView
            ?? SidebarCellView()

        view.identifier = .settingsSidebarCell
        view.textField?.stringValue = section.title(strings: strings)
        view.imageView?.image = NSImage(
            systemSymbolName: section.imageName,
            accessibilityDescription: section.title(strings: strings)
        )

        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let section = SettingsSection(rawValue: tableView.selectedRow) else {
            return
        }

        onSelectSection?(section)
    }

    func update(strings: AppStrings) {
        self.strings = strings
        tableView.reloadData()
    }
}

private final class SidebarCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        imageView = iconView
        textField = titleField

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleField.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(titleField)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            titleField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

@MainActor
private final class SettingsDetailViewController: NSHostingController<AnyView> {
    private let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    private let onCheckPermission: @MainActor () -> Void
    private let onLanguageChange: @MainActor (AppLanguage) -> Void
    private let onChooseScreenshotDirectory: @MainActor () -> URL?
    private let onResetScreenshotDirectory: @MainActor () -> Void
    private let onClearCaptureHistory: @MainActor () -> Void
    private var strings: AppStrings
    private var currentSection: SettingsSection = .general

    init(
        strings: AppStrings,
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onCheckPermission: @escaping @MainActor () -> Void,
        onLanguageChange: @escaping @MainActor (AppLanguage) -> Void,
        onChooseScreenshotDirectory: @escaping @MainActor () -> URL?,
        onResetScreenshotDirectory: @escaping @MainActor () -> Void,
        onClearCaptureHistory: @escaping @MainActor () -> Void
    ) {
        self.strings = strings
        self.onShortcutChange = onShortcutChange
        self.onCheckPermission = onCheckPermission
        self.onLanguageChange = onLanguageChange
        self.onChooseScreenshotDirectory = onChooseScreenshotDirectory
        self.onResetScreenshotDirectory = onResetScreenshotDirectory
        self.onClearCaptureHistory = onClearCaptureHistory
        super.init(rootView: AnyView(EmptyView()))
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    func show(_ section: SettingsSection) {
        currentSection = section
        NSLog("Frame 设置页 detail 切换到 \(section.title(strings: strings))")
        switch section {
        case .general:
            rootView = AnyView(
                GeneralSettingsView(
                    strings: strings,
                    onShortcutChange: onShortcutChange,
                    onCheckPermission: onCheckPermission,
                    onLanguageChange: onLanguageChange,
                    onChooseScreenshotDirectory: onChooseScreenshotDirectory,
                    onResetScreenshotDirectory: onResetScreenshotDirectory,
                    onClearCaptureHistory: onClearCaptureHistory
                )
            )
        case .about:
            rootView = AnyView(AboutSettingsView(strings: strings))
        }
    }

    func update(strings: AppStrings) {
        self.strings = strings
        show(currentSection)
    }
}

private struct GeneralSettingsView: View {
    let strings: AppStrings
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onCheckPermission: @MainActor () -> Void
    let onLanguageChange: @MainActor (AppLanguage) -> Void
    let onChooseScreenshotDirectory: @MainActor () -> URL?
    let onResetScreenshotDirectory: @MainActor () -> Void
    let onClearCaptureHistory: @MainActor () -> Void

    @State private var selectedShortcut = SettingsStore.screenshotShortcut()
    @State private var hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
    @State private var selectedLanguage = SettingsStore.appLanguage()
    @State private var selectedOCRLanguageIdentifiers = Set(SettingsStore.ocrRecognitionLanguages())
    @State private var screenshotDirectoryPath = (try? SettingsStore.screenshotDirectory().path) ?? ""
    @State private var isCaptureHistoryEnabled = SettingsStore.isCaptureHistoryEnabled()
    @State private var selectedCaptureHistoryRetention = SettingsStore.captureHistoryRetention()
    @State private var selectedCaptureHistorySizeLimit = SettingsStore.captureHistorySizeLimit()

    var body: some View {
        SettingsPane(title: strings.settingsGeneral) {
            Form {
                Picker(strings.settingsScreenshotShortcut, selection: $selectedShortcut) {
                    ForEach(ScreenshotShortcut.allCases) { shortcut in
                        Text(shortcut.keyboardShortcut.displayName)
                            .tag(shortcut)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedShortcut) { _, newShortcut in
                    changeShortcut(newShortcut)
                }

                LabeledContent(strings.settingsSaveLocation) {
                    HStack(spacing: 8) {
                        Text(screenshotDirectoryPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button(strings.settingsChooseFolder, action: chooseScreenshotDirectory)
                        Button(strings.settingsResetFolder, action: resetScreenshotDirectory)
                    }
                }

                Picker(strings.settingsLanguage, selection: $selectedLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName(strings: strings))
                            .tag(language)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedLanguage) { _, newLanguage in
                    SettingsStore.setAppLanguage(newLanguage)
                    onLanguageChange(newLanguage)
                }

                LabeledContent(strings.settingsOCRLanguages) {
                    VStack(alignment: .leading, spacing: 6) {
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
                        }
                    }
                    .accessibilityLabel(strings.settingsOCRLanguages)
                }

                LabeledContent(strings.settingsCaptureHistory) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(strings.settingsCaptureHistoryEnabled, isOn: $isCaptureHistoryEnabled)
                            .onChange(of: isCaptureHistoryEnabled) { _, isEnabled in
                                SettingsStore.setCaptureHistoryEnabled(isEnabled)
                            }

                        Picker(strings.settingsCaptureHistoryRetention, selection: $selectedCaptureHistoryRetention) {
                            ForEach(CaptureHistoryRetention.allCases) { retention in
                                Text(retention.displayName(strings: strings))
                                    .tag(retention)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedCaptureHistoryRetention) { _, retention in
                            SettingsStore.setCaptureHistoryRetention(retention)
                        }

                        Picker(strings.settingsCaptureHistorySizeLimit, selection: $selectedCaptureHistorySizeLimit) {
                            ForEach(CaptureHistorySizeLimit.settingsCases) { sizeLimit in
                                Text(sizeLimit.displayName(strings: strings))
                                    .tag(sizeLimit)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedCaptureHistorySizeLimit) { _, sizeLimit in
                            SettingsStore.setCaptureHistorySizeLimit(sizeLimit)
                        }

                        Button(strings.settingsCaptureHistoryClear, action: onClearCaptureHistory)
                    }
                }

                LabeledContent(strings.settingsScreenRecordingPermission) {
                    HStack(spacing: 8) {
                        Text(hasScreenRecordingAccess ? strings.settingsPermissionGranted : strings.settingsPermissionMissing)
                            .foregroundStyle(hasScreenRecordingAccess ? .green : .secondary)
                        Button(strings.settingsCheckPermission, action: checkPermission)
                        Button(strings.settingsOpenSystemSettings, action: ScreenRecordingPermission.openSettings)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private func changeShortcut(_ shortcut: ScreenshotShortcut) {
        guard onShortcutChange(shortcut) else {
            selectedShortcut = SettingsStore.screenshotShortcut()
            return
        }

        hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
    }

    private func chooseScreenshotDirectory() {
        guard let directory = onChooseScreenshotDirectory() else {
            return
        }

        SettingsStore.setScreenshotDirectory(directory)
        screenshotDirectoryPath = directory.path
    }

    private func resetScreenshotDirectory() {
        onResetScreenshotDirectory()
        screenshotDirectoryPath = (try? SettingsStore.screenshotDirectory().path) ?? ""
    }

    private func updateOCRLanguage(_ option: OCRLanguageOption, isSelected: Bool) {
        if isSelected {
            selectedOCRLanguageIdentifiers.insert(option.rawValue)
        } else {
            selectedOCRLanguageIdentifiers.remove(option.rawValue)
        }

        let validatedIdentifiers = SettingsStore.setOCRRecognitionLanguages(
            Array(selectedOCRLanguageIdentifiers)
        )
        selectedOCRLanguageIdentifiers = Set(validatedIdentifiers)
    }

    private func checkPermission() {
        onCheckPermission()
        hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
    }
}

private struct AboutSettingsView: View {
    let strings: AppStrings

    var body: some View {
        SettingsPane(title: strings.settingsAbout) {
            Form {
                LabeledContent(strings.settingsAppName, value: appName)
                LabeledContent(strings.settingsVersion, value: versionText)
                LabeledContent(strings.settingsBuild, value: buildText)
            }
            .formStyle(.grouped)
        }
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

private struct SettingsPane<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))
                .padding(.top, 26)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let settingsSidebarColumn = NSUserInterfaceItemIdentifier("settingsSidebarColumn")
    static let settingsSidebarCell = NSUserInterfaceItemIdentifier("settingsSidebarCell")
}
