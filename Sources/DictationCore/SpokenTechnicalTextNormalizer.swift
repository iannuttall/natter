import Foundation

public enum SpokenFormattingContext: String, Codable, Sendable {
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

    private static let flagBoundaryWords: Set<String> = [
        "and", "as", "at", "before", "but", "by", "every", "for", "from",
        "if", "in", "into", "of", "on", "or", "so", "than", "that", "the",
        "then", "to", "when", "while", "with"
    ]

    public static func normalize(
        _ transcript: String,
        context: SpokenFormattingContext = .prose
    ) -> String {
        var result = replaceSpelledLetterSequences(in: transcript)
        if context == .technical {
            result = replaceMatches(
                in: result,
                using: etCeteraRegex,
                with: { _ in "etc." }
            )
            result = replaceMatches(
                in: result,
                using: spokenVersionRegex,
                with: spokenVersion
            )
        }
        result = replaceMatches(
            in: result,
            using: spokenDecimalRegex,
            with: spokenDecimal
        )
        result = replaceDigitSequences(in: result)
        result = replacePercentages(in: result)
        result = replaceMatches(
            in: result,
            using: tildePathRegex,
            with: tildePath
        )
        result = replaceMatches(
            in: result,
            using: dotSuffixRegex,
            with: dotSuffix
        )
        result = replaceMatches(
            in: result,
            using: emailAddressRegex,
            with: emailAddress
        )
        if context == .technical {
            result = replaceMatches(
                in: result,
                using: technicalDotRegex,
                with: { _ in "." }
            )
            result = replaceMatches(
                in: result,
                using: slashSeparatorRegex,
                with: { _ in "/" }
            )
            result = replaceMatches(
                in: result,
                using: doubleDashRegex,
                with: doubleDash
            )
            result = replaceMatches(
                in: result,
                using: singleDashRegex,
                with: singleDash
            )
            result = replaceMatches(
                in: result,
                using: spokenColonRegex,
                with: { _ in ":" }
            )
        }
        return result
    }

