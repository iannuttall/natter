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
    var activeApplicationName: String?
    var activeModeSource: String?

    private(set) var selectedMode: DictationMode

    var defaultMode: DictationMode {
        didSet {
            defaults.set(defaultMode.rawValue, forKey: Keys.defaultMode)
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

    var overlayStyle: OverlayStyle {
        didSet {
            defaults.set(overlayStyle.rawValue, forKey: Keys.overlayStyle)
        }
    }

    private var pendingModeOverride: DictationMode?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let persistedMode = defaults.string(forKey: Keys.defaultMode)
            ?? defaults.string(forKey: Keys.legacySelectedMode)
        let initialMode = persistedMode
            .flatMap(DictationMode.init(rawValue:))
            ?? .raw
        defaultMode = initialMode
        selectedMode = initialMode
        selectedHotKey = defaults.string(forKey: Keys.selectedHotKey)
            .flatMap(ModifierHotKey.init(rawValue:))
            ?? .rightOption
        terminalPacingEnabled = defaults.object(forKey: Keys.terminalPacingEnabled) as? Bool
            ?? true
        overlayStyle = defaults.string(forKey: Keys.overlayStyle)
            .flatMap(OverlayStyle.init(rawValue:))
            ?? .full

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
        pendingModeOverride = mode
    }

    func selectDefault(_ mode: DictationMode) {
        guard !phase.isBusy else { return }
        defaultMode = mode
        selectedMode = mode
        pendingModeOverride = nil
    }

    func selectNextModeForSession() {
        guard !phase.isBusy else { return }
        select(selectedMode.next)
    }

    func selectDuringSession(_ mode: DictationMode) {
        guard phase == .listening else { return }
        selectedMode = mode
        activeModeSource = "Changed for this recording"
    }

    func prepareSessionMode(_ resolution: ModeResolution) {
        if let pendingModeOverride {
            selectedMode = pendingModeOverride
            activeModeSource = "Chosen for this recording"
            self.pendingModeOverride = nil
            return
        }

        selectedMode = resolution.mode
        switch resolution.source {
        case let .application(name):
            activeModeSource = "\(name) profile"
        case let .group(group):
            activeModeSource = "\(group.label) profile"
        case .defaultMode:
            activeModeSource = nil
        }
    }

    func restoreIdleMode(_ resolution: ModeResolution) {
        guard phase == .idle, pendingModeOverride == nil else { return }
        selectedMode = resolution.mode
        activeModeSource = nil
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
        activeApplicationName = nil
        activeModeSource = nil
    }

    private enum Keys {
        static let defaultMode = "defaultMode"
        static let legacySelectedMode = "selectedMode"
        static let selectedHotKey = "selectedHotKey"
        static let terminalPacingEnabled = "terminalPacingEnabled"
        static let overlayStyle = "overlayStyle"
    }
}

enum OverlayStyle: String, CaseIterable, Identifiable {
    case full
    case compact
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Full transcript"
        case .compact: "Compact indicator"
        case .hidden: "Menu bar only"
        }
    }
}
