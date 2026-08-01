import DictationCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DictationStore
    @Bindable var modelManager: ModelManager
    @Bindable var permissions: PermissionController
    @Bindable var rules: RulesManager
    @Bindable var profiles: ApplicationProfileManager
    @Bindable var history: HistoryManager
    @Bindable var onboarding: OnboardingManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header
                permissionRows
                hotKeyPicker
                terminalDelivery
                agentDelivery
                overlayPreferences
                modePicker
                applicationProfiles
                historyPreferences
                rulesControls
                modelPacks
                footer
            }
            .padding(24)
        }
        .frame(width: 600, height: 720)
        .background(Theme.Colour.panel)
        .onAppear {
            modelManager.refresh()
            permissions.refresh()
            profiles.refreshInstalledApplications()
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

    private var agentDelivery: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("Agent delivery")
                .font(.headline)
            Toggle("Type live while speaking", isOn: $store.agentTypesLive)
            Text("Off by default: show the live transcript in the overlay, format it when you stop, then type it visibly into the destination.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Use local AI cleanup when installed", isOn: $store.smartAgentEnabled)
            Text("Falls back to deterministic technical formatting when Writing tools are not installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .disabled(store.phase.isBusy)
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
                Button("View History…") { HistoryWindow.shared.show(history: history) }
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
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
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

    private var terminalDelivery: some View {
        Toggle(isOn: $store.terminalPacingEnabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep terminal dictation visible")
                    .font(.headline)
                Text("Pace long input so coding agents do not collapse it into a paste block.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(store.phase.isBusy)
    }

    private var hotKeyPicker: some View {
        HStack(spacing: Theme.Space.regular) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictation key")
                    .font(.headline)
                Text("Double tap to start. Hold before or during dictation to switch mode. Tap once to stop.")
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

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("Default mode")
                .font(.headline)

            ForEach(DictationMode.allCases) { mode in
                Button {
                    store.selectDefault(mode)
                } label: {
                    HStack(alignment: .top, spacing: Theme.Space.regular) {
                        Image(systemName: store.defaultMode == mode
                            ? "checkmark.circle.fill"
                            : "circle")
                            .foregroundStyle(store.defaultMode == mode
                                ? Theme.Colour.accent
                                : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label)
                                .fontWeight(.medium)
                            Text(mode.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.phase.isBusy)
            }
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private var applicationProfiles: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Toggle("Choose modes automatically for apps", isOn: $profiles.isEnabled)
                .font(.headline)

            Text("An app assignment wins over its group. A mode chosen from the menu or by holding the dictation key wins for one recording.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ApplicationGroup.allCases) { group in
                HStack(spacing: Theme.Space.regular) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label)
                            .fontWeight(.medium)
                        Text(group.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker(group.label, selection: groupModeBinding(group)) {
                        Text("Use default").tag(nil as DictationMode?)
                        ForEach(DictationMode.allCases) { mode in
                            Text(mode.label).tag(mode as DictationMode?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 135)
                }
            }

            if !profiles.configuration.applications.isEmpty {
                Divider()
                ForEach(profiles.configuration.applications) { profile in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.displayName)
                                .fontWeight(.medium)
                            Text(profile.bundleIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Picker(profile.displayName, selection: applicationModeBinding(profile)) {
                            ForEach(DictationMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Button {
                            profiles.remove(bundleIdentifier: profile.bundleIdentifier)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            HStack {
                Menu("Add installed app") {
                    ForEach(unassignedApplications) { application in
                        Button(application.displayName) {
                            profiles.setMode(store.defaultMode, for: application)
                        }
                    }
                    if unassignedApplications.isEmpty {
                        Text("No unassigned apps found")
                    }
                }
                Button("Choose App…") { chooseApplication() }
                Spacer()
            }

            if let errorMessage = profiles.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .disabled(store.phase.isBusy)
        .opacity(profiles.isEnabled ? 1 : 0.72)
    }

    private var unassignedApplications: [InstalledApplication] {
        let assigned = Set(profiles.configuration.applications.map {
            $0.bundleIdentifier.lowercased()
        })
        return profiles.installedApplications.filter {
            !assigned.contains($0.bundleIdentifier.lowercased())
        }
    }

    private func groupModeBinding(_ group: ApplicationGroup) -> Binding<DictationMode?> {
        Binding(
            get: { profiles.mode(for: group) },
            set: { profiles.setMode($0, for: group) }
        )
    }

    private func applicationModeBinding(
        _ profile: ApplicationModeProfile
    ) -> Binding<DictationMode> {
        Binding(
            get: { profile.mode },
            set: { mode in
                if let application = profiles.installedApplications.first(where: {
                    $0.bundleIdentifier == profile.bundleIdentifier
                }) {
                    profiles.setMode(mode, for: application)
                } else {
                    profiles.setMode(
                        mode,
                        for: InstalledApplication(
                            bundleIdentifier: profile.bundleIdentifier,
                            displayName: profile.displayName,
                            url: URL(fileURLWithPath: "/")
                        )
                    )
                }
            }
        )
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK,
              let url = panel.url,
              let application = profiles.application(at: url) else { return }
        profiles.setMode(store.defaultMode, for: application)
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
                    modelAction(for: pack)
                }
                .padding(Theme.Space.regular)
                .background(Theme.Colour.secondaryPanel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }

            if let errorMessage = modelManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var rulesControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictionary and writing rules")
                    .font(.headline)
                Text("Correct recurring mistakes or customise local AI formatting.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dictionary…") {
                DictionaryWindow.shared.show(rules: rules)
            }
            Button("Writing Rules…") {
                RulesWindow.shared.show(rules: rules)
            }
        }
    }

    @ViewBuilder
    private func modelAction(for pack: ModelPack) -> some View {
        if modelManager.installing == pack {
            VStack(alignment: .trailing, spacing: 4) {
                ProgressView(value: modelManager.progress)
                    .frame(width: 110)
                Text(modelManager.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if modelManager.isInstalled(pack) {
            HStack(spacing: 8) {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Button("Remove", role: .destructive) {
                    modelManager.remove(pack)
                }
                .controlSize(.small)
            }
        } else {
            Button("Download") {
                modelManager.install(pack)
            }
            .disabled(modelManager.installing != nil)
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
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
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
            Button("Quit \(AppInfo.displayName)") {
                NSApp.terminate(nil)
            }
        }
    }
}
