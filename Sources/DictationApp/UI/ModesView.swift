import AppKit
import DictationCore
import SwiftUI

struct ModesView: View {
    @Bindable var store: DictationStore
    @Bindable var modes: ModeManager
    @Bindable var profiles: ApplicationProfileManager
    @State private var selectedModeID = DictationMode.agent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                header
                modeLibrary
                modeEditor
                delivery
                applicationProfiles
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colour.panel)
        .onAppear {
            profiles.refreshInstalledApplications()
            if modes.modes.contains(where: { $0.id == store.defaultMode }) {
                selectedModeID = store.defaultMode
            }
            reconcileSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Modes & Apps")
                .font(.system(size: 26, weight: .semibold))
            Text("Raw stays untouched. Every other mode starts with the same deterministic cleanup, then chooses Fast, Refine or Rewrite.")
                .foregroundStyle(.secondary)
        }
    }

    private var modeLibrary: some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            HStack {
                Text("Modes")
                    .font(.headline)
                Spacer()
                if !hiddenModes.isEmpty {
                    Menu("Hidden") {
                        ForEach(hiddenModes) { mode in
                            Button("Show \(modes.name(for: mode.id))") {
                                modes.setEnabled(true, for: mode.id)
                                selectedModeID = mode.id
                            }
                        }
                    }
                }
                Button {
                    let mode = modes.addMode(copying: selectedDefinition?.isRaw == false
                        ? selectedDefinition
                        : nil)
                    selectedModeID = mode.id
                } label: {
                    Label("Add Mode", systemImage: "plus")
                }
            }

            ForEach(modes.enabledModes) { mode in
                HStack(spacing: 10) {
                    Button {
                        selectedModeID = mode.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: symbol(for: mode))
                                .foregroundStyle(Theme.Colour.accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modes.name(for: mode.id))
                                    .fontWeight(.medium)
                                Text(mode.isRaw ? "Untouched" : mode.processing.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if store.defaultMode == mode.id {
                        Text("Default")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.Colour.accent)
                    } else {
                        Button("Make Default") { store.selectDefault(mode.id) }
                            .controlSize(.small)
                    }
                }
                .padding(10)
                .background(selectedModeID == mode.id
                    ? Theme.Colour.accent.opacity(0.12)
                    : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .disabled(store.phase.isBusy)
    }

    @ViewBuilder
    private var modeEditor: some View {
        if let mode = selectedDefinition {
            VStack(alignment: .leading, spacing: Theme.Space.regular) {
                HStack {
                    Text(mode.isRaw ? "Raw mode" : "Edit mode")
                        .font(.headline)
                    Spacer()
                    if !mode.isRaw {
                        Button {
                            let copy = modes.addMode(copying: mode)
                            selectedModeID = copy.id
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .controlSize(.small)
                    }
                }

                if mode.isRaw {
                    Text("Raw is fixed: it types Parakeet’s final transcript without corrections, cleanup or a writing model.")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Mode name", text: nameBinding(for: mode))
                        .textFieldStyle(.roundedBorder)

                    Picker("Processing", selection: processingBinding(for: mode)) {
                        ForEach(ModeProcessing.allCases) { processing in
                            Text(processing.label).tag(processing)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(currentDefinition(for: mode).processing.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if currentDefinition(for: mode).processing == .fast {
                        Text("Fast uses the shared deterministic cleanup. Instructions are kept but only used after switching this mode to Refine or Rewrite.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Instructions")
                            .font(.subheadline.weight(.semibold))
                        TextEditor(text: instructionsBinding(for: mode))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 150)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Theme.Colour.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        if currentDefinition(for: mode).processing == .refine {
                            Toggle(
                                "Tidy spoken false starts",
                                isOn: falseStartsBinding(for: mode)
                            )
                            Text("Refine remains guarded: it may remove an abandoned thought but cannot add or reorder facts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button("Move Up") { modes.move(mode.id, by: -1) }
                            .controlSize(.small)
                        Button("Move Down") { modes.move(mode.id, by: 1) }
                            .controlSize(.small)
                        Spacer()
                        if mode.isBuiltIn {
                            Button("Reset") { modes.resetBuiltIn(mode.id) }
                                .controlSize(.small)
                            Button("Hide") { hide(mode) }
                                .controlSize(.small)
                        } else {
                            Button("Delete", role: .destructive) { delete(mode) }
                                .controlSize(.small)
                        }
                    }
                }

                if let error = modes.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(Theme.Space.regular)
            .background(Theme.Colour.secondaryPanel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .disabled(store.phase.isBusy)
        }
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
            Toggle("Submit with a final “Enter” or “Send”", isOn: $store.voiceSubmitEnabled)
            Text("Removes the final command and presses Return after the transcript is safely inserted. Off by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Toggle("Type live in Agent mode", isOn: $store.agentTypesLive)
            Text("An advanced Agent-only option. Final cleanup still runs after you stop.")
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
                        ForEach(modes.enabledModes) { mode in
                            Text(modes.name(for: mode.id)).tag(mode.id as DictationMode?)
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
                            ForEach(modes.enabledModes) { mode in
                                Text(modes.name(for: mode.id)).tag(mode.id)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 125)
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
                Button("Choose App…") { chooseApplication() }
                Spacer()
            }

            if let errorMessage = profiles.errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(Theme.Space.regular)
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .disabled(store.phase.isBusy)
        .opacity(profiles.isEnabled ? 1 : 0.72)
    }

    private var selectedDefinition: ModeDefinition? {
        modes.modes.first { $0.id == selectedModeID }
    }

    private var hiddenModes: [ModeDefinition] {
        modes.modes.filter { !$0.isRaw && !$0.isEnabled }
    }

    private func currentDefinition(for mode: ModeDefinition) -> ModeDefinition {
        modes.definition(for: mode.id)
    }

    private func nameBinding(for mode: ModeDefinition) -> Binding<String> {
        Binding(
            get: { currentDefinition(for: mode).name },
            set: { value in
                var updated = currentDefinition(for: mode)
                updated.name = value
                modes.update(updated)
            }
        )
    }

    private func processingBinding(for mode: ModeDefinition) -> Binding<ModeProcessing> {
        Binding(
            get: { currentDefinition(for: mode).processing },
            set: { value in
                var updated = currentDefinition(for: mode)
                updated.processing = value
                modes.update(updated)
            }
        )
    }

    private func instructionsBinding(for mode: ModeDefinition) -> Binding<String> {
        Binding(
            get: { currentDefinition(for: mode).instructions },
            set: { value in
                var updated = currentDefinition(for: mode)
                updated.instructions = value
                modes.update(updated)
            }
        )
    }

    private func falseStartsBinding(for mode: ModeDefinition) -> Binding<Bool> {
        Binding(
            get: { currentDefinition(for: mode).removesFalseStarts },
            set: { value in
                var updated = currentDefinition(for: mode)
                updated.removesFalseStarts = value
                modes.update(updated)
            }
        )
    }

    private func hide(_ mode: ModeDefinition) {
        if store.defaultMode == mode.id { store.selectDefault(.raw) }
        modes.setEnabled(false, for: mode.id)
        selectedModeID = .raw
    }

    private func delete(_ mode: ModeDefinition) {
        if store.defaultMode == mode.id { store.selectDefault(.raw) }
        modes.delete(mode.id)
        selectedModeID = .raw
    }

    private func reconcileSelection() {
        if !modes.modes.contains(where: { $0.id == selectedModeID }) {
            selectedModeID = .raw
        }
        if modes.enabledDefinition(for: store.defaultMode) == nil {
            store.selectDefault(.raw)
        }
    }

    private func symbol(for mode: ModeDefinition) -> String {
        if mode.isRaw { return "waveform" }
        return switch mode.processing {
        case .fast: "bolt"
        case .refine: "sparkles"
        case .rewrite: "text.badge.star"
        }
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
            get: {
                let mode = profiles.mode(for: group)
                return mode.flatMap { modes.enabledDefinition(for: $0)?.id }
            },
            set: { profiles.setMode($0, for: group) }
        )
    }

    private func applicationModeBinding(
        _ profile: ApplicationModeProfile
    ) -> Binding<DictationMode> {
        Binding(
            get: { modes.enabledDefinition(for: profile.mode)?.id ?? store.defaultMode },
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
}
