import AppKit
import CoreGraphics
import DictationCore

private struct ModifierFlagsEvent: Sendable {
    let keyCode: UInt16
    let flags: CGEventFlags
    let timestamp: TimeInterval
}

private final class HotKeyEventSink: @unchecked Sendable {
    let eventHandler: @Sendable (ModifierFlagsEvent) -> Void
    let disabledHandler: @Sendable () -> Void

    init(
        eventHandler: @escaping @Sendable (ModifierFlagsEvent) -> Void,
        disabledHandler: @escaping @Sendable () -> Void
    ) {
        self.eventHandler = eventHandler
        self.disabledHandler = disabledHandler
    }
}

private func modifierEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let sink = Unmanaged<HotKeyEventSink>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        sink.disabledHandler()
        return Unmanaged.passUnretained(event)
    }
    guard type == .flagsChanged else { return Unmanaged.passUnretained(event) }

    sink.eventHandler(ModifierFlagsEvent(
        keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
        flags: event.flags,
        timestamp: Double(event.timestamp) / 1_000_000_000
    ))
    return Unmanaged.passUnretained(event)
}

@MainActor
final class ModifierHotKeyMonitor {
    private let store: DictationStore
    private let actionHandler: (ModifierHotKeyAction) -> Void
    private let eventObservationHandler: () -> Void
    private var detector = ModifierTapDetector()
    private var holdDetector = ModifierHoldDetector()
    private var edgeTracker = ModifierKeyEdgeTracker()
    private var cancelChordDetector = CancelModifierChordDetector()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var eventSinkPointer: UnsafeMutableRawPointer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var watchdog: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObserver: NSObjectProtocol?
    private var pressStartedDuringSession = false
    private var startTriggeredForPress = false
    private var hasProvenInputMonitoring = false
    private var lastHandledEvent: (keyCode: UInt16, active: Bool, timestamp: TimeInterval)?

    init(
        store: DictationStore,
        eventObservationHandler: @escaping () -> Void = {},
        actionHandler: @escaping (ModifierHotKeyAction) -> Void
    ) {
        self.store = store
        self.eventObservationHandler = eventObservationHandler
        self.actionHandler = actionHandler
    }

