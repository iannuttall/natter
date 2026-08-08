import Foundation

public struct SpokenLowercaseResult: Equatable, Sendable {
    public let transcript: String
    public let consumedCommand: Bool

    public init(transcript: String, consumedCommand: Bool) {
        self.transcript = transcript
        self.consumedCommand = consumedCommand
    }
}

public enum SpokenLowercaseCommand {
    private static let phrases = ["lowercase", "lower case"]
    private static let commandPunctuation = CharacterSet(charactersIn: ",.:;-")

    public static func consume(from transcript: String) -> SpokenLowercaseResult {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()
        guard let phrase = phrases.first(where: { phrase in
            guard normalized.hasPrefix(phrase) else { return false }
            guard normalized.count > phrase.count else { return true }
            let boundary = normalized.index(normalized.startIndex, offsetBy: phrase.count)
            let character = normalized[boundary]
            return character.isWhitespace || character.unicodeScalars.allSatisfy {
                commandPunctuation.contains($0)
            }
        }) else {
            return SpokenLowercaseResult(transcript: transcript, consumedCommand: false)
        }

        var remainder = String(trimmed.dropFirst(phrase.count))
            .trimmingCharacters(in: .whitespaces)
        while let first = remainder.unicodeScalars.first,
              commandPunctuation.contains(first) {
            remainder.removeFirst()
            remainder = remainder.trimmingCharacters(in: .whitespaces)
        }

        guard remainder.contains(where: \.isLetter) else {
            return SpokenLowercaseResult(transcript: "", consumedCommand: true)
        }
        return SpokenLowercaseResult(
            transcript: lowercaseInitial(in: remainder),
            consumedCommand: true
        )
    }

    public static func lowercaseInitial(in transcript: String) -> String {
        guard let firstLetter = transcript.firstIndex(where: \.isLetter) else {
            return transcript
        }
        var result = transcript
        result.replaceSubrange(
            firstLetter...firstLetter,
            with: String(transcript[firstLetter]).lowercased()
        )
        return result
    }
}
