import AppKit
import DictationCore
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: DictationStore!
    private var statusItemController: StatusItemController?
    private var coordinator: DictationCoordinator?
    private var hotKeyMonitor: ModifierHotKeyMonitor?
    private var modelManager: ModelManager?
    private var permissions: PermissionController?
    private var rules: RulesManager?
    private var profiles: ApplicationProfileManager?
    private var history: HistoryManager?
    private var onboarding: OnboardingManager?
    private var activationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            try LegacyDataMigrator.migrateIfNeeded(to: AppInfo.bundleIdentifier)
        } catch {
            FileHandle.standardError.write(Data(
                "Natter data migration failed: \(error.localizedDescription)\n".utf8
            ))
        }
        let store = DictationStore.shared
        self.store = store
        let speechTranscriber = SpeechTranscriber()
        let modelManager = ModelManager(speechTranscriber: speechTranscriber)
        let permissions = PermissionController()
        let rules = RulesManager()
        let profiles = ApplicationProfileManager()
        let history = HistoryManager()
        let onboarding = OnboardingManager()
        self.modelManager = modelManager
        self.permissions = permissions
        self.rules = rules
        self.profiles = profiles
        self.history = history
        self.onboarding = onboarding
        let coordinator = DictationCoordinator(
            store: store,
            transcriber: speechTranscriber,
            rules: rules,
            profiles: profiles,
            history: history
        )
        self.coordinator = coordinator
        statusItemController = StatusItemController(
            store: store,
            modelManager: modelManager,
            permissions: permissions,
            rules: rules,
            profiles: profiles,
            history: history,
            onboarding: onboarding,
            cancelHandler: { [weak coordinator] in coordinator?.cancel() }
        )
        let hotKeyMonitor = ModifierHotKeyMonitor(store: store) { [weak coordinator] action in
            coordinator?.handle(action)
        }
        self.hotKeyMonitor = hotKeyMonitor
        hotKeyMonitor.start()
        observeInputMonitoringPermission()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak permissions, weak modelManager] _ in
            Task { @MainActor in
                permissions?.refresh()
                modelManager?.refresh()
            }
        }

        let insertionSmokeText = ProcessInfo.processInfo.environment[
            "NATTER_TEST_INSERT_ON_LAUNCH"
        ]
        if ProcessInfo.processInfo.environment["DICTATION_OPEN_ON_LAUNCH"] == "1" {
            SettingsWindow.shared.show(
                store: store,
                modelManager: modelManager,
                permissions: permissions,
                rules: rules,
                profiles: profiles,
                history: history,
                onboarding: onboarding
            )
        } else if insertionSmokeText == nil, onboarding.needsAttention(
            modelManager: modelManager,
            permissions: permissions
        ) {
            OnboardingWindow.shared.show(
                store: store,
                modelManager: modelManager,
                permissions: permissions,
                onboarding: onboarding
            )
        }

        if ProcessInfo.processInfo.environment["DICTATION_PREPARE_ON_LAUNCH"] == "1" {
            coordinator.prepareForDebug()
        }

        if ProcessInfo.processInfo.environment["DICTATION_INSTALL_SPEECH_ON_LAUNCH"] == "1" {
            modelManager.install(.speech)
        }

        if let transcript = ProcessInfo.processInfo.environment[
            "DICTATION_TEST_WRITING_ON_LAUNCH"
        ] {
            coordinator.testWritingForDebug(transcript)
        }

        if let insertionSmokeText {
            let delayMilliseconds = ProcessInfo.processInfo.environment[
                "NATTER_TEST_INSERT_DELAY_MS"
            ].flatMap(Int.init) ?? 2_000
            coordinator.testInsertionForDebug(
                insertionSmokeText,
                delay: .milliseconds(delayMilliseconds)
            )
            if ProcessInfo.processInfo.environment["NATTER_EXIT_AFTER_INSERT"] == "1" {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(delayMilliseconds + 3_000))
                    NSApp.terminate(nil)
                }
            }
        }

        if ProcessInfo.processInfo.environment["DICTATION_CAPTURE_SMOKE_ON_LAUNCH"] == "1" {
            coordinator.handle(.start)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                coordinator.handle(.stop)
                try? await Task.sleep(for: .seconds(1))
                FileHandle.standardError.write(
                    Data("DICTATION_CAPTURE_SMOKE_COMPLETE\n".utf8)
                )
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let command = AppCommand(url: url) else { continue }
            switch command {
            case let .setMode(mode):
                store.select(mode)
            }
        }
    }

    private func observeInputMonitoringPermission() {
        guard let permissions else { return }
        withObservationTracking {
            _ = permissions.inputMonitoringGranted
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.permissions?.inputMonitoringGranted == true {
                    self.hotKeyMonitor?.restart()
                }
                self.observeInputMonitoringPermission()
            }
        }
    }
}
