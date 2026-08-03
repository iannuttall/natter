import Foundation

public enum PersonalCorrectionScope: String, CaseIterable, Codable, Identifiable, Sendable {
    case everywhere
    case agent

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .everywhere: "Everywhere"
        case .agent: "Agent only"
        }
    }
}

public struct PersonalCorrection: Equatable, Identifiable, Sendable {
    public let heard: String
    public let replacement: String
    public let scope: PersonalCorrectionScope

    // Built once per rule so applying a rule set to every partial transcript does
    // not recompile the pattern. Rules are rebuilt whenever the markdown changes.
    private let matcher: NSRegularExpression?
    private let template: String

    public var id: String { scope.rawValue + "\u{0}" + heard.lowercased() }

    public init(
        heard: String,
        replacement: String,
        scope: PersonalCorrectionScope = .everywhere
    ) {
        self.heard = heard
        self.replacement = replacement
        self.scope = scope
        let escaped = NSRegularExpression.escapedPattern(for: heard)
        matcher = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#
        )
        template = NSRegularExpression.escapedTemplate(for: replacement)
    }

    public static func == (lhs: PersonalCorrection, rhs: PersonalCorrection) -> Bool {
        lhs.heard == rhs.heard
            && lhs.replacement == rhs.replacement
            && lhs.scope == rhs.scope
    }

    fileprivate func applied(to text: String) -> String {
        guard let matcher else { return text }
        return matcher.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template
        )
    }
}

public enum PersonalCorrections {
    public static let defaultMarkdown = """
    # Personal corrections

    Add one correction per line. Matching ignores case; replacements keep the spelling below.

    <!-- Example: - "port man" → "Portman" -->
    """

    public static func parse(_ markdown: String) -> [PersonalCorrection] {
        markdown.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    public static func apply(
        _ corrections: [PersonalCorrection],
        to text: String,
        scope: PersonalCorrectionScope = .everywhere
    ) -> String {
        corrections.filter {
            $0.scope == .everywhere || $0.scope == scope
        }.reduce(text) { result, correction in
            correction.applied(to: result)
        }
    }

    public static func appending(
        _ correction: PersonalCorrection,
        to markdown: String
    ) -> String {
        guard correction.heard != correction.replacement else { return markdown }

        let existing = parse(markdown)
        if existing.contains(where: {
            $0.heard.caseInsensitiveCompare(correction.heard) == .orderedSame
                && $0.replacement == correction.replacement
                && $0.scope == correction.scope
        }) {
            return markdown
        }

        var lines = markdown.components(separatedBy: "\n")
        if let index = lines.firstIndex(where: {
            guard let existing = parseLine($0) else { return false }
            return existing.heard.caseInsensitiveCompare(correction.heard) == .orderedSame
                && existing.scope == correction.scope
        }) {
            lines[index] = formattedLine(for: correction)
            return lines.joined(separator: "\n")
        }

        let separator = markdown.hasSuffix("\n") ? "" : "\n"
        return markdown + separator + formattedLine(for: correction) + "\n"
    }

    public static func removing(
        _ correction: PersonalCorrection,
        from markdown: String
    ) -> String {
        let lines = markdown.components(separatedBy: "\n")
        return lines.filter { line in
            guard let existing = parseLine(line) else { return true }
            return existing.id != correction.id
        }.joined(separator: "\n")
    }

    private static func parseLine(_ line: String) -> PersonalCorrection? {
        let text = line.trimmingCharacters(in: .whitespaces)
        let scope: PersonalCorrectionScope
        let prefix: String
        if text.hasPrefix("- [Agent] \"") {
            scope = .agent
            prefix = "- [Agent] \""
        } else {
            scope = .everywhere
            prefix = "- \""
        }
        guard text.hasPrefix(prefix),
              let arrowRange = text.range(of: "\" → \"") ?? text.range(of: "\" => \""),
              text.hasSuffix("\"") else {
            return nil
        }

        let heardStart = text.index(text.startIndex, offsetBy: prefix.count)
        let heard = String(text[heardStart..<arrowRange.lowerBound])
        let replacementStart = arrowRange.upperBound
        let replacement = String(text[replacementStart..<text.index(before: text.endIndex)])
        guard !heard.isEmpty, !replacement.isEmpty else { return nil }
        return PersonalCorrection(heard: heard, replacement: replacement, scope: scope)
    }

    private static func formattedLine(for correction: PersonalCorrection) -> String {
        let scope = correction.scope == .agent ? "[Agent] " : ""
        return "- \(scope)\"\(correction.heard)\" → \"\(correction.replacement)\""
    }
}

public struct SpokenCorrectionExtraction: Codable, Equatable, Sendable {
    public let isCorrection: Bool
    public let heard: String
    public let replacement: String

