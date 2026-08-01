import Foundation

public struct WritingFixture: Codable, Sendable {
    public let id: String
    public let mode: String
    public let instructions: String
    public let transcript: String
    public let expected: String
    public let required: [String]
    public let forbidden: [String]

    public init(
        id: String,
        mode: String,
        instructions: String,
        transcript: String,
        expected: String,
        required: [String],
        forbidden: [String]
    ) {
        self.id = id
        self.mode = mode
        self.instructions = instructions
        self.transcript = transcript
        self.expected = expected
        self.required = required
        self.forbidden = forbidden
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

    public static func systemInstructions(for fixture: WritingFixture) -> String {
        guard fixture.mode == "Smart formatting" else { return baseInstructions }
        return baseInstructions + "\n" + minimalFormattingInstructions
    }

    public static let aiSmells = [
        "—", "–", "it's worth noting", "it is worth noting", "in conclusion",
        "to summarize", "to wrap things up", "delve", "leverage", "seamless",
        "in today's", "at the end of the day", "the honest answer"
    ]

    public static func prompt(for fixture: WritingFixture, repeatTranscript: Int = 1) -> String {
        let transcript = Array(repeating: fixture.transcript, count: repeatTranscript)
            .joined(separator: "\n\n")
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
        latencySeconds: Double
    ) -> WritingFixtureResult {
        let output = fixture.mode == "Smart formatting"
            ? cleanMinimalFormattingEnvelope(rawOutput)
            : cleanEnvelope(rawOutput)
        let expectedWords = normalizedWords(fixture.expected)
        let outputWords = normalizedWords(output)
        let errors = editDistance(expectedWords, outputWords)
        let lowered = output.lowercased()
        let requiredPassed = fixture.required.filter {
            lowered.contains($0.lowercased())
        }.count
        let forbiddenPassed = fixture.forbidden.filter {
            !lowered.contains($0.lowercased())
        }.count
        let smellHits = aiSmells.filter { lowered.contains($0.lowercased()) }

        return WritingFixtureResult(
            id: fixture.id,
            mode: fixture.mode,
            latencySeconds: latencySeconds,
            expectedWordErrorRate: expectedWords.isEmpty
                ? 0
                : Double(errors) / Double(expectedWords.count),
            requiredPassed: requiredPassed,
            requiredTotal: fixture.required.count,
            forbiddenPassed: forbiddenPassed,
            forbiddenTotal: fixture.forbidden.count,
            aiSmellHits: smellHits,
            expected: fixture.expected,
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
}
