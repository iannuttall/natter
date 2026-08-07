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
    case arm
    case start
    case stop
    case cycleMode
    case cancel
}

public enum CancelModifierTapEvent: Equatable, Sendable {
    case passThrough
    case cancel
}

public struct CancelModifierTapDetector: Sendable {
    public static let leftOptionKeyCode: UInt16 = 58

    public let doubleTapInterval: TimeInterval
    private var firstTapTime: TimeInterval?
    private var isDown = false

    public init(doubleTapInterval: TimeInterval = 0.42) {
        self.doubleTapInterval = doubleTapInterval
    }

    public mutating func observe(
        keyCode: UInt16,
        isDown: Bool,
        at time: TimeInterval,
        sessionIsActive: Bool
    ) -> CancelModifierTapEvent {
        guard keyCode == Self.leftOptionKeyCode else {
            return .passThrough
        }

        guard sessionIsActive else {
            reset()
            return .passThrough
        }

        let isPress = isDown && !self.isDown
        self.isDown = isDown
        guard isPress else { return .passThrough }

        guard let firstTapTime else {
            self.firstTapTime = time
            return .passThrough
        }

        let elapsed = time - firstTapTime
        if elapsed >= 0, elapsed <= doubleTapInterval {
            self.firstTapTime = nil
            return .cancel
        }

        self.firstTapTime = time
        return .passThrough
    }

    public mutating func reset() {
        firstTapTime = nil
        isDown = false
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
            return .arm
        }

        let elapsed = time - firstTapTime
        guard elapsed >= 0, elapsed <= doubleTapInterval else {
            self.firstTapTime = time
            return .arm
        }

        self.firstTapTime = nil
        return .start
    }

    public mutating func reset() {
        firstTapTime = nil
    }
}