    public init(isCorrection: Bool, heard: String, replacement: String) {
        self.isCorrection = isCorrection
        self.heard = heard
        self.replacement = replacement
    }
}

public enum SpokenCorrectionCommand {
    public static let instructions = """
    Interpret a spoken request to remember a personal speech-recognition correction.
    Return only the requested JSON object. The previous transcript is authoritative evidence for
    the exact text that was heard incorrectly. Copy `heard` exactly from that transcript, excluding
    unrelated surrounding words. Set `replacement` to the spelling or phrase the speaker requests.
    Speech recognition may collapse a distinction inside the command itself, so use its meaning and
    any explicit spelling together with the previous transcript. Never invent a correction. If the
    request is not clearly a correction, set isCorrection to false and both strings to empty.

    Example: previous transcript `I spoke to port man yesterday`; command `Hey Nata, you just
    transcribed it as Portman, but what I said was Portman Portman. Add that to my rules.`; output
    `{"isCorrection":true,"heard":"port man","replacement":"Portman"}`. The command lost the
    spacing distinction, but the requested correction and previous transcript make it recoverable.

    Example: previous transcript `Send it to en.is`; command `Hey Natter, that should be ian.is,
    i-a-n. Remember that correction.`; output
    `{"isCorrection":true,"heard":"en.is","replacement":"ian.is"}`.

    Example: there is no previous transcript; command `Hey Nata, add a rule to my profile to change
    en to en an`; output `{"isCorrection":true,"heard":"en","replacement":"ian"}`. In this common
    speech-recognition error, `en an` is a mangled letter-by-letter spelling of the name Ian.
    """

    public static let jsonSchema = #"{"type":"object","properties":{"isCorrection":{"type":"boolean"},"heard":{"type":"string"},"replacement":{"type":"string"}},"required":["isCorrection","heard","replacement"],"additionalProperties":false}"#

    public static func couldBeCommand(_ transcript: String, appNames: [String]) -> Bool {
        let spoken = normalizedWakeText(transcript)
        guard !spoken.isEmpty else { return false }

        return appNames.contains { appName in
            let wake = "hey \(normalizedWakeText(appName))"
            return wake.hasPrefix(spoken) || spoken.hasPrefix(wake)
        }
    }

    public static func looksLikeRuleRequest(_ transcript: String) -> Bool {
        let words = Set(normalizedWakeText(transcript).split(separator: " ").map(String.init))
        return (words.contains("rule") || words.contains("rules"))
            && ["add", "remember", "correct", "correction", "transcribed"].contains {
                words.contains($0)
            }
    }

    public static func canonicalizingWakeWord(
        in transcript: String,
        canonicalName: String,
        aliases: [String]
    ) -> String {
        let names = Set(aliases + [canonicalName])
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        let pattern = #"(?i)^(\s*hey\s+)(?:"# + names + #")(?=\b|[\s,])"#
        guard let regex = WakeWordPatternCache.regex(for: pattern) else { return transcript }
        return regex.stringByReplacingMatches(
            in: transcript,
            range: NSRange(transcript.startIndex..., in: transcript),
            withTemplate: "$1" + NSRegularExpression.escapedTemplate(for: canonicalName)
        )
    }

    public static func prompt(command: String, previousTranscript: String) -> String {
        let evidence = previousTranscript.isEmpty ? "(none)" : previousTranscript
        return """
        Previous transcript:
        <previous_transcript>
        \(evidence)
        </previous_transcript>

        Spoken command:
        <command>
        \(command)
        </command>
        """
    }

    public static func validatedCorrection(
        from extraction: SpokenCorrectionExtraction,
        command: String,
        previousTranscript: String
    ) -> PersonalCorrection? {
        let heard = extraction.heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = extraction.replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard extraction.isCorrection,
              !heard.isEmpty,
              !replacement.isEmpty,
              heard != replacement else {
            return nil
        }
        let correction = PersonalCorrection(heard: heard, replacement: replacement)
        let evidence = previousTranscript + "\n" + command
        guard PersonalCorrections.apply([correction], to: evidence) != evidence else {
            return nil
        }
        return correction
    }

    private static let separatorRegex = try? NSRegularExpression(pattern: #"[^\p{L}\p{N}]+"#)

    private static func normalizedWakeText(_ text: String) -> String {
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorRegex else { return trimmed.trimmingCharacters(in: .whitespaces) }
        return separatorRegex.stringByReplacingMatches(
            in: trimmed,
            range: NSRange(trimmed.startIndex..., in: trimmed),
            withTemplate: " "
        ).trimmingCharacters(in: .whitespaces)
    }
}

/// Wake-word patterns depend on the configured app names, so they cannot be a
/// literal `static let`. They change only when those names change, so a small
/// bounded cache keyed by the built pattern keeps the per-partial cost to a
/// dictionary lookup.
private enum WakeWordPatternCache {
    private static let limit = 16
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    static func regex(for pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        if cache.count >= limit { cache.removeAll() }
        cache[pattern] = regex
        return regex
    }
}
