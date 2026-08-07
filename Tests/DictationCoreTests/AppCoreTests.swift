import Foundation
import Testing
@testable import DictationCore

@Test func onboardingStopsAtTheFirstIncompleteRequirement() {
    var snapshot = OnboardingSnapshot(
        welcomed: false,
        speechModelInstalled: false,
        microphoneGranted: false,
        accessibilityGranted: false,
        inputMonitoringGranted: false,
        practiceCompleted: false,
        writingChoiceCompleted: false
    )
    #expect(snapshot.currentStep == .welcome)

    snapshot = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: false,
        microphoneGranted: true,
        accessibilityGranted: true,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: true
    )
    #expect(snapshot.currentStep == .speechModel)

    snapshot = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: true,
        microphoneGranted: true,
        accessibilityGranted: false,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: true
    )
    #expect(snapshot.currentStep == .permissions)
}

@Test func writingModelChoiceIsOptionalButExplicit() {
    let pending = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: true,
        microphoneGranted: true,
        accessibilityGranted: true,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: false
    )
    #expect(pending.currentStep == .writingModel)
    #expect(!pending.isReadyToComplete)

    let ready = OnboardingSnapshot(
        welcomed: true,
        speechModelInstalled: true,
        microphoneGranted: true,
        accessibilityGranted: true,
        inputMonitoringGranted: true,
        practiceCompleted: true,
        writingChoiceCompleted: true
    )
    #expect(ready.currentStep == .ready)
    #expect(ready.isReadyToComplete)
    #expect(ready.essentialSetupIsValid)
}

@Test func modesSeparateLiveAndGenerativeDelivery() {
    #expect(!DictationMode.raw.typesIncrementally)
    #expect(!DictationMode.agent.typesIncrementally)
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
    let cleanURL = try #require(URL(string: "natter://mode/clean"))
    let legacyURL = try #require(URL(string: "ian-dictation://mode/agent"))
    let unknownURL = try #require(URL(string: "natter://delete/everything"))
    let webURL = try #require(URL(string: "https://example.com/mode/clean"))

    #expect(AppCommand(url: cleanURL) == .setMode(.clean))
    #expect(AppCommand(url: legacyURL) == .setMode(.agent))
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

@Test func legacyDataMigrationMovesOnlyMissingTopLevelItems() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("old", isDirectory: true)
    let destination = root.appendingPathComponent("new", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    try Data("model".utf8).write(to: source.appendingPathComponent("Models"))
    try Data("old rules".utf8).write(to: source.appendingPathComponent("Rules"))
    try Data("new rules".utf8).write(to: destination.appendingPathComponent("Rules"))

    try LegacyApplicationDataMigration.moveMissingItems(
        from: source,
        to: destination
    )

    #expect(try String(
        contentsOf: destination.appendingPathComponent("Models"),
        encoding: .utf8
    ) == "model")
    #expect(try String(
        contentsOf: destination.appendingPathComponent("Rules"),
        encoding: .utf8
    ) == "new rules")
    #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("Rules").path))
    #expect(!FileManager.default.fileExists(atPath: source.appendingPathComponent("Models").path))
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

    #expect(detector.keyDown(at: 10, sessionIsActive: false) == .arm)
    #expect(detector.keyDown(at: 10.4, sessionIsActive: false) == .start)
    #expect(detector.keyDown(at: 11, sessionIsActive: true) == .stop)
}

@Test func firstModifierTapArmsPreRollWithoutStartingDictation() {
    var detector = ModifierTapDetector(doubleTapInterval: 0.42)

    #expect(detector.keyDown(at: 10, sessionIsActive: false) == .arm)
    #expect(detector.keyDown(at: 10.43, sessionIsActive: false) == .arm)
    #expect(detector.keyDown(at: 10.7, sessionIsActive: false) == .start)
}

@Test func adaptiveStopTimingUsesMeasuredCadenceWithinSafeBounds() {
    var estimator = AdaptiveStopTimingEstimator()
    #expect(estimator.gracePeriod == 0.05)

    estimator.observe(callbackAt: 1, bufferDuration: 0.021)
    estimator.observe(callbackAt: 1.022, bufferDuration: 0.021)
    #expect(abs(estimator.gracePeriod - 0.03) < 0.000_001)

    estimator.observe(callbackAt: 1.2, bufferDuration: 0.2)
    #expect(estimator.gracePeriod == 0.08)
}

