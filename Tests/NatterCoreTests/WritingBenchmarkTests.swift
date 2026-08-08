import Foundation
import Testing
@testable import NatterCore

@Test func promptPreservesModeAndTranscript() {
    let fixture = makeFixture()
    let prompt = WritingBenchmark.prompt(for: fixture, repeatTranscript: 2)

    #expect(prompt.contains("Fix punctuation only"))
    #expect(prompt.components(separatedBy: "hello um world").count == 3)
}

@Test func smartFormattingUsesMinimalEditInstructions() {
    let fixture = WritingFixture(
        id: "smart",
        mode: "Smart formatting",
        instructions: "Format identifiers.",
        transcript: "Set scroll restoration: true.",
        expected: "Set scrollRestoration: true.",
        required: [],
        forbidden: []
    )

    let instructions = WritingBenchmark.systemInstructions(for: fixture)
    #expect(instructions.contains("smallest possible edit"))
    #expect(instructions.contains("Never translate prose into source code"))
}

@Test func cleanBenchmarkUsesTheProductionPromptAndEnvelope() {
    let fixture = WritingFixture(
        id: "clean",
        mode: "Clean",
        instructions: "- Restore sentence boundaries without rephrasing.",
        transcript: "Run Claude dash P.",
        expected: "Run claude -p.",
        required: [],
        forbidden: []
    )

    #expect(WritingBenchmark.systemInstructions(for: fixture)
        .contains("smallest possible edit"))
    #expect(WritingBenchmark.prompt(for: fixture).contains("Mode: Clean"))
    #expect(WritingBenchmark.prompt(for: fixture)
        .contains("Restore sentence boundaries"))
    #expect(WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: "Run `claude -p`.",
        latencySeconds: 0.5
    ).output == "Run claude -p.")
}

@Test func smartFormattingRemovesUnrequestedMarkdownBackticks() {
    #expect(WritingBenchmark.cleanMinimalFormattingEnvelope(
        "Keep the `@MainActor` annotation."
    ) == "Keep the @MainActor annotation.")
}

@Test func shortArticleRulesDoNotInviteAnInventedTitle() {
    let rules = WritingRules.defaultMarkdown(for: .article)
    #expect(rules.contains("Do not add a title"))
    #expect(rules.contains("several distinct sections"))
}

@Test func writingOutputPolicyRemovesAForbiddenMarkdownTitle() {
    let output = """
    # Building Your Own Dictation App

    The useful thing is being able to notice tiny delays.
    """

    #expect(WritingOutputPolicy.enforce(
        output,
        markdownRules: "- Do not add a title."
    ) == "The useful thing is being able to notice tiny delays.")
}

@Test func writingOutputPolicyKeepsTitlesWhenRulesAllowThem() {
    let output = "# A requested title\n\nThe article body."

    #expect(WritingOutputPolicy.enforce(
        output,
        markdownRules: "- Add a useful title."
    ) == output)
}

@Test func evaluationScoresRequirementsAndForbiddenText() {
    let fixture = makeFixture()
    let result = WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: "Hello world.",
        latencySeconds: 0.5
    )

    #expect(result.requiredPassed == 1)
    #expect(result.requiredTotal == 1)
    #expect(result.forbiddenPassed == 1)
    #expect(result.forbiddenTotal == 1)
    #expect(result.expectedWordErrorRate == 0)
}

@Test func repeatedBenchmarkEvaluationRepeatsItsReferenceAndReportsLength() {
    let fixture = makeFixture()
    let output = Array(repeating: fixture.expected, count: 60).joined(separator: "\n\n")
    let result = WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: output,
        latencySeconds: 1.5,
        repeatExpected: 60
    )

    #expect(result.inputWordCount == 180)
    #expect(result.outputWordCount == 120)
    #expect(result.expectedWordErrorRate == 0)
    #expect(WritingBenchmark.lengthBucket(for: result.inputWordCount) == .medium)
}

@Test func repeatedBenchmarkEvaluationExpandsIndexedQualityChecks() {
    let fixture = WritingFixture(
        id: "indexed",
        mode: "Agent",
        instructions: "Correct grammar",
        transcript: "Segment {{index}} are wrong.",
        expected: "Segment {{index}} is wrong.",
        required: ["Segment {{index}} is wrong"],
        forbidden: ["Segment {{index}} are wrong"]
    )
    let result = WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: "Segment 1 is wrong. Segment 2 are wrong.",
        latencySeconds: 1,
        repeatExpected: 2
    )

    #expect(result.requiredPassed == 1)
    #expect(result.requiredTotal == 2)
    #expect(result.forbiddenPassed == 1)
    #expect(result.forbiddenTotal == 2)
}

@Test func qualityChecksDoNotMatchPrefixesInsideLongerWords() {
    let fixture = WritingFixture(
        id: "boundaries",
        mode: "Agent",
        instructions: "Correct grammar",
        transcript: "The terminal checks needs Ghostty.",
        expected: "The terminal checks need Ghostty.",
        required: ["terminal checks need"],
        forbidden: ["terminal checks needs"]
    )
    let result = WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: fixture.transcript,
        latencySeconds: 1
    )

    #expect(result.requiredPassed == 0)
    #expect(result.forbiddenPassed == 0)
}

@Test func repeatedBenchmarkExpansionMakesStressSegmentsUnique() {
    #expect(
        WritingBenchmark.expanded("Segment {{index}} needs work.", count: 3)
            == "Segment 1 needs work.\n\nSegment 2 needs work.\n\nSegment 3 needs work."
    )
}

@Test func benchmarkSummaryReportsLatencyByWordBucket() {
    let fixture = makeFixture()
    let short = WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: fixture.expected,
        latencySeconds: 0.4
    )
    let longOutput = Array(repeating: fixture.expected, count: 120).joined(separator: "\n\n")
    let long = WritingBenchmark.evaluate(
        fixture: fixture,
        rawOutput: longOutput,
        latencySeconds: 2.5,
        repeatExpected: 120
    )
    let summary = WritingBenchmark.summarize(
        provider: "test",
        model: "test",
        results: [short, long]
    )

    #expect(summary.latencyByLength.map(\.bucket) == [.short, .long])
    #expect(summary.latencyByLength.last?.p50LatencySeconds == 2.5)
}

@Test func fencedOutputIsUnwrapped() {
    #expect(WritingBenchmark.cleanEnvelope("```text\nHello\n```") == "Hello")
}

@Test func editDistanceHandlesInsertionAndReplacement() {
    #expect(WritingBenchmark.editDistance(["a", "b"], ["a", "x", "b"]) == 1)
    #expect(WritingBenchmark.editDistance(["a", "b"], ["a", "c"]) == 1)
}


private func makeFixture() -> WritingFixture {
    WritingFixture(
        id: "test",
        mode: "Test",
        instructions: "Fix punctuation only",
        transcript: "hello um world",
        expected: "Hello world.",
        required: ["hello world"],
        forbidden: [" um "]
    )
}
