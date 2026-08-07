import Foundation
import Testing
@testable import NatterCore

@Test func agentSelfEditEvalCorpusIsCompleteAndRoutedIntentionally() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtureURL = repositoryRoot
        .appendingPathComponent("ProductCorpus/agent-self-edit-fixtures.json")
    let fixtureSet = try JSONDecoder().decode(
        WritingFixtureSet.self,
        from: Data(contentsOf: fixtureURL)
    )

    #expect(fixtureSet.fixtures.count >= 40)
    #expect(Set(fixtureSet.fixtures.map(\.id)).count == fixtureSet.fixtures.count)

    for fixture in fixtureSet.fixtures {
        #expect(!fixture.transcript.isEmpty)
        #expect(!fixture.expected.isEmpty)
        #expect(!fixture.required.isEmpty)
        if fixture.id.starts(with: "bypass-") {
            #expect(!AgentSelfEditPolicy.containsCorrectionCue(fixture.transcript))
        } else {
            #expect(AgentSelfEditPolicy.containsCorrectionCue(fixture.transcript))
        }
    }
}

@Test func agentSelfEditSafetyRequiresReplacementFromCorrectedSide() {
    let valid = TranscriptEdit(
        source: "Use the small icon no delete that use the large icon",
        replacement: "use the large icon"
    )
    let leavesBothVersions = TranscriptEdit(
        source: "no delete that",
        replacement: ""
    )
    let keepsAbandonedVersion = TranscriptEdit(
        source: "small icon no delete that large icon",
        replacement: "small icon"
    )

    let safe = AgentSelfEditPolicy.safePlan(from: TranscriptEditPlan(
        edits: [valid, leavesBothVersions, keepsAbandonedVersion]
    ))
    #expect(safe.edits == [valid])
}

@Test func agentSelfEditFinishedOutputAcceptsOnlyGroundedDeletions() {
    let input = "Ship on Monday delete that ship on Tuesday and email Sam ignore that email Alex."
    #expect(AgentSelfEditPolicy.safeOutput(
        input: input,
        proposedOutput: "Ship on Tuesday and email Alex."
    ) == "Ship on Tuesday and email Alex.")
    #expect(AgentSelfEditPolicy.safeOutput(
        input: input,
        proposedOutput: "Ship immediately on Tuesday and email Alex."
    ) == nil)
    #expect(AgentSelfEditPolicy.safeOutput(
        input: input,
        proposedOutput: "Ship on Monday ship on Tuesday and email Alex."
    ) == nil)
    #expect(AgentSelfEditPolicy.safeOutput(
        input: "Book the morning train ignore that book the evening train.",
        proposedOutput: "Book the morning train."
    ) == nil)
}

@Test func agentSelfEditFinishedOutputPreservesNoEditAndAcknowledgementCases() {
    let meta = "I said the words delete that in my example."
    #expect(AgentSelfEditPolicy.safeOutput(
        input: meta,
        proposedOutput: meta
    ) == meta)
    #expect(AgentSelfEditPolicy.safeOutput(
        input: "It is a mute point but a moot point there we go that's better.",
        proposedOutput: "It is a moot point."
    ) == "It is a moot point.")
}
