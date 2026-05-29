import CoreGraphics
import Foundation

/// A normalized image-space rectangle using a lower-left origin.
///
/// The OCR layout treats larger `y` values as visually higher in the image,
/// matching Vision-style normalized coordinates.
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
        let rows = Self.sortedRows(nonEmptyLines)
        self.lines = rows.flatMap { $0 }
        self.fullText = Self.joinedText(from: rows)
    }

    public var isEmpty: Bool {
        fullText.isEmpty
    }

    private static func sortedRows(_ lines: [RecognizedTextLine]) -> [[RecognizedTextLine]] {
        let topSortedLines = lines.sorted(by: isVisuallyBefore)
        var rows: [[RecognizedTextLine]] = []

        for line in topSortedLines {
            if let lastRow = rows.indices.last,
               let reference = rows[lastRow].first,
               isSameRow(line, reference) {
                rows[lastRow].append(line)
            } else {
                rows.append([line])
            }
        }

        return rows.map { row in row.sorted(by: isVisuallyBeforeInRow) }
    }

    private static func isVisuallyBefore(_ first: RecognizedTextLine, _ second: RecognizedTextLine) -> Bool {
        compare(firstMidY: midY(for: first), secondMidY: midY(for: second))
            ?? isVisuallyBeforeInRow(first, second)
    }

    private static func isVisuallyBeforeInRow(_ first: RecognizedTextLine, _ second: RecognizedTextLine) -> Bool {
        if let orderedByX = compare(first.bounds.x, second.bounds.x, ascending: true) {
            return orderedByX
        }

        if let orderedByY = compare(firstMidY: midY(for: first), secondMidY: midY(for: second)) {
            return orderedByY
        }

        if let orderedByWidth = compare(first.bounds.width, second.bounds.width, ascending: true) {
            return orderedByWidth
        }

        if let orderedByHeight = compare(first.bounds.height, second.bounds.height, ascending: true) {
            return orderedByHeight
        }

        if first.text != second.text {
            return first.text < second.text
        }

        return isLowerConfidence(first.confidence, than: second.confidence)
    }

    private static func compare(_ first: CGFloat, _ second: CGFloat, ascending: Bool) -> Bool? {
        if abs(first - second) <= comparisonEpsilon {
            return nil
        }

        return ascending ? first < second : first > second
    }

    private static func compare(firstMidY: CGFloat, secondMidY: CGFloat) -> Bool? {
        compare(firstMidY, secondMidY, ascending: false)
    }

    private static func isSameRow(_ first: RecognizedTextLine, _ second: RecognizedTextLine) -> Bool {
        let rowTolerance = max(first.bounds.height, second.bounds.height) * 0.6
        return abs(midY(for: first) - midY(for: second)) <= rowTolerance + comparisonEpsilon
    }

    private static func midY(for line: RecognizedTextLine) -> CGFloat {
        line.bounds.y + line.bounds.height / 2
    }

    private static func isLowerConfidence(_ first: Float?, than second: Float?) -> Bool {
        switch (first, second) {
        case (.none, .some):
            return true
        case let (.some(first), .some(second)) where first != second:
            return first < second
        default:
            return false
        }
    }

    private static func joinedText(from rows: [[RecognizedTextLine]]) -> String {
        return rows
            .map { row in row.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    private static let comparisonEpsilon: CGFloat = 1e-9
}
