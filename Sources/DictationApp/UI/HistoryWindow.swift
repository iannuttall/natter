import AppKit
import SwiftUI

@MainActor
final class HistoryWindow: NSObject, NSWindowDelegate {
    static let shared = HistoryWindow()

    private var window: NSWindow?

    func show(history: HistoryManager) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppInfo.displayName) History"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 560)
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: HistoryView(history: history))
        self.window = window

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
