import Foundation
import Testing

@testable import NatterCore

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

    #expect(
        try String(
            contentsOf: destination.appendingPathComponent("Models"),
            encoding: .utf8
        ) == "model")
    #expect(
        try String(
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

    #expect(
        detector.observe(keyCode: 58, isDown: true, at: 10, sessionIsActive: false)
            == .passThrough)
    #expect(
        detector.observe(keyCode: 58, isDown: false, at: 10.1, sessionIsActive: false)
            == .passThrough)
    #expect(
        detector.observe(keyCode: 58, isDown: true, at: 10.2, sessionIsActive: true)
            == .passThrough)
    #expect(
        detector.observe(keyCode: 58, isDown: false, at: 10.3, sessionIsActive: true)
            == .passThrough)
    #expect(
        detector.observe(keyCode: 58, isDown: true, at: 10.6, sessionIsActive: true)
            == .cancel)
}

@Test func slowLeftOptionTapsDoNotCancel() {
    var detector = CancelModifierTapDetector(doubleTapInterval: 0.42)

    #expect(
        detector.observe(keyCode: 58, isDown: true, at: 10, sessionIsActive: true)
            == .passThrough)
    #expect(
        detector.observe(keyCode: 58, isDown: false, at: 10.1, sessionIsActive: true)
            == .passThrough)
    #expect(
        detector.observe(keyCode: 58, isDown: true, at: 10.5, sessionIsActive: true)
            == .passThrough)
}
