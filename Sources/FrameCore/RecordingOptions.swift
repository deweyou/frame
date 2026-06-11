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

public struct RecordingMouseHintColor: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamped(red)
        self.green = Self.clamped(green)
        self.blue = Self.clamped(blue)
        self.alpha = Self.clamped(alpha)
    }

    public static let red = RecordingMouseHintColor(red: 1, green: 0.231, blue: 0.188, alpha: 1)
    public static let `default` = red

    public static func == (lhs: RecordingMouseHintColor, rhs: RecordingMouseHintColor) -> Bool {
        abs(lhs.red - rhs.red) < 0.0025
            && abs(lhs.green - rhs.green) < 0.0025
            && abs(lhs.blue - rhs.blue) < 0.0025
            && abs(lhs.alpha - rhs.alpha) < 0.0025
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

public struct RecordingOptions: Equatable, Sendable {
    public let format: RecordingFormat
    public let showsCursor: Bool
    public let showsMouseClickHighlights: Bool
    public let showsKeyboardHints: Bool
    public let audioSource: RecordingAudioSource
    public let mouseHintColor: RecordingMouseHintColor

    public init(
        format: RecordingFormat,
        showsCursor: Bool,
        showsMouseClickHighlights: Bool = true,
        showsKeyboardHints: Bool,
        audioSource: RecordingAudioSource,
        mouseHintColor: RecordingMouseHintColor = .default
    ) {
        self.format = format
        self.showsCursor = showsCursor
        self.showsMouseClickHighlights = showsMouseClickHighlights
        self.showsKeyboardHints = showsKeyboardHints
        self.audioSource = audioSource
        self.mouseHintColor = mouseHintColor
    }

    public static let defaults = RecordingOptions(
        format: .mp4,
        showsCursor: true,
        showsMouseClickHighlights: true,
        showsKeyboardHints: true,
        audioSource: .none,
        mouseHintColor: .default
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
