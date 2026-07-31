import AppKit
import DictationCore

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: DictationStore
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(store: DictationStore) {
        self.store = store
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
        SettingsWindow.shared.show(store: store)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
