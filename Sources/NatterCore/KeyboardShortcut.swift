public struct DictationShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let shift = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let control = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
}

public struct DictationShortcut: Equatable, Sendable {
    public let keyCode: UInt16
    public let modifiers: DictationShortcutModifiers

    public init(keyCode: UInt16, modifiers: DictationShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public func matches(
        keyCode: UInt16,
        modifiers: DictationShortcutModifiers
    ) -> Bool {
        self.keyCode == keyCode && self.modifiers == modifiers
    }

    /// Command-Shift-M. Kept as one value so shortcut customization can replace
    /// the default without changing the event monitor or mode-cycling behavior.
    public static let defaultModeCycle = Self(
        keyCode: 46,
        modifiers: [.command, .shift]
    )
}
