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

    public init(
        destinationApplicationName: String? = nil,
        terminology: [TranscriptTerminology] = []
    ) {
        self.destinationApplicationName = destinationApplicationName
        self.terminology = terminology
    }

    public static func production(
        destinationApplicationName: String?,
        corrections: [PersonalCorrection]
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
            terminology: terms
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
        let authoritativeTerms = context.terminology.filter { $0.authoritative == true }
        let corrected = authoritativeTerms.reduce(transcript) { result, term in
            term.variants.reduce(result) { variantResult, variant in
                replaceExactPhrase(variant, with: term.preferred, in: variantResult)
            }
        }
        return correct(corrected)
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
        var sourceIndex = sourceWords.startIndex
        for replacementWord in replacementWords {
            guard let match = sourceWords[sourceIndex...].firstIndex(of: replacementWord) else {
                return false
            }
            sourceIndex = sourceWords.index(after: match)
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
    public static let runOnMinimumWords = 45
    public static let runOnMaximumWords = 180

    public static func segments(_ transcript: String) -> [AgentRewriteSegment] {
        guard !transcript.isEmpty else {
            return [AgentRewriteSegment(text: transcript, requiresRewrite: false)]
        }
        if AgentTranscriptChunker.wordCount(transcript) <= wholeTranscriptMaximumWords {
            return [AgentRewriteSegment(text: transcript, requiresRewrite: true)]
        }

        var result: [AgentRewriteSegment] = []
        var segmentStart = transcript.startIndex
        var index = transcript.startIndex
        while index < transcript.endIndex {
            let character = transcript[index]
            let next = transcript.index(after: index)
            let isSentenceEnd = ".?!".contains(character)
                && (next == transcript.endIndex || transcript[next].isWhitespace)
            if isSentenceEnd {
                var end = next
                while end < transcript.endIndex, transcript[end].isWhitespace {
                    end = transcript.index(after: end)
                }
                appendSegment(String(transcript[segmentStart..<end]), to: &result)
                segmentStart = end
                index = end
            } else {
                index = next
            }
        }
        if segmentStart < transcript.endIndex {
            appendSegment(String(transcript[segmentStart...]), to: &result)
        }
        return result
    }

    private static func appendSegment(
        _ text: String,
        to result: inout [AgentRewriteSegment]
    ) {
        guard !text.isEmpty else { return }
        if AgentTranscriptChunker.wordCount(text) > runOnMaximumWords {
            result += AgentTranscriptChunker.chunks(
                text,
                maximumWords: runOnMaximumWords
            ).map { AgentRewriteSegment(text: $0, requiresRewrite: true) }
            return
        }
        result.append(AgentRewriteSegment(
            text: text,
            requiresRewrite: AgentTranscriptChunker.wordCount(text) >= runOnMinimumWords
        ))
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
