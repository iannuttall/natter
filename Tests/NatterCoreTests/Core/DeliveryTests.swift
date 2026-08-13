import Foundation
import Testing

@testable import NatterCore

@Test func dictationTranscriptPipelineKeepsPreviewAndFinalRulesConsistent() {
    let corrections = [
        PersonalCorrection(heard: "port man", replacement: "Portman"),
        PersonalCorrection(heard: "clawed", replacement: "Claude", scope: .agent),
    ]

    #expect(
        DictationTranscriptPipeline.preview(
            rawTranscript: "Ask port man in clawed",
            mode: .agent,
            corrections: corrections
        ) == "Ask Portman in Claude")
    #expect(
        DictationTranscriptPipeline.preview(
            rawTranscript: "Ask port man in clawed",
            mode: .clean,
            corrections: corrections
        ) == "Ask Portman in clawed")

    let final = DictationTranscriptPipeline.prepareFinal(
        rawTranscript: "Ask port man in clawed send",
        mode: .agent,
        corrections: corrections,
        destinationApplicationName: "Terminal",
        voiceSubmitEnabled: true
    )
    #expect(
        final
            == PreparedDictationTranscript(
                transcript: "Ask Portman in Claude.",
                shouldSubmit: true
            ))
}

@Test func dictationTranscriptPipelinePreservesRawWordsAndAddsFinalPunctuation() {
    let result = DictationTranscriptPipeline.prepareFinal(
        rawTranscript: "open dot context",
        mode: .raw,
        corrections: [PersonalCorrection(heard: "dot context", replacement: ".context")],
        destinationApplicationName: nil,
        voiceSubmitEnabled: false
    )

    #expect(
        result
            == PreparedDictationTranscript(
                transcript: "open dot context.",
                shouldSubmit: false
            ))
}

@Test func dictationTranscriptPipelineRecognizesNatterInEveryMode() {
    for mode in [DictationMode.raw, .agent, .clean, .email, .article] {
        #expect(
            DictationTranscriptPipeline.preview(
                rawTranscript: "Use NATA for this, not NATAware",
                mode: mode,
                corrections: []
            ) == "Use Natter for this, not NATAware"
        )

        let result = DictationTranscriptPipeline.prepareFinal(
            rawTranscript: "Use NATA",
            mode: mode,
            corrections: [],
            destinationApplicationName: nil,
            voiceSubmitEnabled: false
        )
        #expect(result.transcript == "Use Natter.")
    }
}

@Test func appendOnlyTranscriptEmitsEveryNewDelta() {
    var emitter = StableTranscriptEmitter()

    #expect(emitter.observe("hello wor") == .text("hello wor"))
    #expect(emitter.observe("hello world") == .text("ld"))
    #expect(emitter.observe("hello world from") == .text(" from"))
    #expect(emitter.observe("hello world from Ian") == .text(" Ian"))
    #expect(emitter.finish("hello world from Ian.") == .text("."))
    #expect(emitter.delivered == "hello world from Ian.")
}

@Test func stableTranscriptRefusesToRewriteDeliveredText() {
    var emitter = StableTranscriptEmitter()

    #expect(emitter.observe("ship the build") == .text("ship the build"))
    #expect(emitter.observe("ship the build now") == .text(" now"))
    #expect(emitter.observe("skip the build now") == .conflict)
    #expect(emitter.finish("skip the build now") == .conflict)
}

@Test func deletionOnlyGuardAcceptsFalseStartRemoval() {
    let input = "I'm now comparing what am I comparing Natter to Monologue."
    let output = "I'm now comparing Natter to Monologue."
    #expect(TranscriptWordingGuard.allowsOnlyDeletions(from: input, in: output))
}

