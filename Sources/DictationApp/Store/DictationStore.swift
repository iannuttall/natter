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
    var latestRecoveryURL: URL?

    var selectedMode: DictationMode {
        didSet {
            defaults.set(selectedMode.rawValue, forKey: Keys.selectedMode)
        }
    }

    var selectedHotKey: ModifierHotKey {
        didSet {
            defaults.set(selectedHotKey.rawValue, forKey: Keys.selectedHotKey)
        }
    }

    var terminalPacingEnabled: Bool {
        didSet {
            defaults.set(terminalPacingEnabled, forKey: Keys.terminalPacingEnabled)
        }
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedMode = defaults.string(forKey: Keys.selectedMode)
            .flatMap(DictationMode.init(rawValue:))
            ?? .raw
        selectedHotKey = defaults.string(forKey: Keys.selectedHotKey)
            .flatMap(ModifierHotKey.init(rawValue:))
            ?? .rightOption
        terminalPacingEnabled = defaults.object(forKey: Keys.terminalPacingEnabled) as? Bool
            ?? true

        try? AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
            .createRequiredDirectories()
    }

    var canStart: Bool {
        phase.canStartSession
    }

    var isRecoverable: Bool {
        if case .recoverable = phase { return true }
        return false
    }

    func select(_ mode: DictationMode) {
        guard !phase.isBusy else { return }
        selectedMode = mode
    }

    func select(_ hotKey: ModifierHotKey) {
        guard !phase.isBusy else { return }
        selectedHotKey = hotKey
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
        static let selectedHotKey = "selectedHotKey"
        static let terminalPacingEnabled = "terminalPacingEnabled"
    }
}
