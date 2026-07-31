import Foundation

public enum WritingRules {
    public static func defaultMarkdown(for mode: DictationMode) -> String {
        switch mode {
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
            - Add headings only when they materially improve a longer piece.
            - Never invent evidence, transitions or conclusions.
            """
        case .raw, .agent:
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
    public static func removeFillers(from transcript: String) -> String {
        var result = transcript
        let patterns = [
            #"(?i)(?<![\p{L}\p{N}_])(?:um+|erm+|uh+|ah+)(?:[,.]?\s+|[,.]?$)"#,
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
