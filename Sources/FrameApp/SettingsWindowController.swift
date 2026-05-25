import AppKit
import FrameCore
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onCheckPermission: @escaping @MainActor () -> Void
    ) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let splitViewController = SettingsSplitViewController(
            onShortcutChange: onShortcutChange,
            onCheckPermission: onCheckPermission
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 640, height: 460)
        window.center()
        window.isReleasedWhenClosed = false
        window.contentViewController = splitViewController

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum SettingsSection: Int, CaseIterable {
    case general
    case about

    var title: String {
        switch self {
        case .general:
            "通用"
        case .about:
            "关于"
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

    init(
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onCheckPermission: @escaping @MainActor () -> Void
    ) {
        detailViewController = SettingsDetailViewController(
            onShortcutChange: onShortcutChange,
            onCheckPermission: onCheckPermission
        )

        let sidebarViewController = SettingsSidebarViewController()

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
}

@MainActor
private final class SettingsSidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelectSection: ((SettingsSection) -> Void)?

    private let tableView = NSTableView()

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
        view.textField?.stringValue = section.title
        view.imageView?.image = NSImage(systemSymbolName: section.imageName, accessibilityDescription: section.title)

        return view
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let section = SettingsSection(rawValue: tableView.selectedRow) else {
            return
        }

        onSelectSection?(section)
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

    init(
        onShortcutChange: @escaping @MainActor (ScreenshotShortcut) -> Bool,
        onCheckPermission: @escaping @MainActor () -> Void
    ) {
        self.onShortcutChange = onShortcutChange
        self.onCheckPermission = onCheckPermission
        super.init(rootView: AnyView(EmptyView()))
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        nil
    }

    func show(_ section: SettingsSection) {
        NSLog("Frame 设置页 detail 切换到 \(section.title)")
        switch section {
        case .general:
            rootView = AnyView(
                GeneralSettingsView(
                    onShortcutChange: onShortcutChange,
                    onCheckPermission: onCheckPermission
                )
            )
        case .about:
            rootView = AnyView(AboutSettingsView())
        }
    }
}

private struct GeneralSettingsView: View {
    let onShortcutChange: @MainActor (ScreenshotShortcut) -> Bool
    let onCheckPermission: @MainActor () -> Void

    @State private var selectedShortcut = SettingsStore.screenshotShortcut()
    @State private var hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess

    var body: some View {
        SettingsPane(title: "通用") {
            Form {
                Picker("截图快捷键", selection: $selectedShortcut) {
                    ForEach(ScreenshotShortcut.allCases) { shortcut in
                        Text(shortcut.keyboardShortcut.displayName)
                            .tag(shortcut)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedShortcut) { _, newShortcut in
                    changeShortcut(newShortcut)
                }

                LabeledContent("屏幕录制权限") {
                    HStack(spacing: 8) {
                        Text(hasScreenRecordingAccess ? "已开启" : "未开启")
                            .foregroundStyle(hasScreenRecordingAccess ? .green : .secondary)
                        Button("检查权限", action: checkPermission)
                        Button("打开系统设置", action: ScreenRecordingPermission.openSettings)
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

    private func checkPermission() {
        onCheckPermission()
        hasScreenRecordingAccess = ScreenRecordingPermission.hasAccess
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        SettingsPane(title: "关于") {
            Form {
                LabeledContent("应用", value: appName)
                LabeledContent("版本", value: versionText)
                LabeledContent("构建", value: buildText)
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
