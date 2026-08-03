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

@Test func productionAgentContextIncludesBuiltInAndPersonalTerminology() {
    let context = AgentWritingContext.production(
        destinationApplicationName: "Claude",
        corrections: [PersonalCorrection(heard: "en dot is", replacement: "ian.is")]
    )

    #expect(context.promptSection.contains("Destination application: Claude"))
    #expect(context.promptSection.contains("Protected terminology"))
    #expect(context.promptSection.contains("ian.is, en dot is"))
    #expect(context.protectedSpellings.contains("Nata"))
    #expect(context.protectedSpellings.contains("NATA"))
    let relevant = context.promptSection(relevantTo: "Send ian.is to Claude.")
    #expect(relevant.contains("ian.is"))
    #expect(relevant.contains("Destination application: Claude"))
    #expect(!relevant.contains("Natter"))
}

@Test func selectiveAgentRewritePromptOmitsRedundantDefaultsAndIrrelevantTerminology() {
    let context = AgentWritingContext.production(
        destinationApplicationName: nil,
        corrections: []
    )
    let prompt = WritingBenchmark.selectiveAgentRewritePrompt(
        transcript: "use Natter for this run on sentence",
        markdownRules: WritingRules.defaultMarkdown(for: .agent),
        context: context
    )

    #expect(prompt.contains("Natter"))
    #expect(!prompt.contains("GitHub"))
    #expect(!prompt.contains("User rules:"))

    let legacyDefaults = """
    # Agent mode
    - Make the smallest possible corrections justified by technical context.
    - Preserve the speaker's request, word order, constraints, profanity and line breaks.
    """
    #expect(!WritingRules.agentRulesContainCustomInstructions(legacyDefaults))
    #expect(WritingRules.agentRulesContainCustomInstructions(
        legacyDefaults + "\n- Always keep my issue keys uppercase."
    ))
}

@Test func authoritativeTerminologyIsAppliedBeforeModelEdits() {
    let context = AgentWritingContext(
        terminology: [
            TranscriptTerminology(
                preferred: "Keep MCP",
                variants: ["keep NCP"],
                authoritative: true
            )
        ]
    )

    #expect(ContextualTranscriptCorrector.correct(
        "Inspect the keep NCP integration but keep NCPish unchanged.",
        context: context
    ) == "Inspect the Keep MCP integration but keep NCPish unchanged.")
}

@Test func contextualCorrectionsRequireSupportingTechnicalContext() {
    #expect(ContextualTranscriptCorrector.correct(
        "Look at all the Gitter repos and test this using NATA."
    ) == "Look at all the GitHub repos and test this using Natter.")
    #expect(ContextualTranscriptCorrector.correct(
        "The old Gitter chat linked to the NATA organisation."
    ) == "The old Gitter chat linked to the NATA organisation.")
    #expect(ContextualTranscriptCorrector.correct(
        "In the Swift code, set scroll restoration: true, keep the main actor annotation, and inspect app delegate before changing launch behaviour."
    ) == "In the Swift code, set scrollRestoration: true, keep the @MainActor annotation, and inspect AppDelegate before changing launch behaviour.")
    #expect(ContextualTranscriptCorrector.correct(
        "Keep the main actor annotation, inspect app delegate, and confirm the dictation app still has the raw transcript."
    ) == "Keep the @MainActor annotation, inspect AppDelegate, and confirm the dictation app still has the raw transcript.")
}

