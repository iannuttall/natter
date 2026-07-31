import Foundation
import Testing
@testable import DictationCore

@Test func modesSeparateLiveAndGenerativeDelivery() {
    #expect(DictationMode.raw.typesIncrementally)
    #expect(DictationMode.agent.typesIncrementally)
    #expect(!DictationMode.clean.typesIncrementally)
    #expect(DictationMode.email.isGenerative)
    #expect(DictationMode.article.isGenerative)
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

@Test func stableTranscriptOnlyEmitsConfirmedWords() {
    var emitter = StableTranscriptEmitter()

    #expect(emitter.observe("hello wor") == .none)
    #expect(emitter.observe("hello world") == .text("hello "))
    #expect(emitter.observe("hello world from") == .text("world"))
    #expect(emitter.observe("hello world from Ian") == .text(" from"))
    #expect(emitter.finish("hello world from Ian.") == .text(" Ian."))
    #expect(emitter.delivered == "hello world from Ian.")
}

@Test func stableTranscriptRefusesToRewriteDeliveredText() {
    var emitter = StableTranscriptEmitter()

    #expect(emitter.observe("ship the build") == .none)
    #expect(emitter.observe("ship the build now") == .text("ship the build"))
    #expect(emitter.observe("skip the build now") == .conflict)
    #expect(emitter.finish("skip the build now") == .conflict)
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

@Test func deterministicCleanerRemovesOnlyExplicitFillers() {
    let cleaned = DeterministicTranscriptCleaner.removeFillers(
        from: "Um, ship the hummingbird, erm, to /tmp/build at 70%."
    )
    #expect(cleaned == "ship the hummingbird, to /tmp/build at 70%.")
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
