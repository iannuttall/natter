import DictationCore
import Foundation

@MainActor
final class DictationCoordinator {
    private let store: DictationStore
    private let microphone = MicrophoneCapture()
    private let transcriber: SpeechTranscriber
    private let rules: RulesManager
    private let writingEngine = WritingEngine()
    private let textInserter = FocusedTextInserter()
    private let recovery = TranscriptRecovery()
    private let feedback = FeedbackSoundPlayer()
    private let overlay: OverlayPanelController
    private var streamTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var focusTarget: FocusedTextTarget?
    private var emitter = StableTranscriptEmitter()
    private var deliveryIssue: String?
    private var sessionCorrections: [PersonalCorrection] = []
    private var commandCandidate = false

    init(
        store: DictationStore,
        transcriber: SpeechTranscriber,
        rules: RulesManager
    ) {
        self.store = store
        self.transcriber = transcriber
        self.rules = rules
        overlay = OverlayPanelController(store: store)
    }

    func handle(_ action: ModifierHotKeyAction) {
        switch action {
        case .start: start()
        case .stop: stop()
        }
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

    private func start() {
        guard store.canStart else { return }
        sessionTask?.cancel()
        sessionTask = Task { await beginSession() }
    }

    private func beginSession() async {
        store.resetSession()
        emitter.reset()
        deliveryIssue = nil
        sessionCorrections = rules.corrections
        commandCandidate = false
        captureFocusTarget()
        store.phase = .preparing
        store.statusMessage = "Loading local speech model…"
        overlay.show()

        do {
            try validateSelectedMode()
            try await prepareTranscriber()
            guard !Task.isCancelled else { return }
            await transcriber.reset()

            let stream = try microphone.start { [weak store] level in
                store?.audioLevel = level
            }
            store.phase = .listening
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
                        self?.store.rawTranscript = rawPartial
                        self?.handlePartial(rawPartial)
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
            feedback.play(.stopped)
            sessionTask?.cancel()
            sessionTask = nil
            store.resetSession()
            overlay.hide()
            return
        }

        feedback.play(.stopped)
        microphone.stop()
        let drainingStreamTask = streamTask
        streamTask = nil
        store.audioLevel = 0
        store.phase = .finalizing
        store.statusMessage = "Finishing locally…"

        sessionTask = Task {
            await drainingStreamTask?.value
            guard store.phase == .finalizing else { return }

            do {
                let rawTranscript = try await transcriber.finish()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                store.rawTranscript = rawTranscript

                if handleCorrectionCommand(rawTranscript) {
                    await hideOverlayAfterResult()
                    return
                }

                let correctedTranscript = PersonalCorrections.apply(
                    sessionCorrections,
                    to: rawTranscript
                )
                let transcript: String
                switch store.selectedMode {
                case .raw:
                    transcript = FinalTranscriptFormatter.punctuateRawProse(correctedTranscript)
                case .clean:
                    transcript = FinalTranscriptFormatter.punctuateRawProse(
                        DeterministicTranscriptCleaner.clean(correctedTranscript)
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

                if store.selectedMode.isGenerative {
                    await deliverWritingMode(transcript)
                } else {
                    deliverFinalTranscript(transcript)
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
            focusTarget = try textInserter.captureTarget()
        } catch {
            focusTarget = nil
            deliveryIssue = error.localizedDescription
        }
    }

    private func deliverStablePartial(_ transcript: String) {
        guard store.selectedMode.typesIncrementally, deliveryIssue == nil else { return }

        switch emitter.observe(transcript) {
        case .none:
            break
        case let .text(text):
            insert(text)
        case .conflict:
            deliveryIssue = "The live transcript changed after text had already been typed."
            store.statusMessage = "Still listening · transcript will be copied"
        }
    }

    private func handlePartial(_ rawTranscript: String) {
        if commandCandidate || SpokenCorrectionParser.couldBeCommand(
            rawTranscript,
            appNames: correctionAppNames
        ) {
            commandCandidate = true
            store.liveTranscript = rawTranscript
            return
        }

        let corrected = PersonalCorrections.apply(sessionCorrections, to: rawTranscript)
        store.liveTranscript = corrected
        deliverStablePartial(corrected)
    }

    private func deliverFinalTranscript(_ transcript: String) {
        guard deliveryIssue == nil else { return }

        switch emitter.finish(transcript) {
        case .none:
            break
        case let .text(text):
            insert(text)
        case .conflict:
            deliveryIssue = "The final transcript conflicted with text already typed."
        }
    }

    private func insert(_ text: String) {
        guard let focusTarget else {
            deliveryIssue = "The original text control is no longer available."
            return
        }

        do {
            try textInserter.insert(text, into: focusTarget)
        } catch {
            deliveryIssue = error.localizedDescription
            store.statusMessage = "Still listening · transcript will be copied"
        }
    }

    private func recoverTranscript(_ transcript: String, reason: String) {
        let record = RecoveryRecord(
            transcript: transcript,
            deliveredPrefix: emitter.delivered,
            targetBundleIdentifier: focusTarget?.bundleIdentifier,
            reason: reason
        )

        do {
            store.latestRecoveryURL = try recovery.saveAndCopy(record)
            store.statusMessage = "Focus changed · full transcript copied"
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

        rules.add(correction)
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
            store.liveTranscript = output
            store.finalTranscript = output
            insert(output)
            finishDelivery(of: output)
        } catch {
            recoverTranscript(transcript, reason: error.localizedDescription)
        }
    }

    private func finishDelivery(of transcript: String) {
        if let deliveryIssue {
            recoverTranscript(transcript, reason: deliveryIssue)
        } else {
            store.statusMessage = nil
            store.phase = .idle
        }
    }

    private func hideOverlayAfterResult() async {
        try? await Task.sleep(for: .seconds(1.4))
        if store.phase == .idle || store.isRecoverable { overlay.hide() }
    }

    private func validateSelectedMode() throws {
        guard store.selectedMode.isGenerative else { return }
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard WritingModelLocation.resolve(in: paths) != nil else {
            throw DictationCoordinatorError.writingModelMissing
        }
    }

    private var correctionAppNames: [String] {
        Array(Set([AppInfo.displayName, "Dictation"]))
    }

    private func fail(_ error: Error) {
        microphone.stop()
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
