import AppKit
import DictationCore
import SwiftUI

struct ModesView: View {
    @Bindable var store: DictationStore
    @Bindable var profiles: ApplicationProfileManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header
                defaultMode
                delivery
                applicationProfiles
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colour.panel)
        .onAppear { profiles.refreshInstalledApplications() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Modes & Apps")
                .font(.system(size: 26, weight: .semibold))
            Text("Choose how Natter formats text, then override it for particular apps.")
                .foregroundStyle(.secondary)
        }
    }

    private var defaultMode: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("Default mode")
                .font(.headline)
            ForEach(DictationMode.allCases) { mode in
                Button {
                    store.selectDefault(mode)
                } label: {
                    HStack(alignment: .top, spacing: Theme.Space.regular) {
                        Image(systemName: store.defaultMode == mode ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.defaultMode == mode ? Theme.Colour.accent : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label).fontWeight(.medium)
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

    private var delivery: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Text("Delivery")
                .font(.headline)
            Toggle("Keep terminal dictation visible", isOn: $store.terminalPacingEnabled)
            Text("Pace long input so coding agents do not collapse it into a paste block.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle("Type live in Agent mode", isOn: $store.agentTypesLive)
            Text("When off, Natter formats the complete transcript locally, then types it into the destination.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Use local AI cleanup when installed", isOn: $store.smartAgentEnabled)
            Text("Uses the fast 4B Agent model and falls back to deterministic technical formatting when it is not installed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Tidy false starts in Agent mode", isOn: $store.agentRemovesFalseStarts)
            Text("Removes abandoned thoughts spoken out loud, like “what am I—”. Words are only ever deleted, never added, and protected terms always survive.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .disabled(store.phase.isBusy)
    }

    private var applicationProfiles: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            Toggle("Choose modes automatically for apps", isOn: $profiles.isEnabled)
                .font(.headline)
            Text("An app assignment wins over its group. A mode chosen manually wins for one recording.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(ApplicationGroup.allCases) { group in
                HStack(spacing: Theme.Space.regular) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.label).fontWeight(.medium)
                        Text(group.detail).font(.caption).foregroundStyle(.secondary)
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
                            Text(profile.displayName).fontWeight(.medium)
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
                    if unassignedApplications.isEmpty { Text("No unassigned apps found") }
                }
                Button("Choose App…", action: chooseApplication)
                Spacer()
            }
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .disabled(store.phase.isBusy)
        .opacity(profiles.isEnabled ? 1 : 0.72)
    }

    private var unassignedApplications: [InstalledApplication] {
        let assigned = Set(profiles.configuration.applications.map { $0.bundleIdentifier.lowercased() })
        return profiles.installedApplications.filter { !assigned.contains($0.bundleIdentifier.lowercased()) }
    }

    private func groupModeBinding(_ group: ApplicationGroup) -> Binding<DictationMode?> {
        Binding(get: { profiles.mode(for: group) }, set: { profiles.setMode($0, for: group) })
    }

    private func applicationModeBinding(_ profile: ApplicationModeProfile) -> Binding<DictationMode> {
        Binding(
            get: { profile.mode },
            set: { mode in
                if let application = profiles.installedApplications.first(where: {
                    $0.bundleIdentifier == profile.bundleIdentifier
                }) {
                    profiles.setMode(mode, for: application)
                } else {
                    profiles.setMode(mode, for: InstalledApplication(
                        bundleIdentifier: profile.bundleIdentifier,
                        displayName: profile.displayName,
                        url: URL(fileURLWithPath: "/")
                    ))
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
}