@Test func preRollKeepsOnlyTheNewestBoundedAudio() {
    var buffer = TimedPreRollBuffer<String>(maximumDuration: 0.45)
    buffer.append("old", duration: 0.2)
    buffer.append("middle", duration: 0.2)
    buffer.append("new", duration: 0.2)

    #expect(buffer.drain() == ["middle", "new"])
    #expect(buffer.duration == 0)
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

    #expect(detector.keyDown(at: 10, sessionIsActive: false) == .arm)
    #expect(detector.keyDown(at: 10.5, sessionIsActive: false) == .arm)
    #expect(detector.keyDown(at: 10.8, sessionIsActive: false) == .start)
}

@Test func modifierPressDistinguishesTapAndHold() {
    var detector = ModifierHoldDetector(holdInterval: 0.6)

    detector.keyDown(at: 10)
    let shortPress = detector.keyUp(at: 10.4)
    detector.keyDown(at: 11)
    let longPress = detector.keyUp(at: 11.7)

    #expect(shortPress == .tap)
    #expect(longPress == .hold)
    #expect(detector.keyUp(at: 13) == nil)
}

@Test func doubleTapLeftOptionCancelsOnlyAnActiveSession() {
    var detector = CancelModifierTapDetector(doubleTapInterval: 0.42)

    #expect(detector.observe(keyCode: 58, isDown: true, at: 10, sessionIsActive: false)
        == .passThrough)
    #expect(detector.observe(keyCode: 58, isDown: false, at: 10.1, sessionIsActive: false)
        == .passThrough)
    #expect(detector.observe(keyCode: 58, isDown: true, at: 10.2, sessionIsActive: true)
        == .passThrough)
    #expect(detector.observe(keyCode: 58, isDown: false, at: 10.3, sessionIsActive: true)
        == .passThrough)
    #expect(detector.observe(keyCode: 58, isDown: true, at: 10.6, sessionIsActive: true)
        == .cancel)
}

@Test func slowLeftOptionTapsDoNotCancel() {
    var detector = CancelModifierTapDetector(doubleTapInterval: 0.42)

    #expect(detector.observe(keyCode: 58, isDown: true, at: 10, sessionIsActive: true)
        == .passThrough)
    #expect(detector.observe(keyCode: 58, isDown: false, at: 10.1, sessionIsActive: true)
        == .passThrough)
    #expect(detector.observe(keyCode: 58, isDown: true, at: 10.5, sessionIsActive: true)
        == .passThrough)
}

@Test func dictationModesCycleInDisplayedOrder() {
    #expect(DictationMode.raw.next == .agent)
    #expect(DictationMode.agent.next == .clean)
    #expect(DictationMode.clean.next == .email)
    #expect(DictationMode.email.next == .article)
    #expect(DictationMode.article.next == .raw)
}

@Test func appModeProfilesPreferExactAppThenGroupThenDefault() {
    let configuration = ApplicationModeConfiguration(
        groupModes: [.terminal: .agent, .mail: .email],
        applications: [
            ApplicationModeProfile(
                bundleIdentifier: "com.mitchellh.ghostty",
                displayName: "Ghostty",
                mode: .raw
            )
        ]
    )

    #expect(configuration.resolve(
        bundleIdentifier: "com.mitchellh.ghostty",
        defaultMode: .clean
    ) == ModeResolution(mode: .raw, source: .application("Ghostty")))
    #expect(configuration.resolve(
        bundleIdentifier: "com.apple.Terminal",
        defaultMode: .clean
    ) == ModeResolution(mode: .agent, source: .group(.terminal)))
    #expect(configuration.resolve(
        bundleIdentifier: "com.apple.mail",
        defaultMode: .raw
    ) == ModeResolution(mode: .email, source: .group(.mail)))
    #expect(configuration.resolve(
        bundleIdentifier: "com.apple.TextEdit",
        defaultMode: .clean
    ) == ModeResolution(mode: .clean, source: .defaultMode))
}

