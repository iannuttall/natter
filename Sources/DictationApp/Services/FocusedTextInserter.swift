import AppKit
import ApplicationServices
import DictationCore
import Foundation

struct FocusedTextTarget {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let applicationName: String?
    let element: AXUIElement?
    let window: AXUIElement?
    let elementFingerprint: AccessibilityFingerprint?
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
    private static let directAccessibilityBundleIdentifiers: Set<String> = [
        "com.conductor.app"
    ]
    private let eventPoster = KeyboardEventPoster()

    func captureTarget() throws -> FocusedTextTarget {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            throw FocusedTextInsertionError.accessibilityPermissionRequired
        }
        guard let workspaceApplication = NSWorkspace.shared.frontmostApplication else {
            throw FocusedTextInsertionError.noFocusedApplication
        }

        let systemWide = AXUIElementCreateSystemWide()
        let systemFocusedElement = try? copyFocusedElement(from: systemWide)
        let systemFocusedApplication = systemFocusedElement
            .flatMap { element -> NSRunningApplication? in
                guard isEditableTextControl(element),
                      let processIdentifier = processIdentifier(of: element) else {
                    return nil
                }
                return NSRunningApplication(processIdentifier: processIdentifier)
            }
        let application = systemFocusedApplication ?? workspaceApplication

        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedElement = systemFocusedElement.flatMap {
            belongsToProcess($0, processIdentifier: application.processIdentifier) ? $0 : nil
        } ?? (try? copyFocusedElement(from: appElement))
        let editableElement = focusedElement.flatMap {
            isEditableTextControl($0) ? $0 : nil
        }
        let focusedWindow = focusedElement.flatMap {
            copyElementAttribute(kAXWindowAttribute, from: $0)
        }
            ?? copyElementAttribute(kAXFocusedWindowAttribute, from: appElement)
        return FocusedTextTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName,
            element: editableElement,
            window: focusedWindow,
            elementFingerprint: editableElement.map(fingerprint),
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

        let payload = TextInsertionPlan.insertionText(for: text, destination: applicationKind)
        guard !payload.isEmpty else { return }

        if let bundleIdentifier = target.bundleIdentifier?.lowercased(),
           Self.directAccessibilityBundleIdentifiers.contains(bundleIdentifier),
           NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
           let capturedElement = target.element,
           belongsToProcess(capturedElement, processIdentifier: target.processIdentifier),
           eventPoster.insertThroughAccessibility(payload, into: capturedElement) {
            NatterLog.delivery.notice("text inserted through captured accessibility element")
            return
        }

        // Standard apps take the whole transcript, newlines included, in a
        // single paste. Terminals stay on the paced per-character path.
        let chunks = applicationKind == .standard
            ? [payload]
            : TextInsertionPlan.chunks(for: payload, maximumCharacterCount: 16)
        for (chunkIndex, chunk) in chunks.enumerated() {
            let element = try validate(target)
            try await eventPoster.postText(
                chunk,
                into: element,
                destination: applicationKind
            )

            if chunkIndex < chunks.index(before: chunks.endIndex),
               paceTerminalInput,
               applicationKind == .terminal {
                try await Task.sleep(for: Self.terminalChunkDelay)
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
                _ = try validate(target)
            }
            try eventPoster.postBackspace()

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

    func submit(in target: FocusedTextTarget) async throws {
        try await Task.sleep(for: .milliseconds(40))
        _ = try validate(target)
        try eventPoster.postReturn()
    }

    private func validate(_ target: FocusedTextTarget) throws -> AXUIElement? {
        let systemFocusedElement = try? copyFocusedElement(
            from: AXUIElementCreateSystemWide()
        )
        let systemFocusBelongsToTarget = systemFocusedElement.map {
            belongsToProcess($0, processIdentifier: target.processIdentifier)
        } ?? false
        let workspaceFocusBelongsToTarget = NSWorkspace.shared.frontmostApplication?
            .processIdentifier == target.processIdentifier
        guard systemFocusBelongsToTarget || workspaceFocusBelongsToTarget else {
            throw FocusedTextInsertionError.focusChanged
        }

        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        let current = systemFocusBelongsToTarget
            ? systemFocusedElement
            : (try? copyFocusedElement(from: appElement))
        let currentEditable = current.flatMap { isEditableTextControl($0) ? $0 : nil }
        if let targetWindow = target.window,
           let currentWindow = copyElementAttribute(kAXFocusedWindowAttribute, from: appElement),
           !CFEqual(currentWindow, targetWindow),
           let expected = target.windowFingerprint,
           !fingerprint(of: currentWindow).matches(expected) {
            throw FocusedTextInsertionError.focusChanged
        }

        // React and other rich editors can replace their accessibility node
        // after every edit. The frontmost process and window are stable; use
        // whichever editable node is focused now, or fall back to Cmd-V when
        // the editor temporarily exposes only its web container.
        return currentEditable
    }

    private func belongsToProcess(
        _ element: AXUIElement,
        processIdentifier targetProcessIdentifier: pid_t
    ) -> Bool {
        processIdentifier(of: element) == targetProcessIdentifier
    }

    private func processIdentifier(of element: AXUIElement) -> pid_t? {
        var identifier = pid_t.zero
        guard AXUIElementGetPid(element, &identifier) == .success else { return nil }
        return identifier
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

    private func isEditableTextControl(_ element: AXUIElement) -> Bool {
        var selectedTextIsSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedTextIsSettable
        )
        return EditableTextTargetPolicy.accepts(
            role: copyStringAttribute(kAXRoleAttribute, from: element),
            selectedTextIsSettable: settableResult == .success
                && selectedTextIsSettable.boolValue
        )
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
