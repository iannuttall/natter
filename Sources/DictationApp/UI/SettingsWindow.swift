import AppKit
import Observation
import SwiftUI

enum NatterAppSection: String, CaseIterable, Identifiable {
    case home
    case modes
    case dictionary
    case rules
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .home: "Home"
        case .modes: "Modes & Apps"
        case .dictionary: "Dictionary"
        case .rules: "Writing Rules"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .modes: "slider.horizontal.3"
        case .dictionary: "character.book.closed"
        case .rules: "text.badge.star"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class NatterAppSelection {
    var section: NatterAppSection = .home
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?
    private let selection = NatterAppSelection()

    func show(
        store: DictationStore,
        modelManager: ModelManager,
        permissions: PermissionController,
        rules: RulesManager,
        profiles: ApplicationProfileManager,
        history: HistoryManager,
        onboarding: OnboardingManager,
        section: NatterAppSection = .settings
    ) {
        selection.section = section
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppInfo.displayName
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 500)
        let restoredFrame = window.setFrameUsingName("NatterMainWindow")
        window.setFrameAutosaveName("NatterMainWindow")
        if !restoredFrame { window.center() }
        window.delegate = self
        let hostingView = NSHostingView(
            rootView: NatterAppView(
                store: store,
                modelManager: modelManager,
                permissions: permissions,
                rules: rules,
                profiles: profiles,
                history: history,
                onboarding: onboarding,
                selection: selection
            )
        )
        // The dashboard has a wide ideal layout. Let the user opt into that by resizing
        // instead of allowing SwiftUI to turn the first launch into a near-fullscreen window.
        hostingView.sizingOptions = []
        window.contentView = hostingView
        if !restoredFrame {
            window.setContentSize(NSSize(width: 820, height: 620))
        }
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct NatterAppView: View {
    @Bindable var store: DictationStore
    @Bindable var modelManager: ModelManager
    @Bindable var permissions: PermissionController
    @Bindable var rules: RulesManager
    @Bindable var profiles: ApplicationProfileManager
    @Bindable var history: HistoryManager
    @Bindable var onboarding: OnboardingManager
    @Bindable var selection: NatterAppSelection

    var body: some View {
        NavigationSplitView {
            List(selection: $selection.section) {
                ForEach(NatterAppSection.allCases) { section in
                    Label(section.label, systemImage: section.symbol)
                        .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detail
                .navigationTitle(selection.section.label)
        }
        .background(Theme.Colour.panel)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection.section {
        case .home:
            HistoryView(history: history)
        case .modes:
            ModesView(store: store, profiles: profiles)
        case .dictionary:
            DictionaryView(rules: rules) {
                selection.section = .rules
            }
        case .rules:
            RulesEditorView(rules: rules)
        case .settings:
            SettingsView(
                store: store,
                modelManager: modelManager,
                permissions: permissions,
                rules: rules,
                profiles: profiles,
                history: history,
                onboarding: onboarding
            ) {
                selection.section = .home
            }
        }
    }
}
