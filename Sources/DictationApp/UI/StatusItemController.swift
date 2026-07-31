import AppKit
import DictationCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: DictationStore
    private let modelManager: ModelManager
    private let permissions: PermissionController
    private let rules: RulesManager
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(
        store: DictationStore,
        modelManager: ModelManager,
        permissions: PermissionController,
        rules: RulesManager
    ) {
        self.store = store
        self.modelManager = modelManager
        self.permissions = permissions
        self.rules = rules
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: AppInfo.displayName
            )
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(showMenu)
            button.toolTip = AppInfo.displayName
        }

        menu.delegate = self
    }

    @objc private func showMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = NSMenuItem(
            title: "\(store.phase.label) · \(store.selectedMode.label)",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        for mode in DictationMode.allCases {
            let item = NSMenuItem(
                title: mode.label,
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = store.selectedMode == mode ? .on : .off
            item.isEnabled = !store.phase.isBusy
            menu.addItem(item)
        }

        menu.addItem(.separator())
        if !store.finalTranscript.isEmpty {
            let copyTranscript = NSMenuItem(
                title: "Copy Last Transcript",
                action: #selector(copyLastTranscript),
                keyEquivalent: ""
            )
            copyTranscript.target = self
            menu.addItem(copyTranscript)
            menu.addItem(.separator())
        }
        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(
            title: "Quit \(AppInfo.displayName)",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DictationMode(rawValue: rawValue) else {
            return
        }
        store.select(mode)
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show(
            store: store,
            modelManager: modelManager,
            permissions: permissions,
            rules: rules
        )
    }

    @objc private func copyLastTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.finalTranscript, forType: .string)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
