import AppKit
import DictationCore

@MainActor
final class ModifierHotKeyMonitor {
    private let store: DictationStore
    private let actionHandler: (ModifierHotKeyAction) -> Void
    private var detector = ModifierTapDetector()
    private var holdDetector = ModifierHoldDetector()
    private var edgeTracker = ModifierKeyEdgeTracker()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pressStartedDuringSession = false
    private var startTriggeredForPress = false

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
        edgeTracker.reset()
        detector.reset()
        holdDetector.reset()
    }

    private func handle(_ event: NSEvent) {
        let hotKey = store.selectedHotKey
        guard event.keyCode == hotKey.keyCode else {
            return
        }

        let modifierIsActive = event.modifierFlags.contains(hotKey.modifierFlag)
        let pressed = edgeTracker.observe(isActive: modifierIsActive)
        let sessionIsActive = store.phase == .preparing || store.phase == .listening

        if !modifierIsActive {
            guard let gesture = holdDetector.keyUp(at: event.timestamp) else { return }
            defer {
                pressStartedDuringSession = false
                startTriggeredForPress = false
            }
            if gesture == .hold {
                detector.reset()
                actionHandler(.cycleMode)
            } else if pressStartedDuringSession && !startTriggeredForPress {
                actionHandler(.stop)
            }
            return
        }
        guard pressed else { return }

        pressStartedDuringSession = sessionIsActive
        startTriggeredForPress = false
        holdDetector.keyDown(at: event.timestamp)
        if !sessionIsActive, let action = detector.keyDown(
            at: event.timestamp,
            sessionIsActive: false
        ) {
            startTriggeredForPress = action == .start
            actionHandler(action)
        }
    }
}

private extension ModifierHotKey {
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: .option
        case .rightControl: .control
        }
    }
}
