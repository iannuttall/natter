import Foundation
import Testing

@testable import NatterCore

@Test func transcriptEditPlanAppliesUniqueNonOverlappingChanges() throws {
    let input = "Open the Gitter repo in NATA and keep /tmp/build intact."
    let plan = TranscriptEditPlan(edits: [
        TranscriptEdit(source: "Gitter", replacement: "GitHub"),
        TranscriptEdit(source: "NATA", replacement: "Natter"),
    ])

    #expect(
        try TranscriptEditApplier.apply(plan, to: input)
            == "Open the GitHub repo in Natter and keep /tmp/build intact.")
}

@Test func transcriptEditPlanAcceptsLongSentenceAnchorWithDifferentCase() throws {
    let input =
        "the delivery checks for segment 2 is running in ChatGPT Desktop and Claude Desktop."
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(
                source:
                    "The delivery checks for segment 2 is running in ChatGPT Desktop and Claude Desktop.",
                replacement:
                    "The delivery checks for segment 2 are running in ChatGPT Desktop and Claude Desktop."
            )
        ]),
        to: input
    )

    #expect(
        result
            == "The delivery checks for segment 2 are running in ChatGPT Desktop and Claude Desktop."
    )
}

@Test func transcriptEditPlanMeasuresLocalChangesInsideAFullSentence() throws {
    let input =
        "The result are still wrong, the validator have preserved the raw transcript, and the delivery checks is running while the constraints remains unchanged."
    let replacement =
        "The result is still wrong, the validator has preserved the raw transcript, and the delivery checks are running while the constraints remain unchanged."

    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(source: input, replacement: replacement)
        ]),
        to: input
    )

    #expect(result == replacement)
}

@Test func transcriptEditPlanAllowsManySmallSafeCorrections() throws {
    let sources = (1...24).map { "issue-\($0)-end" }
    let input =
        sources.joined(separator: " ")
        + " " + String(repeating: "deliberate context ", count: 40)
    let plan = TranscriptEditPlan(
        edits: sources.enumerated().map { index, source in
            TranscriptEdit(source: source, replacement: "fixed-\(index + 1)-end")
        })

    let output = try TranscriptEditApplier.apply(plan, to: input)

    #expect(output.contains("fixed-1-end fixed-2-end"))
    #expect(output.contains("fixed-23-end fixed-24-end"))
}

@Test func structuredEditGenerationBudgetScalesWithTranscriptLength() {
    let short = String(repeating: "word ", count: 20)
    let medium = String(repeating: "word ", count: 350)
    let stress = String(repeating: "word ", count: 1_500)

    #expect(AgentEditGenerationBudget.maximumTokens(for: short) == 1_024)
    #expect(AgentEditGenerationBudget.maximumTokens(for: medium) == 3_056)
    #expect(AgentEditGenerationBudget.maximumTokens(for: stress) == 8_192)
}

@Test func agentChunkingIsLosslessAndBoundedForVeryLongText() {
    let sentence = "The result are wrong and NATA needs the GitHub fix. "
    let transcript = String(repeating: sentence, count: 180)

    let chunks = AgentTranscriptChunker.chunks(transcript, maximumWords: 120)

    #expect(chunks.count > 10)
    #expect(chunks.joined() == transcript)
    #expect(chunks.allSatisfy { AgentTranscriptChunker.wordCount($0) <= 120 })
}

@Test func selectiveAgentRewriteSegmentationIsLosslessAndAlwaysProcessesCleanText() {
    let shortSentence = "This sentence is already fine. "
    let runOn = String(repeating: "unfinished thought ", count: 80)
    let transcript = shortSentence + runOn

    let segments = AgentRewriteSegmenter.segments(transcript)

    #expect(segments.map(\.text).joined() == transcript)
    #expect(segments.count == 2)
    #expect(segments.allSatisfy { $0.requiresRewrite })
    #expect(
        segments.allSatisfy {
            AgentTranscriptChunker.wordCount($0.text)
                <= AgentRewriteSegmenter.wholeTranscriptMaximumWords
        })
}

@Test func selectiveAgentRewriteProcessesShortDictationAsOneUnit() {
    let transcript = "The result are wrong and it need another pass."
    #expect(
        AgentRewriteSegmenter.segments(transcript) == [
            AgentRewriteSegment(text: transcript, requiresRewrite: true)
        ])
}

