import Foundation

public enum TranscriptEmission: Equatable, Sendable {
    case none
    case text(String)
    case conflict
}

public struct StableTranscriptEmitter: Sendable {
    public private(set) var delivered = ""

    public init() {}

    public mutating func observe(_ transcript: String) -> TranscriptEmission {
        guard transcript.hasPrefix(delivered) else { return .conflict }
        let addition = String(transcript.dropFirst(delivered.count))
        delivered = transcript
        return addition.isEmpty ? .none : .text(addition)
    }

    public mutating func finish(_ transcript: String) -> TranscriptEmission {
        guard transcript.hasPrefix(delivered) else { return .conflict }
        let addition = String(transcript.dropFirst(delivered.count))
        delivered = transcript
        return addition.isEmpty ? .none : .text(addition)
    }

    public func remainingText(in transcript: String) -> String? {
        guard transcript.hasPrefix(delivered) else { return nil }
        return String(transcript.dropFirst(delivered.count))
    }

    /// Word-level remainder for finals that came from a different decode than
    /// the delivered partials. The batch pass can disagree with the streaming
    /// preview on capitalization or punctuation while agreeing on every word;
    /// an exact prefix match would report those sessions as conflicts even
    /// though the typed text is fine. Words match on their case-folded
    /// alphanumeric content; any word-level disagreement still returns nil so
    /// real conflicts keep flowing into recovery.
    public func tolerantRemainder(in transcript: String) -> String? {
        if let exact = remainingText(in: transcript) { return exact }

        let deliveredWords = Self.foldedWords(in: delivered)
        guard !deliveredWords.isEmpty else { return transcript }

        var matched = 0
        var searchIndex = transcript.startIndex
        var remainderStart = transcript.endIndex
        for (range, folded) in Self.foldedWordRanges(in: transcript) {
            guard matched < deliveredWords.count else { break }
            guard folded == deliveredWords[matched], range.lowerBound >= searchIndex else {
                return nil
            }
            matched += 1
            searchIndex = range.upperBound
            remainderStart = range.upperBound
        }
        guard matched == deliveredWords.count else { return nil }
        return String(transcript[remainderStart...])
    }

    private static func foldedWords(in text: String) -> [String] {
        foldedWordRanges(in: text).map(\.folded)
    }

    private static func foldedWordRanges(
        in text: String
    ) -> [(range: Range<String.Index>, folded: String)] {
        var results: [(Range<String.Index>, String)] = []
        var wordStart: String.Index?
        var index = text.startIndex
        while index <= text.endIndex {
            let isWordCharacter = index < text.endIndex
                && (text[index].isLetter || text[index].isNumber || text[index] == "'")
            if isWordCharacter {
                if wordStart == nil { wordStart = index }
            } else if let start = wordStart {
                let folded = text[start..<index]
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                    .replacingOccurrences(of: "'", with: "")
                results.append((start..<index, folded))
                wordStart = nil
            }
            if index == text.endIndex { break }
            index = text.index(after: index)
        }
        return results
    }

    public mutating func reset() {
        delivered = ""
    }
}
