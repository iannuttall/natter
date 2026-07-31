import AppKit
import DictationCore

@MainActor
final class ModifierHotKeyMonitor {
    private let store: DictationStore
    private let actionHandler: (ModifierHotKeyAction) -> Void
    private var detector = ModifierTapDetector()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    init(
        store: DictationStore,
        actionHandler: @escaping (ModifierHotKeyAction) -> Void
    ) {
        self.store = store
        self.actionHandler = actionHandler
    }

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        let hotKey = store.selectedHotKey
        guard event.keyCode == hotKey.keyCode,
              CGEventSource.keyState(
                  .combinedSessionState,
                  key: CGKeyCode(hotKey.keyCode)
              ) else {
            return
        }

        let sessionIsActive = store.phase == .preparing || store.phase == .listening
        if let action = detector.keyDown(
            at: event.timestamp,
            sessionIsActive: sessionIsActive
        ) {
            actionHandler(action)
        }
    }

}
