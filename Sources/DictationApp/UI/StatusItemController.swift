import AppKit
import DictationCore
import Observation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: DictationStore
    private let modelManager: ModelManager
    private let permissions: PermissionController
    private let rules: RulesManager
    private let profiles: ApplicationProfileManager
    private let history: HistoryManager
    private let onboarding: OnboardingManager
    private let cancelHandler: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let audioInputs = AudioInputDeviceManager.shared

    init(
        store: DictationStore,
        modelManager: ModelManager,
        permissions: PermissionController,
        rules: RulesManager,
        profiles: ApplicationProfileManager,
        history: HistoryManager,
        onboarding: OnboardingManager,
        cancelHandler: @escaping () -> Void
    ) {
        self.store = store
        self.modelManager = modelManager
        self.permissions = permissions
        self.rules = rules
        self.profiles = profiles
        self.history = history
        self.onboarding = onboarding
        self.cancelHandler = cancelHandler
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
        observeStore()
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
        audioInputs.refresh()

        let status = item(
            title: "\(store.phase.label) · \(store.selectedMode.label)",
            symbol: phaseSymbol
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(item(
            title: "Open \(AppInfo.displayName)…",
            action: #selector(openNatter),
            symbol: "macwindow"
        ))

        if store.phase == .preparing || store.phase == .listening {
            let cancel = item(
                title: "Cancel Dictation",
                action: #selector(cancelDictation),
                symbol: "xmark.circle"
            )
            menu.addItem(cancel)
        }

        if onboarding.needsAttention(
            modelManager: modelManager,
            permissions: permissions
        ) {
            let finishSetup = item(
                title: "Finish Setup…",
                action: #selector(openOnboarding),
                symbol: "checklist"
            )
            menu.addItem(finishSetup)
        }

        menu.addItem(.separator())
        let modeMenu = NSMenu()
        for mode in DictationMode.allCases {
            let modeItem = item(
                title: mode.label,
                action: #selector(selectMode(_:)),
                symbol: symbol(for: mode)
            )
            modeItem.representedObject = mode.rawValue
            modeItem.state = store.selectedMode == mode ? .on : .off
            modeItem.isEnabled = !store.phase.isBusy
            modeMenu.addItem(modeItem)
        }
        let modes = item(title: "Mode: \(store.selectedMode.label)", symbol: "slider.horizontal.3")
        modes.submenu = modeMenu
        menu.addItem(modes)

        let microphoneMenu = NSMenu()
        let systemDefault = item(
            title: "System Default",
            action: #selector(selectMicrophone(_:)),
            symbol: "mic"
        )
        systemDefault.representedObject = ""
        systemDefault.state = audioInputs.selectedDeviceUID.isEmpty ? .on : .off
        systemDefault.isEnabled = !store.phase.isBusy
        microphoneMenu.addItem(systemDefault)
        for device in audioInputs.devices {
            let microphone = item(
                title: device.name,
                action: #selector(selectMicrophone(_:)),
                symbol: "mic"
            )
            microphone.representedObject = device.id
            microphone.state = audioInputs.selectedDeviceUID == device.id ? .on : .off
            microphone.isEnabled = !store.phase.isBusy
            microphoneMenu.addItem(microphone)
        }
        let microphone = item(title: "Microphone: \(selectedMicrophoneName)", symbol: "mic")
        microphone.submenu = microphoneMenu
        menu.addItem(microphone)

        let recent = history.recentRecords.compactMap { record -> (DictationHistoryRecord, String)? in
            guard let transcript = record.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcript.isEmpty else { return nil }
            return (record, transcript)
        }.prefix(5)
        if !recent.isEmpty {
            let recentMenu = NSMenu()
            for (record, transcript) in recent {
                let recentItem = NSMenuItem(
                    title: transcriptPreview(transcript),
                    action: #selector(copyRecentTranscript(_:)),
                    keyEquivalent: ""
                )
                recentItem.target = self
                recentItem.representedObject = transcript
                recentItem.toolTip = transcript
                recentItem.image = applicationIcon(bundleIdentifier: record.sourceBundleIdentifier)
                recentMenu.addItem(recentItem)
            }
            recentMenu.addItem(.separator())
            recentMenu.addItem(item(
                title: "View All…",
                action: #selector(openHistory),
                symbol: "clock.arrow.circlepath"
            ))
            let recentItem = item(title: "Recent Dictations", symbol: "clock")
            recentItem.submenu = recentMenu
            menu.addItem(recentItem)
        }

        if !store.finalTranscript.isEmpty {
            let copyTranscript = item(
                title: "Copy Last Transcript",
                action: #selector(copyLastTranscript),
                symbol: "doc.on.doc"
            )
            menu.addItem(copyTranscript)
        }

        menu.addItem(.separator())
        let settings = item(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ",",
            symbol: "gearshape"
        )
        menu.addItem(settings)

        let legal = item(
            title: "About & Legal…",
            action: #selector(openLegal),
            symbol: "info.circle"
        )
        menu.addItem(legal)

        let quit = item(
            title: "Quit \(AppInfo.displayName)",
            action: #selector(quitApp),
            keyEquivalent: "q",
            symbol: "power"
        )
        menu.addItem(quit)
    }

    private func item(
        title: String,
        action: Selector? = nil,
        keyEquivalent: String = "",
        symbol: String? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = action == nil ? nil : self
        if let symbol,
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }
        return item
    }

    private var phaseSymbol: String {
        switch store.phase {
        case .idle: "waveform"
        case .preparing: "hourglass.circle.fill"
        case .listening: "record.circle.fill"
        case .finalizing, .transforming: "ellipsis.circle.fill"
        case .recoverable: "doc.on.clipboard.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func symbol(for mode: DictationMode) -> String {
        switch mode {
        case .raw: "waveform"
        case .agent: "terminal"
        case .clean: "sparkles"
        case .email: "envelope"
        case .article: "doc.text"
        }
    }

    private var selectedMicrophoneName: String {
        guard !audioInputs.selectedDeviceUID.isEmpty else { return "System Default" }
        return audioInputs.devices.first { $0.id == audioInputs.selectedDeviceUID }?.name
            ?? "Unavailable"
    }

    private func transcriptPreview(_ transcript: String) -> String {
        let singleLine = transcript
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard singleLine.count > 54 else { return singleLine }
        return "\(singleLine.prefix(53))…"
    }

    private func applicationIcon(bundleIdentifier: String?) -> NSImage? {
        let image: NSImage?
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        }
        image?.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = DictationMode(rawValue: rawValue) else {
            return
        }
        store.select(mode)
    }

    @objc private func selectMicrophone(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        audioInputs.selectedDeviceUID = uid
    }

    @objc private func openNatter() {
        showApp(section: .home)
    }

    @objc private func openSettings() {
        showApp(section: .settings)
    }

    private func showApp(section: NatterAppSection) {
        SettingsWindow.shared.show(
            store: store,
            modelManager: modelManager,
            permissions: permissions,
            rules: rules,
            profiles: profiles,
            history: history,
            onboarding: onboarding,
            section: section
        )
    }

    @objc private func openOnboarding() {
        OnboardingWindow.shared.show(
            store: store,
            modelManager: modelManager,
            permissions: permissions,
            onboarding: onboarding
        )
    }

    @objc private func openHistory() {
        showApp(section: .home)
    }

    @objc private func openLegal() {
        LegalWindow.shared.show()
    }

    @objc private func cancelDictation() {
        cancelHandler()
    }

    @objc private func copyLastTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.finalTranscript, forType: .string)
    }

    @objc private func copyRecentTranscript(_ sender: NSMenuItem) {
        guard let transcript = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func observeStore() {
        withObservationTracking {
            updateStatusIcon(phase: store.phase, mode: store.selectedMode)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStore() }
        }
    }

    private func updateStatusIcon(phase: DictationPhase, mode: DictationMode) {
        guard let button = statusItem.button else { return }
        let symbolName: String
        switch phase {
        case .idle:
            symbolName = "waveform"
        case .preparing:
            symbolName = "hourglass.circle.fill"
        case .listening:
            symbolName = "record.circle.fill"
        case .finalizing, .transforming:
            symbolName = "ellipsis.circle.fill"
        case .recoverable:
            symbolName = "doc.on.clipboard.fill"
        case .failed:
            symbolName = "exclamationmark.triangle.fill"
        }

        let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "\(AppInfo.displayName): \(phase.label)"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "\(AppInfo.displayName) · \(phase.label) · \(mode.label)"
    }
}