@Test func terminologyGuardRejectsDroppedOrMergedProtectedTerms() {
    let input = "Do not commit this apart from Keep. Keep is fine."

    #expect(
        TranscriptTerminologyGuard.preserves(
            ["Keep"],
            from: input,
            in: "Do not commit this apart from Keep. Keep is fine."
        ))
    #expect(
        !TranscriptTerminologyGuard.preserves(
            ["Keep"],
            from: input,
            in: "Do not commit this apart from keeping it fine."
        ))
}

@Test func wordingGuardAllowsOnlyPunctuationCapitalizationAndAgreement() {
    #expect(
        TranscriptWordingGuard.preservesWords(
            from: "the checks is running and the result need work",
            in: "The checks are running. And the result needs work."
        ))
    #expect(
        !TranscriptWordingGuard.preservesWords(
            from: "do not drop this constraint or this example",
            in: "Do not drop this constraint or example."
        ))
    #expect(
        !TranscriptWordingGuard.preservesWords(
            from: "if I say switch the profile",
            in: "If I switch the profile."
        ))
}

@Test func formattingProjectionKeepsPunctuationButRestoresChangedWords() {
    let source = "Whatever was enter or send then it would recognize that"
    let proposed = "Whatever was entered or sent, then it would recognize that."

    #expect(
        TranscriptFormattingProjection.project(
            from: source,
            onto: proposed
        ) == "Whatever was enter or send, then it would recognize that.")
}

@Test func formattingProjectionRejectsDroppedAndBroadlyRewrittenContent() {
    #expect(
        TranscriptFormattingProjection.project(
            from: "Keep every original word here",
            onto: "Keep every word here"
        ) == nil)
    #expect(
        TranscriptFormattingProjection.project(
            from: "Keep every original word here",
            onto: "Replace all of this now"
        ) == nil)
}

@Test func agentSelfEditPolicyAcceptsOnlyGroundedCueEdits() {
    let safe = TranscriptEdit(
        source: "Q C UE delete that CUE",
        replacement: "CUE"
    )
    let invented = TranscriptEdit(
        source: "Q C UE delete that CUE",
        replacement: "Queue"
    )
    let unrelated = TranscriptEdit(
        source: "Delete the cache and restart",
        replacement: "restart"
    )

    #expect(AgentSelfEditPolicy.containsCorrectionCue("No, delete that and use this"))
    #expect(!AgentSelfEditPolicy.containsCorrectionCue("Delete the cache and restart"))
    #expect(
        AgentSelfEditPolicy.safePlan(
            from: TranscriptEditPlan(
                edits: [safe, invented, unrelated]
            )) == TranscriptEditPlan(edits: [safe]))
}

@Test func groundedAgentSelfEditAppliesObservedCorrection() {
    let transcript = "The queue app Q C UE delete that CUE is interesting."
    let plan = AgentSelfEditPolicy.safePlan(
        from: TranscriptEditPlan(edits: [
            TranscriptEdit(source: "Q C UE delete that CUE", replacement: "CUE")
        ]))

    #expect(
        TranscriptEditApplier.applyRecovering(plan, to: transcript).output
            == "The queue app CUE is interesting.")
}

@Test func transcriptEditPlanRejectsAmbiguousAndOversizedChanges() {
    #expect(throws: TranscriptEditApplicationError.sourceNotUnique("test", matches: 2)) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [TranscriptEdit(source: "test", replacement: "check")]),
            to: "test this test"
        )
    }

    #expect(throws: TranscriptEditApplicationError.self) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [
                TranscriptEdit(
                    source: "Keep this complete sentence exactly as it was originally spoken.",
                    replacement: "Replace everything."
                )
            ]),
            to: "Keep this complete sentence exactly as it was originally spoken."
        )
    }
}

@Test func residualAcknowledgementIsRemovedOnlyAfterAGroundedEdit() {
    let transcript = "It might be a moot point there we go that's better."
    #expect(
        AgentSelfEditPolicy.removingResidualAcknowledgementCues(from: transcript)
            == "It might be a moot point"
    )
}

@Test func transcriptEditPlanCanTargetOneRepeatedOccurrenceExplicitly() throws {
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(source: "NATA", replacement: "Natter", occurrence: 2)
        ]),
        to: "NATA is an organisation. This app is NATA."
    )

    #expect(result == "NATA is an organisation. This app is Natter.")
}

