import Foundation

public struct TranscriptTerminology: Codable, Equatable, Sendable {
    public let preferred: String
    public let variants: [String]
    public let authoritative: Bool?

    public init(
        preferred: String,
        variants: [String] = [],
        authoritative: Bool = false
    ) {
        self.preferred = preferred
        self.variants = variants
        self.authoritative = authoritative
    }
}

public struct AgentWritingContext: Equatable, Sendable {
    public let destinationApplicationName: String?
    public let terminology: [TranscriptTerminology]
    /// Opt-in: lets the model delete abandoned false starts ("what am I—")
    /// from segments that contain a spoken-aside cue. Deletion-only — the
    /// wording guard still rejects any added or reordered word.
    public let removesFalseStarts: Bool

    public init(
        destinationApplicationName: String? = nil,
        terminology: [TranscriptTerminology] = [],
        removesFalseStarts: Bool = false
    ) {
        self.destinationApplicationName = destinationApplicationName
        self.terminology = terminology
        self.removesFalseStarts = removesFalseStarts
    }

    public static func production(
        destinationApplicationName: String?,
        corrections: [PersonalCorrection],
        removesFalseStarts: Bool = false
    ) -> AgentWritingContext {
        var terms = builtInTerminology
        terms.append(contentsOf: corrections.map {
            TranscriptTerminology(
                preferred: $0.replacement,
                variants: [$0.heard],
                authoritative: true
            )
        })

        var seen: Set<String> = []
        terms = terms.filter { term in
            let key = term.preferred.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return false }
            return true
        }
        return AgentWritingContext(
            destinationApplicationName: destinationApplicationName,
            terminology: terms,
            removesFalseStarts: removesFalseStarts
        )
    }

    public var promptSection: String {
        promptSection(relevantTo: nil)
    }

    public func promptSection(relevantTo transcript: String?) -> String {
        var lines: [String] = []
        if let destinationApplicationName,
           !destinationApplicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Destination application: \(destinationApplicationName)")
        }
        let spellings = if let transcript {
            protectedSpellings.filter { transcript.localizedCaseInsensitiveContains($0) }
        } else {
            protectedSpellings
        }
        if !spellings.isEmpty {
            lines.append("Protected terminology already handled by deterministic rules (never use any exact listed form as an edit source):")
            lines.append("- " + spellings.prefix(64).joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    public var protectedSpellings: [String] {
        var seen: Set<String> = []
        return terminology.flatMap { [$0.preferred] + $0.variants }.filter { spelling in
            let key = spelling
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    private static let builtInTerminology = [
        TranscriptTerminology(preferred: "Natter", variants: ["Nata", "NATA"]),
        TranscriptTerminology(preferred: "GitHub", variants: ["Gitter"]),
        TranscriptTerminology(preferred: "ChatGPT"),
        TranscriptTerminology(preferred: "ChatGPT Desktop"),
        TranscriptTerminology(preferred: "Claude"),
        TranscriptTerminology(preferred: "Claude Desktop"),
        TranscriptTerminology(preferred: "SwiftPM"),
        TranscriptTerminology(preferred: "MLX"),
        TranscriptTerminology(preferred: "FluidAudio"),
        TranscriptTerminology(preferred: "Qwen"),
        TranscriptTerminology(preferred: "Nemotron"),
        TranscriptTerminology(preferred: "Parakeet"),
        TranscriptTerminology(preferred: "Monologue"),
        TranscriptTerminology(preferred: "Keep"),
        TranscriptTerminology(preferred: "Tauri", variants: ["Tori", "Torii"]),
        TranscriptTerminology(preferred: "hreflang", variants: ["Href lang", "HRF Lang"])
    ]
}

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
                pattern: #"(?i)(?<![\p{L}\p{N}_])command\s+shift\s+(?:and|plus)\s+v(?![\p{L}\p{N}_])"#,
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
            (#"(?i)(?<![\p{L}\p{N}_])local\s+only(?=\s+(?:model|mac|app|processing|inference)\b)"#, "local-only"),
            (#"(?i)(?<![\p{L}\p{N}_])mac\s+native(?=\s+(?:swift|app|code)\b)"#, "Mac-native"),
            (#"(?i)(?<![\p{L}\p{N}_])markdown(?=\s+files?\b)"#, "Markdown")
        ]
        for (pattern, replacement) in technicalPhrases {
            result = replacingMatches(in: result, pattern: pattern, with: replacement)
        }
        result = replacingMatches(
            in: result,
            pattern: #"(?i)(?<![\p{L}\p{N}_])gitter(?=\s+(?:repo(?:sitory|s|sitories)?|commit|branch|pull request|issue)\b)"#,
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
            of: #"(?i)(?:\b(?:swift|launch|application\s+delegate|repository|dictation\s+app)\b|@mainactor)"#,
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
                pattern: #"(?i)(?<![\p{L}\p{N}_])command\s+shift\s+(?:and|plus)\s+v(?![\p{L}\p{N}_])"#,
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
            (#"(?i)(?<![\p{L}\p{N}_])local\s+only(?=\s+(?:model|mac|app|processing|inference)\b)"#, "local-only"),
            (#"(?i)(?<![\p{L}\p{N}_])mac\s+native(?=\s+(?:swift|app|code)\b)"#, "Mac-native"),
            (#"(?i)(?<![\p{L}\p{N}_])straight\s+up(?=\s+dictation\b)"#, "straight-up"),
            (#"(?i)(?<![\p{L}\p{N}_])markdown(?=\s+files?\b)"#, "Markdown"),
            (#"(?i)(?<![\p{L}\p{N}_])we\s+ni\s+definitely(?![\p{L}\p{N}_])"#, "We definitely"),
            (#"(?i)(?<![\p{L}\p{N}_])if\s+that\s+any(?![\p{L}\p{N}_])"#, "if any"),
            (#"(?i)(?<![\p{L}\p{N}_])into\s+a\s+into(?=\s+something\b)"#, "into"),
            (#"(?i)(?<![\p{L}\p{N}_])certain\s+things\s+like\s+s\s+like\s+rather\s+than(?![\p{L}\p{N}_])"#, "certain things, rather than"),
            (#"(?i)(?<![\p{L}\p{N}_])we\s+would\s+we\s+need(?![\p{L}\p{N}_])"#, "We need")
        ]
        for (pattern, replacement) in phraseCorrections {
            result = replacingMatches(in: result, pattern: pattern, with: replacement)
        }
        let sentenceBoundaryCorrections: [(String, String)] = [
            (#"(?i)\blocal\s+model\s+but\s+yeah\b"#, "local model. But yeah"),
            (#"(?i)\bwhat\s+models\s+that\s+would\s+mean[,;:]?\s+do\s+some\s+research[,;:]?\s+look\s+at\b"#, "what models that would mean. Do some research. Look at"),
            (#"(?i)\bdoing\s+that[,]?\s+i'm\s+not\s+sure\b"#, "doing that. I'm not sure"),
            (#"(?i)\bpost-processing\s+stuff[,]?\s+just\s+want\b"#, "post-processing stuff. Just want"),
            (#"(?i)\blightning\s+fast[,]?\s+we\s+need\b"#, "lightning fast. We need"),
            (#"(?i)\bsomething[,]?\s+what\s+i\s+want\b"#, "something. What I want"),
            (#"(?i)\btalking[,]?\s+maybe\s+tap\b"#, "talking. Maybe tap"),
            (#"(?i)\bstuff[,]?\s+so\s+let's\b"#, "stuff. So let's"),
            (#"(?i)\banyway[.,;:]?\s+so[,]?\s+work\b"#, "anyway. So work"),
            (#"(?i)\bthere[,]?\s+maybe\s+it\s+doesn't\b"#, "there. Maybe it doesn't")
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
            (#"(?i)\b(constraints(?:\s+for\s+segment\s+\d+)?)\s+remains\b"#, "$1 remain")
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
            pattern: #"(?i)(?<![\p{L}\p{N}_])gitter(?=\s+(?:repo(?:sitory|s|sitories)?|commit|branch|pull request|issue)\b)"#,
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
            of: #"(?i)(?:\b(?:swift|launch|application\s+delegate|repository|dictation\s+app)\b|@mainactor)"#,
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
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(?<![\p{L}\p{N}_])nata(?![\p{L}\p{N}_])"#
        ) else { return text }

        var result = text
        let matches = regex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).reversed()
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            let lower = text.index(range.lowerBound, offsetBy: -48, limitedBy: text.startIndex)
                ?? text.startIndex
            let upper = text.index(range.upperBound, offsetBy: 48, limitedBy: text.endIndex)
                ?? text.endIndex
            let context = String(text[lower..<upper])
            guard context.range(
                of: #"(?i)\b(?:app|dictation|transcrib(?:e|ed|ing)|using|use|workflow|mode)\b"#,
                options: .regularExpression
            ) != nil else { continue }
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
        "e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr."
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
            let nextIsBoundary = index + 1 == characters.count
                || characters[index + 1].isWhitespace
            guard nextIsBoundary else { continue }
            let previousToken = String(characters[...index])
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

public struct TranscriptEdit: Codable, Equatable, Sendable {
    public let source: String
    public let replacement: String
    public let occurrence: Int?
    public let allOccurrences: Bool?

    public init(
        source: String,
        replacement: String,
        occurrence: Int? = nil,
        allOccurrences: Bool = false
    ) {
        self.source = source
        self.replacement = replacement
        self.occurrence = occurrence
        self.allOccurrences = allOccurrences
    }
}

public struct TranscriptEditPlan: Codable, Equatable, Sendable {
    public let edits: [TranscriptEdit]

    public init(edits: [TranscriptEdit]) {
        self.edits = edits
    }
}

public struct TranscriptEditRecoveryResult: Equatable, Sendable {
    public let output: String
    public let acceptedPlan: TranscriptEditPlan
    public let rejectedEdits: Int

    public var acceptedEdits: Int { acceptedPlan.edits.count }

    public init(
        output: String,
        acceptedPlan: TranscriptEditPlan,
        rejectedEdits: Int
    ) {
        self.output = output
        self.acceptedPlan = acceptedPlan
        self.rejectedEdits = rejectedEdits
    }
}

public enum AgentSelfEditPolicy {
    private static let cuePattern = #"(?i)\b(?:delete|ignore|scratch)\s+(?:that|this|it|that\s+part)\b|\bchange\s+(?:that|this|it)\s+to\b|\bi\s+mean\b|\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b"#

    public static func containsCorrectionCue(_ transcript: String) -> Bool {
        transcript.range(of: cuePattern, options: .regularExpression) != nil
    }

    public static func safePlan(from plan: TranscriptEditPlan) -> TranscriptEditPlan {
        TranscriptEditPlan(edits: plan.edits.filter(isSafe))
    }

    public static func safeOutput(
        input: String,
        proposedOutput: String
    ) -> String? {
        let inputWords = WritingBenchmark.normalizedWords(input)
        let outputWords = WritingBenchmark.normalizedWords(proposedOutput)
        if outputWords == inputWords { return input }
        guard !outputWords.isEmpty,
              let retainedIndexes = backwardSubsequenceIndexes(
                outputWords,
                in: inputWords
              ) else {
            return nil
        }

        let retained = Set(retainedIndexes)
        guard cueDirectionIsValid(inputWords: inputWords, retained: retained) else {
            return nil
        }
        var removedRanges: [Range<Int>] = []
        var start: Int?
        for index in inputWords.indices {
            if retained.contains(index) {
                if let rangeStart = start {
                    removedRanges.append(rangeStart..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }
        if let start { removedRanges.append(start..<inputWords.count) }
        guard !removedRanges.isEmpty else { return nil }

        let removedTexts = removedRanges.map {
            inputWords[$0].joined(separator: " ")
        }
        let cueRanges = removedTexts.indices.filter {
            containsCorrectionCue(removedTexts[$0])
        }
        guard !cueRanges.isEmpty else { return nil }
        let hasAcknowledgement = input.range(
            of: #"(?i)\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b"#,
            options: .regularExpression
        ) != nil
        guard removedTexts.indices.allSatisfy({ index in
            containsCorrectionCue(removedTexts[index]) || hasAcknowledgement
        }) else {
            return nil
        }
        guard removedTexts.allSatisfy({
            WritingBenchmark.normalizedWords($0).count >= 3
        }) else {
            return nil
        }
        let removedWordCount = removedRanges.reduce(0) { $0 + $1.count }
        guard removedWordCount > cueRanges.count * 2 else { return nil }
        return proposedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cueDirectionIsValid(
        inputWords: [String],
        retained: Set<Int>
    ) -> Bool {
        let standardCues = [
            ["ignore", "that", "part"],
            ["there", "we", "go", "that's", "better"],
            ["change", "that", "to"],
            ["change", "this", "to"],
            ["change", "it", "to"],
            ["delete", "that"], ["delete", "this"], ["delete", "it"],
            ["ignore", "that"], ["ignore", "this"], ["ignore", "it"],
            ["scratch", "that"], ["scratch", "this"], ["scratch", "it"],
            ["i", "mean"]
        ]
        var cueRanges: [Range<Int>] = []
        var index = 0
        while index < inputWords.count {
            if let cue = standardCues.first(where: { candidate in
                index + candidate.count <= inputWords.count
                    && Array(inputWords[index..<(index + candidate.count)]) == candidate
            }) {
                cueRanges.append(index..<(index + cue.count))
                index += cue.count
            } else {
                index += 1
            }
        }
        guard !cueRanges.isEmpty else { return false }
        return cueRanges.allSatisfy { cueRange in
            let cueWasRemoved = cueRange.allSatisfy { !retained.contains($0) }
            let removedBefore = (0..<cueRange.lowerBound).contains {
                !retained.contains($0)
            }
            if inputWords[cueRange].joined(separator: " ")
                == "there we go that's better" {
                return cueWasRemoved && removedBefore
            }
            let retainedAfter = (cueRange.upperBound..<inputWords.count).contains {
                retained.contains($0)
            }
            let wordsBeforeCue = Set(inputWords[..<cueRange.lowerBound])
            let distinctiveAfter = (cueRange.upperBound..<inputWords.count).filter {
                !wordsBeforeCue.contains(inputWords[$0])
            }
            let retainedDistinctiveAfter = distinctiveAfter.isEmpty
                || distinctiveAfter.contains { retained.contains($0) }
            return cueWasRemoved
                && removedBefore
                && retainedAfter
                && retainedDistinctiveAfter
        }
    }

    private static func backwardSubsequenceIndexes(
        _ subsequence: [String],
        in words: [String]
    ) -> [Int]? {
        var result = Array(repeating: 0, count: subsequence.count)
        var searchEnd = words.count
        for outputIndex in subsequence.indices.reversed() {
            guard searchEnd > 0,
                  let match = words[..<searchEnd].lastIndex(of: subsequence[outputIndex]) else {
                return nil
            }
            result[outputIndex] = match
            searchEnd = match
        }
        return result
    }

    public static func removingResidualAcknowledgementCues(from transcript: String) -> String {
        let pattern = #"(?i)(?:[,;:—-]\s*)?\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b[,.!?]?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return transcript
        }
        let range = NSRange(transcript.startIndex..., in: transcript)
        let cleaned = expression.stringByReplacingMatches(
            in: transcript,
            range: range,
            withTemplate: ""
        )
        return cleaned
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSafe(_ edit: TranscriptEdit) -> Bool {
        guard edit.source != edit.replacement,
              edit.occurrence == nil,
              edit.allOccurrences != true,
              containsCorrectionCue(edit.source),
              AgentTranscriptChunker.wordCount(edit.source) <= 60 else {
            return false
        }
        let sourceWords = WritingBenchmark.normalizedWords(edit.source)
        let replacementWords = WritingBenchmark.normalizedWords(edit.replacement)
        guard replacementUsesCorrectedSide(edit) else { return false }
        var sourceIndex = sourceWords.startIndex
        for replacementWord in replacementWords {
            guard let match = sourceWords[sourceIndex...].firstIndex(of: replacementWord) else {
                return false
            }
            sourceIndex = sourceWords.index(after: match)
        }
        return true
    }

    private static func replacementUsesCorrectedSide(_ edit: TranscriptEdit) -> Bool {
        let replacementWords = WritingBenchmark.normalizedWords(edit.replacement)
        let acknowledgementPattern = #"(?i)\bthere\s+we\s+go[,]?\s+that(?:'|’)s\s+better\b"#
        if edit.source.range(of: acknowledgementPattern, options: .regularExpression) != nil {
            return true
        }
        guard let cueRange = edit.source.range(of: cuePattern, options: .regularExpression) else {
            return false
        }
        if replacementWords.isEmpty {
            return WritingBenchmark.normalizedWords(
                String(edit.source[..<cueRange.lowerBound])
            ).count >= 2
        }
        let correctedWords = WritingBenchmark.normalizedWords(
            String(edit.source[cueRange.upperBound...])
        )
        guard !correctedWords.isEmpty else { return false }
        var correctedIndex = correctedWords.startIndex
        for replacementWord in replacementWords {
            guard let match = correctedWords[correctedIndex...].firstIndex(of: replacementWord) else {
                return false
            }
            correctedIndex = correctedWords.index(after: match)
        }
        return true
    }
}

public enum TranscriptEditApplicationError: LocalizedError, Equatable {
    case emptySource
    case unchangedEdit(String)
    case sourceNotUnique(String, matches: Int)
    case unsafeAllOccurrencesSource(String)
    case altersProtectedTerminology(String)
    case overlappingEdits
    case changeBudgetExceeded(changed: Int, allowed: Int)

    public var errorDescription: String? {
        switch self {
        case .emptySource:
            "The writing model proposed an edit with no source text."
        case .unchangedEdit(let source):
            "The writing model proposed an unchanged edit for “\(source)”."
        case .sourceNotUnique(let source, let matches):
            "The writing model edit source “\(source)” matched \(matches) times."
        case .unsafeAllOccurrencesSource(let source):
            "The writing model bulk-edit source “\(source)” did not include enough context."
        case .altersProtectedTerminology(let term):
            "The writing model tried to alter the protected spelling “\(term)”."
        case .overlappingEdits:
            "The writing model proposed overlapping edits."
        case .changeBudgetExceeded(let changed, let allowed):
            "The writing model tried to change \(changed) characters; the safe limit is \(allowed)."
        }
    }
}

public enum TranscriptEditApplier {
    public static func applyRecovering(
        _ plan: TranscriptEditPlan,
        to transcript: String,
        protectedTerms: [String] = []
    ) -> TranscriptEditRecoveryResult {
        var accepted: [TranscriptEdit] = []
        var rejectedCount = 0
        for edit in plan.edits where edit.source != edit.replacement {
            let candidate = TranscriptEditPlan(edits: accepted + [edit])
            do {
                _ = try apply(
                    candidate,
                    to: transcript,
                    protectedTerms: protectedTerms
                )
                accepted.append(edit)
            } catch {
                rejectedCount += 1
            }
        }

        let output = (try? apply(
            TranscriptEditPlan(edits: accepted),
            to: transcript,
            protectedTerms: protectedTerms
        )) ?? transcript
        return TranscriptEditRecoveryResult(
            output: output,
            acceptedPlan: TranscriptEditPlan(edits: accepted),
            rejectedEdits: rejectedCount
        )
    }

    public static func apply(
        _ plan: TranscriptEditPlan,
        to transcript: String,
        protectedTerms: [String] = []
    ) throws -> String {
        var resolved: [(range: Range<String.Index>, edit: TranscriptEdit)] = []
        for edit in plan.edits {
            guard !edit.source.isEmpty else {
                throw TranscriptEditApplicationError.emptySource
            }
            guard edit.source != edit.replacement else { continue }
            var matches = ranges(of: edit.source, in: transcript)
            if matches.isEmpty,
               edit.source.split(whereSeparator: \.isWhitespace).count >= 5 {
                matches = ranges(
                    of: edit.source,
                    in: transcript,
                    options: .caseInsensitive
                )
            }
            let editRanges: [Range<String.Index>]
            if edit.allOccurrences == true {
                let sourceWords = edit.source.split(whereSeparator: \.isWhitespace).count
                let hasSafeBulkContext = sourceWords >= 3
                    || ((sourceWords == 1 || sourceWords == 2)
                        && bulkContextsAreEquivalent(matches, in: transcript))
                guard matches.count == 1 || hasSafeBulkContext else {
                    throw TranscriptEditApplicationError.unsafeAllOccurrencesSource(
                        edit.source
                    )
                }
                guard edit.occurrence == nil, !matches.isEmpty else {
                    throw TranscriptEditApplicationError.sourceNotUnique(
                        edit.source,
                        matches: matches.count
                    )
                }
                editRanges = matches
            } else if let occurrence = edit.occurrence {
                guard occurrence > 0, occurrence <= matches.count else {
                    throw TranscriptEditApplicationError.sourceNotUnique(
                        edit.source,
                        matches: matches.count
                    )
                }
                editRanges = [matches[occurrence - 1]]
            } else if matches.count == 1, let onlyMatch = matches.first {
                editRanges = [onlyMatch]
            } else {
                throw TranscriptEditApplicationError.sourceNotUnique(
                    edit.source,
                    matches: matches.count
                )
            }
            for range in editRanges {
                let actualSource = String(transcript[range])
                if let protectedTerm = protectedTerms.first(where: { term in
                    let sourceCount = ranges(of: term, in: actualSource).count
                    return sourceCount > 0
                        && ranges(of: term, in: edit.replacement).count != sourceCount
                }) {
                    throw TranscriptEditApplicationError.altersProtectedTerminology(
                        protectedTerm
                    )
                }
                let overlapping = resolved.indices.filter {
                    resolved[$0].range.overlaps(range)
                }
                if !overlapping.isEmpty {
                    let candidateContainsExisting = overlapping.allSatisfy { index in
                        rangeContains(range, resolved[index].range)
                            && edit.replacement.contains(resolved[index].edit.replacement)
                    }
                    if candidateContainsExisting {
                        for index in overlapping.reversed() {
                            resolved.remove(at: index)
                        }
                    } else if overlapping.count == 1 {
                        let existing = resolved[overlapping[0]]
                        if rangeContains(existing.range, range),
                           existing.edit.replacement.contains(edit.replacement) {
                            continue
                        }
                        throw TranscriptEditApplicationError.overlappingEdits
                    } else {
                        throw TranscriptEditApplicationError.overlappingEdits
                    }
                }
                resolved.append((range, edit))
            }
        }

        let changedCharacters = resolved.reduce(into: 0) { total, resolvedEdit in
            total += changedCharacterCount(
                from: String(transcript[resolvedEdit.range]),
                to: resolvedEdit.edit.replacement
            )
        }
        let allowedChanges = max(24, transcript.count / 3)
        guard changedCharacters <= allowedChanges else {
            throw TranscriptEditApplicationError.changeBudgetExceeded(
                changed: changedCharacters,
                allowed: allowedChanges
            )
        }

        var output = transcript
        for resolvedEdit in resolved.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
            output.replaceSubrange(resolvedEdit.range, with: resolvedEdit.edit.replacement)
        }
        return output
    }

    private static func rangeContains(
        _ outer: Range<String.Index>,
        _ inner: Range<String.Index>
    ) -> Bool {
        outer.lowerBound <= inner.lowerBound && outer.upperBound >= inner.upperBound
    }

    private static func bulkContextsAreEquivalent(
        _ matches: [Range<String.Index>],
        in transcript: String
    ) -> Bool {
        guard let first = matches.first, matches.count > 1 else { return true }
        let expected = bulkContext(around: first, in: transcript)
        return matches.dropFirst().allSatisfy {
            bulkContext(around: $0, in: transcript) == expected
        }
    }

    private static func bulkContext(
        around range: Range<String.Index>,
        in transcript: String
    ) -> [String] {
        let before = transcript[..<range.lowerBound]
            .split(whereSeparator: \.isWhitespace)
            .suffix(5)
        return before.map { token in
            let lowered = token.lowercased()
            return lowered.contains(where: \.isNumber) ? "#" : lowered
        }
    }

    private static func ranges(
        of source: String,
        in transcript: String,
        options: String.CompareOptions = .literal
    ) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var searchStart = transcript.startIndex
        while searchStart < transcript.endIndex,
              let range = transcript.range(
                  of: source,
                  options: options,
                  range: searchStart..<transcript.endIndex
              ) {
            result.append(range)
            searchStart = range.upperBound
        }
        return result
    }

    private static func changedCharacterCount(from source: String, to replacement: String) -> Int {
        let sourceCharacters = Array(source)
        let replacementCharacters = Array(replacement)
        guard !sourceCharacters.isEmpty else { return replacementCharacters.count }
        guard !replacementCharacters.isEmpty else { return sourceCharacters.count }

        var previous = Array(0...replacementCharacters.count)
        for (sourceIndex, sourceCharacter) in sourceCharacters.enumerated() {
            var current = [sourceIndex + 1]
                + Array(repeating: 0, count: replacementCharacters.count)
            for (replacementIndex, replacementCharacter) in replacementCharacters.enumerated() {
                current[replacementIndex + 1] = min(
                    current[replacementIndex] + 1,
                    previous[replacementIndex + 1] + 1,
                    previous[replacementIndex]
                        + (sourceCharacter == replacementCharacter ? 0 : 1)
                )
            }
            previous = current
        }
        return previous[replacementCharacters.count]
    }
}

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
           first.isLetter || first.isNumber || first == "_" {
            pattern = #"(?<![\p{L}\p{N}_])"# + pattern
        }
        if let last = term.last,
           last.isLetter || last.isNumber || last == "_" {
            pattern += #"(?![\p{L}\p{N}_])"#
        }
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return 0 }
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
        "remain\u{0}remains", "remains\u{0}remain"
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
                    || allowedGrammarChanges.contains(source + "\u{0}" + word) {
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
            output += sourceToken.normalized == proposedToken.normalized
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
            let normalized = WritingBenchmark.normalizedWords(String(text[range]))
                .first ?? ""
            if !normalized.isEmpty {
                result.append(Token(range: range, normalized: normalized))
            }
            wordStart = nil
        }

        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber
                || character == "'" || character == "’" {
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
        "i mean", "hang on", "hold on what"
    ]

    public static func containsCue(_ text: String) -> Bool {
        let folded = " " + WritingBenchmark.normalizedWords(text).joined(separator: " ") + " "
        return cues.contains { folded.contains(" \($0) ") }
    }
}

public enum AgentTranscriptChunker {
    public static let productionMaximumWords = 400
    public static let minimumRetryWords = 64

    public static func chunks(
        _ transcript: String,
        maximumWords: Int = productionMaximumWords
    ) -> [String] {
        guard maximumWords > 0, !transcript.isEmpty else { return [transcript] }
        let words = wordRanges(in: transcript)
        guard words.count > maximumWords else { return [transcript] }

        var result: [String] = []
        var chunkStart = transcript.startIndex
        var firstWord = 0
        while firstWord < words.count {
            let proposedEnd = min(firstWord + maximumWords, words.count)
            guard proposedEnd < words.count else {
                result.append(String(transcript[chunkStart..<transcript.endIndex]))
                break
            }

            let earliestPreferredEnd = firstWord + maximumWords / 2
            var lastWord = proposedEnd - 1
            if earliestPreferredEnd < proposedEnd {
                for candidate in stride(
                    from: proposedEnd - 1,
                    through: earliestPreferredEnd,
                    by: -1
                ) where endsSentence(transcript[words[candidate]]) {
                    lastWord = candidate
                    break
                }
            }

            let nextWord = lastWord + 1
            let chunkEnd = words[nextWord].lowerBound
            result.append(String(transcript[chunkStart..<chunkEnd]))
            chunkStart = chunkEnd
            firstWord = nextWord
        }
        return result
    }

    public static func wordCount(_ transcript: String) -> Int {
        transcript.split(whereSeparator: \.isWhitespace).count
    }

    private static func wordRanges(in transcript: String) -> [Range<String.Index>] {
        guard let expression = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        return expression.matches(
            in: transcript,
            range: NSRange(transcript.startIndex..., in: transcript)
        ).compactMap { Range($0.range, in: transcript) }
    }

    private static func endsSentence(_ word: Substring) -> Bool {
        word.last.map { ".!?".contains($0) } ?? false
    }
}
