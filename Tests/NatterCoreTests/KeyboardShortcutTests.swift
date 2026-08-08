import Testing
@testable import NatterCore

@Test func modeCycleShortcutRequiresCommandShiftM() {
    let shortcut = DictationShortcut.defaultModeCycle

    #expect(shortcut.matches(
        keyCode: 46,
        modifiers: [.command, .shift]
    ))
    #expect(!shortcut.matches(
        keyCode: 48,
        modifiers: []
    ))
    #expect(!shortcut.matches(
        keyCode: 46,
        modifiers: []
    ))
    #expect(!shortcut.matches(
        keyCode: 46,
        modifiers: [.command, .shift, .option]
    ))
}