@Test func contextualCorrectionsHandleObservedProductAndTechnicalASRErrors() {
    let input = """
    I use monologues for dictation. Tap write shift instead of Tab, then use command shift and v.
    Build a Tori app, do not use Tori, while spitboarding the text to speech workflow.
    Pick a MIT licensed local only model with Mac native Swift code and straight up dictation.
    Use markdown files. We ni definitely should fix it if that any option works.
    Write it into a into something. We would we need another pass. Do not make it Maggally overkill.
    Search console shows keeps alternatives. Apart from keep is fine. Add Href lang and cyto architecture to the repo readme.
    """

    #expect(ContextualTranscriptCorrector.correct(input) == """
    I use Monologue for dictation. Tap Right Shift instead of Tab, then use Command-Shift-V.
    Build a Tauri app, do not use Tauri, while spitballing the text-to-speech workflow.
    Pick a MIT-licensed local-only model with Mac-native Swift code and straight-up dictation.
    Use Markdown files. We definitely should fix it if any option works.
    Write it into something. We need another pass. Do not make it massively overkill.
    Search Console shows Keep alternatives. Apart from Keep; Keep is fine. Add hreflang and site architecture to the repo README.
    """)
}

@Test func sentenceBoundaryCapitalizerRepairsLowercaseStartsWithoutTouchingAbbreviations() {
    #expect(SentenceBoundaryCapitalizer.capitalize(
        "first sentence. second sentence uses e.g. a stable abbreviation. third sentence."
    ) == "First sentence. Second sentence uses e.g. a stable abbreviation. Third sentence.")
}

@Test func contextualCorrectionsRepairObservedRunOnBoundaries() {
    let input = """
    I use a local model But yeah this works. What models that would mean, do some research, look at the repos. If they are doing that I'm not sure. Make it lightning fast we need evidence. It is post-processing stuff just want to finish. Use something what I want is control while talking maybe tap the key. Test my stuff, so let's ship anyway. So, work through it. Put it there, maybe it doesn't belong.
    """

    #expect(ContextualTranscriptCorrector.correct(input) == """
    I use a local model. But yeah this works. What models that would mean. Do some research. Look at the repos. If they are doing that. I'm not sure. Make it lightning fast. We need evidence. It is post-processing stuff. Just want to finish. Use something. What I want is control while talking. Maybe tap the key. Test my stuff. So let's ship anyway. So work through it. Put it there. Maybe it doesn't belong.
    """)
}

@Test func contextualCorrectionsRepairHighConfidenceAgreement() {
    let input = """
    The medium result are low. The long result need another run. The validator have preserved it and it do not rewrite facts. The first benchmark result for segment 12 are incomplete. The validator for segment 12 have preserved it. The validator for segment 12 do not invent. The delivery checks for segment 12 is running. The terminal checks for segment 12 needs Ghostty. The constraints for segment 12 remains deliberate.
    """

    #expect(ContextualTranscriptCorrector.correct(input) == """
    The medium result is low. The long result needs another run. The validator has preserved it and it does not rewrite facts. The first benchmark result for segment 12 is incomplete. The validator for segment 12 has preserved it. The validator for segment 12 does not invent. The delivery checks for segment 12 are running. The terminal checks for segment 12 need Ghostty. The constraints for segment 12 remain deliberate.
    """)
}

@Test func transcriptEditPlanAppliesUniqueNonOverlappingChanges() throws {
    let input = "Open the Gitter repo in NATA and keep /tmp/build intact."
    let plan = TranscriptEditPlan(edits: [
        TranscriptEdit(source: "Gitter", replacement: "GitHub"),
        TranscriptEdit(source: "NATA", replacement: "Natter")
    ])

    #expect(try TranscriptEditApplier.apply(plan, to: input)
        == "Open the GitHub repo in Natter and keep /tmp/build intact.")
}

@Test func transcriptEditPlanAcceptsLongSentenceAnchorWithDifferentCase() throws {
    let input = "the delivery checks for segment 2 is running in ChatGPT Desktop and Claude Desktop."
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(
                source: "The delivery checks for segment 2 is running in ChatGPT Desktop and Claude Desktop.",
                replacement: "The delivery checks for segment 2 are running in ChatGPT Desktop and Claude Desktop."
            )
        ]),
        to: input
    )

    #expect(result == "The delivery checks for segment 2 are running in ChatGPT Desktop and Claude Desktop.")
}

@Test func transcriptEditPlanMeasuresLocalChangesInsideAFullSentence() throws {
    let input = "The result are still wrong, the validator have preserved the raw transcript, and the delivery checks is running while the constraints remains unchanged."
    let replacement = "The result is still wrong, the validator has preserved the raw transcript, and the delivery checks are running while the constraints remain unchanged."

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
    let input = sources.joined(separator: " ")
        + " " + String(repeating: "deliberate context ", count: 40)
    let plan = TranscriptEditPlan(edits: sources.enumerated().map { index, source in
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

@Test func selectiveAgentRewriteSegmentationIsLosslessAndTargetsRunOns() {
    let shortSentence = "This sentence is already fine. "
    let runOn = String(repeating: "unfinished thought ", count: 80)
    let transcript = shortSentence + runOn

    let segments = AgentRewriteSegmenter.segments(transcript)

    #expect(segments.map(\.text).joined() == transcript)
    #expect(segments.count == 2)
    #expect(segments[0].requiresRewrite == false)
    #expect(segments[1].requiresRewrite == true)
}

@Test func selectiveAgentRewriteProcessesShortDictationAsOneUnit() {
    let transcript = "The result are wrong and it need another pass."
    #expect(AgentRewriteSegmenter.segments(transcript) == [
        AgentRewriteSegment(text: transcript, requiresRewrite: true)
    ])
}

@Test func terminologyGuardRejectsDroppedOrMergedProtectedTerms() {
    let input = "Do not commit this apart from Keep. Keep is fine."

    #expect(TranscriptTerminologyGuard.preserves(
        ["Keep"],
        from: input,
        in: "Do not commit this apart from Keep. Keep is fine."
    ))
    #expect(!TranscriptTerminologyGuard.preserves(
        ["Keep"],
        from: input,
        in: "Do not commit this apart from keeping it fine."
    ))
}

@Test func wordingGuardAllowsOnlyPunctuationCapitalizationAndAgreement() {
    #expect(TranscriptWordingGuard.preservesWords(
        from: "the checks is running and the result need work",
        in: "The checks are running. And the result needs work."
    ))
    #expect(!TranscriptWordingGuard.preservesWords(
        from: "do not drop this constraint or this example",
        in: "Do not drop this constraint or example."
    ))
    #expect(!TranscriptWordingGuard.preservesWords(
        from: "if I say switch the profile",
        in: "If I switch the profile."
    ))
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
    #expect(AgentSelfEditPolicy.safePlan(from: TranscriptEditPlan(
        edits: [safe, invented, unrelated]
    )) == TranscriptEditPlan(edits: [safe]))
}

@Test func groundedAgentSelfEditAppliesObservedCorrection() {
    let transcript = "The queue app Q C UE delete that CUE is interesting."
    let plan = AgentSelfEditPolicy.safePlan(from: TranscriptEditPlan(edits: [
        TranscriptEdit(source: "Q C UE delete that CUE", replacement: "CUE")
    ]))

    #expect(TranscriptEditApplier.applyRecovering(plan, to: transcript).output ==
        "The queue app CUE is interesting.")
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
        to: "The benchmark result for segment 1 are incomplete. The benchmark result for segment 2 are incomplete."
    )

    #expect(result == "The benchmark result for segment 1 is incomplete. The benchmark result for segment 2 is incomplete.")
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
    let input = "The validator have preserved the raw transcript, but the checks do not yet prove the long case."
    let output = "The validator has preserved the raw transcript, but the checks do not yet prove the long case."
    let result = try TranscriptEditApplier.apply(
        TranscriptEditPlan(edits: [
            TranscriptEdit(source: "The validator have preserved", replacement: "The validator has preserved"),
            TranscriptEdit(source: input, replacement: output)
        ]),
        to: input
    )

    #expect(result == output)
}

@Test func transcriptEditPlanRecoveryKeepsValidEditsAndDropsOnlyInvalidOnes() {
    let result = TranscriptEditApplier.applyRecovering(
        TranscriptEditPlan(edits: [
            TranscriptEdit(source: "The result are wrong", replacement: "The result is wrong"),
            TranscriptEdit(source: "Text beyond the chunk boundary", replacement: "Invented text")
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
        to: "These constraints for segment 1 remains deliberate. These constraints for segment 2 remains deliberate."
    )

    #expect(result == "These constraints for segment 1 remain deliberate. These constraints for segment 2 remain deliberate.")
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
