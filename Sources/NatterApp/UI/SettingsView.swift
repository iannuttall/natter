import NatterCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DictationStore
    @Bindable var modelManager: ModelManager
    @Bindable var permissions: PermissionController
    @Bindable var history: HistoryManager
    @Bindable var onboarding: OnboardingManager
    let onShowHistory: () -> Void
    @State private var launchAtLogin = LaunchAtLoginManager()
    @State private var audioInputs = AudioInputDeviceManager.shared
    @State private var updater = UpdateController.shared

    init(
        store: DictationStore,
        modelManager: ModelManager,
        permissions: PermissionController,
        history: HistoryManager,
        onboarding: OnboardingManager,
        onShowHistory: @escaping () -> Void = {}
    ) {
        self.store = store
        self.modelManager = modelManager
        self.permissions = permissions
        self.history = history
        self.onboarding = onboarding
        self.onShowHistory = onShowHistory
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header
                appPreferences
                permissionRows
                microphonePicker
                hotKeyPicker
                overlayPreferences
                historyPreferences
                modelPacks
                footer
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colour.panel)
        .onAppear {
            modelManager.refresh()
            permissions.refresh()
            launchAtLogin.refresh()
            audioInputs.refresh()
        }
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    private var microphonePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            HStack(spacing: Theme.Space.regular) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone")
                        .font(.headline)
                    Text("Use the system default or remember a specific input device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Microphone", selection: $audioInputs.selectedDeviceUID) {
                    Text("System Default").tag("")
                    ForEach(audioInputs.devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 230)
                .disabled(store.phase.isBusy)
            }

            if audioInputs.selectedDeviceIsUnavailable {
                Text("The selected microphone is disconnected. Natter will use the system default until it returns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .panelCard()
    }

    private var appPreferences: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("App")
                .font(.headline)
            Toggle(
                "Open at login",
                isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.setEnabled($0) }
                )
            )
            Text("Start the menu-bar app when you sign in. Off until you choose otherwise.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if launchAtLogin.requiresApproval {
                HStack {
                    Text("macOS needs you to allow \(AppInfo.displayName) in Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Login Items") {
                        launchAtLogin.openSystemSettings()
                    }
                    .controlSize(.small)
                }
            }

            if let errorMessage = launchAtLogin.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if updater.isConfigured {
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates")
                            .fontWeight(.medium)
                        Text("Natter checks quietly and lets you choose when to install.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updater.pendingUpdate.map { "Update to \($0)…" } ?? "Check Now…") {
                        updater.checkForUpdates()
                    }
                    .disabled(!updater.canCheckForUpdates)
                }
            }
        }
        .panelCard()
    }

    private var historyPreferences: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local history")
                        .font(.headline)
                    Text("Track usage privately and keep recent transcripts if you want them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("View History…", action: onShowHistory)
            }

            HStack {
                Text("Store")
                Spacer()
                Picker("Store", selection: $history.storageMode) {
                    ForEach(HistoryStorageMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 175)
            }

            if history.storageMode == .full {
                HStack {
                    Text("Keep transcript text")
                    Spacer()
                    Picker("Keep transcript text", selection: $history.retention) {
                        ForEach(TranscriptRetention.allCases) { retention in
                            Text(retention.label).tag(retention)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            Stepper(
                "Typing baseline: \(Int(history.typingWordsPerMinute)) WPM",
                value: $history.typingWordsPerMinute,
                in: 10...200,
                step: 5
            )
            Text("Time saved compares speaking time with this typing speed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = history.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .panelCard()
    }

    private var overlayPreferences: some View {
        HStack(spacing: Theme.Space.regular) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Recording overlay")
                    .font(.headline)
                Text("Full and compact overlays can be dragged and remember their position.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Recording overlay", selection: $store.overlayStyle) {
                ForEach(OverlayStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .labelsHidden()
            .frame(width: 180)
        }
    }


    private var hotKeyPicker: some View {
        HStack(spacing: Theme.Space.regular) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictation key")
                    .font(.headline)
                Text("Double tap to start. Press Command-Shift-M while listening to switch mode. Tap once to stop.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("Dictation key", selection: $store.selectedHotKey) {
                ForEach(ModifierHotKey.allCases) { hotKey in
                    Text(hotKey.label).tag(hotKey)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            .disabled(store.phase.isBusy)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(AppInfo.displayName)
                .font(.system(size: 24, weight: .semibold))
            Text("Fast local dictation. No account, cloud or background server.")
                .foregroundStyle(.secondary)
        }
    }


    private var modelPacks: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("Local models")
                .font(.headline)

            ForEach(ModelPack.allCases) { pack in
                HStack(spacing: Theme.Space.regular) {
                    Image(systemName: pack == .speech ? "waveform" : "text.badge.star")
                        .foregroundStyle(Theme.Colour.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.label)
                            .fontWeight(.medium)
                        Text("\(pack.detail) · \(pack.sizeLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ModelPackAction(modelManager: modelManager, pack: pack)
                }
                .panelCard()
            }

            if let errorMessage = modelManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }


    private var permissionRows: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("macOS permissions")
                .font(.headline)

            ForEach(AppPermission.allCases) { permission in
                HStack(spacing: Theme.Space.regular) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.label)
                            .fontWeight(.medium)
                        Text(permission.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if permissions.isGranted(permission) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Granted")
                    } else if permissions.requiresRelaunch(permission) {
                        Button("Restart Natter") {
                            AppRelauncher.relaunch()
                        }
                    } else if permissions.wasRequested(permission) {
                        Button("Open Settings") {
                            permissions.openSystemSettings(for: permission)
                        }
                    } else {
                        Button("Allow") {
                            permissions.request(permission)
                        }
                    }
                }
            }
        }
        .panelCard()
    }

    private var footer: some View {
        HStack {
            Text("Version \(AppInfo.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Setup Assistant…") {
                OnboardingWindow.shared.show(
                    store: store,
                    modelManager: modelManager,
                    permissions: permissions,
                    onboarding: onboarding
                )
            }
            Button("About & Legal…") {
                LegalWindow.shared.show()
            }
            Button("Quit \(AppInfo.displayName)") {
                NSApp.terminate(nil)
            }
        }
    }
}
