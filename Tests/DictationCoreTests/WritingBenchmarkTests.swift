import Foundation
import Testing
@testable import DictationCore

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

@Test func agentBenchmarkUsesTheProductionPromptAndEnvelope() {
    let fixture = WritingFixture(
        id: "agent",
        mode: "Agent",
        instructions: "- Format explicit CLI commands literally.",
        transcript: "Run Claude dash P.",
        expected: "Run claude -p.",
        required: [],
        forbidden: []
    )

    #expect(WritingBenchmark.systemInstructions(for: fixture)
        .contains("smallest possible edit"))
    #expect(WritingBenchmark.prompt(for: fixture).contains("Mode: Agent"))
    #expect(WritingBenchmark.prompt(for: fixture)
        .contains("speech-recognition homophones"))
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
        mode: "clean",
        instructions: "Fix punctuation only",
        transcript: "hello um world",
        expected: "Hello world.",
        required: ["hello world"],
        forbidden: [" um "]
    )
}
