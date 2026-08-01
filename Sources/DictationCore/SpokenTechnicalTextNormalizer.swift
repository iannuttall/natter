import Foundation

public enum SpokenFormattingContext: Sendable {
    case prose
    case technical
}

public enum SpokenTechnicalTextNormalizer {
    private static let digitWords: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3",
        "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8",
        "nine": "9"
    ]

    private static let percentValues: [String: Int] = [
        "zero": 0, "ten": 10, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        "one hundred": 100
    ]

    private static let percentUnits: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9
    ]

    private static let technicalSuffixes = [
        "ai", "app", "co", "com", "css", "dev", "go", "html", "io", "is",
        "island", "js", "json", "jsx", "md", "net",
        "org", "py", "rb", "rs", "sh", "swift", "toml", "ts", "tsx", "txt",
        "uk", "yaml", "yml", "zsh"
    ].joined(separator: "|")

    public static func normalize(
        _ transcript: String,
        context: SpokenFormattingContext = .prose
    ) -> String {
        var result = transcript
        result = replaceDigitSequences(in: result)
        result = replacePercentages(in: result)
        result = replaceMatches(
            in: result,
            pattern: #"(?i)\btilde\s+slash\s+[\p{L}\p{N}._-]+(?:\s+slash\s+[\p{L}\p{N}._-]+)*"#,
            with: tildePath
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)\s+dot\s+("# + technicalSuffixes + #")\b"#,
            with: dotSuffix
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}._%+-])([\p{L}\p{N}._%+-]+)\s+at\s+([\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+)"#,
            with: emailAddress
        )
        if context == .technical {
            result = replaceMatches(
                in: result,
                pattern: #"(?i)\bdot\s+(?=[\p{L}\p{N}_-])"#,
                with: { _ in "." }
            )
            result = replaceMatches(
                in: result,
                pattern: #"(?i)\s+slash\s+"#,
                with: { _ in "/" }
            )
            result = replaceMatches(
                in: result,
                pattern: #"(?i)\bdash\s+dash\s+([\p{L}\p{N}][\p{L}\p{N}-]*)"#,
                withTemplate: "--$1"
            )
            result = replaceMatches(
                in: result,
                pattern: #"(?i)\s+colon(?=\s|$)"#,
                with: { _ in ":" }
            )
        }
        return result
    }

    private static func dotSuffix(_ match: String) -> String {
        let suffix = match.split(whereSeparator: { $0.isWhitespace }).last ?? ""
        return "." + suffix.lowercased()
    }

    private static func tildePath(_ match: String) -> String {
        let withoutPrefix = replaceMatches(
            in: match,
            pattern: #"(?i)^tilde\s+slash\s+"#,
            with: { _ in "" }
        )
        let path = replaceMatches(
            in: withoutPrefix,
            pattern: #"(?i)\s+slash\s+"#,
            with: { _ in "/" }
        )
        return "~/" + path
    }

    private static func emailAddress(_ match: String) -> String {
        replaceMatches(
            in: match,
            pattern: #"(?i)\s+at\s+"#,
            with: { _ in "@" }
        ).lowercased()
    }

    private static func replaceDigitSequences(in text: String) -> String {
        let digit = digitWords.keys.sorted().joined(separator: "|")
        let pattern = #"(?i)(?<![\p{L}\p{N}_])(?:"# + digit
            + #")(?:[\s-]+(?:"# + digit + #"))+(?![\p{L}\p{N}_])"#
        return replaceMatches(in: text, pattern: pattern) { match in
            match.lowercased()
                .split(whereSeparator: { $0 == " " || $0 == "-" })
                .compactMap { digitWords[String($0)] }
                .joined()
        }
    }

    private static func replacePercentages(in text: String) -> String {
        let tens = percentValues.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let units = percentUnits.keys.sorted().joined(separator: "|")
        let pattern = #"(?i)(?<![\p{L}\p{N}_])("# + tens + #")(?:[-\s]+("# + units
            + #"))?\s+(?:percent|per\s+cent)(?![\p{L}\p{N}_])"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let tensRange = Range(match.range(at: 1), in: result),
                  let base = percentValues[String(result[tensRange]).lowercased()] else {
                continue
            }
            let unit: Int
            if let unitRange = Range(match.range(at: 2), in: result) {
                unit = percentUnits[String(result[unitRange]).lowercased()] ?? 0
            } else {
                unit = 0
            }
            result.replaceSubrange(fullRange, with: "\(base + unit)%")
        }
        return result
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        with transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }

    private static func replaceMatches(
        in text: String,
        pattern: String,
        withTemplate template: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
