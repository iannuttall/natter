import Foundation

public enum ContextualTranscriptCorrector {
    public static func correct(
        _ transcript: String,
        context: AgentWritingContext
    ) -> String {
        correct(applyingAuthoritativeTerminology(to: transcript, context: context))
    }

    public static func correctTechnical(
        _ transcript: String,
        context: AgentWritingContext
    ) -> String {
        correctTechnical(applyingAuthoritativeTerminology(to: transcript, context: context))
    }

    public static func correctTechnical(_ transcript: String) -> String {
        var result = transcript
        if result.range(
            of: #"(?i)\b(?:dictation|transcription|shortcut|mode picker|local model)\b"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])monologues?(?![\p{L}\p{N}_])"#,
                with: "Monologue"
            )
        }
        if result.range(
            of: #"(?i)\b(?:keyboard|shortcut|tab|escape|shift|dictat(?:e|ing|ion))\b"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])(?:right|write)\s+shift(?![\p{L}\p{N}_])"#,
                with: "Right Shift"
            )
            result = replacingMatches(
                in: result,
                pattern:
                    #"(?i)(?<![\p{L}\p{N}_])command\s+shift\s+(?:and|plus)\s+v(?![\p{L}\p{N}_])"#,
                with: "Command-Shift-V"
            )
        }
        if result.range(
            of: #"(?i)(?<![\p{L}\p{N}_])tori{1,2}\s+app\b"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])tori{1,2}(?![\p{L}\p{N}_])"#,
                with: "Tauri"
            )
        }
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])(?:href\s*,?\s*lang|hrf\s+lang)(?![\p{L}\p{N}_])"#,
            with: "hreflang"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])search\s+console(?![\p{L}\p{N}_])"#,
            with: "Search Console"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<=\brepo\s)readme(?![\p{L}\p{N}_])"#,
            with: "README"
        )
        let technicalPhrases: [(String, String)] = [
            (#"(?i)(?<![\p{L}\p{N}_])text\s+to\s+speech(?![\p{L}\p{N}_])"#, "text-to-speech"),
            (#"(?i)(?<![\p{L}\p{N}_])mit\s+licensed(?![\p{L}\p{N}_])"#, "MIT-licensed"),
            (
                #"(?i)(?<![\p{L}\p{N}_])local\s+only(?=\s+(?:model|mac|app|processing|inference)\b)"#,
                "local-only"
            ),
            (#"(?i)(?<![\p{L}\p{N}_])mac\s+native(?=\s+(?:swift|app|code)\b)"#, "Mac-native"),
            (#"(?i)(?<![\p{L}\p{N}_])markdown(?=\s+files?\b)"#, "Markdown"),
        ]
        for (pattern, replacement) in technicalPhrases {
            result = replacingMatches(in: result, pattern: pattern, with: replacement)
        }
        result = replacingMatches(
            in: result,
            pattern:
                #"(?i)(?<![\p{L}\p{N}_])gitter(?=\s+(?:repo(?:sitory|s|sitories)?|commit|branch|pull request|issue)\b)"#,
            with: "GitHub"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])scroll\s+restoration(?=\s*:\s*(?:true|false)\b)"#,
            with: "scrollRestoration"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])main\s+actor(?=\s+annotation\b)"#,
            with: "@MainActor"
        )
        if result.range(
            of:
                #"(?i)(?:\b(?:swift|launch|application\s+delegate|repository|dictation\s+app)\b|@mainactor)"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])app\s+delegate(?![\p{L}\p{N}_])"#,
                with: "AppDelegate"
            )
        }
        return replacingNatterVariantsWhenSelfReferential(in: result)
    }

    private static func applyingAuthoritativeTerminology(
        to transcript: String,
        context: AgentWritingContext
    ) -> String {
        let authoritativeTerms = context.terminology.filter { $0.authoritative == true }
        return authoritativeTerms.reduce(transcript) { result, term in
            term.variants.reduce(result) { variantResult, variant in
                replaceExactPhrase(variant, with: term.preferred, in: variantResult)
            }
        }
    }

    public static func correct(_ transcript: String) -> String {
        var result = transcript
        if result.range(
            of: #"(?i)\b(?:dictation|transcription|shortcut|mode picker|local model)\b"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])monologues?(?![\p{L}\p{N}_])"#,
                with: "Monologue"
            )
        }
        if result.range(
            of: #"(?i)\b(?:keyboard|shortcut|tab|escape|shift|dictat(?:e|ing|ion))\b"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])(?:right|write)\s+shift(?![\p{L}\p{N}_])"#,
                with: "Right Shift"
            )
            result = replacingMatches(
                in: result,
                pattern:
                    #"(?i)(?<![\p{L}\p{N}_])command\s+shift\s+(?:and|plus)\s+v(?![\p{L}\p{N}_])"#,
                with: "Command-Shift-V"
            )
        }
        if result.range(
            of: #"(?i)(?<![\p{L}\p{N}_])tori{1,2}\s+app\b"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])tori{1,2}(?![\p{L}\p{N}_])"#,
                with: "Tauri"
            )
        }
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])spitboarding(?![\p{L}\p{N}_])"#,
            with: "spitballing"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])maggally(?=\s+overkill\b)"#,
            with: "massively"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])(?:href\s*,?\s*lang|hrf\s+lang)(?![\p{L}\p{N}_])"#,
            with: "hreflang"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])cyto\s+architecture(?![\p{L}\p{N}_])"#,
            with: "site architecture"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])search\s+console(?![\p{L}\p{N}_])"#,
            with: "Search Console"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])keeps(?=\s+(?:alternatives|versus)\b)"#,
            with: "Keep"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<=\brepo\s)readme(?![\p{L}\p{N}_])"#,
            with: "README"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])apart\s+from\s+keep\s+is\s+fine(?![\p{L}\p{N}_])"#,
            with: "apart from Keep; Keep is fine"
        )
        let phraseCorrections: [(String, String)] = [
            (#"(?i)(?<![\p{L}\p{N}_])text\s+to\s+speech(?![\p{L}\p{N}_])"#, "text-to-speech"),
            (#"(?i)(?<![\p{L}\p{N}_])mit\s+licensed(?![\p{L}\p{N}_])"#, "MIT-licensed"),
            (
                #"(?i)(?<![\p{L}\p{N}_])local\s+only(?=\s+(?:model|mac|app|processing|inference)\b)"#,
                "local-only"
            ),
            (#"(?i)(?<![\p{L}\p{N}_])mac\s+native(?=\s+(?:swift|app|code)\b)"#, "Mac-native"),
            (#"(?i)(?<![\p{L}\p{N}_])straight\s+up(?=\s+dictation\b)"#, "straight-up"),
            (#"(?i)(?<![\p{L}\p{N}_])markdown(?=\s+files?\b)"#, "Markdown"),
            (#"(?i)(?<![\p{L}\p{N}_])we\s+ni\s+definitely(?![\p{L}\p{N}_])"#, "We definitely"),
            (#"(?i)(?<![\p{L}\p{N}_])if\s+that\s+any(?![\p{L}\p{N}_])"#, "if any"),
            (#"(?i)(?<![\p{L}\p{N}_])into\s+a\s+into(?=\s+something\b)"#, "into"),
            (
                #"(?i)(?<![\p{L}\p{N}_])certain\s+things\s+like\s+s\s+like\s+rather\s+than(?![\p{L}\p{N}_])"#,
                "certain things, rather than"
            ),
            (#"(?i)(?<![\p{L}\p{N}_])we\s+would\s+we\s+need(?![\p{L}\p{N}_])"#, "We need"),
        ]
        for (pattern, replacement) in phraseCorrections {
            result = replacingMatches(in: result, pattern: pattern, with: replacement)
        }
        let sentenceBoundaryCorrections: [(String, String)] = [
            (#"(?i)\blocal\s+model\s+but\s+yeah\b"#, "local model. But yeah"),
            (
                #"(?i)\bwhat\s+models\s+that\s+would\s+mean[,;:]?\s+do\s+some\s+research[,;:]?\s+look\s+at\b"#,
                "what models that would mean. Do some research. Look at"
            ),
            (#"(?i)\bdoing\s+that[,]?\s+i'm\s+not\s+sure\b"#, "doing that. I'm not sure"),
            (
                #"(?i)\bpost-processing\s+stuff[,]?\s+just\s+want\b"#,
                "post-processing stuff. Just want"
            ),
            (#"(?i)\blightning\s+fast[,]?\s+we\s+need\b"#, "lightning fast. We need"),
            (#"(?i)\bsomething[,]?\s+what\s+i\s+want\b"#, "something. What I want"),
            (#"(?i)\btalking[,]?\s+maybe\s+tap\b"#, "talking. Maybe tap"),
            (#"(?i)\bstuff[,]?\s+so\s+let's\b"#, "stuff. So let's"),
            (#"(?i)\banyway[.,;:]?\s+so[,]?\s+work\b"#, "anyway. So work"),
            (#"(?i)\bthere[,]?\s+maybe\s+it\s+doesn't\b"#, "there. Maybe it doesn't"),
        ]
        for (pattern, replacement) in sentenceBoundaryCorrections {
            result = replacingMatches(in: result, pattern: pattern, with: replacement)
        }
        let agreementCorrections: [(String, String)] = [
            (#"(?i)\b(result(?:\s+for\s+segment\s+\d+)?)\s+are\b"#, "$1 is"),
            (#"(?i)\b(result(?:\s+for\s+segment\s+\d+)?)\s+need\b"#, "$1 needs"),
            (#"(?i)\b(validator(?:\s+for\s+segment\s+\d+)?)\s+have\b"#, "$1 has"),
            (#"(?i)\b(validator(?:\s+for\s+segment\s+\d+)?|it)\s+do\s+not\b"#, "$1 does not"),
            (#"(?i)\b(delivery\s+checks(?:\s+for\s+segment\s+\d+)?)\s+is\b"#, "$1 are"),
            (#"(?i)\b(terminal\s+checks(?:\s+for\s+segment\s+\d+)?)\s+needs\b"#, "$1 need"),
            (#"(?i)\b(constraints(?:\s+for\s+segment\s+\d+)?)\s+remains\b"#, "$1 remain"),
        ]
        for (pattern, replacement) in agreementCorrections {
            result = replacingMatchesTemplate(
                in: result,
                pattern: pattern,
                withTemplate: replacement
            )
        }
        result = replacingMatches(
            in: result,
            pattern:
                #"(?i)(?<![\p{L}\p{N}_])gitter(?=\s+(?:repo(?:sitory|s|sitories)?|commit|branch|pull request|issue)\b)"#,
            with: "GitHub"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])scroll\s+restoration(?=\s*:\s*(?:true|false)\b)"#,
            with: "scrollRestoration"
        )
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])main\s+actor(?=\s+annotation\b)"#,
            with: "@MainActor"
        )
        if result.range(
            of:
                #"(?i)(?:\b(?:swift|launch|application\s+delegate|repository|dictation\s+app)\b|@mainactor)"#,
            options: .regularExpression
        ) != nil {
            result = replacingMatches(
                in: result,
                pattern: #"(?i)(?<![\p{L}\p{N}_])app\s+delegate(?![\p{L}\p{N}_])"#,
                with: "AppDelegate"
            )
        }
        result = replacingNatterVariantsWhenSelfReferential(in: result)
        return SentenceBoundaryCapitalizer.capitalize(result)
    }

    private static func replaceExactPhrase(
        _ phrase: String,
        with replacement: String,
        in transcript: String
    ) -> String {
        guard !phrase.isEmpty else { return transcript }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return replacingMatches(
            in: transcript,
            pattern: #"(?i)(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"#,
            with: replacement
        )
    }

    private static func replacingNatterVariantsWhenSelfReferential(in text: String) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: #"(?i)(?<![\p{L}\p{N}_])nata(?![\p{L}\p{N}_])"#
            )
        else { return text }

        var result = text
        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).reversed()
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let lower =
                text.index(range.lowerBound, offsetBy: -48, limitedBy: text.startIndex)
                ?? text.startIndex
            let upper =
                text.index(range.upperBound, offsetBy: 48, limitedBy: text.endIndex)
                ?? text.endIndex
            let context = String(text[lower..<upper])
            guard
                context.range(
                    of: #"(?i)\b(?:app|dictation|transcrib(?:e|ed|ing)|using|use|workflow|mode)\b"#,
                    options: .regularExpression
                ) != nil
            else { continue }
            result.replaceSubrange(range, with: "Natter")
        }
        return result
    }

    private static func replacingMatches(
        in text: String,
        pattern: String,
        with replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }

    private static func replacingMatchesTemplate(
        in text: String,
        pattern: String,
        withTemplate replacement: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}

public enum SentenceBoundaryCapitalizer {
    private static let abbreviations: Set<String> = [
        "e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr.",
    ]

    public static func capitalize(_ text: String) -> String {
        let characters = Array(text)
        var output = ""
        var shouldCapitalize = true
        for (index, character) in characters.enumerated() {
            if shouldCapitalize, character.isLetter {
                output += character.uppercased()
                shouldCapitalize = false
            } else {
                output.append(character)
            }

            guard ".!?".contains(character) else { continue }
            let nextIsBoundary =
                index + 1 == characters.count
                || characters[index + 1].isWhitespace
            guard nextIsBoundary else { continue }
            let previousToken =
                String(characters[...index])
                .split(whereSeparator: \.isWhitespace)
                .last?
                .lowercased() ?? ""
            if !abbreviations.contains(previousToken) {
                shouldCapitalize = true
            }
        }
        return output
    }
}
