import DictationCore
import SwiftUI

struct SettingsView: View {
    @Bindable var store: DictationStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            header
            hotKeyPicker
            modePicker
            modelSummary
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 560, height: 500)
        .background(Theme.Colour.panel)
    }

    private var hotKeyPicker: some View {
        HStack(spacing: Theme.Space.regular) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictation key")
                    .font(.headline)
                Text("Double tap to start. Tap once to stop.")
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

    private var modelSummary: some View {
        HStack(spacing: Theme.Space.regular) {
            Label("Speech model", systemImage: "waveform")
            Spacer()
            Text("613 MB")
                .foregroundStyle(.secondary)
            Divider().frame(height: 16)
            Label("Writing tools optional", systemImage: "text.badge.star")
            Text("5.95 GB")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
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
