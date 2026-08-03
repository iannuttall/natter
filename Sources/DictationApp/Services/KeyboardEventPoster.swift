import AppKit
import Carbon.HIToolbox
import CoreGraphics
import DictationCore
import Foundation

@MainActor
final class KeyboardEventPoster {
    private let eventSource = CGEventSource(stateID: .combinedSessionState)
    private var keyboardLayout: PhysicalKeyboardLayout?

    func postText(
        _ text: String,
        into element: AXUIElement?,
        destination: DestinationApplicationKind
    ) async throws {
        guard !text.isEmpty else { return }
        try requirePostEventPermission()

        // Paste is the common input path understood by AppKit, WebKit and
        // Chromium editors. Direct AXSelectedText writes can report success
        // while controlled React editors silently discard the change.
        if destination == .standard {
            try await pasteTemporarily(text)
            return
        }

        refreshKeyboardLayout()

        var unsupported = ""
        for character in text {
            if let stroke = keyboardLayout?.strokes[character] {
                try await flushUnsupported(
                    &unsupported,
                    into: element,
                    destination: destination
                )
                try postKey(code: stroke.keyCode, flags: stroke.flags)
            } else {
                unsupported.append(character)
            }
        }
        try await flushUnsupported(
            &unsupported,
            into: element,
            destination: destination
        )
    }

    func postBackspace() throws {
        try requirePostEventPermission()
        try postKey(code: 51)
    }

    private func flushUnsupported(
        _ text: inout String,
        into element: AXUIElement?,
        destination: DestinationApplicationKind
    ) async throws {
        guard !text.isEmpty else { return }
        let pending = text
        text = ""

        if let element, replaceSelection(with: pending, in: element) { return }

        if destination == .terminal {
            try postUnicode(pending)
        } else {
            try await pasteTemporarily(pending)
        }
    }

    private func replaceSelection(with text: String, in element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }

    private func pasteTemporarily(_ text: String) async throws {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw FocusedTextInsertionError.eventCreationFailed
        }
        let temporaryChangeCount = pasteboard.changeCount

        try postKey(code: 9, flags: .maskCommand)
        // Electron and browser paste handlers may read the pasteboard on a later
        // run-loop turn, so keep the temporary value alive long enough for them.
        try await Task.sleep(for: .milliseconds(120))

        // Never overwrite something the user copied while the paste was in flight.
        if pasteboard.changeCount == temporaryChangeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    private func postKey(
        code: CGKeyCode,
        flags: CGEventFlags = []
    ) throws {
        guard let eventSource,
              let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: code,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: code,
                keyDown: false
              ) else {
            throw FocusedTextInsertionError.eventCreationFailed
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func postUnicode(_ text: String) throws {
        guard let eventSource,
              let keyDown = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: 0,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: eventSource,
                virtualKey: 0,
                keyDown: false
              ) else {
            throw FocusedTextInsertionError.eventCreationFailed
        }

        let units = Array(text.utf16)
        units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.flags = []
        keyUp.flags = []
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func requirePostEventPermission() throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            throw FocusedTextInsertionError.accessibilityPermissionRequired
        }
    }

    private func refreshKeyboardLayout() {
        guard let identifier = PhysicalKeyboardLayout.currentIdentifier(),
              identifier != keyboardLayout?.identifier else {
            return
        }
        keyboardLayout = PhysicalKeyboardLayout.current()
    }
}

private struct PhysicalKeyStroke {
    let keyCode: CGKeyCode
    let flags: CGEventFlags
}

private struct PhysicalKeyboardLayout {
    let identifier: String
    let strokes: [Character: PhysicalKeyStroke]

    static func currentIdentifier() -> String? {
        guard let unmanagedSource = TISCopyCurrentKeyboardLayoutInputSource() else {
            return nil
        }
        let source = unmanagedSource.takeRetainedValue()
        guard let rawIdentifier = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceID
        ) else {
            return nil
        }
        return unsafeBitCast(rawIdentifier, to: CFString.self) as String
    }

    static func current() -> Self? {
        guard let unmanagedSource = TISCopyCurrentKeyboardLayoutInputSource() else {
            return nil
        }
        let source = unmanagedSource.takeRetainedValue()
        guard let rawIdentifier = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceID
        ), let rawLayout = TISGetInputSourceProperty(
            source,
            kTISPropertyUnicodeKeyLayoutData
        ) else {
            return nil
        }

        let identifier = unsafeBitCast(rawIdentifier, to: CFString.self) as String
        let layoutData = unsafeBitCast(rawLayout, to: CFData.self)
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes)
            .assumingMemoryBound(to: UCKeyboardLayout.self)

        let modifiers: [(carbon: UInt32, event: CGEventFlags)] = [
            (0, []),
            (UInt32(shiftKey >> 8), .maskShift),
            (UInt32(optionKey >> 8), .maskAlternate),
            (UInt32((shiftKey | optionKey) >> 8), [.maskShift, .maskAlternate])
        ]
        var strokes: [Character: PhysicalKeyStroke] = [:]

        for keyCode in UInt16(0)..<UInt16(128) {
            for modifier in modifiers {
                var deadKeyState: UInt32 = 0
                var characters = [UniChar](repeating: 0, count: 8)
                var length = 0
                let result = UCKeyTranslate(
                    layout,
                    keyCode,
                    UInt16(kUCKeyActionDown),
                    modifier.carbon,
                    UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    characters.count,
                    &length,
                    &characters
                )
                guard result == noErr, length > 0 else { continue }

                let value = String(utf16CodeUnits: characters, count: length)
                guard value.count == 1,
                      value.rangeOfCharacter(from: .controlCharacters) == nil,
                      let character = value.first,
                      strokes[character] == nil else {
                    continue
                }
                strokes[character] = PhysicalKeyStroke(
                    keyCode: keyCode,
                    flags: modifier.event
                )
            }
        }

        return Self(identifier: identifier, strokes: strokes)
    }
}

private struct PasteboardSnapshot {
    let items: [NSPasteboardItem]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
