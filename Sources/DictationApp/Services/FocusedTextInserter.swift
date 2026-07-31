import AppKit
import ApplicationServices
import DictationCore
import Foundation

struct FocusedTextTarget {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let element: AXUIElement
}

enum FocusedTextInsertionError: LocalizedError {
    case accessibilityPermissionRequired
    case noFocusedApplication
    case noFocusedTextControl
    case focusChanged
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionRequired:
            "Accessibility permission is required to type the transcript."
        case .noFocusedApplication:
            "No destination app was focused when dictation started."
        case .noFocusedTextControl:
            "No editable text control was focused when dictation started."
        case .focusChanged:
            "The destination app or text control changed while you were speaking."
        case .eventCreationFailed:
            "macOS could not create a keyboard event for the transcript."
        }
    }
}

@MainActor
final class FocusedTextInserter {
    // Codex classifies character gaps of 8 ms or less as a paste burst.
    // Keep terminal chunks above that boundary without slowing normal fields.
    private static let terminalChunkDelay = Duration.milliseconds(12)

    func captureTarget() throws -> FocusedTextTarget {
        guard AXIsProcessTrusted() else {
            throw FocusedTextInsertionError.accessibilityPermissionRequired
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw FocusedTextInsertionError.noFocusedApplication
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedElement = try copyFocusedElement(from: appElement)
        return FocusedTextTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            element: focusedElement
        )
    }

    func insert(_ text: String, into target: FocusedTextTarget) async throws {
        guard !text.isEmpty else { return }
        let chunks = text.utf16Chunks(maximumCount: 16)
        let applicationKind = DestinationApplicationKind.classify(
            bundleIdentifier: target.bundleIdentifier
        )

        for (index, chunk) in chunks.enumerated() {
            try validate(target)
            guard let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: false
            ) else {
                throw FocusedTextInsertionError.eventCreationFailed
            }

            chunk.withUnsafeBufferPointer { units in
                keyDown.keyboardSetUnicodeString(
                    stringLength: units.count,
                    unicodeString: units.baseAddress
                )
            }
            keyDown.postToPid(target.processIdentifier)
            keyUp.postToPid(target.processIdentifier)

            if applicationKind == .terminal, index < chunks.index(before: chunks.endIndex) {
                try await Task.sleep(for: Self.terminalChunkDelay)
            }
        }
    }

    private func validate(_ target: FocusedTextTarget) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.processIdentifier else {
            throw FocusedTextInsertionError.focusChanged
        }

        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        let current = try copyFocusedElement(from: appElement)
        guard CFEqual(current, target.element) else {
            throw FocusedTextInsertionError.focusChanged
        }
    }

    private func copyFocusedElement(from application: AXUIElement) throws -> AXUIElement {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            application,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw FocusedTextInsertionError.noFocusedTextControl
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }
}

private extension String {
    func utf16Chunks(maximumCount: Int) -> [[UniChar]] {
        let units = Array(utf16)
        guard !units.isEmpty else { return [] }
        return stride(from: 0, to: units.count, by: maximumCount).map { start in
            Array(units[start..<Swift.min(start + maximumCount, units.count)])
        }
    }
}
