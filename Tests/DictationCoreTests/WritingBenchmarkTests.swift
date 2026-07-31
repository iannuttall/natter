import Foundation
import Testing
@testable import DictationCore

@Test func promptPreservesModeAndTranscript() {
    let fixture = makeFixture()
    let prompt = WritingBenchmark.prompt(for: fixture, repeatTranscript: 2)

    #expect(prompt.contains("Fix punctuation only"))
    #expect(prompt.components(separatedBy: "hello um world").count == 3)
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
