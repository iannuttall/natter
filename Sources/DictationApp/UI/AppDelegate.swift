import AppKit
import DictationCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DictationStore.shared
    private var statusItemController: StatusItemController?
    private var coordinator: DictationCoordinator?
    private var hotKeyMonitor: ModifierHotKeyMonitor?
    private var modelManager: ModelManager?
    private var permissions: PermissionController?
    private var rules: RulesManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let speechTranscriber = SpeechTranscriber()
        let modelManager = ModelManager(speechTranscriber: speechTranscriber)
        let permissions = PermissionController()
        let rules = RulesManager()
        self.modelManager = modelManager
        self.permissions = permissions
        self.rules = rules
        statusItemController = StatusItemController(
            store: store,
            modelManager: modelManager,
            permissions: permissions,
            rules: rules
        )
        let coordinator = DictationCoordinator(
            store: store,
            transcriber: speechTranscriber,
            rules: rules
        )
        self.coordinator = coordinator
        let hotKeyMonitor = ModifierHotKeyMonitor(store: store) { [weak coordinator] action in
            coordinator?.handle(action)
        }
        self.hotKeyMonitor = hotKeyMonitor
        hotKeyMonitor.start()

        if ProcessInfo.processInfo.environment["DICTATION_OPEN_ON_LAUNCH"] == "1"
            || !modelManager.speechInstalled
            || !permissions.allRequiredPermissionsGranted {
            SettingsWindow.shared.show(
                store: store,
                modelManager: modelManager,
                permissions: permissions,
                rules: rules
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
}
