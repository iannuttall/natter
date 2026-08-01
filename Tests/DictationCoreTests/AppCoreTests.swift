import Foundation
import Testing
@testable import DictationCore

@Test func modesSeparateLiveAndGenerativeDelivery() {
    #expect(DictationMode.raw.typesIncrementally)
    #expect(DictationMode.agent.typesIncrementally)
    #expect(!DictationMode.clean.typesIncrementally)
    #expect(!DictationMode.clean.isGenerative)
    #expect(DictationMode.email.isGenerative)
    #expect(DictationMode.article.isGenerative)
}

@Test func knownTerminalsUseTerminalDelivery() {
    for bundleIdentifier in [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty"
    ] {
        #expect(DestinationApplicationKind.classify(bundleIdentifier: bundleIdentifier) == .terminal)
    }

    #expect(DestinationApplicationKind.classify(bundleIdentifier: "com.apple.Safari") == .standard)
    #expect(DestinationApplicationKind.classify(bundleIdentifier: nil) == .standard)
}

@Test func corpusURLCanSelectModeWithoutAcceptingOtherCommands() throws {
    let cleanURL = try #require(URL(string: "ian-dictation://mode/clean"))
    let unknownURL = try #require(URL(string: "ian-dictation://delete/everything"))
    let webURL = try #require(URL(string: "https://example.com/mode/clean"))

    #expect(AppCommand(url: cleanURL) == .setMode(.clean))
    #expect(AppCommand(url: unknownURL) == nil)
    #expect(AppCommand(url: webURL) == nil)
}

@Test func appPathsStayUnderConfiguredRoot() {
    let root = URL(fileURLWithPath: "/tmp/dictation-tests", isDirectory: true)
    let paths = AppPaths(root: root)

    #expect(paths.models.path == "/tmp/dictation-tests/Models")
    #expect(paths.rules.path == "/tmp/dictation-tests/Rules")
    #expect(paths.recovery.path == "/tmp/dictation-tests/Recovery")
}

@Test func busyPhasesAreExplicit() {
    #expect(DictationPhase.listening.isBusy)
    #expect(DictationPhase.transforming.isBusy)
    #expect(!DictationPhase.idle.isBusy)
    #expect(!DictationPhase.recoverable("saved").isBusy)
}

@Test func aResolvedFailureCanStartANewSession() {
    #expect(DictationPhase.idle.canStartSession)
    #expect(DictationPhase.recoverable("copied").canStartSession)
    #expect(DictationPhase.failed("permission missing").canStartSession)
    #expect(!DictationPhase.preparing.canStartSession)
    #expect(!DictationPhase.listening.canStartSession)
    #expect(!DictationPhase.finalizing.canStartSession)
    #expect(!DictationPhase.transforming.canStartSession)
}

@Test func modifierDoubleTapStartsAndActiveTapStops() {
    var detector = ModifierTapDetector(doubleTapInterval: 0.42)

    #expect(detector.keyDown(at: 10, sessionIsActive: false) == nil)
    #expect(detector.keyDown(at: 10.4, sessionIsActive: false) == .start)
    #expect(detector.keyDown(at: 11, sessionIsActive: true) == .stop)
}

@Test func modifierEdgeTrackerCountsPressesNotReleases() {
    var tracker = ModifierKeyEdgeTracker()

    let firstPress = tracker.observe(isActive: true)
    let heldEvent = tracker.observe(isActive: true)
    let release = tracker.observe(isActive: false)
    let secondPress = tracker.observe(isActive: true)
    tracker.reset()
    let pressAfterReset = tracker.observe(isActive: true)

    #expect(firstPress)
    #expect(!heldEvent)
    #expect(!release)
    #expect(secondPress)
    #expect(pressAfterReset)
}

@Test func modifierTapOutsideWindowStartsANewPair() {
    var detector = ModifierTapDetector(doubleTapInterval: 0.42)

    #expect(detector.keyDown(at: 10, sessionIsActive: false) == nil)
    #expect(detector.keyDown(at: 10.5, sessionIsActive: false) == nil)
    #expect(detector.keyDown(at: 10.8, sessionIsActive: false) == .start)
}

@Test func speechModelRequiresEveryRuntimeFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for relativePath in [
        "encoder/encoder_int8.mlmodelc",
        "decoder.mlmodelc",
        "joint.mlmodelc",
        "tokenizer.json"
    ] {
        let file = directory.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        #expect(FileManager.default.createFile(atPath: file.path, contents: Data()))
    }

    #expect(SpeechModelLocation.isComplete(at: directory))
    try FileManager.default.removeItem(
        at: directory.appendingPathComponent("tokenizer.json")
    )
    #expect(!SpeechModelLocation.isComplete(at: directory))
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

