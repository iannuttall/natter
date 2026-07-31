import DictationCore
import Foundation

@MainActor
final class DictationCoordinator {
    private let store: DictationStore
    private let microphone = MicrophoneCapture()
    private let transcriber = SpeechTranscriber()
    private let overlay: OverlayPanelController
    private var streamTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?

    init(store: DictationStore) {
        self.store = store
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

    private func start() {
        guard store.canStart else { return }
        sessionTask?.cancel()
        sessionTask = Task { await beginSession() }
    }

    private func beginSession() async {
        store.resetSession()
        store.phase = .preparing
        store.statusMessage = "Loading local speech model…"
        overlay.show()

        do {
            try await prepareTranscriber()
            guard !Task.isCancelled else { return }
            await transcriber.reset()

            let stream = try microphone.start { [weak store] level in
                store?.audioLevel = level
            }
            store.phase = .listening
            store.statusMessage = nil

            streamTask = Task { [weak self] in
                for await chunk in stream {
                    guard !Task.isCancelled else { break }
                    do {
                        let partial = try await self?.transcriber.consume(chunk) ?? ""
                        guard !partial.isEmpty else { continue }
                        self?.store.liveTranscript = partial
                        self?.store.rawTranscript = partial
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
            sessionTask?.cancel()
            sessionTask = nil
            store.resetSession()
            overlay.hide()
            return
        }

        microphone.stop()
        streamTask?.cancel()
        streamTask = nil
        store.audioLevel = 0
        store.phase = .finalizing
        store.statusMessage = "Finishing locally…"

        sessionTask = Task {
            do {
                let transcript = try await transcriber.finish()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                store.rawTranscript = transcript
                store.liveTranscript = transcript
                store.finalTranscript = transcript
                store.statusMessage = transcript.isEmpty ? "No speech detected" : nil
                store.phase = .idle

                try? await Task.sleep(for: .seconds(1.4))
                if store.phase == .idle { overlay.hide() }
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

    var errorDescription: String? {
        switch self {
        case let .speechModelMissing(directory):
            "Install the speech model in Settings. Expected it at \(directory.path)."
        }
    }
}
