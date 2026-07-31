import Foundation

public struct PersonalCorrection: Equatable, Sendable {
    public let heard: String
    public let replacement: String

    public init(heard: String, replacement: String) {
        self.heard = heard
        self.replacement = replacement
    }
}

public enum PersonalCorrections {
    public static let defaultMarkdown = """
    # Personal corrections

    Add one correction per line. Matching ignores case; replacements keep the spelling below.

    - "en.is" → "ian.is"
    """

    public static func parse(_ markdown: String) -> [PersonalCorrection] {
        markdown.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line).trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("- \""),
                  let arrowRange = text.range(of: "\" → \"") ?? text.range(of: "\" => \""),
                  text.hasSuffix("\"") else {
                return nil
            }

            let heardStart = text.index(text.startIndex, offsetBy: 3)
            let heard = String(text[heardStart..<arrowRange.lowerBound])
            let replacementStart = arrowRange.upperBound
            let replacement = String(text[replacementStart..<text.index(before: text.endIndex)])
            guard !heard.isEmpty, !replacement.isEmpty else { return nil }
            return PersonalCorrection(heard: heard, replacement: replacement)
        }
    }

    public static func apply(_ corrections: [PersonalCorrection], to text: String) -> String {
        corrections.reduce(text) { result, correction in
            let escaped = NSRegularExpression.escapedPattern(for: correction.heard)
            let pattern = #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
            let range = NSRange(result.startIndex..., in: result)
            return regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: correction.replacement)
            )
        }
    }

    public static func appending(
        _ correction: PersonalCorrection,
        to markdown: String
    ) -> String {
        let existing = parse(markdown)
        if existing.contains(where: {
            $0.heard.caseInsensitiveCompare(correction.heard) == .orderedSame
                && $0.replacement == correction.replacement
        }) {
            return markdown
        }

        let separator = markdown.hasSuffix("\n") ? "" : "\n"
        return markdown + separator + "- \"\(correction.heard)\" → \"\(correction.replacement)\"\n"
    }
}

public enum SpokenCorrectionParser {
    public static func couldBeCommand(_ transcript: String, appNames: [String]) -> Bool {
        let spoken = normalizedWakeText(transcript)
        guard !spoken.isEmpty else { return false }

        return appNames.contains { appName in
            let wake = "hey \(normalizedWakeText(appName))"
            return wake.hasPrefix(spoken) || spoken.hasPrefix(wake)
        }
    }

    public static func parse(
        _ transcript: String,
        appNames: [String]
    ) -> PersonalCorrection? {
        let escapedNames = appNames
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        let pattern = #"(?is)^\s*hey\s+(?:"# + escapedNames
            + #")\s*,?\s+(?:you\s+)?(?:just\s+)?transcribed(?:\s+it)?\s+as\s+(.+?)\s+but\s+(?:what\s+)?i\s+actually\s+said\s+was\s+(.+?)(?:\s+[a-z](?:-[a-z]){1,})?(?:\s+can\s+you\s+add\b.*)?\s*[.?!]?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: transcript,
                  range: NSRange(transcript.startIndex..., in: transcript)
              ),
              let heardRange = Range(match.range(at: 1), in: transcript),
              let replacementRange = Range(match.range(at: 2), in: transcript) else {
            return nil
        }

        let heard = transcript[heardRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = transcript[replacementRange].trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !heard.isEmpty, !replacement.isEmpty else { return nil }
        return PersonalCorrection(heard: heard, replacement: replacement)
    }

    private static func normalizedWakeText(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