@Test func rawPunctuationFinishesProseButNotTechnicalTokens() {
    #expect(FinalTranscriptFormatter.punctuateRawProse("this is a sentence")
        == "this is a sentence.")
    #expect(FinalTranscriptFormatter.punctuateRawProse("is this complete?")
        == "is this complete?")
    #expect(FinalTranscriptFormatter.punctuateRawProse("run git diff --check")
        == "run git diff --check")
    #expect(FinalTranscriptFormatter.punctuateRawProse("save to ~/output.json")
        == "save to ~/output.json")
    #expect(FinalTranscriptFormatter.punctuateRawProse("email ian@example.com")
        == "email ian@example.com")
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
}

@Test func modelPackPathsAndSizesAreExplicit() {
    let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/dictation-models"))

    #expect(SpeechModelLocation.installedDirectory(in: paths).path
        == "/tmp/dictation-models/Models/nemotron-streaming/560ms")
    #expect(WritingModelLocation.installedDirectory(in: paths).path
        == "/tmp/dictation-models/Models/writing/models/mlx-community/Qwen3.5-9B-MLX-4bit")
    #expect(ModelPack.writing.downloadSizeBytes > ModelPack.speech.downloadSizeBytes)
}

@Test func writingModelRequiresWeightsAndMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    for name in ["config.json", "tokenizer.json", "model.safetensors.index.json"] {
        #expect(FileManager.default.createFile(
            atPath: directory.appendingPathComponent(name).path,
            contents: Data()
        ))
    }
    #expect(!WritingModelLocation.isComplete(at: directory))
    #expect(FileManager.default.createFile(
        atPath: directory.appendingPathComponent("model-00001-of-00002.safetensors").path,
        contents: Data()
    ))
    #expect(WritingModelLocation.isComplete(at: directory))
}

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

    #expect(PersonalCorrections.parse(updated) == [
        PersonalCorrection(heard: "Port Man", replacement: "Portman")
    ])
}

@Test func addingAnExactIdentityCorrectionDoesNothing() {
    let markdown = PersonalCorrections.defaultMarkdown
    let updated = PersonalCorrections.appending(
        PersonalCorrection(heard: "Portman", replacement: "Portman"),
        to: markdown
    )

    #expect(updated == markdown)
}

@Test func spokenCorrectionCommandExtractsRuleAndSpellingHint() {
    let transcript = """
    Hey Dictation, you just transcribed it as en.is but what I actually said was ian.is \
    i-a-n can you add that to my rules so you remember for next time
    """
    let correction = SpokenCorrectionParser.parse(transcript, appNames: ["Dictation"])

    #expect(correction == PersonalCorrection(heard: "en.is", replacement: "ian.is"))
    #expect(SpokenCorrectionParser.couldBeCommand("hey dicta", appNames: ["Dictation"]))
    #expect(!SpokenCorrectionParser.couldBeCommand("here is the build", appNames: ["Dictation"]))
}

@Test func spokenCorrectionCommandCleansObservedPunctuationAndRepeatedSpelling() {
    let transcript = """
    Hey Dictation, you just transcribed it as Port Man, but what I actually said was \
    Portman Portman. Can you add that to my rules so you remember for next time.
    """
    let correction = SpokenCorrectionParser.parse(transcript, appNames: ["Dictation"])

    #expect(correction == PersonalCorrection(heard: "Port Man", replacement: "Portman"))
}

@Test func spokenTechnicalTokensBecomeLiteralWithoutAnLLM() {
    let transcript = """
    Send the results to Ian at example dot com. Keep the threshold at seventy percent and \
    save the report under tilde slash dev slash native slash dictation slash results before \
    build four oh two.
    """

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
    Send the results to ian@example.com. Keep the threshold at 70% and \
    save the report under ~/dev/native/dictation/results before build 402.
    """)
}

@Test func spokenEmailAddressesAreLowercasedWithoutLowercasingPaths() {
    let transcript = "Email Ian at Example dot COM and open ~/dev/MyProject/AppDelegate.swift."

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) ==
        "Email ian@example.com and open ~/dev/MyProject/AppDelegate.swift.")
}

@Test func proseFormattingDoesNotRewriteAmbiguousDomainLanguage() {
    let transcript = "Calculate the dot product, discuss slash fiction, and meet Ian at five."

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript) == transcript)
}

@Test func technicalFormattingHandlesHiddenFilesPathsAndFlags() {
    let transcript = """
    Open dot context, inspect tilde slash Documents slash Research slash notes dot txt, and \
    run tool dash dash verbose.
    """

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
    Open .context, inspect ~/Documents/Research/notes.txt, and run tool --verbose.
    """)
}

