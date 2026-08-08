import AppKit
import NatterCore
import Foundation

@MainActor
final class DictationCoordinator {
    let store: DictationStore
    private let microphone = MicrophoneCapture()
    let transcriber: SpeechTranscriber
    let rules: RulesManager
    let modes: ModeManager
    private let profiles: ApplicationProfileManager
    private let history: HistoryManager
    let writingEngine: WritingEngine
    private let correctionService: SpokenCorrectionService
    let textInserter = FocusedTextInserter()
    private let recovery = TranscriptRecovery()
    private let feedback = FeedbackSoundPlayer()
    private let overlay: OverlayPanelController
    private var armExpiryTask: Task<Void, Never>?
    private var streamTask: Task<Void, Never>?
    var sessionTask: Task<Void, Never>?
    private var session = DictationSessionState()

    init(
        store: DictationStore,
        transcriber: SpeechTranscriber,
        rules: RulesManager,
        modes: ModeManager,
        profiles: ApplicationProfileManager,
        history: HistoryManager,
        writingEngine: WritingEngine = WritingEngine()
    ) {
        self.store = store
        self.transcriber = transcriber
        self.rules = rules
        self.modes = modes
        self.profiles = profiles
        self.history = history
        self.writingEngine = writingEngine
        correctionService = SpokenCorrectionService(
            writingEngine: writingEngine,
            rules: rules
        )
        overlay = OverlayPanelController(store: store, modes: modes)
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
        session.recordingStoppedAt = Date()
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
                deliveredPrefix: session.emitter.delivered,
                targetBundleIdentifier: session.sourceBundleIdentifier,
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
        store.select(nextAvailableMode(after: store.selectedMode))
        store.liveTranscript = ""
        store.statusMessage = "\(modes.name(for: store.selectedMode)) mode selected"
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
        let nextName = modes.name(for: nextMode)
        store.statusMessage = sessionTypesIncrementally
            ? "Switched to \(nextName) · typing live"
            : "Switched to \(nextName) · finishes when you stop"
    }

    private func nextAvailableMode(after mode: DictationMode) -> DictationMode {
        let available = modes.enabledModes
        guard !available.isEmpty else { return .raw }
        let currentIndex = available.firstIndex { $0.id == mode } ?? -1
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        let writingModelIsAvailable = WritingModelLocation.resolve(in: paths) != nil
        for offset in 1...available.count {
            let index = (currentIndex + offset + available.count) % available.count
            let candidate = available[index]
            if candidate.processing != .rewrite || writingModelIsAvailable {
                return candidate.id
            }
        }
        return .raw
    }


