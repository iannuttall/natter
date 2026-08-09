import Foundation
import Testing

@testable import NatterCore

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
        markdownRules: WritingRules.defaultMarkdown(for: .clean),
        context: context
    )

    #expect(prompt.contains("Natter"))
    #expect(!prompt.contains("GitHub"))
    #expect(!prompt.contains("User rules:"))

    let cleanDefaults = WritingRules.defaultMarkdown(for: .clean)
    #expect(!WritingRules.cleanRulesContainCustomInstructions(cleanDefaults))
    #expect(
        WritingRules.cleanRulesContainCustomInstructions(
            cleanDefaults + "\n- Always keep my issue keys uppercase."
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

    #expect(
        ContextualTranscriptCorrector.correct(
            "Inspect the keep NCP integration but keep NCPish unchanged.",
            context: context
        ) == "Inspect the Keep MCP integration but keep NCPish unchanged.")
}

@Test func contextualCorrectionsRequireSupportingTechnicalContext() {
    #expect(
        ContextualTranscriptCorrector.correct(
            "Look at all the Gitter repos and test this using NATA."
        ) == "Look at all the GitHub repos and test this using Natter.")
    #expect(
        ContextualTranscriptCorrector.correct(
            "The old Gitter chat linked to the NATA organisation."
        ) == "The old Gitter chat linked to the NATA organisation.")
    #expect(
        ContextualTranscriptCorrector.correct(
            "In the Swift code, set scroll restoration: true, keep the main actor annotation, and inspect app delegate before changing launch behaviour."
        )
            == "In the Swift code, set scrollRestoration: true, keep the @MainActor annotation, and inspect AppDelegate before changing launch behaviour."
    )
    #expect(
        ContextualTranscriptCorrector.correct(
            "Keep the main actor annotation, inspect app delegate, and confirm the dictation app still has the raw transcript."
        )
            == "Keep the @MainActor annotation, inspect AppDelegate, and confirm the dictation app still has the raw transcript."
    )
}

@Test func agentTechnicalCorrectionsDoNotApplyCleanModeEdits() {
    let input = "Open the Gitter repo the result are ready but yeah keep going"

    #expect(
        ContextualTranscriptCorrector.correctTechnical(input)
            == "Open the GitHub repo the result are ready but yeah keep going")
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

    #expect(
        ContextualTranscriptCorrector.correct(input) == """
            I use Monologue for dictation. Tap Right Shift instead of Tab, then use Command-Shift-V.
            Build a Tauri app, do not use Tauri, while spitballing the text-to-speech workflow.
            Pick a MIT-licensed local-only model with Mac-native Swift code and straight-up dictation.
            Use Markdown files. We definitely should fix it if any option works.
            Write it into something. We need another pass. Do not make it massively overkill.
            Search Console shows Keep alternatives. Apart from Keep; Keep is fine. Add hreflang and site architecture to the repo README.
            """)
}

@Test func sentenceBoundaryCapitalizerRepairsLowercaseStartsWithoutTouchingAbbreviations() {
    #expect(
        SentenceBoundaryCapitalizer.capitalize(
            "first sentence. second sentence uses e.g. a stable abbreviation. third sentence."
        ) == "First sentence. Second sentence uses e.g. a stable abbreviation. Third sentence.")
}

@Test func contextualCorrectionsRepairObservedRunOnBoundaries() {
    let input = """
        I use a local model But yeah this works. What models that would mean, do some research, look at the repos. If they are doing that I'm not sure. Make it lightning fast we need evidence. It is post-processing stuff just want to finish. Use something what I want is control while talking maybe tap the key. Test my stuff, so let's ship anyway. So, work through it. Put it there, maybe it doesn't belong.
        """

    #expect(
        ContextualTranscriptCorrector.correct(input) == """
            I use a local model. But yeah this works. What models that would mean. Do some research. Look at the repos. If they are doing that. I'm not sure. Make it lightning fast. We need evidence. It is post-processing stuff. Just want to finish. Use something. What I want is control while talking. Maybe tap the key. Test my stuff. So let's ship anyway. So work through it. Put it there. Maybe it doesn't belong.
            """)
}

@Test func contextualCorrectionsRepairHighConfidenceAgreement() {
    let input = """
        The medium result are low. The long result need another run. The validator have preserved it and it do not rewrite facts. The first benchmark result for segment 12 are incomplete. The validator for segment 12 have preserved it. The validator for segment 12 do not invent. The delivery checks for segment 12 is running. The terminal checks for segment 12 needs Ghostty. The constraints for segment 12 remains deliberate.
        """

    #expect(
        ContextualTranscriptCorrector.correct(input) == """
            The medium result is low. The long result needs another run. The validator has preserved it and it does not rewrite facts. The first benchmark result for segment 12 is incomplete. The validator for segment 12 has preserved it. The validator for segment 12 does not invent. The delivery checks for segment 12 are running. The terminal checks for segment 12 need Ghostty. The constraints for segment 12 remain deliberate.
            """)
}
