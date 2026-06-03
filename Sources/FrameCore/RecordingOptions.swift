import Foundation

public enum RecordingFormat: String, CaseIterable, Sendable {
    case mp4
    case gif

    public var fileExtension: String {
        rawValue
    }
}

public enum RecordingAudioSource: String, CaseIterable, Sendable {
    case none
    case microphone
    case system
}

public struct RecordingOptions: Equatable, Sendable {
    public let format: RecordingFormat
    public let showsCursor: Bool
    public let showsKeyboardHints: Bool
    public let audioSource: RecordingAudioSource

    public init(
        format: RecordingFormat,
        showsCursor: Bool,
        showsKeyboardHints: Bool,
        audioSource: RecordingAudioSource
    ) {
        self.format = format
        self.showsCursor = showsCursor
        self.showsKeyboardHints = showsKeyboardHints
        self.audioSource = audioSource
    }

    public static let defaults = RecordingOptions(
        format: .mp4,
        showsCursor: true,
        showsKeyboardHints: true,
        audioSource: .none
    )
}

public struct RecordingElapsedClock: Equatable, Sendable {
    private let startedAt: Date
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    public mutating func pause(at date: Date) {
        guard pausedAt == nil else {
            return
        }

        pausedAt = date
    }

    public mutating func resume(at date: Date) {
        guard let pausedAt else {
            return
        }

        accumulatedPausedDuration += date.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    public func elapsed(at date: Date) -> TimeInterval {
        let effectiveNow = pausedAt ?? date
        return max(0, effectiveNow.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }
}
