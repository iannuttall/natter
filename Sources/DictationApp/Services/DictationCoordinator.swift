import AppKit
import DictationCore
import Foundation

@MainActor
final class DictationCoordinator {
    private let store: DictationStore
    private let microphone = MicrophoneCapture()
    private let transcriber: SpeechTranscriber
    private let rules: RulesManager
    private let profiles: ApplicationProfileManager
    private let history: HistoryManager
    private let writingEngine = WritingEngine()
    private let textInserter = FocusedTextInserter()
    private let recovery = TranscriptRecovery()
    private let feedback = FeedbackSoundPlayer()
    private let overlay: OverlayPanelController
    private var armExpiryTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var focusTarget: FocusedTextTarget?
    private var sourceBundleIdentifier: String?
    private var sourceApplicationName: String?
    private var emitter = StableTranscriptEmitter()
    private var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 1)
    private var deliveryIssue: String?
    private var liveTranscriptConflict = false
    private var sessionCorrections: [PersonalCorrection] = []
    private var commandCandidate = false
    private var recordingStartedAt: Date?
    private var recordingStoppedAt: Date?
    private var historyWasRecorded = false
    private var performanceTrace: DictationPerformanceTrace?

    init(
        store: DictationStore,
        transcriber: SpeechTranscriber,
        rules: RulesManager,
        profiles: ApplicationProfileManager,
        history: HistoryManager
    ) {
        self.store = store
        self.transcriber = transcriber
        self.rules = rules
        self.profiles = profiles
        self.history = history
        overlay = OverlayPanelController(store: store)
        overlay.onCancel = { [weak self] in self?.cancel() }
    }

    func handle(_ action: ModifierHotKeyAction) {
        switch action {
        case .arm: arm()
        case .start: start()
        case .stop: stop()
        case .cycleMode: cycleMode()
        case .cancel: cancel()
        }
    }

    func cancel() {
        guard store.phase == .preparing || store.phase == .listening else { return }
        armExpiryTask?.cancel()
        armExpiryTask = nil
        recordingStoppedAt = Date()
        microphone.stopImmediately()
        feedback.play(.stopped)
        streamTask?.cancel()
        streamTask = nil
        sessionTask?.cancel()
        sessionTask = nil
        store.audioLevel = 0

        let draft = (store.liveTranscript.isEmpty
            ? store.rawTranscript
            : store.liveTranscript)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !draft.isEmpty {
            let record = RecoveryRecord(
                transcript: draft,
                deliveredPrefix: emitter.delivered,
                targetBundleIdentifier: sourceBundleIdentifier,
                reason: "Cancelled by user"
            )
            store.latestRecoveryURL = try? recovery.saveAndCopy(
                record,
                copyToClipboard: false
            )
            store.finalTranscript = draft
            recordHistory(draft, outcome: .cancelled)
            store.statusMessage = "Cancelled · draft saved locally"
        } else {
            store.statusMessage = "Cancelled"
        }
        store.phase = .idle
        sessionTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard store.phase == .idle else { return }
            overlay.hide()
            store.statusMessage = nil
        }
    }

    private func cycleMode() {
        if store.phase == .listening {
            cycleActiveMode()
            return
        }
        guard store.canStart else { return }
        sessionTask?.cancel()
        store.selectNextModeForSession()
        store.liveTranscript = ""
        store.statusMessage = "\(store.selectedMode.label) mode selected"
        overlay.show()
        sessionTask = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard store.phase == .idle else { return }
            overlay.hide()
            store.statusMessage = nil
        }
    }

    private func cycleActiveMode() {
        let nextMode = nextAvailableMode(after: store.selectedMode)
        store.selectDuringSession(nextMode)
        store.statusMessage = sessionTypesIncrementally
            ? "Switched to \(nextMode.label) · typing live"
            : "Switched to \(nextMode.label) · finishes when you stop"
    }

    private func nextAvailableMode(after mode: DictationMode) -> DictationMode {
        var candidate = mode.next
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        let writingModelIsAvailable = WritingModelLocation.resolve(in: paths) != nil
        while candidate.isGenerative && !writingModelIsAvailable {
            candidate = candidate.next
        }
        return candidate
    }

    func prepareForDebug() {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await prepareTranscriber()
                store.statusMessage = "Speech model ready"
                FileHandle.standardError.write(Data("DICTATION_SPEECH_MODEL_READY\n".utf8))
            } catch {
                fail(error)
                FileHandle.standardError.write(
                    Data("DICTATION_SPEECH_MODEL_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    func testWritingForDebug(_ transcript: String) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
                guard let directory = WritingModelLocation.resolve(in: paths) else {
                    throw DictationCoordinatorError.writingModelMissing
                }
                let output = try await writingEngine.transform(
                    transcript: transcript,
                    mode: .clean,
                    markdownRules: rules.markdown(for: .clean),
                    modelDirectory: directory
                )
                FileHandle.standardError.write(
                    Data("DICTATION_WRITING_RESULT: \(output)\n".utf8)
                )
            } catch {
                FileHandle.standardError.write(
                    Data("DICTATION_WRITING_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    func testInsertionForDebug(_ text: String, delay: Duration = .seconds(2)) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await Task.sleep(for: delay)
                let target = try textInserter.captureTarget()
                FileHandle.standardError.write(Data((
                    "NATTER_INSERT_TARGET: \(target.applicationName ?? "unknown") "
                        + "\(target.bundleIdentifier ?? "unknown") "
                        + "\(target.elementFingerprint.role ?? "unknown")\n"
                ).utf8))
                try await textInserter.insert(
                    text,
                    into: target,
                    paceTerminalInput: false
                )
                FileHandle.standardError.write(
                    Data("NATTER_INSERT_RESULT: success\n".utf8)
                )
            } catch {
                FileHandle.standardError.write(
                    Data("NATTER_INSERT_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    private func start() {
        guard store.canStart else { return }
        armExpiryTask?.cancel()
        armExpiryTask = nil
        performanceTrace = DictationPerformanceTrace()
        sessionTask?.cancel()
        sessionTask = Task { await beginSession() }
    }

    private func arm() {
        guard store.canStart else { return }
        armExpiryTask?.cancel()
        do {
            try microphone.arm()
            NatterLog.audio.debug("capture primed on first modifier tap")
        } catch {
            NatterLog.audio.error(
                "capture pre-roll unavailable error=\(error.localizedDescription, privacy: .public)"
            )
            return
        }
        armExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.microphone.disarmIfIdle()
        }
    }

    private func beginSession() async {
        store.resetSession()
        emitter.reset()
        deliveryIssue = nil
        liveTranscriptConflict = false
        sessionCorrections = rules.corrections
        commandCandidate = false
        recordingStartedAt = nil
        recordingStoppedAt = nil
        historyWasRecorded = false
        captureSourceApplication()
        captureFocusTarget()
        let resolution = profiles.resolution(
            bundleIdentifier: sourceBundleIdentifier,
            defaultMode: store.defaultMode
        )
        store.prepareSessionMode(resolution)
        store.activeApplicationName = sourceApplicationName
        stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
        store.phase = .preparing
        store.statusMessage = "Loading local speech model…"
        overlay.show()
        performanceTrace?.mark(.overlayVisible)

        do {
            try validateSelectedMode()
            try await prepareTranscriber()
            performanceTrace?.mark(.modelReady)
            guard !Task.isCancelled else { return }
            await transcriber.reset()

            let stream = try microphone.start(
                levelHandler: { [weak store] level in store?.audioLevel = level },
                firstBufferHandler: { [weak self] in
                    self?.performanceTrace?.mark(.firstAudioBuffer)
                },
                routeFailureHandler: { [weak self] error in self?.fail(error) }
            )
            performanceTrace?.mark(.captureStarted)
            store.phase = .listening
            recordingStartedAt = Date()
            store.statusMessage = deliveryIssue == nil
                ? nil
                : "Listening · transcript will be copied"
            feedback.play(.started)

            streamTask = Task { [weak self] in
                for await chunk in stream {
                    guard !Task.isCancelled else { break }
                    do {
                        let rawPartial = try await self?.transcriber.consume(chunk) ?? ""
                        guard !rawPartial.isEmpty else { continue }
                        self?.performanceTrace?.mark(.firstPartial)
                        self?.store.rawTranscript = rawPartial
                        await self?.handlePartial(rawPartial)
                    } catch {
                        self?.fail(error)
                        break
                    }
                }
            }
        } catch {
            fail(error)
        }
    }

    private func stop() {
        guard store.phase == .preparing || store.phase == .listening else { return }

        if store.phase == .preparing {
            armExpiryTask?.cancel()
            armExpiryTask = nil
            sessionTask?.cancel()
            sessionTask = nil
            microphone.stopImmediately()
            feedback.play(.stopped)
            store.resetSession()
            overlay.hide()
            return
        }

        recordingStoppedAt = Date()
        performanceTrace?.mark(.stopRequested)
        let drainingStreamTask = streamTask
        streamTask = nil
        store.audioLevel = 0
        store.phase = .finalizing
        store.statusMessage = "Finishing locally…"

        sessionTask = Task {
            await microphone.stopDrainingTail()
            performanceTrace?.mark(.captureStopped)
            feedback.play(.stopped)
            await drainingStreamTask?.value
            guard store.phase == .finalizing else { return }

            do {
                let rawTranscript = try await transcriber.finish()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                performanceTrace?.mark(.finalTranscript)
                store.rawTranscript = rawTranscript

                if handleCorrectionCommand(rawTranscript) {
                    await hideOverlayAfterResult()
                    return
                }

                let normalizedTranscript = SpokenTechnicalTextNormalizer.normalize(
                    rawTranscript,
                    context: spokenFormattingContext
                )
                let correctedTranscript = PersonalCorrections.apply(
                    sessionCorrections,
                    to: normalizedTranscript,
                    scope: correctionScope
                )
                let transcript: String
                switch store.selectedMode {
                case .raw:
                    transcript = FinalTranscriptFormatter.punctuateRawProse(
                        correctedTranscript,
                        capitalizesInitial: spokenFormattingContext == .prose
                    )
                case .clean:
                    transcript = FinalTranscriptFormatter.punctuateRawProse(
                        DeterministicTranscriptCleaner.clean(correctedTranscript),
                        capitalizesInitial: spokenFormattingContext == .prose
                    )
                case .agent, .email, .article:
                    transcript = correctedTranscript
                }
                store.liveTranscript = transcript
                store.finalTranscript = transcript

                guard !transcript.isEmpty else {
                    store.statusMessage = "No speech detected"
                    store.phase = .idle
                    await hideOverlayAfterResult()
                    return
                }

                if shouldUseWritingModel {
                    await deliverWritingMode(transcript)
                } else {
                    await deliverFinalTranscript(transcript)
                    finishDelivery(of: transcript)
                }

                await hideOverlayAfterResult()
            } catch {
                fail(error)
            }
        }
    }

    private func prepareTranscriber() async throws {
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let modelDirectory = SpeechModelLocation.resolve(in: paths) else {
            throw DictationCoordinatorError.speechModelMissing(
                SpeechModelLocation.installedDirectory(in: paths)
            )
        }
        try await transcriber.prepare(modelDirectory: modelDirectory)
    }

    private func captureFocusTarget() {
        do {
            let target = try textInserter.captureTarget()
            focusTarget = target
            sourceBundleIdentifier = target.bundleIdentifier ?? sourceBundleIdentifier
            sourceApplicationName = target.applicationName ?? sourceApplicationName
        } catch {
            focusTarget = nil
            deliveryIssue = error.localizedDescription
        }
    }

    private func captureSourceApplication() {
        let application = NSWorkspace.shared.frontmostApplication
        sourceBundleIdentifier = application?.bundleIdentifier
        sourceApplicationName = application?.localizedName
    }

    private func deliverStablePartial(_ transcript: String) async {
        guard sessionTypesIncrementally, deliveryIssue == nil else { return }

        switch emitter.observe(transcript) {
        case .none:
            break
        case let .text(text):
            await insert(text)
        case .conflict:
            liveTranscriptConflict = true
            deliveryIssue = "The live transcript changed after text had already been typed."
            store.statusMessage = "Still listening · field will be corrected on stop"
        }
    }

    private func handlePartial(_ rawTranscript: String) async {
        if commandCandidate || SpokenCorrectionParser.couldBeCommand(
            rawTranscript,
            appNames: correctionAppNames
        ) {
            commandCandidate = true
            store.liveTranscript = rawTranscript
            return
        }

        let visible = SpokenTechnicalTextNormalizer.normalize(
            rawTranscript,
            context: spokenFormattingContext
        )
        store.liveTranscript = PersonalCorrections.apply(
            sessionCorrections,
            to: visible,
            scope: correctionScope
        )

        switch stabilizer.observe(store.liveTranscript) {
        case let .prefix(prefix):
            await deliverStablePartial(prefix)
        case .conflict:
            liveTranscriptConflict = true
            deliveryIssue = "The live transcript changed after text had already been typed."
            store.statusMessage = "Still listening · field will be corrected on stop"
        }
    }

    private func deliverFinalTranscript(_ transcript: String) async {
        if liveTranscriptConflict, let focusTarget {
            await repairFinalTranscript(transcript, in: focusTarget)
            return
        }

        guard deliveryIssue == nil else { return }

        switch emitter.finish(transcript) {
        case .none:
            break
        case let .text(text):
            await insert(text)
        case .conflict:
            guard let focusTarget else {
                deliveryIssue = "The final transcript conflicted with text already typed."
                return
            }
            await repairFinalTranscript(transcript, in: focusTarget)
        }
    }

    private func repairFinalTranscript(
        _ transcript: String,
        in focusTarget: FocusedTextTarget
    ) async {
        do {
            store.statusMessage = "Correcting final text locally…"
            try await textInserter.replaceInsertedText(
                emitter.delivered,
                with: transcript,
                in: focusTarget,
                paceTerminalInput: store.terminalPacingEnabled
            )
            deliveryIssue = nil
            liveTranscriptConflict = false
        } catch {
            deliveryIssue = error.localizedDescription
            liveTranscriptConflict = false
        }
    }

    private func insert(_ text: String) async {
        guard let focusTarget else {
            deliveryIssue = "The original text control is no longer available."
            return
        }

        do {
            try await textInserter.insert(
                text,
                into: focusTarget,
                paceTerminalInput: store.terminalPacingEnabled
            )
        } catch {
            deliveryIssue = error.localizedDescription
            store.statusMessage = "Still listening · transcript will be copied"
        }
    }

    private func recoverTranscript(_ transcript: String, reason: String) {
        let record = RecoveryRecord(
            transcript: transcript,
            deliveredPrefix: emitter.delivered,
            targetBundleIdentifier: sourceBundleIdentifier,
            reason: reason
        )

        do {
            store.latestRecoveryURL = try recovery.saveAndCopy(record)
            recordHistory(transcript, outcome: .recovered)
            if reason == FocusedTextInsertionError.accessibilityPermissionRequired
                .localizedDescription {
                store.statusMessage = "Allow Accessibility in Settings · transcript copied"
            } else if record.clipboardTranscript != record.transcript {
                store.statusMessage = "Couldn’t finish typing · remaining text copied"
            } else {
                store.statusMessage = "Couldn’t type · transcript copied"
            }
            store.phase = .recoverable(reason)
        } catch {
            fail(error)
        }
    }

    private func handleCorrectionCommand(_ rawTranscript: String) -> Bool {
        guard commandCandidate,
              let correction = SpokenCorrectionParser.parse(
                  rawTranscript,
                  appNames: correctionAppNames
              ) else {
            return false
        }

        rules.add(PersonalCorrection(
            heard: correction.heard,
            replacement: correction.replacement,
            scope: correctionScope
        ))
        store.liveTranscript = "Remembered “\(correction.heard)” → “\(correction.replacement)”"
        store.finalTranscript = ""
        store.statusMessage = "Personal correction saved locally"
        store.phase = .idle
        return true
    }

    private func deliverWritingMode(_ transcript: String) async {
        store.phase = .transforming
        store.statusMessage = "Applying \(store.selectedMode.label) rules locally…"

        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let modelDirectory = WritingModelLocation.resolve(in: paths) else {
            if store.selectedMode == .agent {
                await deliverFinalTranscript(transcript)
                finishDelivery(of: transcript)
                return
            }
            recoverTranscript(
                transcript,
                reason: DictationCoordinatorError.writingModelMissing.localizedDescription
            )
            return
        }

        do {
            let output = try await writingEngine.transform(
                transcript: transcript,
                mode: store.selectedMode,
                markdownRules: rules.markdown(for: store.selectedMode),
                modelDirectory: modelDirectory
            )
            performanceTrace?.mark(.transformFinished)
            store.liveTranscript = output
            store.finalTranscript = output
            if !emitter.delivered.isEmpty, let focusTarget {
                do {
                    try await textInserter.replaceInsertedText(
                        emitter.delivered,
                        with: output,
                        in: focusTarget,
                        paceTerminalInput: store.terminalPacingEnabled
                    )
                    deliveryIssue = nil
                } catch {
                    deliveryIssue = error.localizedDescription
                }
            } else {
                await insert(output)
            }
            finishDelivery(of: output)
        } catch {
            recoverTranscript(transcript, reason: error.localizedDescription)
        }
    }

    private func finishDelivery(of transcript: String) {
        performanceTrace?.mark(.deliveryFinished)
        if let deliveryIssue {
            recoverTranscript(transcript, reason: deliveryIssue)
        } else {
            recordHistory(transcript, outcome: .delivered)
            store.statusMessage = nil
            store.phase = .idle
        }
    }

    private func recordHistory(
        _ transcript: String,
        outcome: DictationOutcome
    ) {
        guard !historyWasRecorded else { return }
        let end = recordingStoppedAt ?? Date()
        let duration = recordingStartedAt.map { end.timeIntervalSince($0) } ?? 0
        history.record(
            transcript: transcript,
            rawTranscript: store.rawTranscript,
            durationSeconds: duration,
            mode: store.selectedMode,
            sourceBundleIdentifier: sourceBundleIdentifier,
            sourceApplicationName: sourceApplicationName,
            outcome: outcome
        )
        historyWasRecorded = true
    }

    private func hideOverlayAfterResult() async {
        try? await Task.sleep(for: .milliseconds(450))
        if store.phase == .idle || store.isRecoverable { overlay.hide() }
        if store.phase == .idle {
            store.restoreIdleMode(profiles.resolution(
                bundleIdentifier: sourceBundleIdentifier,
                defaultMode: store.defaultMode
            ))
        }
    }

    private func validateSelectedMode() throws {
        guard store.selectedMode.isGenerative else { return }
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard WritingModelLocation.resolve(in: paths) != nil else {
            throw DictationCoordinatorError.writingModelMissing
        }
    }

    private var sessionTypesIncrementally: Bool {
        store.selectedMode == .raw
            || (store.selectedMode == .agent && store.agentTypesLive)
    }

    private var shouldUseWritingModel: Bool {
        store.selectedMode.isGenerative
            || (store.selectedMode == .agent && store.smartAgentEnabled)
    }

    private var correctionAppNames: [String] {
        Array(Set([AppInfo.displayName, "Dictation"]))
    }

    private var spokenFormattingContext: SpokenFormattingContext {
        if store.selectedMode == .agent
            || DestinationApplicationKind.classify(
                bundleIdentifier: sourceBundleIdentifier
            ) == .terminal {
            return .technical
        }
        return .prose
    }

    private var correctionScope: PersonalCorrectionScope {
        store.selectedMode == .agent ? .agent : .everywhere
    }

    private func fail(_ error: Error) {
        armExpiryTask?.cancel()
        armExpiryTask = nil
        microphone.stopImmediately()
        streamTask?.cancel()
        streamTask = nil
        store.audioLevel = 0
        store.statusMessage = error.localizedDescription
        store.phase = .failed(error.localizedDescription)
        overlay.show()
    }
}

enum DictationCoordinatorError: LocalizedError {
    case speechModelMissing(URL)
    case writingModelMissing

    var errorDescription: String? {
        switch self {
        case let .speechModelMissing(directory):
            "Install the speech model in Settings. Expected it at \(directory.path)."
        case .writingModelMissing:
            "Install the optional writing model in Settings before using this mode."
        }
    }
}