@Test func disabledAppModeProfilesAlwaysUseDefault() {
    let configuration = ApplicationModeConfiguration(
        enabled: false,
        groupModes: [.terminal: .agent]
    )

    #expect(configuration.resolve(
        bundleIdentifier: "com.apple.Terminal",
        defaultMode: .raw
    ) == ModeResolution(mode: .raw, source: .defaultMode))
}

@Test func speechModelRequiresEveryRuntimeFile() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    for relativePath in [
        "parakeet_unified_encoder_int8.mlmodelc",
        "parakeet_unified_encoder_streaming_70_7_1_int8.mlmodelc",
        "parakeet_unified_decoder.mlmodelc",
        "parakeet_unified_joint_decision_single_step.mlmodelc",
        "vocab.json"
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
        at: directory.appendingPathComponent("vocab.json")
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

@Test func deletionOnlyGuardAcceptsFalseStartRemoval() {
    let input = "I'm now comparing what am I comparing Natter to Monologue."
    let output = "I'm now comparing Natter to Monologue."
    #expect(TranscriptWordingGuard.allowsOnlyDeletions(from: input, in: output))
}

@Test func deletionOnlyGuardRejectsAdditionsReorderingAndOverDeletion() {
    let input = "ship the build to staging now"
    #expect(!TranscriptWordingGuard.allowsOnlyDeletions(
        from: input, in: "ship the new build to staging now"))
    #expect(!TranscriptWordingGuard.allowsOnlyDeletions(
        from: input, in: "ship to staging the build now"))
    #expect(!TranscriptWordingGuard.allowsOnlyDeletions(
        from: input, in: "ship now"))
    #expect(TranscriptWordingGuard.allowsOnlyDeletions(
        from: input, in: "ship the build to staging now"))
}

@Test func falseStartCuesMatchWholePhrasesOnly() {
    #expect(FalseStartCues.containsCue(
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
    #expect(emitter.tolerantRemainder(
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
    #expect(FinalTranscriptFormatter.punctuateRawProse("this is a sentence")
        == "This is a sentence.")
    #expect(FinalTranscriptFormatter.punctuateRawProse("is this complete?")
        == "Is this complete?")
    #expect(FinalTranscriptFormatter.punctuateRawProse(
        "run git diff --check",
        capitalizesInitial: false
    )
        == "run git diff --check")
    #expect(FinalTranscriptFormatter.punctuateRawProse("save to ~/output.json")
        == "Save to ~/output.json")
    #expect(FinalTranscriptFormatter.punctuateRawProse("email ian@example.com")
        == "Email ian@example.com")
    #expect(FinalTranscriptFormatter.punctuateRawProse("ian.is is the site")
        == "ian.is is the site.")
}

@Test func textInsertionPlanKeepsStandardLineBreaksInOnePayload() {
    #expect(TextInsertionPlan.insertionText(
        for: "# Heading\n\nThe first paragraph.",
        destination: .standard
    ) == "# Heading\n\nThe first paragraph.")
    #expect(TextInsertionPlan.insertionText(
        for: "First line\r\nSecond line\rThird line",
        destination: .standard
    ) == "First line\nSecond line\nThird line")
}

@Test func textInsertionPlanFlattensTerminalLineBreaksWithoutJoiningWords() {
    #expect(TextInsertionPlan.insertionText(
        for: "First line\n\nSecond line",
        destination: .terminal
    ) == "First line Second line")
}

@Test func textInsertionPlanPreservesStreamingBoundarySpacesInTerminals() {
    #expect(TextInsertionPlan.insertionText(
        for: " left the room ",
        destination: .terminal
    ) == " left the room ")
    #expect(TextInsertionPlan.insertionText(
        for: "\nNext paragraph",
        destination: .terminal
    ) == " Next paragraph")
}

@Test func textInsertionPlanReturnsEmptyPayloadForEmptyText() {
    #expect(TextInsertionPlan.insertionText(for: "", destination: .standard).isEmpty)
    #expect(TextInsertionPlan.insertionText(for: "", destination: .terminal).isEmpty)
}

@Test func textInsertionChunksPreserveComposedCharacters() {
    #expect(TextInsertionPlan.chunks(
        for: "123456789012345🙂next",
        maximumCharacterCount: 16
    ) == ["123456789012345🙂", "next"])
    #expect(TextInsertionPlan.chunks(
        for: "👨‍👩‍👧‍👦 café",
        maximumCharacterCount: 1
    ).first == "👨‍👩‍👧‍👦")
}