@Test func transcriptEditPlanCanCorrectEveryIdenticalOccurrenceExplicitly() throws {
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(
                source: "the result are wrong",
                replacement: "the result is wrong",
                allOccurrences: true
            )
        ]),
        to: "First, the result are wrong. Later, the result are wrong again."
    )

    #expect(result == "First, the result is wrong. Later, the result is wrong again.")
}

@Test func transcriptEditPlanCanBulkCorrectAContextualTwoWordPhrase() throws {
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(
                source: "are incomplete",
                replacement: "is incomplete",
                allOccurrences: true
            )
        ]),
        to:
            "The benchmark result for segment 1 are incomplete. The benchmark result for segment 2 are incomplete."
    )

    #expect(
        result
            == "The benchmark result for segment 1 is incomplete. The benchmark result for segment 2 is incomplete."
    )
}

@Test func transcriptEditPlanRejectsTwoWordBulkCorrectionAcrossDifferentContexts() {
    #expect(throws: TranscriptEditApplicationError.unsafeAllOccurrencesSource("are incomplete")) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [
                TranscriptEdit(
                    source: "are incomplete",
                    replacement: "is incomplete",
                    allOccurrences: true
                )
            ]),
            to: "The first results are incomplete. Later, the final result are incomplete."
        )
    }
}

@Test func transcriptEditPlanIgnoresCompatibleRedundantOverlaps() throws {
    let input =
        "The validator have preserved the raw transcript, but the checks do not yet prove the long case."
    let output =
        "The validator has preserved the raw transcript, but the checks do not yet prove the long case."
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(
                source: "The validator have preserved", replacement: "The validator has preserved"),
            TranscriptEdit(source: input, replacement: output),
        ]),
        to: input
    )

    #expect(result == output)
}

@Test func transcriptEditPlanRecoveryKeepsValidEditsAndDropsOnlyInvalidOnes() {
    let result = TranscriptEditApplier.applyRecovering(
        TranscriptEditPlan(edits: [
            TranscriptEdit(source: "The result are wrong", replacement: "The result is wrong"),
            TranscriptEdit(source: "Text beyond the chunk boundary", replacement: "Invented text"),
        ]),
        to: "The result are wrong, but the raw transcript remains intact."
    )

    #expect(result.output == "The result is wrong, but the raw transcript remains intact.")
    #expect(result.acceptedEdits == 1)
    #expect(result.rejectedEdits == 1)
}

@Test func transcriptEditPlanRejectsContextFreeBulkCorrections() {
    #expect(throws: TranscriptEditApplicationError.unsafeAllOccurrencesSource("are")) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [
                TranscriptEdit(source: "are", replacement: "is", allOccurrences: true)
            ]),
            to: "The result are wrong, but the checks are useful."
        )
    }
}

@Test func transcriptEditPlanAllowsOneWordBulkOnlyAcrossEquivalentContexts() throws {
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(source: "remains", replacement: "remain", allOccurrences: true)
        ]),
        to:
            "These constraints for segment 1 remains deliberate. These constraints for segment 2 remains deliberate."
    )

    #expect(
        result
            == "These constraints for segment 1 remain deliberate. These constraints for segment 2 remain deliberate."
    )
}

@Test func transcriptEditPlanRejectsChangesToProtectedCanonicalTerms() {
    #expect(throws: TranscriptEditApplicationError.altersProtectedTerminology("Natter")) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [
                TranscriptEdit(source: "Natter", replacement: "native", occurrence: 1)
            ]),
            to: "Natter should preserve the raw transcript.",
            protectedTerms: ["Natter", "GitHub"]
        )
    }

    #expect(throws: TranscriptEditApplicationError.altersProtectedTerminology("NATA")) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [
                TranscriptEdit(source: "NATA", replacement: "Natter", occurrence: 1)
            ]),
            to: "Keep the NATA organisation unchanged.",
            protectedTerms: ["Natter", "Nata", "NATA"]
        )
    }
}

@Test func transcriptEditPlanProtectsTerminologyInsideSentenceEdits() {
    #expect(throws: TranscriptEditApplicationError.altersProtectedTerminology("Natter")) {
        try TranscriptEditApplier.apply(
            TranscriptEditPlan(edits: [
                TranscriptEdit(
                    source: "Natter keeps the raw transcript when a model fails.",
                    replacement: "Native keeps the raw transcript when a model fails."
                )
            ]),
            to: "Natter keeps the raw transcript when a model fails.",
            protectedTerms: ["Natter"]
        )
    }
}
