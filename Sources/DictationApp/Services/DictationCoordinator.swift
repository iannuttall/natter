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
    private var lastHandledPartial = ""
    private var previousTranscript: String?
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
        overlay.onCycleMode = { [weak self] in self?.cycleMode() }
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
        store.audioBands = []

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

    func cycleMode() {
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
        NatterLog.app.notice(
            "session mode switched mode=\(nextMode.rawValue, privacy: .public)"
        )
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

    func warmAgentModelIfInstalled() {
        guard store.smartAgentEnabled else { return }
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let directory = AgentWritingModelLocation.resolve(in: paths) else { return }
        Task { await writingEngine.warmAgent(modelDirectory: directory) }
    }

    func warmWritingModelIfInstalled() {
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let directory = WritingModelLocation.resolve(in: paths) else { return }
        Task { await writingEngine.warmWriting(modelDirectory: directory) }
    }

    func testWritingForDebug(
        _ transcript: String,
        mode: DictationMode,
        iterations: Int = 1,
        delay: Duration = .zero
    ) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await Task.sleep(for: delay)
                let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
                let qualityDirectory = WritingModelLocation.resolve(in: paths)
                let agentDirectory = AgentWritingModelLocation.resolve(in: paths)
                if mode.isGenerative, qualityDirectory == nil {
                    throw DictationCoordinatorError.writingModelMissing
                }
                for iteration in 1...max(iterations, 1) {
                    let startedAt = ProcessInfo.processInfo.systemUptime
                    let output = try await writingEngine.transform(
                        transcript: transcript,
                        mode: mode,
                        markdownRules: rules.markdown(for: mode),
                        modelDirectory: qualityDirectory,
                        agentModelDirectory: agentDirectory,
                        agentContext: AgentWritingContext.production(
                            destinationApplicationName: "Debug",
                            corrections: rules.corrections
                        )
                    )
                    let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                    let result = "DICTATION_WRITING_RESULT run=\(iteration) "
                        + "elapsed_ms=\(String(format: "%.1f", milliseconds)): \(output)\n"
                    FileHandle.standardError.write(Data(result.utf8))
                }
                if ProcessInfo.processInfo.environment["DICTATION_EXIT_AFTER_WRITING"] == "1" {
                    NSApp.terminate(nil)
                }
            } catch {
                FileHandle.standardError.write(
                    Data("DICTATION_WRITING_ERROR: \(error.localizedDescription)\n".utf8)
                )
                if ProcessInfo.processInfo.environment["DICTATION_EXIT_AFTER_WRITING"] == "1" {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func testCorrectionForDebug(command: String, previousTranscript: String) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
                guard let modelDirectory = WritingModelLocation.resolve(in: paths)
                    ?? AgentWritingModelLocation.resolve(in: paths) else {
                    throw WritingEngineError.modelMissing
                }
                let correction = try await writingEngine.extractPersonalCorrection(
                    command: command,
                    previousTranscript: previousTranscript,
                    modelDirectory: modelDirectory
                )
                let result = correction.map { "\($0.heard) -> \($0.replacement)" } ?? "none"
                FileHandle.standardError.write(
                    Data("DICTATION_CORRECTION_RESULT: \(result)\n".utf8)
                )
            } catch {
                FileHandle.standardError.write(
                    Data("DICTATION_CORRECTION_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
            if ProcessInfo.processInfo.environment["DICTATION_EXIT_AFTER_CORRECTION"] == "1" {
                NSApp.terminate(nil)
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
                        + "\(target.elementFingerprint?.role ?? "app-fallback")\n"
                ).utf8))
                let startedAt = ProcessInfo.processInfo.systemUptime
                try await textInserter.insert(
                    text,
                    into: target,
                    paceTerminalInput: false
                )
                let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                FileHandle.standardError.write(
                    Data(
                        "NATTER_INSERT_RESULT: success "
                            .appending("elapsed_ms=\(String(format: "%.1f", milliseconds))\n")
                            .utf8
                    )
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
        previousTranscript = store.finalTranscript.isEmpty ? nil : store.finalTranscript
        store.resetSession()
        emitter.reset()
        deliveryIssue = nil
        liveTranscriptConflict = false
        sessionCorrections = rules.corrections
        commandCandidate = false
        lastHandledPartial = ""
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
                levelHandler: { [weak store] level, bands in
                    store?.audioLevel = level
                    if let bands { store?.audioBands = bands }
                },
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
        store.audioBands = []
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

                if await handleCorrectionCommand(rawTranscript) {
                    await hideOverlayAfterResult(delay: .milliseconds(1_500))
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
                    if !emitter.delivered.isEmpty,
                       let remainder = emitter.tolerantRemainder(in: correctedTranscript) {
                        let continuation = FinalTranscriptFormatter.punctuateRawProse(
                            DeterministicTranscriptCleaner.clean(remainder),
                            capitalizesInitial: false
                        )
                        transcript = joinedTranscript(
                            prefix: emitter.delivered,
                            continuation: continuation
                        )
                    } else {
                        transcript = FinalTranscriptFormatter.punctuateRawProse(
                            DeterministicTranscriptCleaner.clean(correctedTranscript),
                            capitalizesInitial: spokenFormattingContext == .prose
                        )
                    }
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
            let targetBundle = target.bundleIdentifier ?? "unknown"
            let targetRole = target.elementFingerprint?.role ?? "clipboard-fallback"
            NatterLog.delivery.notice(
                "target captured app=\(targetBundle, privacy: .public) element=\(targetRole, privacy: .public)"
            )
        } catch {
            focusTarget = nil
            deliveryIssue = error.localizedDescription
            NatterLog.delivery.error(
                "target capture failed error=\(error.localizedDescription, privacy: .public)"
            )
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
        // The ASR emits a new hypothesis roughly every 560 ms while the tap
        // delivers buffers ~47x/sec; skip the normalization pipeline for the
        // ~25 of 26 callbacks whose transcript hasn't changed.
        guard rawTranscript != lastHandledPartial else { return }
        lastHandledPartial = rawTranscript

        if commandCandidate || SpokenCorrectionCommand.couldBeCommand(
            rawTranscript,
            appNames: correctionAppNames
        ) {
            commandCandidate = true
            store.liveTranscript = visibleCorrectionCommand(rawTranscript)
            if SpokenCorrectionCommand.looksLikeRuleRequest(rawTranscript) {
                store.statusMessage = "Rule command detected · keep speaking"
            }
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
        if liveTranscriptConflict {
            deliveryIssue = "The final transcript changed after text had already been typed."
            return
        }

        guard deliveryIssue == nil else { return }

        switch emitter.finish(transcript) {
        case .none:
            break
        case let .text(text):
            await insert(text)
        case .conflict:
            deliveryIssue = "The final transcript changed after text had already been typed."
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
            NatterLog.delivery.error(
                "text insertion failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func recoverTranscript(
        _ transcript: String,
        reason: String,
        statusMessage: String? = nil
    ) {
        let record = RecoveryRecord(
            transcript: transcript,
            deliveredPrefix: emitter.delivered,
            targetBundleIdentifier: sourceBundleIdentifier,
            reason: reason
        )

        do {
            store.latestRecoveryURL = try recovery.saveAndCopy(record)
            recordHistory(transcript, outcome: .recovered)
            if let statusMessage {
                store.statusMessage = statusMessage
            } else if reason == FocusedTextInsertionError.accessibilityPermissionRequired
                .localizedDescription {
                store.statusMessage = "Allow Accessibility in Settings · transcript copied"
            } else {
                store.statusMessage = "Couldn’t finish typing · complete transcript copied"
            }
            store.phase = .recoverable(reason)
        } catch {
            fail(error)
        }
    }

    private func handleCorrectionCommand(_ rawTranscript: String) async -> Bool {
        guard commandCandidate,
              SpokenCorrectionCommand.looksLikeRuleRequest(rawTranscript) else {
            return false
        }
        let visibleCommand = visibleCorrectionCommand(rawTranscript)
        store.liveTranscript = visibleCommand

        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let modelDirectory = WritingModelLocation.resolve(in: paths)
            ?? AgentWritingModelLocation.resolve(in: paths) else {
            recoverTranscript(
                visibleCommand,
                reason: "Install a writing model to add corrections by voice.",
                statusMessage: "Couldn’t add rule · writing model required · command copied"
            )
            return true
        }

        store.statusMessage = "Natter is checking that rule locally…"
        do {
            guard let correction = try await writingEngine.extractPersonalCorrection(
                command: rawTranscript,
                previousTranscript: previousTranscript ?? "",
                modelDirectory: modelDirectory
            ) else {
                recoverTranscript(
                    visibleCommand,
                    reason: "Couldn’t verify a personal correction from the spoken command.",
                    statusMessage: "Couldn’t add rule · command copied"
                )
                return true
            }

            rules.add(PersonalCorrection(
                heard: correction.heard,
                replacement: correction.replacement,
                scope: .everywhere
            ))
            store.liveTranscript = "Added “\(correction.heard)” → “\(correction.replacement)”"
            store.finalTranscript = ""
            store.statusMessage = "Rule added everywhere"
            store.phase = .idle
            recordHistory(visibleCommand, outcome: .delivered)
        } catch {
            recoverTranscript(
                visibleCommand,
                reason: error.localizedDescription,
                statusMessage: "Couldn’t add rule · command copied"
            )
        }
        return true
    }

    private func visibleCorrectionCommand(_ rawTranscript: String) -> String {
        SpokenCorrectionCommand.canonicalizingWakeWord(
            in: rawTranscript,
            canonicalName: AppInfo.displayName,
            aliases: correctionAppNames
        )
    }

    private func deliverWritingMode(_ transcript: String) async {
        store.phase = .transforming
        store.statusMessage = "Applying \(store.selectedMode.label) rules locally…"

        let lockedPrefix = emitter.delivered
        let transformInput: String
        if lockedPrefix.isEmpty {
            transformInput = transcript
        } else if let remainder = emitter.tolerantRemainder(in: transcript) {
            transformInput = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            recoverTranscript(
                transcript,
                reason: "The final transcript changed after text had already been typed."
            )
            return
        }

        guard !transformInput.isEmpty else {
            store.liveTranscript = lockedPrefix
            store.finalTranscript = lockedPrefix
            finishDelivery(of: lockedPrefix)
            return
        }

        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        let modelDirectory = WritingModelLocation.resolve(in: paths)
        let agentModelDirectory = store.smartAgentEnabled
            ? AgentWritingModelLocation.resolve(in: paths)
            : nil
        if modelDirectory == nil, store.selectedMode != .agent {
            recoverTranscript(
                transcript,
                reason: DictationCoordinatorError.writingModelMissing.localizedDescription
            )
            return
        }

        do {
            var output = try await writingEngine.transform(
                transcript: transformInput,
                mode: store.selectedMode,
                markdownRules: rules.markdown(for: store.selectedMode),
                modelDirectory: modelDirectory,
                agentModelDirectory: agentModelDirectory,
                agentContext: AgentWritingContext.production(
                    destinationApplicationName: sourceApplicationName,
                    corrections: sessionCorrections
                )
            )
            if store.selectedMode == .agent {
                // The selective rewrite preserves wording and leaves untouched
                // segments verbatim, so a dictation that trails off mid-thought
                // often ends without terminal punctuation. Close the final
                // sentence deterministically, using the same technical-token
                // guard Raw mode uses so commands and paths stay untouched.
                output = FinalTranscriptFormatter.punctuateRawProse(
                    output,
                    capitalizesInitial: false
                )
            }
            performanceTrace?.mark(.transformFinished)
            let finalOutput = joinedTranscript(
                prefix: lockedPrefix,
                continuation: output
            )
            let insertion = String(finalOutput.dropFirst(lockedPrefix.count))
            store.liveTranscript = finalOutput
            store.finalTranscript = finalOutput
            if deliveryIssue == nil, !insertion.isEmpty { await insert(insertion) }
            finishDelivery(of: finalOutput)
        } catch {
            recoverTranscript(transcript, reason: error.localizedDescription)
        }
    }

    private func joinedTranscript(prefix: String, continuation: String) -> String {
        let continuation = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return continuation }
        guard !continuation.isEmpty else { return prefix }
        guard prefix.last?.isWhitespace != true else { return prefix + continuation }

        let closingPunctuation = CharacterSet(charactersIn: ".,!?;:)]}")
        if let first = continuation.unicodeScalars.first,
           closingPunctuation.contains(first) {
            return prefix + continuation
        }
        return prefix + " " + continuation
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

    private func hideOverlayAfterResult(delay: Duration = .milliseconds(450)) async {
        try? await Task.sleep(for: delay)
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
        store.selectedMode.typesIncrementally
            || (store.selectedMode == .agent && store.agentTypesLive)
    }

    private var shouldUseWritingModel: Bool {
        store.selectedMode.isGenerative
            || (store.selectedMode == .agent && store.smartAgentEnabled)
    }

    private var correctionAppNames: [String] {
        Array(Set([AppInfo.displayName, "Nata", "Dictation"]))
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
        store.audioBands = []
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