@Test func editableTextPolicyRejectsFocusedWebContentAndLinks() {
    #expect(EditableTextTargetPolicy.accepts(
        role: "AXTextArea",
        selectedTextIsSettable: false
    ))
    #expect(EditableTextTargetPolicy.accepts(
        role: "AXGroup",
        selectedTextIsSettable: true
    ))
    #expect(!EditableTextTargetPolicy.accepts(
        role: "AXWebArea",
        selectedTextIsSettable: false
    ))
    #expect(!EditableTextTargetPolicy.accepts(
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
        )
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

@Test func modelPackPathsAndSizesAreExplicit() {
    let paths = AppPaths(root: URL(fileURLWithPath: "/tmp/dictation-models"))

    #expect(SpeechModelLocation.installedDirectory(in: paths).path
        == "/tmp/dictation-models/Models/parakeet-unified-en-0.6b")
    #expect(AgentWritingModelLocation.installedDirectory(in: paths).path
        == "/tmp/dictation-models/Models/agent-writing/models/mlx-community/Qwen3.5-4B-MLX-4bit")
    #expect(WritingModelLocation.installedDirectory(in: paths).path
        == "/tmp/dictation-models/Models/writing/models/mlx-community/Qwen3.5-9B-MLX-4bit")
    #expect(ModelPack.agentWriting.downloadSizeBytes > ModelPack.speech.downloadSizeBytes)
    #expect(ModelPack.agentWriting.downloadSizeBytes < ModelPack.writing.downloadSizeBytes)
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

@Test func personalCorrectionsRespectAgentScope() {
    let markdown = """
    # Personal corrections
    - "port man" → "Portman"
    - [Agent] "clawed" → "Claude"
    """
    let corrections = PersonalCorrections.parse(markdown)

    #expect(corrections == [
        PersonalCorrection(heard: "port man", replacement: "Portman"),
        PersonalCorrection(heard: "clawed", replacement: "Claude", scope: .agent)
    ])
    #expect(PersonalCorrections.apply(
        corrections,
        to: "port man and the animal clawed the door"
    ) == "Portman and the animal clawed the door")
    #expect(PersonalCorrections.apply(
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
    #expect(PersonalCorrections.parse(PersonalCorrections.removing(agent, from: markdown)) == [
        everywhere
    ])
}

@Test func spokenCorrectionCommandRoutesWakeWordsAndRuleRequests() {
    #expect(SpokenCorrectionCommand.couldBeCommand("hey natt", appNames: ["Natter"]))
    #expect(SpokenCorrectionCommand.couldBeCommand("Hey Nata, add this", appNames: ["Nata"]))
    #expect(!SpokenCorrectionCommand.couldBeCommand(
        "here is the build",
        appNames: ["Natter"]
    ))
    #expect(SpokenCorrectionCommand.looksLikeRuleRequest(
        "Hey Nata, add that correction to my rules"
    ))
    #expect(!SpokenCorrectionCommand.looksLikeRuleRequest("Hey Nata, open settings"))
    #expect(SpokenCorrectionCommand.canonicalizingWakeWord(
        in: "Hey Nata, add that correction to my rules",
        canonicalName: "Natter",
        aliases: ["Nata", "Dictation"]
    ) == "Hey Natter, add that correction to my rules")
    #expect(SpokenCorrectionCommand.canonicalizingWakeWord(
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
    #expect(SpokenCorrectionCommand.validatedCorrection(
        from: extraction,
        command: "Remember that correction",
        previousTranscript: "I spoke to somebody yesterday."
    ) == nil)
    #expect(PersonalCorrections.apply([correction!], to: "Ask port man tomorrow") ==
        "Ask Portman tomorrow")
}