@Test func agentModeFormatsGenericSpokenSymbolsWithoutGuessingIdentifierCase() {
    let transcript = "Set scroll restoration colon true, run tool double dash verbose, and open dot unfamiliar slash config."

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) ==
        "Set scroll restoration: true, run tool --verbose, and open .unfamiliar/config.")
}

@Test func agentModeAcceptsCommonDoubleHyphenPhrases() {
    for spoken in ["dash dash", "double dash", "hyphen hyphen", "two dashes", "two hyphens"] {
        #expect(SpokenTechnicalTextNormalizer.normalize(
            "Run git diff \(spoken) check",
            context: .technical
        ) == "Run git diff --check")
    }
}

@Test func standaloneDoubleDashDoesNotConsumeFollowingProse() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Use dash dash and make it double dash every time",
        context: .technical
    ) == "Use -- and make it -- every time")
}

@Test func spokenDomainsHiddenFilesFlagsAndExtensionsBecomeLiteral() {
    let transcript = """
    Open en dot is but leave open dot island unchanged, edit dot context, save output dot \
    Json, and run git diff dash dash check.
    """

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
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
        "Send it to Ian at example dot com when build four oh two reaches seventy percent and continue"
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for partial in partials {
        let formatted = SpokenTechnicalTextNormalizer.normalize(partial, context: .technical)
        guard case let .prefix(prefix) = stabilizer.observe(formatted) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }
    let final = SpokenTechnicalTextNormalizer.normalize(
        partials.last!,
        context: .technical
    ) + "."
    #expect(emitter.finish(final) != .conflict)
    #expect(emitter.delivered == "Send it to ian@example.com when build 402 reaches 70% and continue.")
}

@Test func technicalStabilizerDoesNotSplitSpokenSymbolsOrRevisedPaths() {
    let partials = [
        "Open dot",
        "Open dot context inspect",
        "Open dot context inspect tilde slash Documents",
        "Open dot context inspect tilde slash Documents slash Research slash notes",
        "Open dot context inspect tilde slash Documents slash Research slash notes dot txt and run",
        "Open dot context inspect tilde slash Documents slash Research slash notes dot txt and run tool dash dash verbose"
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for partial in partials {
        let formatted = SpokenTechnicalTextNormalizer.normalize(partial, context: .technical)
        guard case let .prefix(prefix) = stabilizer.observe(formatted) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }

    let final = SpokenTechnicalTextNormalizer.normalize(partials.last!, context: .technical)
    #expect(emitter.finish(final) != .conflict)
    #expect(emitter.delivered == "Open .context inspect ~/Documents/Research/notes.txt and run tool --verbose")
}

@Test func technicalStabilizerSurvivesAProvisionalCodeWordRevision() {
    let hypotheses = [
        "Open sources",
        "Open sources app",
        "Open Sources/DictationApp/AppDelegate.swift keep the main actor",
        "Open Sources/DictationApp/AppDelegate.swift keep the main actor annotation and continue"
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for hypothesis in hypotheses {
        guard case let .prefix(prefix) = stabilizer.observe(hypothesis) else {
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
        "Send the result to Ian at example dot com keep the threshold at seventy percent and continue"
    ]
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
    var emitter = StableTranscriptEmitter()

    for hypothesis in hypotheses {
        let formatted = SpokenTechnicalTextNormalizer.normalize(hypothesis, context: .prose)
        guard case let .prefix(prefix) = stabilizer.observe(formatted) else {
            Issue.record("stable hypothesis unexpectedly conflicted")
            return
        }
        #expect(emitter.observe(prefix) != .conflict)
    }

    let final = SpokenTechnicalTextNormalizer.normalize(hypotheses.last!, context: .prose)
    #expect(emitter.finish(final) != .conflict)
    #expect(emitter.delivered ==
        "Send the result to ian@example.com keep the threshold at 70% and continue")
}

@Test func observedCorrectionCommandVariantIsConsumedSafely() {
    let transcript = """
    Hey dictation, you just transcribed as Portman for what I actually said was portman por \
    tna. Can you add that to my rules so you remember for next time.
    """

    #expect(SpokenCorrectionParser.parse(transcript, appNames: ["Dictation"]) ==
        PersonalCorrection(heard: "Portman", replacement: "Portman"))
}

@Test func deterministicCleanerRemovesOnlyExplicitFillers() {
    let cleaned = DeterministicTranscriptCleaner.removeFillers(
        from: "Um, ship the hummingbird, erm, to /tmp/build at 70%."
    )
    #expect(cleaned == "ship the hummingbird, to /tmp/build at 70%.")
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
