import Foundation

public struct WritingFixture: Codable, Sendable {
    public let id: String
    public let mode: String
    public let instructions: String
    public let transcript: String
    public let expected: String
    public let required: [String]
    public let forbidden: [String]
    public let terminology: [TranscriptTerminology]?

    public init(
        id: String,
        mode: String,
        instructions: String,
        transcript: String,
        expected: String,
        required: [String],
        forbidden: [String],
        terminology: [TranscriptTerminology]? = nil
    ) {
        self.id = id
        self.mode = mode
        self.instructions = instructions
        self.transcript = transcript
        self.expected = expected
        self.required = required
        self.forbidden = forbidden
        self.terminology = terminology
    }
}

public struct WritingFixtureSet: Codable, Sendable {
    public let version: Int
    public let fixtures: [WritingFixture]

    public init(version: Int, fixtures: [WritingFixture]) {
        self.version = version
        self.fixtures = fixtures
    }
}

public struct WritingFixtureResult: Codable, Sendable {
    public let id: String
    public let mode: String
    public let inputWordCount: Int
    public let outputWordCount: Int
    public let changedWordCount: Int
    public let pipelineOutcome: String
    public let latencySeconds: Double
    public let expectedWordErrorRate: Double
    public let requiredPassed: Int
    public let requiredTotal: Int
    public let forbiddenPassed: Int
    public let forbiddenTotal: Int
    public let aiSmellHits: [String]
    public let expected: String
    public let output: String
}

public enum WritingLengthBucket: String, Codable, CaseIterable, Sendable {
    case short
    case medium
    case long
    case stress
}

public struct WritingLatencyBucketSummary: Codable, Sendable {
    public let bucket: WritingLengthBucket
    public let fixtures: Int
    public let minimumInputWords: Int
    public let maximumInputWords: Int
    public let meanLatencySeconds: Double
    public let p50LatencySeconds: Double
    public let p95LatencySeconds: Double
}

public struct WritingSummary: Codable, Sendable {
    public let provider: String
    public let model: String
    public let fixtures: Int
    public let meanLatencySeconds: Double
    public let p50LatencySeconds: Double
    public let p95LatencySeconds: Double
    public let meanExpectedWordErrorRate: Double
    public let requiredPassRate: Double
    public let forbiddenPassRate: Double
    public let totalAISmellHits: Int
    public let fallbackCount: Int
    public let latencyByLength: [WritingLatencyBucketSummary]
    public let createdAt: String
    public let results: [WritingFixtureResult]
}

public enum WritingBenchmark {
    public static let baseInstructions = """
    You edit text produced by speech recognition. Return only the finished text with no commentary.
    Preserve the speaker's meaning, facts, names, numbers, paths, constraints, uncertainty and tone.
    Never invent details. Never make a request more polite, corporate or enthusiastic unless asked.
    Keep profanity when it carries the speaker's tone. Remove verbal debris only when the mode asks.
    Do not add a title, heading, summary, sign-off or list unless the mode or transcript requires it.
    """

    public static let minimalFormattingInstructions = """
    Make the smallest possible edit to the transcript. Keep its sentence structure, word order,
    request form and surrounding prose. Apply only the formatting explicitly justified by the mode
    instructions. Never translate prose into source code, configuration, commands, bullets or
    Markdown. Do not wrap identifiers in backticks. If a change is uncertain, leave it unchanged.
    """

    public static let agentRewriteCompletionInstructions = """
    Process the complete transcript, including its final third. Restore missing sentence boundaries
    and capitalization throughout any unpunctuated run. Remove every explicit filler and repeated
    fragment requested by Agent mode. Do not leave a long run-on merely to minimize edits.
    """

    public static let selectiveAgentRewriteInstructions = """
    Repair one selected run-on from speech recognition and return only the corrected text.
    Copy every input word exactly once and in the same order. Change only punctuation and case,
    except for one-word, unambiguous subject-verb agreement fixes.
    Restore sentence boundaries and capitalization. Filler and repetition cleanup is already done.
    Process the complete segment, including its final third, and do not leave a run-on to minimize
    edits. Never merely capitalize a likely new sentence without adding its missing punctuation.
    Make the smallest possible edits. Preserve wording, order, meaning, facts, names, numbers,
    commands, paths, constraints, uncertainty, profanity, Markdown and line breaks. Never add
    content, headings, lists or commentary. If a change is uncertain, leave it unchanged.
    """

