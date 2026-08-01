import Foundation

public enum SpokenFormattingContext: Sendable {
    case prose
    case technical
}

public enum SpokenTechnicalTextNormalizer {
    private struct Token {
        let range: Range<String.Index>
        let value: String
    }

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

    private static let hiddenFileNames = [
        "context", "editorconfig", "env", "gitconfig", "gitignore", "npmrc", "swiftlint"
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
            pattern: #"(?i)(?<![\p{L}\p{N}])dot\s+("# + hiddenFileNames + #")\b"#,
            with: dotSuffix
        )
        result = replaceMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}._%+-])([\p{L}\p{N}._%+-]+)\s+at\s+([\p{L}\p{N}-]+(?:\.[\p{L}\p{N}-]+)+)"#,
            withTemplate: "$1@$2"
        )
        if context == .technical {
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
        }
        return result
    }

    public static func incrementalPrefix(
        _ transcript: String,
        context: SpokenFormattingContext = .prose
    ) -> String {
        let tokens = tokens(in: transcript)
        guard let last = tokens.last else { return "" }

        var cutoff = last.range.lowerBound
        func hold(from tokenIndex: Int) {
            guard tokens.indices.contains(tokenIndex) else { return }
            cutoff = min(cutoff, tokens[tokenIndex].range.lowerBound)
        }

        for index in tokens.indices {
            let value = tokens[index].value

            if value == "at" {
                guard index > 0 else { continue }
                if index + 2 >= tokens.count {
                    hold(from: index - 1)
                } else if tokens[index + 2].value == "dot" {
                    var suffixIndex = index + 3
                    guard suffixIndex < tokens.count else {
                        hold(from: index - 1)
                        continue
                    }
                    while suffixIndex + 1 < tokens.count,
                          tokens[suffixIndex + 1].value == "dot" {
                        suffixIndex += 2
                    }
                    if suffixIndex + 1 >= tokens.count {
                        hold(from: index - 1)
                    }
                }
            }

            if value == "dot" {
                let suffixIndex = index + 1
                guard suffixIndex < tokens.count else {
                    hold(from: max(0, index - 1))
                    continue
                }
                let suffix = tokens[suffixIndex].value
                let isHidden = hiddenFileNameSet.contains(suffix)
                guard technicalSuffixSet.contains(suffix) || isHidden else { continue }
                if suffixIndex + 1 >= tokens.count {
                    hold(from: isHidden ? index : max(0, index - 1))
                }
            }

            if value == "slash", context == .technical || tokens[..<index].contains(where: {
                $0.value == "tilde"
            }) {
                var firstSlash = index
                while firstSlash >= 2, tokens[firstSlash - 2].value == "slash" {
                    firstSlash -= 2
                }
                if index + 2 >= tokens.count {
                    hold(from: max(0, firstSlash - 1))
                }
            }

            if value == "tilde", index + 1 >= tokens.count {
                hold(from: index)
            }

            if digitWords[value] != nil {
                var end = index
                while end + 1 < tokens.count, digitWords[tokens[end + 1].value] != nil {
                    end += 1
                }
                if end > index, end + 1 >= tokens.count {
                    hold(from: index)
                }
            }

            if percentValues[value] != nil,
               index + 1 < tokens.count,
               tokens[index + 1].value == "percent",
               index + 2 >= tokens.count {
                hold(from: index)
            }
        }

        return normalize(String(transcript[..<cutoff]), context: context)
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

    private static var technicalSuffixSet: Set<String> {
        Set(technicalSuffixes.split(separator: "|").map(String.init))
    }

    private static var hiddenFileNameSet: Set<String> {
        Set(hiddenFileNames.split(separator: "|").map(String.init))
    }

    private static func tokens(in text: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        let punctuation = CharacterSet.punctuationCharacters
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            let value = String(text[range])
                .lowercased()
                .trimmingCharacters(in: punctuation)
            return Token(range: range, value: value)
        }
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
