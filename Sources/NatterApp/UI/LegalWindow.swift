import AppKit
import SwiftUI

@MainActor
final class LegalWindow: NSObject, NSWindowDelegate {
    static let shared = LegalWindow()

    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "About & Legal"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: LegalView())
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct LegalView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case privacy = "Privacy"
        case licence = "App Licence"
        case notices = "Third-party"

        var id: Self { self }
    }

    @State private var selection: Section = .privacy

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.section) {
            HStack(spacing: Theme.Space.regular) {
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(Theme.Colour.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppInfo.displayName)
                        .font(.title2.weight(.semibold))
                    Text("Version \(AppInfo.version)")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Section", selection: $selection) {
                ForEach(Section.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch selection {
                case .privacy:
                    privacy
                case .licence:
                    document(named: "APP_LICENSE", extension: "txt")
                case .notices:
                    document(named: "THIRD_PARTY_NOTICES", extension: "md")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 520)
        .background(Theme.Colour.panel)
    }

    private var privacy: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.section) {
                privacyRow(
                    icon: "lock.shield",
                    title: "Local by default",
                    detail: "Audio, transcription and writing cleanup run on this Mac."
                )
                privacyRow(
                    icon: "person.crop.circle.badge.xmark",
                    title: "No account or analytics",
                    detail: "The app has no sign-in, telemetry endpoint or advertising SDK."
                )
                privacyRow(
                    icon: "externaldrive",
                    title: "Your data stays yours",
                    detail: "Models, rules, app profiles, recovery data and optional history live in Application Support. Nothing is uploaded unless you explicitly copy or export it."
                )

                Text("Local data location")
                    .font(.headline)
                Text("~/Library/Application Support/\(AppInfo.bundleIdentifier)")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(Theme.Space.regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colour.secondaryPanel)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            }
        }
    }

    private func privacyRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.regular) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Theme.Colour.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func document(named name: String, extension fileExtension: String) -> some View {
        ScrollView {
            Text(loadDocument(named: name, extension: fileExtension))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(Theme.Space.regular)
        }
        .background(Theme.Colour.secondaryPanel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
    }

    private func loadDocument(named name: String, extension fileExtension: String) -> String {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Legal"
        ), let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return "This document is included in release builds."
        }
        return contents
    }
}