    public static let agentEditInstructions = """
    You edit speech-recognition text by returning a compact JSON edit plan, never rewritten prose.
    Each edit's source must be one exact, case-sensitive substring from the transcript.
    Terminology and personal spellings are normalized before this step.
    Never edit a term listed as protected terminology, including its ASR variants or capitalization.
    Every edit must include allOccurrences. Set it to false when the source occurs once.
    If a short source repeats in different contexts, choose a longer unique exact phrase and use false.
    Set allOccurrences to true only when the identical correction is required at every exact match.
    An allOccurrences source must contain at least two words and enough context to make the same
    correction safe at every exact match.
    Never use allOccurrences with a lone word such as are, is, have, do, need or remains.
    Never propose overlapping edits.
    When the same grammatical error repeats in equivalent surrounding context, prefer one compact
    two-or-more-word source with allOccurrences true. Otherwise use the shortest exact clause that
    contains both the subject and verb.
    Do not return separate edits that differ only by a number or segment identifier. Collapse them
    into the shortest repeated exact erroneous phrase and set allOccurrences to true.
    Check unambiguous subject-verb agreement: plural subjects take are/have/do/need, while singular
    subjects take is/has/does/needs. Example: "The delivery checks is running" becomes
    "The delivery checks are running", and "the terminal checks needs Ghostty" becomes
    "the terminal checks need Ghostty".
    Contexts that differ only by a numbered segment identifier are equivalent for allOccurrences.
    For sentence-boundary capitalization or punctuation, use the complete sentence.
    For a technical spelling or identifier-only correction, use the shortest unique contextual phrase.
    Example: {"source":"The result are wrong.","replacement":"The result is wrong.","allOccurrences":true}.
    Never include an edit when source and replacement would be identical.
    Scan the transcript from start to finish and return every high-confidence correction in one plan.
    Most sentences may already be correct. Do not list a sentence merely to show that it was checked.
    Do not replace valid wording with a synonym or stylistic alternative; for example, never change
    "has to" into "must". Before returning, remove unchanged edits and redundant overlapping edits.
    If every sentence is already correct under the user rules, return {"edits":[]} immediately.
    Keep edits short and independent. Use an empty replacement only for a clearly justified deletion.
    Make only high-confidence corrections required by the user rules or local context.
    Preserve meaning, facts, names, numbers, paths, constraints, uncertainty, profanity and tone.
    If no change is clearly justified, return {"edits":[]}.
    """

    public static let agentEditJSONSchema = #"{"type":"object","properties":{"edits":{"type":"array","items":{"type":"object","properties":{"source":{"type":"string"},"replacement":{"type":"string"},"allOccurrences":{"type":"boolean"}},"required":["source","replacement","allOccurrences"],"additionalProperties":false}}},"required":["edits"],"additionalProperties":false}"#

    public static let agentSelfEditInstructions = """
    Remove only explicit spoken self-corrections from a speech transcript. Return a compact JSON
    edit plan, never rewritten prose. Each source must be one exact, case-sensitive, unique substring
    containing the abandoned wording, its correction cue, and enough corrected wording to make the
    intent unambiguous. Each replacement must use only words already present in that source, in the
    same order. Set allOccurrences to false. Do not fix grammar, punctuation, names or style here.
    Do not treat instructions such as `delete the cache` as self-edits. Do not remove passages merely
    discussing phrases such as `delete that` or `ignore that part`. If uncertain, return {"edits":[]}.

    Example: `Q C UE delete that CUE is interesting` becomes the edit
    {"source":"Q C UE delete that CUE","replacement":"CUE","allOccurrences":false}.
    Example: `say things wrong no delete that say things in the wrong way` becomes the edit
    {"source":"say things wrong no delete that say things in the wrong way","replacement":"say things in the wrong way","allOccurrences":false}.
    Example: `it is a mute point but a moot point there we go that's better` becomes the edit
    {"source":"a mute point but a moot point there we go that's better","replacement":"a moot point","allOccurrences":false}.
    Example: `I said the words delete that in my example` has no self-edit and returns {"edits":[]}.
    """

    public static func agentSelfEditPrompt(transcript: String) -> String {
        """
        Speech transcript:
        <transcript>
        \(transcript)
        </transcript>

        Return the JSON edit plan now.
        """
    }

    public static func agentEditPrompt(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext
    ) -> String {
        WritingRules.prompt(
            transcript: transcript,
            mode: .agent,
            markdownRules: markdownRules,
            agentContext: context
        ) + "\n\nReturn the JSON edit plan now."
    }

