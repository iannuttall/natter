import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DictationStore.shared
    private var statusItemController: StatusItemController?
    private var coordinator: DictationCoordinator?
    private var hotKeyMonitor: ModifierHotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(store: store)
        let coordinator = DictationCoordinator(store: store)
        self.coordinator = coordinator
        let hotKeyMonitor = ModifierHotKeyMonitor(store: store) { [weak coordinator] action in
            coordinator?.handle(action)
        }
        self.hotKeyMonitor = hotKeyMonitor
        hotKeyMonitor.start()

        if ProcessInfo.processInfo.environment["DICTATION_OPEN_ON_LAUNCH"] == "1" {
            SettingsWindow.shared.show(store: store)
        }

        if ProcessInfo.processInfo.environment["DICTATION_PREPARE_ON_LAUNCH"] == "1" {
            coordinator.prepareForDebug()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }
}
