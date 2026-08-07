import AppKit
import SwiftUI

private final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class OverlayPanelController {
    var onCancel: (() -> Void)?
    var onCycleMode: (() -> Void)?
    private let panel: NSPanel
    private let store: DictationStore
    private let frameAutosaveName = "DictationOverlayFrame"

    init(store: DictationStore, modes: ModeManager) {
        self.store = store
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 166),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = OverlayHostingView(rootView: OverlayView(
            store: store,
            modes: modes,
            onCycleMode: { [weak self] in self?.onCycleMode?() },
            onCancel: { [weak self] in
                NatterLog.app.notice("overlay cancel clicked")
                self?.onCancel?()
            }
        ))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = false
        panel.setFrameAutosaveName(frameAutosaveName)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func show() {
        guard store.overlayStyle != .hidden else {
            hide()
            return
        }
        resizeForCurrentStyle()
        if !panel.setFrameUsingName(frameAutosaveName) {
            positionOnCurrentScreen()
        } else {
            keepOnScreen()
        }
        panel.orderFrontRegardless()
    }

    private func resizeForCurrentStyle() {
        let size = switch store.overlayStyle {
        case .full: NSSize(width: 440, height: 166)
        case .compact: NSSize(width: 250, height: 56)
        case .hidden: NSSize.zero
        }
        guard size != .zero else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func keepOnScreen() {
        guard !NSScreen.screens.contains(where: {
            $0.visibleFrame.intersects(panel.frame)
        }) else { return }
        positionOnCurrentScreen()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func positionOnCurrentScreen() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + 72
        )
        panel.setFrameOrigin(origin)
    }
}
