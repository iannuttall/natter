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
