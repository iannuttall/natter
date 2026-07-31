import DictationCore
import Foundation
import Observation

@MainActor
@Observable
final class DictationStore {
    static let shared = DictationStore()

    private let defaults: UserDefaults

    var phase: DictationPhase = .idle
    var liveTranscript = ""
    var rawTranscript = ""
    var finalTranscript = ""
    var audioLevel: Float = 0
    var statusMessage: String?

    var selectedMode: DictationMode {
        didSet {
            defaults.set(selectedMode.rawValue, forKey: Keys.selectedMode)
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedMode = defaults.string(forKey: Keys.selectedMode)
            .flatMap(DictationMode.init(rawValue:))
            ?? .raw

        try? AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
            .createRequiredDirectories()
    }

    var canStart: Bool {
        phase == .idle || isRecoverable
    }

    var isRecoverable: Bool {
        if case .recoverable = phase { return true }
        return false
    }

    func select(_ mode: DictationMode) {
        guard !phase.isBusy else { return }
        selectedMode = mode
    }

    func resetSession() {
        phase = .idle
        liveTranscript = ""
        rawTranscript = ""
        finalTranscript = ""
        audioLevel = 0
        statusMessage = nil
    }

    private enum Keys {
        static let selectedMode = "selectedMode"
    }
}

