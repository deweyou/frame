import AppKit
import Foundation

enum CaptureHistoryKind: String, Codable, CaseIterable, Equatable {
    case screenshot
    case recording
}

enum CaptureHistoryRetention: String, CaseIterable, Identifiable {
    case oneDay
    case sevenDays
    case thirtyDays
    case forever

    var id: String {
        rawValue
    }

    var duration: TimeInterval? {
        switch self {
        case .oneDay:
            24 * 60 * 60
        case .sevenDays:
            7 * 24 * 60 * 60
        case .thirtyDays:
            30 * 24 * 60 * 60
        case .forever:
            nil
        }
    }
}

enum CaptureHistorySizeLimit: Hashable, Identifiable {
    case fiveHundredMB
    case twoGB
    case fiveGB
    case custom(bytes: Int)

    init?(rawValue: String) {
        switch rawValue {
        case Self.fiveHundredMB.rawValue:
            self = .fiveHundredMB
        case Self.twoGB.rawValue:
            self = .twoGB
        case Self.fiveGB.rawValue:
            self = .fiveGB
        default:
            return nil
        }
    }

    var id: String {
        rawValue
    }

    var rawValue: String {
        switch self {
        case .fiveHundredMB:
            "500MB"
        case .twoGB:
            "2GB"
        case .fiveGB:
            "5GB"
        case let .custom(bytes):
            "custom-\(bytes)"
        }
    }

    var bytes: Int {
        switch self {
        case .fiveHundredMB:
            500 * 1024 * 1024
        case .twoGB:
            2 * 1024 * 1024 * 1024
        case .fiveGB:
            5 * 1024 * 1024 * 1024
        case let .custom(bytes):
            max(bytes, 0)
        }
    }

    static let settingsCases: [CaptureHistorySizeLimit] = [.fiveHundredMB, .twoGB, .fiveGB]
}

extension CaptureHistoryRetention {
    func displayName(strings: AppStrings) -> String {
        switch (strings.language, self) {
        case (.zhHans, .oneDay):
            "1 天"
        case (.en, .oneDay):
            "1 day"
        case (.zhHans, .sevenDays):
            "7 天"
        case (.en, .sevenDays):
            "7 days"
        case (.zhHans, .thirtyDays):
            "30 天"
        case (.en, .thirtyDays):
            "30 days"
        case (.zhHans, .forever):
            "永不自动删除"
        case (.en, .forever):
            "Never"
        }
    }
}

extension CaptureHistorySizeLimit {
    func displayName(strings: AppStrings) -> String {
        switch (strings.language, self) {
        case (.zhHans, .fiveHundredMB):
            "500 MB"
        case (.en, .fiveHundredMB):
            "500 MB"
        case (.zhHans, .twoGB):
            "2 GB"
        case (.en, .twoGB):
            "2 GB"
        case (.zhHans, .fiveGB):
            "5 GB"
        case (.en, .fiveGB):
            "5 GB"
        case let (_, .custom(bytes)):
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }
}

struct CaptureHistoryConfiguration: Equatable {
    let isEnabled: Bool
    let retention: CaptureHistoryRetention
    let sizeLimit: CaptureHistorySizeLimit

    static func current(defaults: UserDefaults = .standard) -> CaptureHistoryConfiguration {
        CaptureHistoryConfiguration(
            isEnabled: SettingsStore.isCaptureHistoryEnabled(defaults: defaults),
            retention: SettingsStore.captureHistoryRetention(defaults: defaults),
            sizeLimit: SettingsStore.captureHistorySizeLimit(defaults: defaults)
        )
    }
}

struct CaptureHistoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let kind: CaptureHistoryKind
    let createdAt: Date
    let filename: String
    let byteSize: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let rect: CGRect
}