@Test func deletionOnlyGuardRejectsAdditionsReorderingAndOverDeletion() {
    let input = "ship the build to staging now"
    #expect(
        !TranscriptWordingGuard.allowsOnlyDeletions(
            from: input, in: "ship the new build to staging now"))
    #expect(
        !TranscriptWordingGuard.allowsOnlyDeletions(
            from: input, in: "ship to staging the build now"))
    #expect(
        !TranscriptWordingGuard.allowsOnlyDeletions(
            from: input, in: "ship now"))
    #expect(
        TranscriptWordingGuard.allowsOnlyDeletions(
            from: input, in: "ship the build to staging now"))
}

@Test func falseStartCuesMatchWholePhrasesOnly() {
    #expect(
        FalseStartCues.containsCue(
            "I'm now comparing what am I comparing Natter to Monologue"))
    #expect(FalseStartCues.containsCue("no wait, use the other branch"))
    #expect(FalseStartCues.containsCue("Scratch that, start with the tests."))
    #expect(!FalseStartCues.containsCue("compare Natter to Monologue for speed"))
    #expect(!FalseStartCues.containsCue("we should wait for the release"))
}

@Test func tolerantRemainderAcceptsPunctuationAndCaseDisagreements() {
    var emitter = StableTranscriptEmitter()
    _ = emitter.observe("okay so the parakeet model is")

    // The batch decode agrees on every word but adds caps and punctuation.
    #expect(
        emitter.tolerantRemainder(
            in: "Okay, so the Parakeet model is faster than before."
        ) == " faster than before.")
}

@Test func tolerantRemainderStillRejectsRealWordConflicts() {
    var emitter = StableTranscriptEmitter()
    _ = emitter.observe("ship the build")

    #expect(emitter.tolerantRemainder(in: "skip the build now") == nil)
}

@Test func tolerantRemainderPrefersExactPrefixAndHandlesEmptyDelivery() {
    var emitter = StableTranscriptEmitter()
    #expect(emitter.tolerantRemainder(in: "anything at all") == "anything at all")

    _ = emitter.observe("hello world")
    #expect(emitter.tolerantRemainder(in: "hello world from Ian") == " from Ian")
}

@Test func stableTranscriptReportsOnlyTextNotYetDelivered() {
    var emitter = StableTranscriptEmitter()

    #expect(emitter.observe("keep this prefix") == .text("keep this prefix"))
    #expect(emitter.remainingText(in: "keep this prefix and add this") == " and add this")
    #expect(emitter.remainingText(in: "replace this prefix") == nil)
}

@Test func rawPunctuationFinishesProseButNotTechnicalTokens() {
    #expect(
        FinalTranscriptFormatter.punctuateRawProse("this is a sentence")
            == "This is a sentence.")
    #expect(
        FinalTranscriptFormatter.punctuateRawProse(
            "this keeps the recognizer casing",
            capitalizesInitial: false
        ) == "this keeps the recognizer casing.")
    #expect(
        FinalTranscriptFormatter.punctuateRawProse("is this complete?")
            == "Is this complete?")
    #expect(
        FinalTranscriptFormatter.punctuateRawProse(
            "run git diff --check",
            capitalizesInitial: false
        )
            == "run git diff --check")
    #expect(
        FinalTranscriptFormatter.punctuateRawProse("save to ~/output.json")
            == "Save to ~/output.json")
    #expect(
        FinalTranscriptFormatter.punctuateRawProse("email ian@example.com")
            == "Email ian@example.com")
    #expect(
        FinalTranscriptFormatter.punctuateRawProse("ian.is is the site")
            == "ian.is is the site.")
}

@Test func textInsertionPlanKeepsStandardLineBreaksInOnePayload() {
    #expect(
        TextInsertionPlan.insertionText(
            for: "# Heading\n\nThe first paragraph.",
            destination: .standard
        ) == "# Heading\n\nThe first paragraph.")
    #expect(
        TextInsertionPlan.insertionText(
            for: "First line\r\nSecond line\rThird line",
            destination: .standard
        ) == "First line\nSecond line\nThird line")
}

@Test func textInsertionPlanFlattensTerminalLineBreaksWithoutJoiningWords() {
    #expect(
        TextInsertionPlan.insertionText(
            for: "First line\n\nSecond line",
            destination: .terminal
        ) == "First line Second line")
}

