import Foundation
import Testing

@testable import NatterCore

@Test func spokenLowercaseCommandConsumesThePrefixAndLowercasesTheNextWord() {
    #expect(
        SpokenLowercaseCommand.consume(
            from: "Lowercase The rest of this sentence"
        ) == SpokenLowercaseResult(
            transcript: "the rest of this sentence",
            consumedCommand: true
        ))
    #expect(
        SpokenLowercaseCommand.consume(
            from: "lower case, “This starts in a quote”"
        ).transcript == "“this starts in a quote”")
    #expect(
        SpokenLowercaseCommand.lowercaseInitial(
            in: "# Heading returned by a writing model"
        ) == "# heading returned by a writing model")
}

@Test func spokenLowercaseCommandWaitsForContentAndIgnoresOrdinaryWords() {
    #expect(
        SpokenLowercaseCommand.consume(from: "lowercase") == SpokenLowercaseResult(
            transcript: "",
            consumedCommand: true
        ))
    #expect(
        SpokenLowercaseCommand.consume(
            from: "lowercaseLetters should stay literal"
        ) == SpokenLowercaseResult(
            transcript: "lowercaseLetters should stay literal",
            consumedCommand: false
        ))
}

@Test func spokenTechnicalTokensBecomeLiteralWithoutAnLLM() {
    let transcript = """
        Send the results to Ian at example dot com. Keep the threshold at seventy percent and \
        save the report under tilde slash dev slash native slash natter slash results before \
        build four oh two.
        """

    #expect(
        SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
            Send the results to ian@example.com. Keep the threshold at 70% and \
            save the report under ~/dev/native/natter/results before build 402.
            """)
}

@Test func spokenEmailAddressesAreLowercasedWithoutLowercasingPaths() {
    let transcript = "Email Ian at Example dot COM and open ~/dev/MyProject/AppDelegate.swift."

    #expect(
        SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical)
            == "Email ian@example.com and open ~/dev/MyProject/AppDelegate.swift.")
}

@Test func proseFormattingDoesNotRewriteAmbiguousDomainLanguage() {
    let transcript = "Calculate the dot product, discuss slash fiction, and meet Ian at five."

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript) == transcript)
    let technical = SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical)
    #expect(technical.contains("discuss slash fiction"))
    #expect(!technical.contains("/fiction"))
}

@Test func technicalFormattingHandlesHiddenFilesPathsAndFlags() {
    let transcript = """
        Open dot context, inspect tilde slash Documents slash Research slash notes dot txt, and \
        run tool dash dash verbose.
        """

    #expect(
        SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
            Open .context, inspect ~/Documents/Research/notes.txt, and run tool --verbose.
            """)
}

@Test func agentModeFormatsGenericSpokenSymbolsWithoutGuessingIdentifierCase() {
    let transcript =
        "Set scroll restoration colon true, run tool double dash verbose, and open dot unfamiliar slash config."

    #expect(
        SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical)
            == "Set scroll restoration: true, run tool --verbose, and open .unfamiliar/config.")
}

@Test func spokenRootRoutesKeepTheirLeadingSpace() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Remind me about the slash connect route and the forward slash account endpoint.",
            context: .technical
        ) == "Remind me about the /connect route and the /account endpoint.")
}

@Test func agentModeShortensEtCeteraWithoutChangingProse() {
    let transcript = "Test Claude, ChatGPT, Codex, et cetera before release"
    #expect(
        SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical)
            == "Test Claude, ChatGPT, Codex, etc. before release")
    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .prose) == transcript)
}

@Test func explicitSpellingAndSingleLetterFlagsBecomeLiteral() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Run C O D E X exec then Claude dash P",
            context: .technical
        ) == "Run CODEX exec then Claude -p")
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "The code is I-A-N",
            context: .prose
        ) == "The code is IAN")
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Use lowercase C O D E X",
            context: .technical
        ) == "Use codex")
}

@Test func repeatedPronounIsRemainSeparateForDeterministicCleanup() {
    let normalized = SpokenTechnicalTextNormalizer.normalize(
        "Yeah I I I don't think that like like works",
        context: .technical
    )

    #expect(normalized == "Yeah I I I don't think that like like works")
    #expect(
        DeterministicTranscriptCleaner.clean(normalized) == "Yeah I don't think that like works")
}

@Test func agentModeAcceptsCommonDoubleHyphenPhrases() {
    for spoken in ["dash dash", "double dash", "hyphen hyphen", "two dashes", "two hyphens"] {
        #expect(
            SpokenTechnicalTextNormalizer.normalize(
                "Run git diff \(spoken) check",
                context: .technical
            ) == "Run git diff --check")
    }
}

@Test func standaloneDoubleDashDoesNotConsumeFollowingProse() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Use dash dash and make it double dash every time",
            context: .technical
        ) == "Use -- and make it -- every time")
}

@Test func agentModeFormatsExplicitVersionGrammarWithoutChoosingAStyle() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Ship V two, keep version two, and test version two point one point zero.",
            context: .technical
        ) == "Ship v2, keep version 2, and test version 2.1.0.")
}

@Test func proseAndHomophonesDoNotBecomeVersionIdentifiers() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Chapter V two is printed here and this version too needs work.",
            context: .prose
        ) == "Chapter V two is printed here and this version too needs work.")
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "This version too needs work.",
            context: .technical
        ) == "This version too needs work.")
}

