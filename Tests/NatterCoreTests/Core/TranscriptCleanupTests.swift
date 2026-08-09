import Foundation
import Testing

@testable import NatterCore

@Test func deterministicCleanerRemovesOnlyExplicitFillers() {
    let cleaned = DeterministicTranscriptCleaner.removeFillers(
        from: "Um, ship the hummingbird, erm, to /tmp/build at 70%."
    )
    #expect(cleaned == "ship the hummingbird, to /tmp/build at 70%.")
}

@Test func deterministicCleanerRemovesConnectorHesitationPunctuation() {
    #expect(
        DeterministicTranscriptCleaner.removeFillers(
            from: "Ship it because, um, we need it."
        ) == "Ship it because we need it.")
}

@Test func deterministicCleanerRemovesObviousRepeatedWordsAndPhrases() {
    let cleaned = DeterministicTranscriptCleaner.clean(
        "Um, I need to, I need to send the report today, erm, but but first check it."
    )
    #expect(cleaned == "I need to send the report today, but first check it.")
}

@Test func deterministicCleanerDoesNotDeduplicateAcrossSentenceBoundaries() {
    let cleaned = DeterministicTranscriptCleaner.clean(
        "It was ready. It was ready for the next test."
    )
    #expect(cleaned == "It was ready. It was ready for the next test.")
}

@Test func deterministicCleanerPreservesMeaningfulAndRhetoricalRepeats() {
    let transcript =
        "No no, this is very very deliberate, and I had had enough. Monday, Monday was repeated."
    #expect(DeterministicTranscriptCleaner.clean(transcript) == transcript)
    #expect(
        DeterministicTranscriptCleaner.clean("But, but this is duplicated.")
            == "But this is duplicated.")
}

@Test func factGuardProtectsNumbersPathsUrlsAndEmails() {
    let transcript = "Send 70% to ian@example.com from ~/dev/app via https://ian.is/test."
    let facts = TranscriptFactGuard.protectedFacts(in: transcript)

    #expect(facts.contains("70%"))
    #expect(facts.contains("ian@example.com"))
    #expect(facts.contains("~/dev/app"))
    #expect(facts.contains("https://ian.is/test"))
    #expect(TranscriptFactGuard.preservesFacts(from: transcript, in: transcript))
    #expect(!TranscriptFactGuard.preservesFacts(from: transcript, in: "Send it tomorrow."))
}