@Test func textInsertionPlanPreservesStreamingBoundarySpacesInTerminals() {
    #expect(
        TextInsertionPlan.insertionText(
            for: " left the room ",
            destination: .terminal
        ) == " left the room ")
    #expect(
        TextInsertionPlan.insertionText(
            for: "\nNext paragraph",
            destination: .terminal
        ) == " Next paragraph")
}

@Test func textInsertionPlanReturnsEmptyPayloadForEmptyText() {
    #expect(TextInsertionPlan.insertionText(for: "", destination: .standard).isEmpty)
    #expect(TextInsertionPlan.insertionText(for: "", destination: .terminal).isEmpty)
}

@Test func textInsertionPlanReplacesUTF16SelectionAndMovesCursor() throws {
    let replacement = try #require(
        TextInsertionPlan.replacingSelection(
            in: "Hi 👋 there",
            utf16Location: 3,
            utf16Length: 2,
            with: "Ian"
        ))

    #expect(replacement.text == "Hi Ian there")
    #expect(replacement.cursorUTF16Location == 6)
    #expect(
        TextInsertionPlan.replacingSelection(
            in: "short",
            utf16Location: 10,
            utf16Length: 0,
            with: "no"
        ) == nil)
}

@Test func voiceSubmitConsumesOnlyAFinalStandaloneCommand() {
    #expect(
        VoiceSubmitCommand.consume(from: "Send this message enter")
            == VoiceSubmitResult(
                transcript: "Send this message",
                shouldSubmit: true
            ))
    #expect(
        VoiceSubmitCommand.consume(from: "Please review this, SEND.")
            == VoiceSubmitResult(
                transcript: "Please review this",
                shouldSubmit: true
            ))
    #expect(
        VoiceSubmitCommand.consume(from: "Send this message tomorrow")
            == VoiceSubmitResult(
                transcript: "Send this message tomorrow",
                shouldSubmit: false
            ))
    #expect(
        VoiceSubmitCommand.consume(from: "sender")
            == VoiceSubmitResult(
                transcript: "sender",
                shouldSubmit: false
            ))
}

@Test func voiceSubmitDoesNotTreatACommandOnlyDictationAsContent() {
    #expect(
        VoiceSubmitCommand.consume(from: "send")
            == VoiceSubmitResult(
                transcript: "send",
                shouldSubmit: false
            ))
    #expect(
        VoiceSubmitCommand.consume(from: "Enter.")
            == VoiceSubmitResult(
                transcript: "Enter.",
                shouldSubmit: false
            ))
}

@Test func textInsertionChunksPreserveComposedCharacters() {
    #expect(
        TextInsertionPlan.chunks(
            for: "123456789012345🙂next",
            maximumCharacterCount: 16
        ) == ["123456789012345🙂", "next"])
    #expect(
        TextInsertionPlan.chunks(
            for: "👨‍👩‍👧‍👦 café",
            maximumCharacterCount: 1
        ).first == "👨‍👩‍👧‍👦")
}

@Test func editableTextPolicyRejectsFocusedWebContentAndLinks() {
    #expect(
        EditableTextTargetPolicy.accepts(
            role: "AXTextArea",
            selectedTextIsSettable: false
        ))
    #expect(
        EditableTextTargetPolicy.accepts(
            role: "AXGroup",
            selectedTextIsSettable: true
        ))
    #expect(
        !EditableTextTargetPolicy.accepts(
            role: "AXWebArea",
            selectedTextIsSettable: false
        ))
    #expect(
        !EditableTextTargetPolicy.accepts(
            role: "AXLink",
            selectedTextIsSettable: false
        ))
}

@Test func recoveryRecordRoundTrips() throws {
    let record = RecoveryRecord(
        createdAt: Date(timeIntervalSince1970: 123),
        transcript: "full transcript",
        deliveredPrefix: "full ",
        targetBundleIdentifier: "com.apple.Terminal",
        reason: "Focus changed"
    )

    let encoded = try JSONEncoder().encode(record)
    #expect(try JSONDecoder().decode(RecoveryRecord.self, from: encoded) == record)
    #expect(record.clipboardTranscript == "full transcript")
}