@Test func explicitSpokenDecimalsBecomeDigits() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "The download is five point two four gigabytes."
        ) == "The download is 5.24 gigabytes.")
}

@Test func explicitSpokenPunctuationAndBreaksBecomeLiteral() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Write hello comma new line open paren ready close paren question mark"
        ) == "Write hello,\n(ready)?")
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Leave this dot dot dot unfinished"
        ) == "Leave this… unfinished")
}

@Test func mentionedPunctuationAndAmbiguousSymbolPhrasesStayAsWords() {
    let transcript = "Explain why a comma and the question mark matter. Review and sign the form."
    #expect(SpokenTechnicalTextNormalizer.normalize(transcript) == transcript)
}

@Test func explicitAtSignCanStillFormAnEmailAddress() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Email Ian at sign Example dot com"
        ) == "Email ian@example.com")
}

@Test func spokenClockTimesUseOnlyStrongTimeGrammar() {
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Meet at three thirty, deploy by nine oh five, and finish around twelve o'clock."
        ) == "Meet at 3:30, deploy by 9:05, and finish around 12:00.")
    #expect(
        SpokenTechnicalTextNormalizer.normalize(
            "Assign three thirty people to the launch."
        ) == "Assign three thirty people to the launch.")
}

@Test func shortProseNumberRunsDoNotBecomeCodes() {
    let transcript = "Compare one two items before choosing."
    #expect(SpokenTechnicalTextNormalizer.normalize(transcript) == transcript)
}

@Test func spokenDomainsHiddenFilesFlagsAndExtensionsBecomeLiteral() {
    let transcript = """
        Open en dot is but leave open dot island unchanged, edit dot context, save output dot \
        Json, and run git diff dash dash check.
        """

    #expect(
        SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
            Open en.is but leave open.island unchanged, edit .context, save output.json, and run git \
            diff --check.
            """)
}

@Test func incrementalTechnicalNormalizationNeverRewritesDeliveredText() {
    let partials = [
        "Send it to Ian",
        "Send it to Ian at",
        "Send it to Ian at example",
        "Send it to Ian at example dot",
        "Send it to Ian at example dot com",
        "Send it to Ian at example dot com when build four",
        "Send it to Ian at example dot com when build four oh",
        "Send it to Ian at example dot com when build four oh two",
        "Send it to Ian at example dot com when build four oh two reaches seventy percent",
        "Send it to Ian at example dot com when build four oh two reaches seventy percent and continue",
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for partial in partials {
        let formatted = SpokenTechnicalTextNormalizer.normalize(partial, context: .technical)
        guard case .prefix(let prefix) = stabilizer.observe(formatted) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }
    let final =
        SpokenTechnicalTextNormalizer.normalize(
            partials.last!,
            context: .technical
        ) + "."
    #expect(emitter.finish(final) != .conflict)
    #expect(
        emitter.delivered == "Send it to ian@example.com when build 402 reaches 70% and continue.")
}

@Test func technicalStabilizerDoesNotSplitSpokenSymbolsOrRevisedPaths() {
    let partials = [
        "Open dot",
        "Open dot context inspect",
        "Open dot context inspect tilde slash Documents",
        "Open dot context inspect tilde slash Documents slash Research slash notes",
        "Open dot context inspect tilde slash Documents slash Research slash notes dot txt and run",
        "Open dot context inspect tilde slash Documents slash Research slash notes dot txt and run tool dash dash verbose",
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for partial in partials {
        let formatted = SpokenTechnicalTextNormalizer.normalize(partial, context: .technical)
        guard case .prefix(let prefix) = stabilizer.observe(formatted) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }

    let final = SpokenTechnicalTextNormalizer.normalize(partials.last!, context: .technical)
    #expect(emitter.finish(final) != .conflict)
    #expect(
        emitter.delivered
            == "Open .context inspect ~/Documents/Research/notes.txt and run tool --verbose")
}

@Test func technicalStabilizerSurvivesAProvisionalCodeWordRevision() {
    let hypotheses = [
        "Open sources",
        "Open sources app",
        "Open Sources/NatterApp/AppDelegate.swift keep the main actor",
        "Open Sources/NatterApp/AppDelegate.swift keep the main actor annotation and continue",
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for hypothesis in hypotheses {
        guard case .prefix(let prefix) = stabilizer.observe(hypothesis) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }

    let final = hypotheses.last!
    #expect(emitter.finish(final) != .conflict)
    #expect(emitter.delivered == final)
}

@Test func proseStabilizerWaitsForACompleteEmailBeforeDelivery() {
    let hypotheses = [
        "Send the result to Ian",
        "Send the result to Ian at example",
        "Send the result to Ian at example dot com keep the threshold",
        "Send the result to Ian at example dot com keep the threshold at seventy percent and continue",
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for hypothesis in hypotheses {
        let formatted = SpokenTechnicalTextNormalizer.normalize(hypothesis, context: .prose)
        guard case .prefix(let prefix) = stabilizer.observe(formatted) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }

    let final = SpokenTechnicalTextNormalizer.normalize(hypotheses.last!, context: .prose)
    #expect(emitter.finish(final) != .conflict)
    #expect(
        emitter.delivered
            == "Send the result to ian@example.com keep the threshold at 70% and continue"
    )
}
