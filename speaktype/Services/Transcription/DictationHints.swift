import Foundation

enum DictationHints {
    static let dictionaryKey = "dictationDictionary"
    static let swedishEnglish = "sv-en"
    static let swedishEnglishLabel = "Swedish + English"
    static let maximumTerms = 30
    static let maximumTermBytes = 64

    static func singleLanguage(_ selection: String) -> String? {
        switch selection {
        case "", "auto", swedishEnglish: return nil
        default: return selection
        }
    }

    static func languages(for selection: String) -> [String] {
        if selection == swedishEnglish { return ["sv", "en"] }
        return singleLanguage(selection).map { [$0] } ?? []
    }

    static func keywords(in dictionary: String) -> [String] {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "<>"))
        var seen: Set<String> = []
        var terms: [String] = []
        for line in dictionary.split(whereSeparator: \.isNewline) {
            let term = line.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, term.utf8.count <= maximumTermBytes,
                  term.rangeOfCharacter(from: forbidden) == nil else { continue }
            let comparison = term.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(comparison).inserted else { continue }
            terms.append(term)
            if terms.count == maximumTerms { break }
        }
        return terms
    }
}
