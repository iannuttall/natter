import Foundation

public enum WritingRules {
    public static let legacyArticleMarkdownV1 = """
    # Article mode

    - Restructure the transcript into clear prose in the speaker's voice.
    - Remove filler and false starts.
    - Preserve every fact, example, qualification and opinion.
    - Add headings only when they materially improve a longer piece.
    - Never invent evidence, transitions or conclusions.
    """

    public static func defaultMarkdown(for mode: DictationMode) -> String {
        switch mode {
        case .agent:
            """
            # Agent mode

            - Make the smallest possible corrections justified by technical context.
            - Correct obvious speech-recognition homophones for commands, tools and identifiers.
            - Format explicit CLI commands, subcommands, flags, paths and code symbols literally.
            - Lowercase command names and flags only when the command context is unambiguous.
            - Preserve the speaker's request, word order, constraints, profanity and line breaks.
            - Do not turn prose into source code, Markdown or a different command.
            - If a change is uncertain, leave it unchanged.
            """
        case .clean:
            """
            # Clean mode

            - Remove filler words such as um, erm, uh and ah.
            - Resolve false starts and repeated fragments.
            - Keep the speaker's wording, meaning, facts, uncertainty and profanity.
            - Do not make the result more formal or polite.
            """
        case .email:
            """
            # Email mode

            - Write a direct, natural email in the speaker's voice.
            - Remove filler and false starts.
            - Use short paragraphs where they help.
            - Do not invent a greeting, sign-off, names, dates or promises.
            - Do not make the message corporate or over-polite.
            """
        case .article:
            """
            # Article mode

            - Restructure the transcript into clear prose in the speaker's voice.
            - Remove filler and false starts.
            - Preserve every fact, example, qualification and opinion.
            - Do not add a title.
            - Use headings only when the transcript contains several distinct sections that need them.
            - Never invent evidence, transitions or conclusions.
            """
        case .raw:
            ""
        }
    }

    public static func prompt(
        transcript: String,
        mode: DictationMode,
        markdownRules: String
    ) -> String {
        """
        Mode: \(mode.label)

        User rules:
        <rules>
        \(markdownRules)
        </rules>

        Speech transcript:
        <transcript>
        \(transcript)
        </transcript>
        """
    }
}

public enum DeterministicTranscriptCleaner {
    public static func clean(_ transcript: String) -> String {
        let withoutFillers = removeFillers(from: transcript)
        return removeRepeatedFragments(from: withoutFillers)
    }

    public static func removeFillers(from transcript: String) -> String {
        var result = transcript
        let patterns = [
            #"(?i)(?<![\p{L}\p{N}_])(?:uhm+|um+|erm+|uh+|ah+|eh+|hmm+)(?:[,.]?\s+|[,.]?$)"#,
            #"\s+([,.;:!?])"#,
            #"[ \t]{2,}"#
        ]
        let replacements = ["", "$1", " "]
        for (pattern, replacement) in zip(patterns, replacements) {
            result = result.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func removeRepeatedFragments(from transcript: String) -> String {
        var result = transcript

        while let range = firstRepeatedFragment(in: result) {
            result.removeSubrange(range)
        }

        result = result.replacingOccurrences(
            of: #"\s+([,.;:!?])"#,
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstRepeatedFragment(in text: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(
            pattern: #"[\p{L}\p{N}]+(?:['’_-][\p{L}\p{N}]+)*"#
        ) else { return nil }

        let fullRange = NSRange(text.startIndex..., in: text)
        let tokens = regex.matches(in: text, range: fullRange).compactMap { match -> Token? in
            guard let range = Range(match.range, in: text) else { return nil }
            return Token(range: range, folded: text[range].folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            ))
        }
        guard tokens.count >= 2 else { return nil }

        for start in tokens.indices {
            let maximumLength = min(8, (tokens.count - start) / 2)
            guard maximumLength > 0 else { continue }

            for length in stride(from: maximumLength, through: 1, by: -1) {
                let secondStart = start + length
                let firstWords = tokens[start ..< secondStart].map(\.folded)
                let secondWords = tokens[secondStart ..< secondStart + length].map(\.folded)
                guard firstWords == secondWords else { continue }

                let separator = text[tokens[secondStart - 1].range.upperBound
                    ..< tokens[secondStart].range.lowerBound]
                guard separator.allSatisfy({ $0.isWhitespace || $0 == "," }) else {
                    continue
                }

                return tokens[start].range.lowerBound ..< tokens[secondStart].range.lowerBound
            }
        }
        return nil
    }

    private struct Token {
        let range: Range<String.Index>
        let folded: String
    }
}

public enum TranscriptFactGuard {
    public static func protectedFacts(in transcript: String) -> [String] {
        let patterns = [
            #"(?:https?://|www\.)[^\s]+"#,
            #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#,
            #"(?<![:/])(?:~?/|/)[A-Za-z0-9._~/-]+"#,
            #"(?<![\p{L}\p{N}_])\d+(?:[.,]\d+)*(?:%|ms|MB|GB|TB|x)?(?![\p{L}\p{N}_])"#
        ]
        var facts: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(transcript.startIndex..., in: transcript)
            for match in regex.matches(in: transcript, range: range) {
                guard let matchRange = Range(match.range, in: transcript) else { continue }
                let fact = String(transcript[matchRange])
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?"))
                if !fact.isEmpty, !facts.contains(fact) { facts.append(fact) }
            }
        }
        return facts
    }

    public static func preservesFacts(from transcript: String, in output: String) -> Bool {
        protectedFacts(in: transcript).allSatisfy {
            output.localizedCaseInsensitiveContains($0)
        }
    }
}
