import Foundation

public enum ModifierHotKey: String, CaseIterable, Codable, Identifiable, Sendable {
    case rightOption
    case rightControl

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightControl: "Right Control"
        }
    }

    public var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightControl: 62
        }
    }
}

public enum ModifierHotKeyAction: Equatable, Sendable {
    case start
    case stop
    case cycleMode
    case cancel
}

public enum CancelModifierChordEvent: Equatable, Sendable {
    case passThrough
    case cancel
    case suppress
}

public struct CancelModifierChordDetector: Sendable {
    private var downKeyCodes: Set<UInt16> = []
    private var chordIsActive = false

    public init() {}

    public mutating func observe(
        keyCode: UInt16,
        isDown: Bool,
        sessionIsActive: Bool
    ) -> CancelModifierChordEvent {
        guard keyCode == ModifierHotKey.rightOption.keyCode
                || keyCode == ModifierHotKey.rightControl.keyCode else {
            return .passThrough
        }

        if isDown {
            downKeyCodes.insert(keyCode)
        } else {
            downKeyCodes.remove(keyCode)
        }

        if chordIsActive {
            if downKeyCodes.isEmpty { chordIsActive = false }
            return .suppress
        }

        if sessionIsActive,
           downKeyCodes.contains(ModifierHotKey.rightOption.keyCode),
           downKeyCodes.contains(ModifierHotKey.rightControl.keyCode) {
            chordIsActive = true
            return .cancel
        }
        return .passThrough
    }

    public mutating func reset() {
        downKeyCodes = []
        chordIsActive = false
    }
}

public enum ModifierPressGesture: Equatable, Sendable {
    case tap
    case hold
}

public struct ModifierHoldDetector: Sendable {
    public let holdInterval: TimeInterval
    private var pressedAt: TimeInterval?

    public init(holdInterval: TimeInterval = 0.6) {
        self.holdInterval = holdInterval
    }

    public mutating func keyDown(at time: TimeInterval) {
        pressedAt = time
    }

    public mutating func keyUp(at time: TimeInterval) -> ModifierPressGesture? {
        defer { pressedAt = nil }
        guard let pressedAt else { return nil }
        return time - pressedAt >= holdInterval ? .hold : .tap
    }

    public mutating func reset() {
        pressedAt = nil
    }
}

public struct ModifierKeyEdgeTracker: Sendable {
    private var isDown = false

    public init() {}

    public mutating func observe(isActive: Bool) -> Bool {
        defer { isDown = isActive }
        return isActive && !isDown
    }

    public mutating func reset() {
        isDown = false
    }
}

public struct ModifierTapDetector: Sendable {
    public let doubleTapInterval: TimeInterval
    private var firstTapTime: TimeInterval?

    public init(doubleTapInterval: TimeInterval = 0.42) {
        self.doubleTapInterval = doubleTapInterval
    }

    public mutating func keyDown(
        at time: TimeInterval,
        sessionIsActive: Bool
    ) -> ModifierHotKeyAction? {
        if sessionIsActive {
            firstTapTime = nil
            return .stop
        }

        guard let firstTapTime else {
            self.firstTapTime = time
            return nil
        }

        let elapsed = time - firstTapTime
        guard elapsed >= 0, elapsed <= doubleTapInterval else {
            self.firstTapTime = time
            return nil
        }

        self.firstTapTime = nil
        return .start
    }

    public mutating func reset() {
        firstTapTime = nil
    }
}