@Test func recoveryAlwaysCopiesTheCompleteTranscript() {
    let record = RecoveryRecord(
        transcript: "The first phrase and the remaining words.",
        deliveredPrefix: "The first phrase",
        targetBundleIdentifier: "com.example.editor",
        reason: "Focus changed"
    )
    #expect(record.clipboardTranscript == "The first phrase and the remaining words.")

    let conflict = RecoveryRecord(
        transcript: "A revised sentence.",
        deliveredPrefix: "The original",
        targetBundleIdentifier: "com.example.editor",
        reason: "Transcript changed"
    )
    #expect(conflict.clipboardTranscript == "A revised sentence.")
}

@Test func historyStatisticsAggregateWordsTimeAndSources() {
    let calendar = Calendar(identifier: .gregorian)
    let first = Date(timeIntervalSince1970: 1_000)
    let records = [
        DictationHistoryRecord(
            createdAt: first,
            durationSeconds: 30,
            mode: .raw,
            wordCount: 100,
            sourceBundleIdentifier: "com.example.editor",
            sourceApplicationName: "Editor",
            transcript: "stored locally",
            outcome: .delivered
        ),
        DictationHistoryRecord(
            createdAt: first.addingTimeInterval(60),
            durationSeconds: 30,
            mode: .agent,
            wordCount: 50,
            sourceBundleIdentifier: "com.example.terminal",
            sourceApplicationName: "Terminal",
            transcript: nil,
            outcome: .recovered
        ),
    ]
    let statistics = DictationStatistics(
        records: records,
        typingWordsPerMinute: 50,
        calendar: calendar
    )

    #expect(statistics.totalWords == 150)
    #expect(statistics.totalDurationSeconds == 60)
    #expect(statistics.averageWordsPerMinute == 150)
    #expect(statistics.estimatedTimeSavedSeconds == 120)
    #expect(statistics.activeDayCount == 1)
    #expect(statistics.topSources.first?.applicationName == "Editor")
}

@Test func historyWordCountUsesWhitespaceBoundaries() {
    #expect(DictationHistoryRecord.countWords(in: "Ship v2 to ian@example.com.") == 4)
}

@Test func historyActivityGroupsRecentRecordsInOneDailySeries() {
    let calendar = Calendar(identifier: .gregorian)
    let end = Date(timeIntervalSince1970: 7 * 86_400 + 12 * 3_600)
    let records = [
        DictationHistoryRecord(
            createdAt: end.addingTimeInterval(-3_600),
            durationSeconds: 1,
            mode: .raw,
            wordCount: 1,
            sourceBundleIdentifier: nil,
            sourceApplicationName: nil,
            transcript: nil,
            outcome: .delivered
        ),
        DictationHistoryRecord(
            createdAt: end.addingTimeInterval(-7_200),
            durationSeconds: 1,
            mode: .raw,
            wordCount: 1,
            sourceBundleIdentifier: nil,
            sourceApplicationName: nil,
            transcript: nil,
            outcome: .delivered
        ),
        DictationHistoryRecord(
            createdAt: end.addingTimeInterval(-2 * 86_400),
            durationSeconds: 1,
            mode: .raw,
            wordCount: 1,
            sourceBundleIdentifier: nil,
            sourceApplicationName: nil,
            transcript: nil,
            outcome: .delivered
        ),
        DictationHistoryRecord(
            createdAt: end.addingTimeInterval(-10 * 86_400),
            durationSeconds: 1,
            mode: .raw,
            wordCount: 1,
            sourceBundleIdentifier: nil,
            sourceApplicationName: nil,
            transcript: nil,
            outcome: .delivered
        ),
    ]

    let days = DictationActivity.recentDays(
        records: records,
        dayCount: 4,
        through: end,
        calendar: calendar
    )

    #expect(days.map(\.count) == [0, 1, 0, 2])
}
