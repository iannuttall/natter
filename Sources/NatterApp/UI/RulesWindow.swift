import AppKit
import NatterCore
import SwiftUI

struct RulesEditorView: View {
    @Bindable var rules: RulesManager
    @Bindable var modes: ModeManager
    @State private var selection = "personal"
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rules")
                        .font(.system(size: 22, weight: .semibold))
                    Text(documentDescription)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Document", selection: $selection) {
                    Text("Dictionary").tag("personal")
                    Divider()
                    ForEach(modes.configurableModes) { mode in
                        Text(modes.name(for: mode.id)).tag(mode.id.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 190)
            }

            TextEditor(text: $draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.Colour.secondaryPanel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            HStack {
                if let error = modes.errorMessage ?? rules.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(selection == "personal" ? rules.status : modes.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reload") {
                    rules.reload()
                    modes.reload()
                    loadDraft()
                }
                Button("Save") { saveDraft() }
                    .keyboardShortcut("s")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colour.panel)
        .onAppear(perform: loadDraft)
        .onChange(of: selection) { _, _ in loadDraft() }
    }

    private var selectedMode: ModeDefinition? {
        guard let id = DictationMode(rawValue: selection) else { return nil }
        return modes.modes.first { $0.id == id }
    }

    private var documentDescription: String {
        guard selection != "personal", let selectedMode else {
            return "Personal spellings and corrections applied to every non-Raw mode."
        }
        return "Instructions used when \(selectedMode.name) is set to Refine or Rewrite."
    }

    private func loadDraft() {
        draft = selection == "personal"
            ? rules.personalMarkdown
            : (selectedMode?.instructions ?? "")
    }

    private func saveDraft() {
        if selection == "personal" {
            rules.personalMarkdown = draft
            rules.save()
            return
        }
        guard var selectedMode else { return }
        selectedMode.instructions = draft
        modes.update(selectedMode)
    }
}

@MainActor
final class RulesWindow: NSObject, NSWindowDelegate {
    static let shared = RulesWindow()
    private var window: NSWindow?

    func show(rules: RulesManager, modes: ModeManager = ModeManager()) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.displayName) Rules"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 400)
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: RulesEditorView(rules: rules, modes: modes))
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