@Test func spokenCorrectionExtractionRejectsNoOpsAndNonCorrections() {
    #expect(SpokenCorrectionCommand.validatedCorrection(
        from: SpokenCorrectionExtraction(
            isCorrection: true,
            heard: "Portman",
            replacement: "Portman"
        ),
        command: "Remember that correction",
        previousTranscript: "Portman"
    ) == nil)
    #expect(SpokenCorrectionCommand.validatedCorrection(
        from: SpokenCorrectionExtraction(
            isCorrection: false,
            heard: "port man",
            replacement: "Portman"
        ),
        command: "Remember that correction",
        previousTranscript: "port man"
    ) == nil)
    #expect(SpokenCorrectionCommand.validatedCorrection(
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

@Test func spokenTechnicalTokensBecomeLiteralWithoutAnLLM() {
    let transcript = """
    Send the results to Ian at example dot com. Keep the threshold at seventy percent and \
    save the report under tilde slash dev slash native slash natter slash results before \
    build four oh two.
    """

    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) == """
    Send the results to ian@example.com. Keep the threshold at 70% and \
    save the report under ~/dev/native/natter/results before build 402.
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

@Test func agentModeShortensEtCeteraWithoutChangingProse() {
    let transcript = "Test Claude, ChatGPT, Codex, et cetera before release"
    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .technical) ==
        "Test Claude, ChatGPT, Codex, etc. before release")
    #expect(SpokenTechnicalTextNormalizer.normalize(transcript, context: .prose) == transcript)
}

@Test func explicitSpellingAndSingleLetterFlagsBecomeLiteral() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Run C O D E X exec then Claude dash P",
        context: .technical
    ) == "Run CODEX exec then Claude -p")
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "The code is I-A-N",
        context: .prose
    ) == "The code is IAN")
    #expect(SpokenTechnicalTextNormalizer.normalize(
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
    #expect(DeterministicTranscriptCleaner.clean(normalized) ==
        "Yeah I don't think that like works")
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

@Test func agentModeFormatsExplicitVersionGrammarWithoutChoosingAStyle() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Ship V two, keep version two, and test version two point one point zero.",
        context: .technical
    ) == "Ship v2, keep version 2, and test version 2.1.0.")
}

@Test func proseAndHomophonesDoNotBecomeVersionIdentifiers() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Chapter V two is printed here and this version too needs work.",
        context: .prose
    ) == "Chapter V two is printed here and this version too needs work.")
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "This version too needs work.",
        context: .technical
    ) == "This version too needs work.")
}

@Test func explicitSpokenDecimalsBecomeDigits() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "The download is five point two four gigabytes."
    ) == "The download is 5.24 gigabytes.")
}

@Test func explicitSpokenPunctuationAndBreaksBecomeLiteral() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Write hello comma new line open paren ready close paren question mark"
    ) == "Write hello,\n(ready)?")
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Leave this dot dot dot unfinished"
    ) == "Leave this… unfinished")
}

@Test func mentionedPunctuationAndAmbiguousSymbolPhrasesStayAsWords() {
    let transcript = "Explain why a comma and the question mark matter. Review and sign the form."
    #expect(SpokenTechnicalTextNormalizer.normalize(transcript) == transcript)
}

@Test func explicitAtSignCanStillFormAnEmailAddress() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Email Ian at sign Example dot com"
    ) == "Email ian@example.com")
}

@Test func spokenClockTimesUseOnlyStrongTimeGrammar() {
    #expect(SpokenTechnicalTextNormalizer.normalize(
        "Meet at three thirty, deploy by nine oh five, and finish around twelve o'clock."
    ) == "Meet at 3:30, deploy by 9:05, and finish around 12:00.")
    #expect(SpokenTechnicalTextNormalizer.normalize(
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

@Test func deterministicCleanerRemovesOnlyExplicitFillers() {
    let cleaned = DeterministicTranscriptCleaner.removeFillers(
        from: "Um, ship the hummingbird, erm, to /tmp/build at 70%."
    )
    #expect(cleaned == "ship the hummingbird, to /tmp/build at 70%.")
}

@Test func deterministicCleanerRemovesConnectorHesitationPunctuation() {
    #expect(DeterministicTranscriptCleaner.removeFillers(
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
    let transcript = "No no, this is very very deliberate, and I had had enough. Monday, Monday was repeated."
    #expect(DeterministicTranscriptCleaner.clean(transcript) == transcript)
    #expect(DeterministicTranscriptCleaner.clean("But, but this is duplicated.") ==
        "But this is duplicated.")
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
