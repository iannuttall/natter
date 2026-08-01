import AppKit
import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()

    private var window: NSWindow?

    func show(
        store: DictationStore,
        modelManager: ModelManager,
        permissions: PermissionController,
        rules: RulesManager,
        profiles: ApplicationProfileManager,
        history: HistoryManager,
        onboarding: OnboardingManager
    ) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.displayName) Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: SettingsView(
                store: store,
                modelManager: modelManager,
                permissions: permissions,
                rules: rules,
                profiles: profiles,
                history: history,
                onboarding: onboarding
            )
        )
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