    // Compiled once and reused: `normalize` runs on every partial transcript, and
    // `NSRegularExpression` is immutable and safe to share.
    private static let etCeteraRegex = compiled(#"(?i)\b(?:et\s+cetera|etcetera)\b"#)

    private static let tildePathRegex = compiled(
        #"(?i)\btilde\s+slash\s+[\p{L}\p{N}._-]+(?:\s+slash\s+[\p{L}\p{N}._-]+)*"#
    )

    private static let dotSuffixRegex = compiled(
        #"(?i)\s+dot\s+("# + technicalSuffixes + #")\b"#
    )

    private static let emailAddressRegex = compiled(
        #"(?i)(?<![\p{L}\p{N}._%+-])([\p{L}\p{N}._%+-]+)\s+at\s+([\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+)"#
    )

    private static let technicalDotRegex = compiled(#"(?i)\bdot\s+(?=[\p{L}\p{N}_-])"#)

    private static let slashSeparatorRegex = compiled(#"(?i)\s+slash\s+"#)

    private static let doubleDashRegex = compiled(
        #"(?i)\b(?:dash\s+dash|double\s+dash|hyphen\s+hyphen|two\s+(?:dashes|hyphens))(?:\s+[\p{L}\p{N}][\p{L}\p{N}-]*)?"#
    )

    private static let singleDashRegex = compiled(#"(?i)\b(?:dash|hyphen)\s+[a-z0-9]\b"#)

    private static let spokenColonRegex = compiled(#"(?i)\s+colon(?=\s|$)"#)

    private static let tildePathPrefixRegex = compiled(#"(?i)^tilde\s+slash\s+"#)

    private static let atSeparatorRegex = compiled(#"(?i)\s+at\s+"#)

    private static let spelledLowercaseRegex = compiled(
        #"(?i)\blowercase\s+((?:[a-z]\s+){2,}[a-z])\b"#
    )

    private static let spelledUppercaseRegex = compiled(
        #"(?<![\p{L}\p{N}])(?:[A-Z]\s+){2,}[A-Z](?![\p{L}\p{N}])"#
    )

    private static let spelledHyphenatedRegex = compiled(
        #"(?<![\p{L}\p{N}])(?:[A-Za-z]-){2,}[A-Za-z](?![\p{L}\p{N}])"#
    )

    private static let numberWords = [
        "zero", "oh", "one", "two", "three", "four", "five", "six", "seven",
        "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
        "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty",
        "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
        "hundred"
    ]

    private static let spokenVersionRegex: NSRegularExpression? = {
        let word = "(?:" + numberWords.joined(separator: "|") + ")"
        let component = "(?:[0-9]+|" + word + "(?:[ -]+" + word + ")*)"
        return compiled(
            #"(?i)\b(?:v|version)\s+"# + component
                + #"(?:\s+point\s+"# + component + #")*\b"#
        )
    }()

    private static let spokenDecimalRegex: NSRegularExpression? = {
        let word = "(?:" + numberWords.joined(separator: "|") + ")"
        let whole = "(?:[0-9]+|" + word + "(?:[ -]+" + word + ")*)"
        let decimalDigit = "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)"
        return compiled(
            #"(?i)\b"# + whole + #"\s+point\s+"#
                + decimalDigit + #"(?:[ -]+"# + decimalDigit + #")*\b"#
        )
    }()

    private static let digitSequenceRegex: NSRegularExpression? = {
        let digit = digitWords.keys.sorted().joined(separator: "|")
        return compiled(
            #"(?i)(?<![\p{L}\p{N}_])(?:"# + digit
                + #")(?:[\s-]+(?:"# + digit + #"))+(?![\p{L}\p{N}_])"#
        )
    }()

    private static let percentageRegex: NSRegularExpression? = {
        let tens = percentValues.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        let units = percentUnits.keys.sorted().joined(separator: "|")
        return compiled(
            #"(?i)(?<![\p{L}\p{N}_])("# + tens + #")(?:[-\s]+("# + units
                + #"))?\s+(?:percent|per\s+cent)(?![\p{L}\p{N}_])"#
        )
    }()

    private static func spokenDecimal(_ match: String) -> String {
        let lowered = match.lowercased()
        guard let range = lowered.range(of: " point "),
              let whole = parseNumberComponent(String(lowered[..<range.lowerBound])) else {
            return match
        }
        let decimalWords = lowered[range.upperBound...]
            .split { $0 == " " || $0 == "-" }
            .map(String.init)
        let decimal = decimalWords.compactMap { digitWords[$0] }.joined()
        guard decimal.count == decimalWords.count else { return match }
        return whole + "." + decimal
    }

    private static func spokenVersion(_ match: String) -> String {
        let pieces = match.split(whereSeparator: \.isWhitespace)
        guard let first = pieces.first else { return match }
        let prefix = first.lowercased() == "v" ? "v" : "version "
        let remainder = pieces.dropFirst().joined(separator: " ").lowercased()
        let components = remainder.components(separatedBy: " point ")
        let values = components.compactMap(parseNumberComponent)
        guard values.count == components.count else { return match }
        return prefix + values.joined(separator: ".")
    }

    private static func parseNumberComponent(_ component: String) -> String? {
        if component.allSatisfy(\.isNumber) {
            return component
        }

        let words = component.lowercased().split { $0 == " " || $0 == "-" }.map(String.init)
        guard !words.isEmpty else { return nil }
        if words.allSatisfy({ digitWords[$0] != nil }) {
            return words.compactMap { digitWords[$0] }.joined()
        }

        let small: [String: Int] = [
            "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
            "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
            "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
            "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
        ]
        var current = 0
        for word in words {
            if word == "hundred" {
                guard current > 0 else { return nil }
                current *= 100
            } else if let value = small[word] {
                current += value
            } else {
                return nil
            }
        }
        return String(current)
    }

    private static func dotSuffix(_ match: String) -> String {
        let suffix = match.split(whereSeparator: { $0.isWhitespace }).last ?? ""
        return "." + suffix.lowercased()
    }

    private static func tildePath(_ match: String) -> String {
        let withoutPrefix = replaceMatches(
            in: match,
            using: tildePathPrefixRegex,
            with: { _ in "" }
        )
        let path = replaceMatches(
            in: withoutPrefix,
            using: slashSeparatorRegex,
            with: { _ in "/" }
        )
        return "~/" + path
    }

    private static func emailAddress(_ match: String) -> String {
        replaceMatches(
            in: match,
            using: atSeparatorRegex,
            with: { _ in "@" }
        ).lowercased()
    }

    private static func doubleDash(_ match: String) -> String {
        let words = match.split(whereSeparator: \.isWhitespace)
        guard words.count > 2 else { return "--" }

        let candidate = String(words.last!)
        if flagBoundaryWords.contains(candidate.lowercased()) {
            return "-- " + candidate
        }
        return "--" + candidate
    }

    private static func singleDash(_ match: String) -> String {
        guard let value = match.split(whereSeparator: \.isWhitespace).last else {
            return match
        }
        return "-" + value.lowercased()
    }

    private static func replaceSpelledLetterSequences(in text: String) -> String {
        var result = replaceMatches(in: text, using: spelledLowercaseRegex) { match in
            match.split(whereSeparator: \.isWhitespace)
                .dropFirst()
                .joined()
                .lowercased()
        }
        result = replaceMatches(in: result, using: spelledUppercaseRegex) { match in
            let letters = match.filter(\.isLetter)
            guard Set(letters.map { String($0).uppercased() }).count > 1 else {
                return match
            }
            return String(letters)
        }
        result = replaceMatches(in: result, using: spelledHyphenatedRegex) { match in
            match.filter(\.isLetter)
        }
        return result
    }

    private static func replaceDigitSequences(in text: String) -> String {
        replaceMatches(in: text, using: digitSequenceRegex) { match in
            match.lowercased()
                .split(whereSeparator: { $0 == " " || $0 == "-" })
                .compactMap { digitWords[String($0)] }
                .joined()
        }
    }

    private static func replacePercentages(in text: String) -> String {
        guard let regex = percentageRegex else { return text }
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

    private static func compiled(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func replaceMatches(
        in text: String,
        using regex: NSRegularExpression?,
        with transform: (String) -> String
    ) -> String {
        guard let regex else { return text }
        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: transform(String(result[range])))
        }
        return result
    }
}
