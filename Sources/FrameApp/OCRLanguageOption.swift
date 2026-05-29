import Foundation

enum OCRLanguageOption: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case french = "fr-FR"
    case italian = "it-IT"
    case german = "de-DE"
    case spanish = "es-ES"
    case portugueseBrazil = "pt-BR"
    case russian = "ru-RU"
    case ukrainian = "uk-UA"
    case thai = "th-TH"
    case vietnamese = "vi-VT"
    case arabic = "ar-SA"
    case turkish = "tr-TR"
    case indonesian = "id-ID"
    case czech = "cs-CZ"
    case danish = "da-DK"
    case dutch = "nl-NL"
    case norwegian = "no-NO"
    case malay = "ms-MY"
    case polish = "pl-PL"
    case romanian = "ro-RO"
    case swedish = "sv-SE"

    var id: String {
        rawValue
    }

    static let defaultIdentifiers = [
        simplifiedChinese.rawValue,
        traditionalChinese.rawValue,
        english.rawValue,
        japanese.rawValue,
        korean.rawValue,
    ]

    static func validatedIdentifiers(_ identifiers: [String]) -> [String] {
        let supportedIdentifiers = Set(allCases.map(\.rawValue))
        let filteredIdentifiers = identifiers.filter { supportedIdentifiers.contains($0) }

        return filteredIdentifiers.isEmpty ? defaultIdentifiers : filteredIdentifiers
    }
}
