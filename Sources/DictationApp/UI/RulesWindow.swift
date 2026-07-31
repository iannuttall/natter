import AppKit
import DictationCore
import SwiftUI

private enum RulesDocument: String, CaseIterable, Identifiable {
    case personal
    case email
    case article

    var id: String { rawValue }

    var label: String {
        switch self {
        case .personal: "Corrections"
        case .email: "Email"
        case .article: "Article"
        }
    }
}

private struct RulesEditorView: View {
    @Bindable var rules: RulesManager
    @State private var document: RulesDocument = .personal

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rules")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Plain Markdown, stored locally and applied on every dictation.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Document", selection: $document) {
                    ForEach(RulesDocument.allCases) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }

            TextEditor(text: markdownBinding)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.Colour.secondaryPanel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))

            HStack {
                if let error = rules.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(rules.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reload") { rules.reload() }
                Button("Save") { rules.save() }
                    .keyboardShortcut("s")
            }
        }
        .padding(24)
        .frame(width: 680, height: 520)
        .background(Theme.Colour.panel)
    }

    private var markdownBinding: Binding<String> {
        Binding(
            get: {
                switch document {
                case .personal: rules.personalMarkdown
                case .email: rules.emailMarkdown
                case .article: rules.articleMarkdown
                }
            },
            set: { value in
                switch document {
                case .personal:
                    rules.personalMarkdown = value
                case .email:
                    rules.emailMarkdown = value
                case .article:
                    rules.articleMarkdown = value
                }
            }
        )
    }
}

@MainActor
final class RulesWindow: NSObject, NSWindowDelegate {
    static let shared = RulesWindow()
    private var window: NSWindow?

    func show(rules: RulesManager) {
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
        window.contentView = NSHostingView(rootView: RulesEditorView(rules: rules))
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
