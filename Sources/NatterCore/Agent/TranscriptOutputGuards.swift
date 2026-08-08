import Foundation

public enum AgentEditGenerationBudget {
    public static func maximumTokens(for transcript: String) -> Int {
        let wordCount = transcript.split(whereSeparator: \.isWhitespace).count
        return min(8_192, max(1_024, 256 + wordCount * 8))
    }
}

public struct AgentRewriteSegment: Equatable, Sendable {
    public let text: String
    public let requiresRewrite: Bool

    public init(text: String, requiresRewrite: Bool) {
        self.text = text
        self.requiresRewrite = requiresRewrite
    }
}

public enum AgentRewriteSegmenter {
    public static let wholeTranscriptMaximumWords = 150

    public static func segments(_ transcript: String) -> [AgentRewriteSegment] {
        guard !transcript.isEmpty else {
            return [AgentRewriteSegment(text: transcript, requiresRewrite: false)]
        }
        return AgentTranscriptChunker.chunks(
            transcript,
            maximumWords: wholeTranscriptMaximumWords
        ).map { AgentRewriteSegment(text: $0, requiresRewrite: true) }
    }
}

public enum TranscriptTerminologyGuard {
    public static func preserves(
        _ terms: [String],
        from input: String,
        in output: String
    ) -> Bool {
        terms.allSatisfy { term in
            let inputCount = occurrenceCount(of: term, in: input)
            return inputCount == 0 || occurrenceCount(of: term, in: output) >= inputCount
        }
    }

    private static func occurrenceCount(of term: String, in text: String) -> Int {
        guard !term.isEmpty else { return 0 }
        var pattern = NSRegularExpression.escapedPattern(for: term)
        if let first = term.first,
            first.isLetter || first.isNumber || first == "_"
        {
            pattern = #"(?<![\p{L}\p{N}_])"# + pattern
        }
        if let last = term.last,
            last.isLetter || last.isNumber || last == "_"
        {
            pattern += #"(?![\p{L}\p{N}_])"#
        }
        guard
            let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
        else { return 0 }
        return regex.numberOfMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
    }
}

public enum TranscriptWordingGuard {
    private static let allowedGrammarChanges: Set<String> = [
        "are\u{0}is", "is\u{0}are",
        "need\u{0}needs", "needs\u{0}need",
        "have\u{0}has", "has\u{0}have",
        "do\u{0}does", "does\u{0}do",
        "remain\u{0}remains", "remains\u{0}remain",
    ]

    public static func preservesWords(from input: String, in output: String) -> Bool {
        let inputWords = WritingBenchmark.normalizedWords(input)
        let outputWords = WritingBenchmark.normalizedWords(output)
        guard inputWords.count == outputWords.count else { return false }
        return zip(inputWords, outputWords).allSatisfy { source, replacement in
            source == replacement
                || allowedGrammarChanges.contains(source + "\u{0}" + replacement)
        }
    }

    /// Deletion-only variant for false-start cleanup: the output's words must
    /// appear in the input in the same order (each kept word unchanged, apart
    /// from the same one-word agreement whitelist). A short abandoned thought
    /// can dominate a short segment, so segments up to 24 words may lose half
    /// their words; longer text is capped at 35% so the model can never
    /// hollow out a long transcript.
    public static func allowsOnlyDeletions(
        from input: String,
        in output: String
    ) -> Bool {
        let inputWords = WritingBenchmark.normalizedWords(input)
        let outputWords = WritingBenchmark.normalizedWords(output)
        guard !inputWords.isEmpty, outputWords.count <= inputWords.count else {
            return outputWords.isEmpty
        }
        let deleted = inputWords.count - outputWords.count
        let maximumDeletedFraction = inputWords.count <= 24 ? 0.5 : 0.35
        guard Double(deleted) / Double(inputWords.count) <= maximumDeletedFraction else {
            return false
        }

        var inputIndex = 0
        for word in outputWords {
            var matched = false
            while inputIndex < inputWords.count {
                let source = inputWords[inputIndex]
                inputIndex += 1
                if source == word
                    || allowedGrammarChanges.contains(source + "\u{0}" + word)
                {
                    matched = true
                    break
                }
            }
            guard matched else { return false }
        }
        return true
    }
}

public enum TranscriptFormattingProjection {
    /// Salvages punctuation and case from a mostly grounded model response
    /// while restoring every source word. This lets the safety guard keep a
    /// useful formatting pass when a small model inflects one or two words.
    public static func project(from source: String, onto proposed: String) -> String? {
        let sourceTokens = tokens(in: source)
        let proposedTokens = tokens(in: proposed)
        guard !sourceTokens.isEmpty, sourceTokens.count == proposedTokens.count else {
            return nil
        }

        let matching = zip(sourceTokens, proposedTokens).filter {
            $0.normalized == $1.normalized
        }.count
        guard Double(matching) / Double(sourceTokens.count) >= 0.8 else { return nil }

        var output = ""
        var cursor = proposed.startIndex
        for (sourceToken, proposedToken) in zip(sourceTokens, proposedTokens) {
            output += proposed[cursor..<proposedToken.range.lowerBound]
            output +=
                sourceToken.normalized == proposedToken.normalized
                ? proposed[proposedToken.range]
                : source[sourceToken.range]
            cursor = proposedToken.range.upperBound
        }
        output += proposed[cursor...]
        return output
    }

    private struct Token {
        let range: Range<String.Index>
        let normalized: String
    }

    private static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var wordStart: String.Index?
        var index = text.startIndex

        func appendToken(endingAt end: String.Index) {
            guard let start = wordStart else { return }
            let range = start..<end
            let normalized =
                WritingBenchmark.normalizedWords(String(text[range]))
                .first ?? ""
            if !normalized.isEmpty {
                result.append(Token(range: range, normalized: normalized))
            }
            wordStart = nil
        }

        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber
                || character == "'" || character == "’"
            {
                wordStart = wordStart ?? index
            } else {
                appendToken(endingAt: index)
            }
            index = text.index(after: index)
        }
        appendToken(endingAt: text.endIndex)
        return result
    }
}

/// Spoken asides that mark a self-interrupted thought worth cleaning up.
/// Only segments containing one of these cues are ever offered to the model
/// with deletion permission, so clean speech costs nothing.
public enum FalseStartCues {
    private static let cues = [
        "what am i", "what was i", "where was i",
        "no wait", "wait no", "actually no", "no sorry",
        "scratch that", "strike that", "forget that",
        "let me start again", "let me start over", "start that again",
        "i mean", "hang on", "hold on what",
    ]

    public static func containsCue(_ text: String) -> Bool {
        let folded = " " + WritingBenchmark.normalizedWords(text).joined(separator: " ") + " "
        return cues.contains { folded.contains(" \($0) ") }
    }
}
