import AppKit
import DictationCore
import SwiftUI
import UniformTypeIdentifiers

private struct DictionaryView: View {
    @Bindable var rules: RulesManager
    @State private var heard = ""
    @State private var replacement = ""
    @State private var scope: PersonalCorrectionScope = .everywhere
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dictionary")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Fix names, products, acronyms and recurring recognition mistakes.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Import…") { importCorrections() }
            }

            HStack(spacing: 10) {
                TextField("When \(AppInfo.displayName) hears…", text: $heard)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.tertiary)
                TextField("Use…", text: $replacement)
                Picker("Scope", selection: $scope) {
                    ForEach(PersonalCorrectionScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .labelsHidden()
                .frame(width: 125)
                Button("Add") { addCorrection() }
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedHeard.isEmpty || trimmedReplacement.isEmpty)
            }

            if let message = importError ?? rules.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    if rules.corrections.isEmpty {
                        Text("No corrections yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(32)
                    } else {
                        ForEach(Array(rules.corrections.enumerated()), id: \.element.id) {
                            index, correction in
                            HStack(spacing: 12) {
                                Text(correction.heard)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.right")
                                    .foregroundStyle(.tertiary)
                                Text(correction.replacement)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(correction.scope.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                Button {
                                    rules.remove(correction)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help("Remove correction")
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                            if index < rules.corrections.count - 1 { Divider() }
                        }
                    }
                }
            }
            .background(Theme.Colour.secondaryPanel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            HStack {
                Text("Stored as portable Markdown in Application Support.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit Markdown…") { RulesWindow.shared.show(rules: rules) }
            }
        }
        .padding(24)
        .frame(width: 760, height: 540)
        .background(Theme.Colour.panel)
    }

    private var trimmedHeard: String {
        heard.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedReplacement: String {
        replacement.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addCorrection() {
        rules.add(PersonalCorrection(
            heard: trimmedHeard,
            replacement: trimmedReplacement,
            scope: scope
        ))
        heard = ""
        replacement = ""
    }

    private func importCorrections() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let imported = PersonalCorrections.parse(markdown)
            guard !imported.isEmpty else {
                importError = "No correction lines were found in that file."
                return
            }
            for correction in imported { rules.add(correction) }
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}

@MainActor
final class DictionaryWindow: NSObject, NSWindowDelegate {
    static let shared = DictionaryWindow()
    private var window: NSWindow?

    func show(rules: RulesManager) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.displayName) Dictionary"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 640, height: 420)
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: DictionaryView(rules: rules))
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
