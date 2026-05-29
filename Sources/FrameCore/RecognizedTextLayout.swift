import CoreGraphics
import Foundation

public struct NormalizedImageRect: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = NormalizedImageRect(x: 0, y: 0, width: 0, height: 0)
}

public struct RecognizedTextLine: Equatable, Sendable {
    public let text: String
    public let bounds: NormalizedImageRect
    public let confidence: Float?

    public init(text: String, bounds: NormalizedImageRect, confidence: Float?) {
        self.text = text
        self.bounds = bounds
        self.confidence = confidence
    }
}

public struct RecognizedTextLayout: Equatable, Sendable {
    public let lines: [RecognizedTextLine]
    public let fullText: String

    public init(lines: [RecognizedTextLine]) {
        let nonEmptyLines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.lines = Self.sortedLines(nonEmptyLines)
        self.fullText = Self.joinedText(from: self.lines)
    }

    public var isEmpty: Bool {
        fullText.isEmpty
    }

    private static func sortedLines(_ lines: [RecognizedTextLine]) -> [RecognizedTextLine] {
        lines.sorted { first, second in
            let firstMidY = first.bounds.y + first.bounds.height / 2
            let secondMidY = second.bounds.y + second.bounds.height / 2
            let rowTolerance = max(first.bounds.height, second.bounds.height) * 0.6

            if abs(firstMidY - secondMidY) <= rowTolerance {
                return first.bounds.x < second.bounds.x
            }

            return firstMidY > secondMidY
        }
    }

    private static func joinedText(from lines: [RecognizedTextLine]) -> String {
        var rows: [[RecognizedTextLine]] = []
        for line in lines {
            if let lastRow = rows.indices.last,
               let reference = rows[lastRow].first,
               abs((line.bounds.y + line.bounds.height / 2) - (reference.bounds.y + reference.bounds.height / 2)) <= max(line.bounds.height, reference.bounds.height) * 0.6 {
                rows[lastRow].append(line)
            } else {
                rows.append([line])
            }
        }

        return rows
            .map { row in row.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
