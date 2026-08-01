import AppKit
import ApplicationServices
import DictationCore
import Foundation

struct FocusedTextTarget {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let applicationName: String?
    let element: AXUIElement
    let window: AXUIElement?
    let elementFingerprint: AccessibilityFingerprint
    let windowFingerprint: AccessibilityFingerprint?
}

struct AccessibilityFingerprint {
    let role: String?
    let subrole: String?
    let identifier: String?
    let description: String?
    let title: String?
    let position: CGPoint?
    let size: CGSize?
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
    private static let lineBreakDelay = Duration.milliseconds(8)

    func captureTarget() throws -> FocusedTextTarget {
        guard AXIsProcessTrusted() else {
            throw FocusedTextInsertionError.accessibilityPermissionRequired
        }
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw FocusedTextInsertionError.noFocusedApplication
        }

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedElement = try copyFocusedElement(from: appElement)
        let focusedWindow = copyElementAttribute(
            kAXFocusedWindowAttribute,
            from: appElement
        )
        return FocusedTextTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName,
            element: focusedElement,
            window: focusedWindow,
            elementFingerprint: fingerprint(of: focusedElement),
            windowFingerprint: focusedWindow.map(fingerprint)
        )
    }

    func insert(
        _ text: String,
        into target: FocusedTextTarget,
        paceTerminalInput: Bool
    ) async throws {
        guard !text.isEmpty else { return }
        let applicationKind = DestinationApplicationKind.classify(
            bundleIdentifier: target.bundleIdentifier
        )

        let segments = TextInsertionPlan.segments(for: text, destination: applicationKind)
        for (segmentIndex, segment) in segments.enumerated() {
            switch segment {
            case let .text(value):
                let chunks = value.utf16Chunks(maximumCount: 16)
                for (chunkIndex, chunk) in chunks.enumerated() {
                    try validate(target)
                    try postUnicode(chunk, to: target.processIdentifier)

                    if paceTerminalInput,
                       applicationKind == .terminal,
                       (chunkIndex < chunks.index(before: chunks.endIndex)
                        || segmentIndex < segments.index(before: segments.endIndex)) {
                        try await Task.sleep(for: Self.terminalChunkDelay)
                    }
                }
            case .lineBreak:
                try validate(target)
                try postKey(code: 36, to: target.processIdentifier)
                try await Task.sleep(for: Self.lineBreakDelay)
            }
        }
    }

    func replaceInsertedText(
        _ insertedText: String,
        with replacement: String,
        in target: FocusedTextTarget,
        paceTerminalInput: Bool
    ) async throws {
        let applicationKind = DestinationApplicationKind.classify(
            bundleIdentifier: target.bundleIdentifier
        )

        for (index, _) in insertedText.enumerated() {
            if index.isMultiple(of: 16) {
                try validate(target)
            }
            try postKey(code: 51, to: target.processIdentifier)

            if paceTerminalInput,
               applicationKind == .terminal,
               index > 0,
               index.isMultiple(of: 16) {
                try await Task.sleep(for: Self.terminalChunkDelay)
            }
        }

        try await insert(
            replacement,
            into: target,
            paceTerminalInput: paceTerminalInput
        )
    }

    private func postKey(code: CGKeyCode, to processIdentifier: pid_t) throws {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: code,
            keyDown: true
        ), let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: code,
            keyDown: false
        ) else {
            throw FocusedTextInsertionError.eventCreationFailed
        }
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }

    private func postUnicode(_ units: [UniChar], to processIdentifier: pid_t) throws {
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
        units.withUnsafeBufferPointer { buffer in
            keyDown.keyboardSetUnicodeString(
                stringLength: buffer.count,
                unicodeString: buffer.baseAddress
            )
        }
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }

    private func validate(_ target: FocusedTextTarget) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
            == target.processIdentifier else {
            throw FocusedTextInsertionError.focusChanged
        }

        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        let current = try copyFocusedElement(from: appElement)
        guard CFEqual(current, target.element)
                || fingerprint(of: current).matches(target.elementFingerprint) else {
            throw FocusedTextInsertionError.focusChanged
        }
        if let targetWindow = target.window,
           let currentWindow = copyElementAttribute(kAXFocusedWindowAttribute, from: appElement),
           !CFEqual(currentWindow, targetWindow),
           let expected = target.windowFingerprint,
           !fingerprint(of: currentWindow).matches(expected) {
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

    private func copyElementAttribute(
        _ attribute: String,
        from element: AXUIElement
    ) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func fingerprint(of element: AXUIElement) -> AccessibilityFingerprint {
        AccessibilityFingerprint(
            role: copyStringAttribute(kAXRoleAttribute, from: element),
            subrole: copyStringAttribute(kAXSubroleAttribute, from: element),
            identifier: copyStringAttribute(kAXIdentifierAttribute, from: element),
            description: copyStringAttribute(kAXDescriptionAttribute, from: element),
            title: copyStringAttribute(kAXTitleAttribute, from: element),
            position: copyPointAttribute(kAXPositionAttribute, from: element),
            size: copySizeAttribute(kAXSizeAttribute, from: element)
        )
    }

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func copyPointAttribute(_ attribute: String, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var point = CGPoint.zero
        return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
    }

    private func copySizeAttribute(_ attribute: String, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(value, to: AXValue.self)
        var size = CGSize.zero
        return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
    }
}

private extension AccessibilityFingerprint {
    func matches(_ other: Self) -> Bool {
        guard role == other.role, subrole == other.subrole else { return false }

        if let identifier, let otherIdentifier = other.identifier,
           !identifier.isEmpty, !otherIdentifier.isEmpty {
            return identifier == otherIdentifier
        }

        // Rich web editors often expose their current text as the AX title or
        // description, and their bounds grow as text arrives. App + window +
        // role + overlapping bounds is the stable identity in that case.
        return geometryOverlaps(other)
    }

    private func geometryOverlaps(_ other: Self) -> Bool {
        guard let position, let size, let otherPosition = other.position,
              let otherSize = other.size else { return true }
        let rectangle = CGRect(origin: position, size: size)
        let otherRectangle = CGRect(origin: otherPosition, size: otherSize)
        guard !rectangle.isEmpty, !otherRectangle.isEmpty else { return true }
        let intersection = rectangle.intersection(otherRectangle)
        guard !intersection.isNull else { return false }
        let smallerArea = min(rectangle.width * rectangle.height,
                              otherRectangle.width * otherRectangle.height)
        return intersection.width * intersection.height >= smallerArea * 0.45
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