    private func start() {
        guard store.canStart else { return }
        armExpiryTask?.cancel()
        armExpiryTask = nil
        session.performanceTrace = DictationPerformanceTrace()
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
        let previousTranscript = store.finalTranscript.isEmpty ? nil : store.finalTranscript
        store.resetSession()
        session.reset(
            previousTranscript: previousTranscript,
            corrections: rules.corrections
        )
        captureSourceApplication()
        captureFocusTarget()
        let resolution = profiles.resolution(
            bundleIdentifier: session.sourceBundleIdentifier,
            defaultMode: store.defaultMode
        )
        store.prepareSessionMode(enabledResolution(resolution))
        store.activeApplicationName = session.sourceApplicationName
        store.phase = .preparing
        store.statusMessage = "Loading local speech model…"
        overlay.show()
        session.performanceTrace?.mark(.overlayVisible)

        do {
            try validateSelectedMode()
            try await prepareTranscriber()
            session.performanceTrace?.mark(.modelReady)
            guard !Task.isCancelled else { return }
            await transcriber.reset()

            let stream = try microphone.start(
                levelHandler: { [weak store] level, bands in
                    store?.audioLevel = level
                    if let bands { store?.audioBands = bands }
                },
                firstBufferHandler: { [weak self] in
                    self?.session.performanceTrace?.mark(.firstAudioBuffer)
                },
                routeFailureHandler: { [weak self] error in self?.fail(error) }
            )
            session.performanceTrace?.mark(.captureStarted)
            store.phase = .listening
            session.recordingStartedAt = Date()
            store.statusMessage = session.deliveryIssue == nil
                ? nil
                : "Listening · transcript will be copied"
            feedback.play(.started)

            streamTask = Task { [weak self] in
                for await chunk in stream {
                    guard !Task.isCancelled else { break }
                    do {
                        let rawPartial = try await self?.transcriber.consume(chunk) ?? ""
                        guard !rawPartial.isEmpty else { continue }
                        self?.session.performanceTrace?.mark(.firstPartial)
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

        session.recordingStoppedAt = Date()
        session.performanceTrace?.mark(.stopRequested)
        let drainingStreamTask = streamTask
        streamTask = nil
        store.audioLevel = 0
        store.audioBands = []
        store.phase = .finalizing
        store.statusMessage = "Finishing locally…"

        sessionTask = Task {
            await microphone.stopDrainingTail()
            session.performanceTrace?.mark(.captureStopped)
            feedback.play(.stopped)
            await drainingStreamTask?.value
            guard store.phase == .finalizing else { return }

            do {
                let rawTranscript = try await transcriber.finish()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                session.performanceTrace?.mark(.finalTranscript)
                store.rawTranscript = rawTranscript

                if await handleCorrectionCommand(rawTranscript) {
                    await hideOverlayAfterResult(delay: .milliseconds(1_500))
                    return
                }

        let lowercaseResult = spokenLowercaseResult(for: rawTranscript)
        session.forcesLowercaseInitial = lowercaseResult.consumedCommand
        let preparedTranscript = DictationTranscriptPipeline.prepareFinal(
            rawTranscript: lowercaseResult.transcript,
            mode: store.selectedMode,
            corrections: session.corrections,
            destinationApplicationName: session.sourceApplicationName,
                    voiceSubmitEnabled: store.voiceSubmitEnabled
        )
        session.pendingVoiceSubmit = preparedTranscript.shouldSubmit
        let transcript = preparedTranscript.transcript
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
                    store.statusMessage = "Typing…"
                    await deliverFinalTranscript(transcript)
                    await completeDelivery(of: transcript)
                }

                await hideOverlayAfterResult()
            } catch {
                fail(error)
            }
        }
    }

    func prepareTranscriber() async throws {
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
            session.focusTarget = target
            session.sourceBundleIdentifier = target.bundleIdentifier ?? session.sourceBundleIdentifier
            session.sourceApplicationName = target.applicationName ?? session.sourceApplicationName
            let targetBundle = target.bundleIdentifier ?? "unknown"
            let targetRole = target.capturedElementRole ?? "clipboard-fallback"
            NatterLog.delivery.notice(
                "target captured app=\(targetBundle, privacy: .public) element=\(targetRole, privacy: .public)"
            )
        } catch {
            session.focusTarget = nil
            session.deliveryIssue = error.localizedDescription
            NatterLog.delivery.error(
                "target capture failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func captureSourceApplication() {
        let application = NSWorkspace.shared.frontmostApplication
        session.sourceBundleIdentifier = application?.bundleIdentifier
        session.sourceApplicationName = application?.localizedName
    }

    private func deliverStablePartial(_ transcript: String) async {
        guard sessionTypesIncrementally, session.deliveryIssue == nil else { return }

        switch session.emitter.observe(transcript) {
        case .none:
            break
        case let .text(text):
            await insert(text)
        case .conflict:
            session.liveTranscriptConflict = true
            session.deliveryIssue = "The live transcript changed after text had already been typed."
            store.statusMessage = "Still listening · field will be corrected on stop"
        }
    }

    private func spokenLowercaseResult(for transcript: String) -> SpokenLowercaseResult {
        guard store.spokenLowercaseEnabled else {
            return SpokenLowercaseResult(transcript: transcript, consumedCommand: false)
        }
        return SpokenLowercaseCommand.consume(from: transcript)
    }

    private func handlePartial(_ rawTranscript: String) async {
        // The ASR emits a new hypothesis roughly every 560 ms while the tap
        // delivers buffers ~47x/sec; skip the normalization pipeline for the
        // ~25 of 26 callbacks whose transcript hasn't changed.
        guard rawTranscript != session.lastHandledPartial else { return }
        session.lastHandledPartial = rawTranscript

        if session.commandCandidate || SpokenCorrectionCommand.couldBeCommand(
            rawTranscript,
            appNames: correctionAppNames
        ) {
            session.commandCandidate = true
            store.liveTranscript = visibleCorrectionCommand(rawTranscript)
            if SpokenCorrectionCommand.looksLikeRuleRequest(rawTranscript) {
                store.statusMessage = "Rule command detected · keep speaking"
            }
            return
        }

        let lowercaseResult = spokenLowercaseResult(for: rawTranscript)
        session.forcesLowercaseInitial = lowercaseResult.consumedCommand
        store.liveTranscript = DictationTranscriptPipeline.preview(
            rawTranscript: lowercaseResult.transcript,
            mode: store.selectedMode,
            corrections: session.corrections
        )

        switch session.stabilizer.observe(store.liveTranscript) {
        case let .prefix(prefix):
            await deliverStablePartial(prefix)
        case .conflict:
            session.liveTranscriptConflict = true
            session.deliveryIssue = "The live transcript changed after text had already been typed."
            store.statusMessage = "Still listening · field will be corrected on stop"
        }
    }

    private func deliverFinalTranscript(_ transcript: String) async {
        if session.liveTranscriptConflict {
            session.deliveryIssue = "The final transcript changed after text had already been typed."
            return
        }

        guard session.deliveryIssue == nil else { return }

        switch session.emitter.finish(transcript) {
        case .none:
            let insertion = finalInsertionText("")
            if !insertion.isEmpty { await insert(insertion) }
        case let .text(text):
            await insert(finalInsertionText(text))
        case .conflict:
            session.deliveryIssue = "The final transcript changed after text had already been typed."
        }
    }

    private func insert(_ text: String) async {
        guard let focusTarget = session.focusTarget else {
            session.deliveryIssue = "The original text control is no longer available."
            return
        }

        do {
            try await textInserter.insert(
                text,
                into: focusTarget,
                paceTerminalInput: store.terminalPacingEnabled
            )
        } catch {
            session.deliveryIssue = error.localizedDescription
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
            deliveredPrefix: session.emitter.delivered,
            targetBundleIdentifier: session.sourceBundleIdentifier,
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
        guard session.commandCandidate,
              SpokenCorrectionCommand.looksLikeRuleRequest(rawTranscript) else {
            return false
        }
        let visibleCommand = visibleCorrectionCommand(rawTranscript)
        store.liveTranscript = visibleCommand

        store.statusMessage = "Natter is checking that rule locally…"
        do {
            let resolution = try await correctionService.resolve(
                command: rawTranscript,
                previousTranscript: session.previousTranscript ?? ""
            )
            switch resolution {
            case .modelMissing:
                recoverTranscript(
                    visibleCommand,
                    reason: "Install a writing model to add corrections by voice.",
                    statusMessage: "Couldn’t add rule · writing model required · command copied"
                )
            case .unverified:
                recoverTranscript(
                    visibleCommand,
                    reason: "Couldn’t verify a personal correction from the spoken command.",
                    statusMessage: "Couldn’t add rule · command copied"
                )
            case let .added(correction):
                store.liveTranscript = "Added “\(correction.heard)” → “\(correction.replacement)”"
                store.finalTranscript = ""
                store.statusMessage = "Rule added everywhere"
                store.phase = .idle
                recordHistory(visibleCommand, outcome: .delivered)
            }
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
        let definition = activeModeDefinition
        store.statusMessage = "Applying \(modes.name(for: definition.id)) rules locally…"

        let lockedPrefix = session.emitter.delivered
        let transformInput: String
        if lockedPrefix.isEmpty {
            transformInput = transcript
        } else if let remainder = session.emitter.tolerantRemainder(in: transcript) {
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
            let insertion = finalInsertionText("")
            if session.deliveryIssue == nil, !insertion.isEmpty {
                await insert(insertion)
            }
            await completeDelivery(of: lockedPrefix)
            return
        }

        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        let modelDirectory = WritingModelLocation.resolve(in: paths)
        let agentModelDirectory = definition.processing == .refine
            ? AgentWritingModelLocation.resolve(in: paths)
            : nil
        if modelDirectory == nil, definition.processing == .rewrite {
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
                modeName: modes.name(for: definition.id),
                processing: definition.processing,
                markdownRules: definition.instructions,
                modelDirectory: modelDirectory,
                agentModelDirectory: agentModelDirectory,
                agentContext: AgentWritingContext.production(
                    destinationApplicationName: session.sourceApplicationName,
                    corrections: activeCorrections,
                    removesFalseStarts: definition.removesFalseStarts
                )
            )
            if session.forcesLowercaseInitial, lockedPrefix.isEmpty {
                output = SpokenLowercaseCommand.lowercaseInitial(in: output)
            }
            // A model can return otherwise-valid text without closing its final
            // sentence. Apply the same deterministic final punctuation rule to
            // every editable processing mode, while preserving technical tails.
            output = FinalTranscriptFormatter.punctuateRawProse(
                output,
                capitalizesInitial: false
            )
            session.performanceTrace?.mark(.transformFinished)
            let finalOutput = joinedTranscript(
                prefix: lockedPrefix,
                continuation: output
            )
            let insertion = String(finalOutput.dropFirst(lockedPrefix.count))
            let finalInsertion = finalInsertionText(insertion)
            store.liveTranscript = finalOutput
            store.finalTranscript = finalOutput
            if session.deliveryIssue == nil, !finalInsertion.isEmpty {
                store.statusMessage = "Typing…"
                await insert(finalInsertion)
            }
            await completeDelivery(of: finalOutput)
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
        session.performanceTrace?.mark(.deliveryFinished)
        if let deliveryIssue = session.deliveryIssue {
            recoverTranscript(transcript, reason: deliveryIssue)
        } else {
            recordHistory(transcript, outcome: .delivered)
            store.statusMessage = nil
            store.phase = .idle
        }
    }

    private func completeDelivery(of transcript: String) async {
        var notice: String?
        if session.deliveryIssue == nil, session.pendingVoiceSubmit {
            notice = await submitTranscript()
        }

        finishDelivery(of: transcript)
        if session.deliveryIssue == nil, let notice {
            store.statusMessage = notice
        }
    }

    private func finalInsertionText(_ text: String) -> String {
        session.pendingVoiceSubmit ? text : text + " "
    }

    private func submitTranscript() async -> String? {
        guard let focusTarget = session.focusTarget else {
            return "Text inserted · couldn’t press Return"
        }
        do {
            try await textInserter.submit(in: focusTarget)
            return nil
        } catch {
            NatterLog.delivery.error(
                "voice submit failed error=\(error.localizedDescription, privacy: .public)"
            )
            return "Text inserted · couldn’t press Return"
        }
    }

    private func recordHistory(
        _ transcript: String,
        outcome: DictationOutcome
    ) {
        guard !session.historyWasRecorded else { return }
        let end = session.recordingStoppedAt ?? Date()
        let duration = session.recordingStartedAt.map { end.timeIntervalSince($0) } ?? 0
        history.record(
            transcript: transcript,
            rawTranscript: store.rawTranscript,
            durationSeconds: duration,
            mode: store.selectedMode,
            modeName: modes.name(for: store.selectedMode),
            sourceBundleIdentifier: session.sourceBundleIdentifier,
            sourceApplicationName: session.sourceApplicationName,
            outcome: outcome
        )
        session.historyWasRecorded = true
    }

    private func hideOverlayAfterResult(delay: Duration? = nil) async {
        let delay = delay ?? (
            store.phase == .idle && store.statusMessage == nil
                ? .zero
                : .milliseconds(450)
        )
        try? await Task.sleep(for: delay)
        if store.phase == .idle || store.isRecoverable { overlay.hide() }
        if store.phase == .idle {
            store.restoreIdleMode(enabledResolution(profiles.resolution(
                bundleIdentifier: session.sourceBundleIdentifier,
                defaultMode: store.defaultMode
            )))
        }
    }

    private func validateSelectedMode() throws {
        guard activeModeDefinition.processing == .rewrite else { return }
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
        activeModeDefinition.processing != .fast
    }

    private var correctionAppNames: [String] {
        Array(Set([AppInfo.displayName, "Nata", "Dictation"]))
    }

    private var activeCorrections: [PersonalCorrection] {
        DictationTranscriptPipeline.applicableCorrections(
            session.corrections,
            for: store.selectedMode
        )
    }

    private var activeModeDefinition: ModeDefinition {
        modes.definition(for: store.selectedMode)
    }

    private func enabledResolution(_ resolution: ModeResolution) -> ModeResolution {
        if modes.enabledDefinition(for: resolution.mode) != nil { return resolution }
        let fallback = modes.enabledDefinition(for: store.defaultMode)?.id ?? .raw
        return ModeResolution(mode: fallback, source: .defaultMode)
    }

    func fail(_ error: Error) {
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