    public static func selectiveAgentRewritePrompt(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext
    ) -> String {
        let trimmedRules = markdownRules.trimmingCharacters(in: .whitespacesAndNewlines)
        let rulesSection = if trimmedRules.isEmpty
            || !WritingRules.agentRulesContainCustomInstructions(trimmedRules) {
            ""
        } else {
            """

            User rules:
            <rules>
            \(trimmedRules)
            </rules>
            """
        }
        let relevantContext = context.promptSection(relevantTo: transcript)
        let contextSection = relevantContext.isEmpty ? "" : """

        Relevant context:
        <context>
        \(relevantContext)
        </context>
        """
        return """
        \(rulesSection)\(contextSection)

        Speech transcript:
        <transcript>
        \(transcript)
        </transcript>
        """
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func systemInstructions(for fixture: WritingFixture) -> String {
        guard usesMinimalFormatting(for: fixture) else { return baseInstructions }
        return baseInstructions + "\n" + minimalFormattingInstructions
    }

    public static let aiSmells = [
        "—", "–", "it's worth noting", "it is worth noting", "in conclusion",
        "to summarize", "to wrap things up", "delve", "leverage", "seamless",
        "in today's", "at the end of the day", "the honest answer"
    ]

    public static func prompt(for fixture: WritingFixture, repeatTranscript: Int = 1) -> String {
        let transcript = expanded(fixture.transcript, count: repeatTranscript)
        if fixture.mode.caseInsensitiveCompare(DictationMode.agent.label) == .orderedSame {
            return WritingRules.prompt(
                transcript: transcript,
                mode: .agent,
                markdownRules: WritingRules.defaultMarkdown(for: .agent)
            )
        }
        return """
        Mode instructions:
        \(fixture.instructions)

        Speech transcript:
        <transcript>
        \(transcript)
        </transcript>
        """
    }

    public static func evaluate(
        fixture: WritingFixture,
        rawOutput: String,
        latencySeconds: Double,
        repeatExpected: Int = 1,
        pipelineOutcome: String = "completed"
    ) -> WritingFixtureResult {
        let output = usesMinimalFormatting(for: fixture)
            ? cleanMinimalFormattingEnvelope(rawOutput)
            : cleanEnvelope(rawOutput)
        let input = expanded(fixture.transcript, count: repeatExpected)
        let expected = expanded(fixture.expected, count: repeatExpected)
        let inputWords = normalizedWords(input)
        let expectedWords = normalizedWords(expected)
        let outputWords = normalizedWords(output)
        let errors = editDistance(expectedWords, outputWords)
        let lowered = output.lowercased()
        let requiredChecks = expandedChecks(fixture.required, count: repeatExpected)
        let forbiddenChecks = expandedChecks(fixture.forbidden, count: repeatExpected)
        let requiredPassed = requiredChecks.filter {
            containsQualityCheck($0, in: lowered)
        }.count
        let forbiddenPassed = forbiddenChecks.filter {
            !containsQualityCheck($0, in: lowered)
        }.count
        let smellHits = aiSmells.filter { lowered.contains($0.lowercased()) }

        return WritingFixtureResult(
            id: fixture.id,
            mode: fixture.mode,
            inputWordCount: inputWords.count,
            outputWordCount: outputWords.count,
            changedWordCount: editDistance(inputWords, outputWords),
            pipelineOutcome: pipelineOutcome,
            latencySeconds: latencySeconds,
            expectedWordErrorRate: expectedWords.isEmpty
                ? 0
                : Double(errors) / Double(expectedWords.count),
            requiredPassed: requiredPassed,
            requiredTotal: requiredChecks.count,
            forbiddenPassed: forbiddenPassed,
            forbiddenTotal: forbiddenChecks.count,
            aiSmellHits: smellHits,
            expected: expected,
            output: output
        )
    }

    public static func summarize(
        provider: String,
        model: String,
        results: [WritingFixtureResult],
        createdAt: Date = Date()
    ) -> WritingSummary {
        let latencies = results.map(\.latencySeconds).sorted()
        let requiredPassed = results.reduce(0) { $0 + $1.requiredPassed }
        let requiredTotal = results.reduce(0) { $0 + $1.requiredTotal }
        let forbiddenPassed = results.reduce(0) { $0 + $1.forbiddenPassed }
        let forbiddenTotal = results.reduce(0) { $0 + $1.forbiddenTotal }

        return WritingSummary(
            provider: provider,
            model: model,
            fixtures: results.count,
            meanLatencySeconds: results.isEmpty
                ? 0
                : latencies.reduce(0, +) / Double(results.count),
            p50LatencySeconds: percentile(latencies, 0.5) ?? 0,
            p95LatencySeconds: percentile(latencies, 0.95) ?? 0,
            meanExpectedWordErrorRate: results.isEmpty
                ? 0
                : results.reduce(0) { $0 + $1.expectedWordErrorRate } / Double(results.count),
            requiredPassRate: requiredTotal == 0
                ? 1
                : Double(requiredPassed) / Double(requiredTotal),
            forbiddenPassRate: forbiddenTotal == 0
                ? 1
                : Double(forbiddenPassed) / Double(forbiddenTotal),
            totalAISmellHits: results.reduce(0) { $0 + $1.aiSmellHits.count },
            fallbackCount: results.filter {
                $0.pipelineOutcome.hasPrefix("fallback")
            }.count,
            latencyByLength: latencySummaries(for: results),
            createdAt: ISO8601DateFormatter().string(from: createdAt),
            results: results
        )
    }

    public static func cleanEnvelope(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") && cleaned.hasSuffix("```") {
            cleaned = cleaned
                .split(whereSeparator: \.isNewline)
                .dropFirst()
                .dropLast()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    public static func cleanMinimalFormattingEnvelope(_ text: String) -> String {
        cleanEnvelope(text).replacingOccurrences(
            of: #"`([^`\n]+)`"#,
            with: "$1",
            options: .regularExpression
        )
    }

    public static func normalizedWords(_ text: String) -> [String] {
        let folded = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                return Character(String(scalar))
            }
            return " "
        }
        return String(cleaned).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    public static func expanded(_ text: String, count: Int) -> String {
        (1...max(count, 1)).map { index in
            text.replacingOccurrences(of: "{{index}}", with: String(index))
        }.joined(separator: "\n\n")
    }

    private static func expandedChecks(_ checks: [String], count: Int) -> [String] {
        checks.flatMap { check in
            guard count > 1, check.contains("{{index}}") else { return [check] }
            return (1...count).map {
                check.replacingOccurrences(of: "{{index}}", with: String($0))
            }
        }
    }

    private static func containsQualityCheck(_ check: String, in loweredText: String) -> Bool {
        let loweredCheck = check.lowercased()
        guard !loweredCheck.isEmpty else { return true }
        var pattern = NSRegularExpression.escapedPattern(for: loweredCheck)
        if let first = loweredCheck.first,
           first.isLetter || first.isNumber || first == "_" {
            pattern = #"(?<![\p{L}\p{N}_])"# + pattern
        }
        if let last = loweredCheck.last,
           last.isLetter || last.isNumber || last == "_" {
            pattern += #"(?![\p{L}\p{N}_])"#
        }
        return loweredText.range(of: pattern, options: .regularExpression) != nil
    }

    public static func editDistance<T: Equatable>(_ left: [T], _ right: [T]) -> Int {
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }

        var previous = Array(0...right.count)
        for (leftIndex, leftValue) in left.enumerated() {
            var current = [leftIndex + 1] + Array(repeating: 0, count: right.count)
            for (rightIndex, rightValue) in right.enumerated() {
                let cost = leftValue == rightValue ? 0 : 1
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + cost
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    private static func percentile(_ sortedValues: [Double], _ fraction: Double) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let index = Int((Double(sortedValues.count - 1) * fraction).rounded())
        return sortedValues[index]
    }

    public static func lengthBucket(for inputWordCount: Int) -> WritingLengthBucket {
        switch inputWordCount {
        case ...150: .short
        case ...350: .medium
        case ...800: .long
        default: .stress
        }
    }

    private static func latencySummaries(
        for results: [WritingFixtureResult]
    ) -> [WritingLatencyBucketSummary] {
        WritingLengthBucket.allCases.compactMap { bucket in
            let matching = results.filter {
                lengthBucket(for: $0.inputWordCount) == bucket
            }
            guard !matching.isEmpty else { return nil }
            let latencies = matching.map(\.latencySeconds).sorted()
            let wordCounts = matching.map(\.inputWordCount)
            return WritingLatencyBucketSummary(
                bucket: bucket,
                fixtures: matching.count,
                minimumInputWords: wordCounts.min() ?? 0,
                maximumInputWords: wordCounts.max() ?? 0,
                meanLatencySeconds: latencies.reduce(0, +) / Double(latencies.count),
                p50LatencySeconds: percentile(latencies, 0.5) ?? 0,
                p95LatencySeconds: percentile(latencies, 0.95) ?? 0
            )
        }
    }

    private static func usesMinimalFormatting(for fixture: WritingFixture) -> Bool {
        fixture.mode == "Smart formatting"
            || fixture.mode.caseInsensitiveCompare(DictationMode.agent.label) == .orderedSame
    }
}
