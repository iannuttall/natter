import DictationCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DictationStore
    @Bindable var modelManager: ModelManager
    @Bindable var permissions: PermissionController
    @Bindable var rules: RulesManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header
                permissionRows
                hotKeyPicker
                terminalDelivery
                modePicker
                rulesButton
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
                Text("Double tap to start. Hold to switch mode. Tap once to stop.")
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
                    store.select(mode)
                } label: {
                    HStack(alignment: .top, spacing: Theme.Space.regular) {
                        Image(systemName: store.selectedMode == mode
                            ? "checkmark.circle.fill"
                            : "circle")
                            .foregroundStyle(store.selectedMode == mode
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

    private var rulesButton: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal rules")
                    .font(.headline)
                Text("Corrections plus Email and Article instructions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Edit Rules…") {
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
            Button("Quit \(AppInfo.displayName)") {
                NSApp.terminate(nil)
            }
        }
    }
}
