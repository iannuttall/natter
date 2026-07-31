import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = DictationStore.shared
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(store: store)

        if ProcessInfo.processInfo.environment["DICTATION_OPEN_ON_LAUNCH"] == "1" {
            SettingsWindow.shared.show(store: store)
        }
    }
}