    func start() {
        installEventTapIfNeeded(reason: "start")
        installNSEventMonitorsIfNeeded()
        guard watchdog == nil else { return }
        watchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.keepEventTapAlive(reason: "watchdog") }
        }
        registerSystemObservers()
    }

    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        removeSystemObservers()
        removeNSEventMonitors()
        tearDownEventTap()
        resetDetectors()
    }

    func restart() {
        tearDownEventTap()
        installEventTapIfNeeded(reason: "permission-change")
        removeNSEventMonitors()
        installNSEventMonitorsIfNeeded()
    }

    private func installEventTapIfNeeded(reason: String) {
        guard eventTap == nil else {
            keepEventTapAlive(reason: reason)
            return
        }

        let sink = HotKeyEventSink(
            eventHandler: { [weak self] event in
                DispatchQueue.main.async { self?.handle(event) }
            },
            disabledHandler: { [weak self] in
                DispatchQueue.main.async { self?.keepEventTapAlive(reason: "disabled") }
            }
        )
        let pointer = Unmanaged.passRetained(sink).toOpaque()
        let mask = CGEventMask(1) << CGEventType.flagsChanged.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: modifierEventTapCallback,
            userInfo: pointer
        ) else {
            Unmanaged<HotKeyEventSink>.fromOpaque(pointer).release()
            NatterLog.hotKey.error(
                "could not create event tap reason=\(reason, privacy: .public)"
            )
            return
        }

        eventTap = tap
        eventSinkPointer = pointer
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NatterLog.hotKey.notice("event tap active reason=\(reason, privacy: .public)")
    }

    private func keepEventTapAlive(reason: String) {
        guard let eventTap else {
            installEventTapIfNeeded(reason: reason)
            return
        }
        guard !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        if !CGEvent.tapIsEnabled(tap: eventTap) {
            tearDownEventTap()
            installEventTapIfNeeded(reason: reason)
        } else {
            NatterLog.hotKey.notice("event tap re-enabled reason=\(reason, privacy: .public)")
        }
    }

    private func tearDownEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        if let eventSinkPointer {
            Unmanaged<HotKeyEventSink>.fromOpaque(eventSinkPointer).release()
        }
        eventSinkPointer = nil
    }

    private func installNSEventMonitorsIfNeeded() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            let sample = Self.sample(from: event)
            DispatchQueue.main.async { self?.handle(sample) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
            [weak self] event in
            let sample = Self.sample(from: event)
            DispatchQueue.main.async { self?.handle(sample) }
            return event
        }
    }

    private func removeNSEventMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private static func sample(from event: NSEvent) -> ModifierFlagsEvent {
        var flags: CGEventFlags = []
        if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
        if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
        return ModifierFlagsEvent(
            keyCode: event.keyCode,
            flags: flags,
            timestamp: event.timestamp
        )
    }

    private func registerSystemObservers() {
        guard workspaceObservers.isEmpty, applicationObserver == nil else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.recreateAfterSystemTransition(name.rawValue) }
            })
        }
        applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.keepEventTapAlive(reason: "application-active") }
        }
    }

    private func removeSystemObservers() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers = []
        if let applicationObserver { NotificationCenter.default.removeObserver(applicationObserver) }
        applicationObserver = nil
    }

    private func recreateAfterSystemTransition(_ reason: String) {
        resetDetectors()
        tearDownEventTap()
        installEventTapIfNeeded(reason: reason)
    }

    private func resetDetectors() {
        edgeTracker.reset()
        detector.reset()
        holdDetector.reset()
        cancelChordDetector.reset()
        pressStartedDuringSession = false
        startTriggeredForPress = false
        lastHandledEvent = nil
    }

    private func handle(_ event: ModifierFlagsEvent) {
        if !hasProvenInputMonitoring {
            hasProvenInputMonitoring = true
            eventObservationHandler()
            NatterLog.hotKey.notice("input monitoring proven by delivered event")
        }

        let eventModifierIsActive = event.flags.contains(
            ModifierHotKey.modifierFlag(for: event.keyCode)
        )
        if let lastHandledEvent,
           lastHandledEvent.keyCode == event.keyCode,
           lastHandledEvent.active == eventModifierIsActive,
           abs(lastHandledEvent.timestamp - event.timestamp) < 0.01 {
            return
        }
        lastHandledEvent = (event.keyCode, eventModifierIsActive, event.timestamp)

        let hotKey = store.selectedHotKey
        let sessionIsActive = store.phase == .preparing || store.phase == .listening
        switch cancelChordDetector.observe(
            keyCode: event.keyCode,
            isDown: eventModifierIsActive,
            sessionIsActive: sessionIsActive
        ) {
        case .cancel:
            resetDetectors()
            actionHandler(.cancel)
            return
        case .suppress:
            return
        case .passThrough:
            break
        }

        guard event.keyCode == hotKey.keyCode else { return }
        let modifierIsActive = event.flags.contains(hotKey.modifierFlag)
        let pressed = edgeTracker.observe(isActive: modifierIsActive)
        NatterLog.hotKey.debug(
            "modifier event active=\(modifierIsActive) edge=\(pressed) timestamp=\(String(format: "%.3f", event.timestamp), privacy: .public)"
        )

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
            NatterLog.hotKey.debug("modifier action=\(String(describing: action), privacy: .public)")
            startTriggeredForPress = action == .start
            actionHandler(action)
        }
    }
}

private extension ModifierHotKey {
    var modifierFlag: CGEventFlags {
        switch self {
        case .rightOption: .maskAlternate
        case .rightControl: .maskControl
        }
    }

    static func modifierFlag(for keyCode: UInt16) -> CGEventFlags {
        switch keyCode {
        case ModifierHotKey.rightOption.keyCode: .maskAlternate
        case ModifierHotKey.rightControl.keyCode: .maskControl
        default: []
        }
    }
}
