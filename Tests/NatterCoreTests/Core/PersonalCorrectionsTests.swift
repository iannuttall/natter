import Foundation
import Testing

@testable import NatterCore

@Test func personalCorrectionsParseAndApplyAtPhraseBoundaries() {
    let markdown = """
        # Personal corrections
        - "en.is" → "ian.is"
        - "port man" => "Portman"
        """
    let rules = PersonalCorrections.parse(markdown)

    #expect(rules.count == 2)
    #expect(PersonalCorrections.apply(rules, to: "EN.IS and port man") == "ian.is and Portman")
    #expect(PersonalCorrections.apply(rules, to: "open.island") == "open.island")
}

@Test func addingCorrectionUpdatesExistingHeardPhrase() {
    let markdown = """
        # Personal corrections
        - "port man" → "Port Man"
        """
    let updated = PersonalCorrections.appending(
        PersonalCorrection(heard: "Port Man", replacement: "Portman"),
        to: markdown
    )

    #expect(
        PersonalCorrections.parse(updated) == [
            PersonalCorrection(heard: "Port Man", replacement: "Portman")
        ])
}

@Test func addingAnExactIdentityCorrectionStoresAProtectedTerm() {
    let markdown = PersonalCorrections.defaultMarkdown
    let updated = PersonalCorrections.appending(
        PersonalCorrection(heard: "Portman", replacement: "Portman"),
        to: markdown
    )

    #expect(
        PersonalCorrections.parse(updated) == [
            PersonalCorrection(heard: "Portman", replacement: "Portman")
        ])
}

@Test func personalCorrectionsJSONRoundTripsAliasesScopesAndTerms() throws {
    let corrections = [
        PersonalCorrection(heard: "envious whisper", replacement: "EnviousWispr"),
        PersonalCorrection(heard: "SwiftPM", replacement: "SwiftPM", scope: .agent),
    ]
    let data = try PersonalCorrectionsTransfer.exportData(corrections)
    #expect(try PersonalCorrectionsTransfer.importData(data) == corrections)
}

@Test func personalCorrectionsImportPlainTermsAndAliases() throws {
    let text = """
        Natter
        envious whisper -> EnviousWispr
        [Agent] swift package manager => SwiftPM
        """
    #expect(
        try PersonalCorrectionsTransfer.importData(Data(text.utf8)) == [
            PersonalCorrection(heard: "Natter", replacement: "Natter"),
            PersonalCorrection(heard: "envious whisper", replacement: "EnviousWispr"),
            PersonalCorrection(
                heard: "swift package manager",
                replacement: "SwiftPM",
                scope: .agent
            ),
        ])
}

@Test func personalCorrectionsImportIgnoresMarkdownInstructions() throws {
    let markdown = PersonalCorrections.appending(
        PersonalCorrection(heard: "gitter", replacement: "GitHub"),
        to: PersonalCorrections.defaultMarkdown
    )
    #expect(
        try PersonalCorrectionsTransfer.importData(Data(markdown.utf8)) == [
            PersonalCorrection(heard: "gitter", replacement: "GitHub")
        ])
}

@Test func personalCorrectionsRespectAgentScope() {
    let markdown = """
        # Personal corrections
        - "port man" → "Portman"
        - [Agent] "clawed" → "Claude"
        """
    let corrections = PersonalCorrections.parse(markdown)

    #expect(
        corrections == [
            PersonalCorrection(heard: "port man", replacement: "Portman"),
            PersonalCorrection(heard: "clawed", replacement: "Claude", scope: .agent),
        ])
    #expect(
        PersonalCorrections.apply(
            corrections,
            to: "port man and the animal clawed the door"
        ) == "Portman and the animal clawed the door")
    #expect(
        PersonalCorrections.apply(
            corrections,
            to: "port man opened clawed desktop",
            scope: .agent
        ) == "Portman opened Claude desktop")
}

@Test func identicalCorrectionsCanExistInDifferentScopes() {
    let everywhere = PersonalCorrection(heard: "clawed", replacement: "Claude")
    let agent = PersonalCorrection(heard: "clawed", replacement: "Claude", scope: .agent)
    let markdown = PersonalCorrections.appending(
        agent,
        to: PersonalCorrections.appending(everywhere, to: PersonalCorrections.defaultMarkdown)
    )

    #expect(PersonalCorrections.parse(markdown) == [everywhere, agent])
    #expect(
        PersonalCorrections.parse(PersonalCorrections.removing(agent, from: markdown)) == [
            everywhere
        ])
}

@Test func spokenCorrectionCommandRoutesWakeWordsAndRuleRequests() {
    #expect(SpokenCorrectionCommand.couldBeCommand("hey natt", appNames: ["Natter"]))
    #expect(SpokenCorrectionCommand.couldBeCommand("Hey Nata, add this", appNames: ["Nata"]))
    #expect(
        !SpokenCorrectionCommand.couldBeCommand(
            "here is the build",
            appNames: ["Natter"]
        ))
    #expect(
        SpokenCorrectionCommand.looksLikeRuleRequest(
            "Hey Nata, add that correction to my rules"
        ))
    #expect(
        SpokenCorrectionCommand.looksLikeRuleRequest(
            "Hey Natter, add Portman to my dictionary"
        ))
    #expect(
        SpokenCorrectionCommand.looksLikeRuleRequest(
            "Hey Natter, remember this custom word"
        ))
    #expect(!SpokenCorrectionCommand.looksLikeRuleRequest("Hey Nata, open settings"))
    #expect(
        !SpokenCorrectionCommand.looksLikeRuleRequest(
            "Hey Natter, write these words into the email"
        ))
    #expect(
        SpokenCorrectionCommand.canonicalizingWakeWord(
            in: "Hey Nata, add that correction to my rules",
            canonicalName: "Natter",
            aliases: ["Nata", "Dictation"]
        ) == "Hey Natter, add that correction to my rules")
    #expect(
        SpokenCorrectionCommand.canonicalizingWakeWord(
            in: "Hey Natter, add that correction to my rules",
            canonicalName: "Natter",
            aliases: ["Nata", "Dictation"]
        ) == "Hey Natter, add that correction to my rules")
}

