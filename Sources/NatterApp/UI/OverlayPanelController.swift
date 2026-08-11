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
    private let defaultScreenInset: CGFloat = 24
    private var hasPreparedInitialFrame = false

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
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    func show() {
        guard store.overlayStyle != .hidden else {
            hide()
            return
        }

        if hasPreparedInitialFrame {
            resizeForCurrentStyle()
            keepOnScreen()
        } else {
            let restoredFrame = panel.setFrameUsingName(frameAutosaveName)
            resizeForCurrentStyle()
            if !restoredFrame {
                positionOnCurrentScreen()
            } else {
                keepOnScreen()
            }
            panel.setFrameAutosaveName(frameAutosaveName)
            hasPreparedInitialFrame = true
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
        guard let screen = NSScreen.screens.max(by: {
            intersectionArea(of: panel.frame, with: $0.visibleFrame)
                < intersectionArea(of: panel.frame, with: $1.visibleFrame)
        }), intersectionArea(of: panel.frame, with: screen.visibleFrame) > 0 else {
            positionOnCurrentScreen()
            return
        }

        let visibleFrame = screen.visibleFrame
        var frame = panel.frame
        frame.origin.x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - frame.height)
        if frame.origin != panel.frame.origin {
            panel.setFrameOrigin(frame.origin)
        }
    }

    private func intersectionArea(of frame: NSRect, with visibleFrame: NSRect) -> CGFloat {
        let intersection = frame.intersection(visibleFrame)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
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
            x: visibleFrame.maxX - panel.frame.width - defaultScreenInset,
            y: visibleFrame.minY + defaultScreenInset
        )
        panel.setFrameOrigin(origin)
    }
}
