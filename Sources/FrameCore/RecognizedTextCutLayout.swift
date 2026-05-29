import Foundation

public struct RecognizedTextCut: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let text: String
    public let lineIndex: Int
    public let tokenIndex: Int
    public let bounds: NormalizedImageRect
    public let needsLeadingSpace: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        lineIndex: Int,
        tokenIndex: Int,
        bounds: NormalizedImageRect,
        needsLeadingSpace: Bool
    ) {
        self.id = id
        self.text = text
        self.lineIndex = lineIndex
        self.tokenIndex = tokenIndex
        self.bounds = bounds
        self.needsLeadingSpace = needsLeadingSpace
    }
}

public struct RecognizedTextCutRow: Equatable, Sendable {
    public let lineIndex: Int
    public let cuts: [RecognizedTextCut]

    public init(lineIndex: Int, cuts: [RecognizedTextCut]) {
        self.lineIndex = lineIndex
        self.cuts = cuts
    }
}

public struct RecognizedTextCutLayout: Equatable, Sendable {
    public let rows: [RecognizedTextCutRow]

    public init(textLayout: RecognizedTextLayout) {
        self.rows = textLayout.lines.enumerated().compactMap { lineIndex, line in
            let tokenizedCuts = Self.tokenize(
                line.text,
                lineIndex: lineIndex,
                lineBounds: line.bounds
            )
            let cuts = tokenizedCuts.isEmpty
                ? Self.fallbackCut(for: line, lineIndex: lineIndex)
                : tokenizedCuts

            return cuts.isEmpty ? nil : RecognizedTextCutRow(lineIndex: lineIndex, cuts: cuts)
        }
    }

    public var allCutIDs: Set<UUID> {
        Set(rows.flatMap(\.cuts).map(\.id))
    }

    public func cut(for id: UUID) -> RecognizedTextCut? {
        rows.flatMap(\.cuts).first { $0.id == id }
    }

    public func selectedText(for selectedIDs: Set<UUID>) -> String {
        rows.compactMap { row in
            let rowText = row.cuts.reduce(into: "") { text, cut in
                guard selectedIDs.contains(cut.id) else {
                    return
                }

                if cut.needsLeadingSpace, !text.isEmpty {
                    text.append(" ")
                }
                text.append(cut.text)
            }

            return rowText.isEmpty ? nil : rowText
        }
        .joined(separator: "\n")
    }

    private static func tokenize(
        _ text: String,
        lineIndex: Int,
        lineBounds: NormalizedImageRect
    ) -> [RecognizedTextCut] {
        var cuts: [RecognizedTextCut] = []
        var token = ""
        var tokenNeedsLeadingSpace = false
        var sawWhitespace = false

        func flushToken() {
            guard !token.isEmpty else {
                return
            }

            cuts.append(RecognizedTextCut(
                text: token,
                lineIndex: lineIndex,
                tokenIndex: cuts.count,
                bounds: lineBounds,
                needsLeadingSpace: tokenNeedsLeadingSpace
            ))
            token = ""
            tokenNeedsLeadingSpace = false
        }

        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if character.isWhitespace {
                flushToken()
                sawWhitespace = true
                continue
            }

            if character.isSingleCharacterTextCut {
                flushToken()
                cuts.append(RecognizedTextCut(
                    text: String(character),
                    lineIndex: lineIndex,
                    tokenIndex: cuts.count,
                    bounds: lineBounds,
                    needsLeadingSpace: sawWhitespace && !cuts.isEmpty
                ))
                sawWhitespace = false
                continue
            }

            if character.isASCIIWordRunCharacter {
                if token.isEmpty {
                    tokenNeedsLeadingSpace = sawWhitespace && !cuts.isEmpty
                }
                token.append(character)
                sawWhitespace = false
                continue
            }

            if character.isCodeJoiner,
               !token.isEmpty,
               characters.dropFirst(index + 1).first?.isASCIIWordRunCharacter == true {
                token.append(character)
                sawWhitespace = false
                continue
            }

            flushToken()
            cuts.append(RecognizedTextCut(
                text: String(character),
                lineIndex: lineIndex,
                tokenIndex: cuts.count,
                bounds: lineBounds,
                needsLeadingSpace: sawWhitespace && !cuts.isEmpty
            ))
            sawWhitespace = false
        }

        flushToken()
        return cuts
    }

    private static func fallbackCut(
        for line: RecognizedTextLine,
        lineIndex: Int
    ) -> [RecognizedTextCut] {
        let trimmedText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return []
        }

        return [
            RecognizedTextCut(
                text: trimmedText,
                lineIndex: lineIndex,
                tokenIndex: 0,
                bounds: line.bounds,
                needsLeadingSpace: false
            ),
        ]
    }
}

private extension Character {
    var isWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    var isSingleCharacterTextCut: Bool {
        unicodeScalars.contains { scalar in
            scalar.isCJKUnifiedIdeograph
                || scalar.isHiragana
                || scalar.isKatakana
                || scalar.isHangul
        }
    }

    var isASCIIWordRunCharacter: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.allSatisfy { scalar in
                scalar.isASCIILetter
                    || scalar.isASCIIDigit
                    || Self.asciiWordScalars.contains(scalar)
            }
    }

    var isCodeJoiner: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.allSatisfy { Self.codeJoinerScalars.contains($0) }
    }

    private static let asciiWordScalars = Set("_-".unicodeScalars)
    private static let codeJoinerScalars = Set("/@.".unicodeScalars)
}

private extension Unicode.Scalar {
    var isASCIILetter: Bool {
        (65...90).contains(value) || (97...122).contains(value)
    }

    var isASCIIDigit: Bool {
        (48...57).contains(value)
    }

    var isCJKUnifiedIdeograph: Bool {
        (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || (0x20000...0x2A6DF).contains(value)
            || (0x2A700...0x2B73F).contains(value)
            || (0x2B740...0x2B81F).contains(value)
            || (0x2B820...0x2CEAF).contains(value)
            || (0x2CEB0...0x2EBEF).contains(value)
            || (0x30000...0x3134F).contains(value)
            || (0x31350...0x323AF).contains(value)
    }

    var isHiragana: Bool {
        (0x3040...0x309F).contains(value)
    }

    var isKatakana: Bool {
        (0x30A0...0x30FF).contains(value)
            || (0x31F0...0x31FF).contains(value)
    }

    var isHangul: Bool {
        (0xAC00...0xD7AF).contains(value)
            || (0x1100...0x11FF).contains(value)
            || (0x3130...0x318F).contains(value)
            || (0xA960...0xA97F).contains(value)
            || (0xD7B0...0xD7FF).contains(value)
    }
}