@Test func spokenCorrectionExtractionRequiresEvidenceFromPreviousTranscript() {
    let extraction = SpokenCorrectionExtraction(
        isCorrection: true,
        heard: "port man",
        replacement: "Portman"
    )
    let correction = SpokenCorrectionCommand.validatedCorrection(
        from: extraction,
        command: "Remember that correction",
        previousTranscript: "I spoke to port man yesterday."
    )

    #expect(correction == PersonalCorrection(heard: "port man", replacement: "Portman"))
    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: extraction,
            command: "Remember that correction",
            previousTranscript: "I spoke to somebody yesterday."
        ) == nil)
    #expect(
        PersonalCorrections.apply([correction!], to: "Ask port man tomorrow")
            == "Ask Portman tomorrow")
}

@Test func spokenCorrectionExtractionRejectsNoOpsAndNonCorrections() {
    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: SpokenCorrectionExtraction(
                isCorrection: true,
                heard: "Portman",
                replacement: "Portman"
            ),
            command: "Remember that correction",
            previousTranscript: "Portman"
        ) == nil)
    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: SpokenCorrectionExtraction(
                isCorrection: false,
                heard: "port man",
                replacement: "Portman"
            ),
            command: "Remember that correction",
            previousTranscript: "port man"
        ) == nil)
    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: SpokenCorrectionExtraction(
                isCorrection: true,
                heard: "portman",
                replacement: "Portman"
            ),
            command: "Change portman to Portman",
            previousTranscript: "Ask portman tomorrow."
        ) == PersonalCorrection(heard: "portman", replacement: "Portman"))
}

@Test func spokenCorrectionExtractionSupportsExplicitCommandsWithoutHistory() {
    let correction = SpokenCorrectionCommand.validatedCorrection(
        from: SpokenCorrectionExtraction(
            isCorrection: true,
            heard: "en",
            replacement: "ian"
        ),
        command: "Hey Nata, add a rule to my profile to change en to en an",
        previousTranscript: ""
    )

    #expect(correction == PersonalCorrection(heard: "en", replacement: "ian"))
}

@Test func spokenCorrectionExtractionEnforcesTitleCaseOnSpelledReplacements() {
    let correction = SpokenCorrectionCommand.validatedCorrection(
        from: SpokenCorrectionExtraction(
            isCorrection: true,
            heard: "port man",
            replacement: "P-O-R-T-M-A-N"
        ),
        command: "Hey Natter, change it to P-O-R-T-M-A-N, title case, and add a rule",
        previousTranscript: "Ask port man tomorrow."
    )

    #expect(correction == PersonalCorrection(heard: "port man", replacement: "Portman"))
}

@Test func spokenCorrectionExtractionEnforcesExplicitLowerUpperAndSentenceCase() {
    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: SpokenCorrectionExtraction(
                isCorrection: true,
                heard: "code x",
                replacement: "C O D E X"
            ),
            command: "Change code x to C O D E X in lowercase and remember the rule",
            previousTranscript: "Open code x."
        ) == PersonalCorrection(heard: "code x", replacement: "codex"))

    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: SpokenCorrectionExtraction(
                isCorrection: true,
                heard: "code x",
                replacement: "codex"
            ),
            command: "Change code x to codex using all caps and add a rule",
            previousTranscript: "Open code x."
        ) == PersonalCorrection(heard: "code x", replacement: "CODEX"))

    #expect(
        SpokenCorrectionCommand.validatedCorrection(
            from: SpokenCorrectionExtraction(
                isCorrection: true,
                heard: "ghost tea helper",
                replacement: "GHOSTY HELPER"
            ),
            command: "Change ghost tea helper to Ghosty Helper in sentence case",
            previousTranscript: "Run ghost tea helper."
        ) == PersonalCorrection(heard: "ghost tea helper", replacement: "Ghosty helper"))
}

@Test func spokenCorrectionExtractionUsesTheLastExplicitCaseInstruction() {
    let correction = SpokenCorrectionCommand.validatedCorrection(
        from: SpokenCorrectionExtraction(
            isCorrection: true,
            heard: "port man",
            replacement: "PORTMAN"
        ),
        command: "Do not store it as uppercase; use title case for the rule",
        previousTranscript: "Ask port man tomorrow."
    )

    #expect(correction == PersonalCorrection(heard: "port man", replacement: "Portman"))
}

@Test func spokenCorrectionExtractionPreservesMixedCaseWithoutAnExplicitDirective() {
    let correction = SpokenCorrectionCommand.validatedCorrection(
        from: SpokenCorrectionExtraction(
            isCorrection: true,
            heard: "swift p m",
            replacement: "SwiftPM"
        ),
        command: "Change swift p m to SwiftPM and remember the rule",
        previousTranscript: "Build it with swift p m."
    )

    #expect(correction == PersonalCorrection(heard: "swift p m", replacement: "SwiftPM"))
}