final class CaptureHistoryStore {
    private let rootDirectory: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        rootDirectory: URL = CaptureHistoryStore.defaultRootDirectory(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static func defaultRootDirectory(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Frame", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    func addScreenshot(
        pngData: Data,
        imageSize: CGSize,
        rect: CGRect,
        date: Date = Date(),
        configuration: CaptureHistoryConfiguration = .current()
    ) throws -> CaptureHistoryRecord? {
        try addCapture(
            kind: .screenshot,
            data: pngData,
            imageSize: imageSize,
            rect: rect,
            date: date,
            configuration: configuration
        )
    }

    func addCapture(
        kind: CaptureHistoryKind,
        data: Data,
        imageSize: CGSize,
        rect: CGRect,
        date: Date = Date(),
        configuration: CaptureHistoryConfiguration = .current()
    ) throws -> CaptureHistoryRecord? {
        guard configuration.isEnabled else {
            return nil
        }

        guard data.count <= configuration.sizeLimit.bytes else {
            return nil
        }

        try ensureDirectories()

        let id = UUID()
        let filename = "\(id.uuidString).\(kind.fileExtension)"
        let record = CaptureHistoryRecord(
            id: id,
            kind: kind,
            createdAt: date,
            filename: filename,
            byteSize: data.count,
            pixelWidth: Int(imageSize.width.rounded()),
            pixelHeight: Int(imageSize.height.rounded()),
            rect: rect
        )

        try data.write(to: captureURL(for: record), options: .atomic)
        var records = try readRecords()
        records.append(record)
        try writeRecords(records)
        try cleanup(now: date, configuration: configuration)
        return try readRecords().first { $0.id == id }
    }

    func addScreenshot(
        _ screenshot: CapturedScreenshot,
        date: Date = Date(),
        configuration: CaptureHistoryConfiguration = .current()
    ) throws -> CaptureHistoryRecord? {
        try addScreenshot(
            pngData: screenshot.pngData,
            imageSize: screenshot.image.size,
            rect: screenshot.rect,
            date: date,
            configuration: configuration
        )
    }

    func records(kind: CaptureHistoryKind? = nil) throws -> [CaptureHistoryRecord] {
        let records = try readRecords().filter { record in
            kind.map { record.kind == $0 } ?? true
        }
        return records.sorted { first, second in
            if first.createdAt == second.createdAt {
                return first.id.uuidString > second.id.uuidString
            }

            return first.createdAt > second.createdAt
        }
    }

    func data(for record: CaptureHistoryRecord) throws -> Data {
        try Data(contentsOf: captureURL(for: record))
    }

    func fileURL(for record: CaptureHistoryRecord) -> URL {
        captureURL(for: record)
    }

    func delete(recordID: UUID) throws {
        var records = try readRecords()
        guard let record = records.first(where: { $0.id == recordID }) else {
            return
        }

        try? fileManager.removeItem(at: captureURL(for: record))
        records.removeAll { $0.id == recordID }
        try writeRecords(records)
    }

    func clear() throws {
        if fileManager.fileExists(atPath: capturesDirectory.path) {
            try fileManager.removeItem(at: capturesDirectory)
        }
        try ensureDirectories()
        try writeRecords([])
    }

    func cleanup(
        now: Date = Date(),
        configuration: CaptureHistoryConfiguration = .current()
    ) throws {
        var records = try readRecords()

        if let retentionDuration = configuration.retention.duration {
            let cutoff = now.addingTimeInterval(-retentionDuration)
            for record in records where record.createdAt < cutoff {
                try? fileManager.removeItem(at: captureURL(for: record))
            }
            records.removeAll { $0.createdAt < cutoff }
        }

        records.sort { $0.createdAt < $1.createdAt }
        var totalBytes = records.reduce(0) { $0 + $1.byteSize }
        while totalBytes > configuration.sizeLimit.bytes, records.count > 1 {
            let removed = records.removeFirst()
            totalBytes -= removed.byteSize
            try? fileManager.removeItem(at: captureURL(for: removed))
        }

        try writeRecords(records)
    }

    private var indexURL: URL {
        rootDirectory.appendingPathComponent("index.json", isDirectory: false)
    }

    private var capturesDirectory: URL {
        rootDirectory.appendingPathComponent("Captures", isDirectory: true)
    }

    private func captureURL(for record: CaptureHistoryRecord) -> URL {
        capturesDirectory.appendingPathComponent(record.filename, isDirectory: false)
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: capturesDirectory, withIntermediateDirectories: true)
    }

    private func readRecords() throws -> [CaptureHistoryRecord] {
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return []
        }

        let data = try Data(contentsOf: indexURL)
        guard !data.isEmpty else {
            return []
        }

        return try decoder.decode([CaptureHistoryRecord].self, from: data)
    }

    private func writeRecords(_ records: [CaptureHistoryRecord]) throws {
        try ensureDirectories()
        let data = try encoder.encode(records)
        try data.write(to: indexURL, options: .atomic)
    }
}

private extension CaptureHistoryKind {
    var fileExtension: String {
        switch self {
        case .screenshot:
            "png"
        case .recording:
            "mov"
        }
    }
}
