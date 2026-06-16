import Foundation

public enum VideoEditingStateError: Equatable, Error {
    case invalidSourceDuration
    case invalidTrimRange
    case unsupportedSpeed
}

public struct VideoPlaybackSpeed: Equatable, Sendable {
    public let rate: Double
    public let displayName: String

    public init(rate: Double, displayName: String) {
        self.rate = rate
        self.displayName = displayName
    }

    public static let half = VideoPlaybackSpeed(rate: 0.5, displayName: "0.5x")
    public static let one = VideoPlaybackSpeed(rate: 1, displayName: "1x")
    public static let oneAndQuarter = VideoPlaybackSpeed(rate: 1.25, displayName: "1.25x")
    public static let oneAndHalf = VideoPlaybackSpeed(rate: 1.5, displayName: "1.5x")
    public static let double = VideoPlaybackSpeed(rate: 2, displayName: "2x")
    public static let quadruple = VideoPlaybackSpeed(rate: 4, displayName: "4x")
    public static let octuple = VideoPlaybackSpeed(rate: 8, displayName: "8x")

    public static let presets: [VideoPlaybackSpeed] = [
        .half,
        .one,
        .oneAndQuarter,
        .oneAndHalf,
        .double,
        .quadruple,
        .octuple,
    ]

    public static func presetsContain(_ speed: VideoPlaybackSpeed) -> Bool {
        presets.contains(speed)
    }
}

public struct VideoEditingState: Equatable, Sendable {
    public static let precision: TimeInterval = 0.01
    public static let minimumSelectedDuration: TimeInterval = 0.05

    public let sourceDuration: TimeInterval
    public private(set) var startTime: TimeInterval
    public private(set) var endTime: TimeInterval
    public private(set) var speed: VideoPlaybackSpeed

    public init(sourceDuration: TimeInterval) throws {
        guard sourceDuration.isFinite,
              sourceDuration > Self.minimumSelectedDuration else {
            throw VideoEditingStateError.invalidSourceDuration
        }

        self.sourceDuration = Self.quantized(sourceDuration)
        startTime = 0
        endTime = Self.quantized(sourceDuration)
        speed = .one
    }

    public var selectedDuration: TimeInterval {
        max(0, endTime - startTime)
    }

    public var outputDuration: TimeInterval {
        selectedDuration / speed.rate
    }

    public var isDirty: Bool {
        abs(startTime) > 0.0001
            || abs(endTime - sourceDuration) > 0.0001
            || speed != .one
    }

    public mutating func setTrimRange(start: TimeInterval, end: TimeInterval) throws {
        let nextStart = Self.quantized(start)
        let nextEnd = Self.quantized(end)

        guard nextStart >= 0,
              nextEnd <= sourceDuration,
              nextEnd - nextStart >= Self.minimumSelectedDuration else {
            throw VideoEditingStateError.invalidTrimRange
        }

        startTime = nextStart
        endTime = nextEnd
    }

    public mutating func setSpeed(_ nextSpeed: VideoPlaybackSpeed) throws {
        guard VideoPlaybackSpeed.presetsContain(nextSpeed) else {
            throw VideoEditingStateError.unsupportedSpeed
        }

        speed = nextSpeed
    }

    public static func quantized(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else {
            return 0
        }

        return (value / precision).rounded() * precision
    }
}
