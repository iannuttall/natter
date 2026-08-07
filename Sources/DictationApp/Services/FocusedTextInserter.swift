import AppKit
import ApplicationServices
import DictationCore
import Foundation

struct FocusedTextTarget {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let applicationName: String?
    let capturedElementRole: String?
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
            "No editable text control is focused in the destination app."
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
        return FocusedTextTarget(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.localizedName,
            capturedElementRole: editableElement.flatMap {
                copyStringAttribute(kAXRoleAttribute, from: $0)
            }
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

        // Standard apps take the whole transcript, newlines included, in a
        // single paste. Terminals stay on the paced per-character path.
        let chunks = applicationKind == .standard
            ? [payload]
            : TextInsertionPlan.chunks(for: payload, maximumCharacterCount: 16)
        for (chunkIndex, chunk) in chunks.enumerated() {
            let element = if applicationKind == .standard {
                try await resolveCurrentEditableElement(for: target)
            } else {
                try validate(target)
            }
            try await eventPoster.postText(
                chunk,
                into: element,
                processIdentifier: target.processIdentifier,
                destination: applicationKind
            )

            if chunkIndex < chunks.index(before: chunks.endIndex),
               paceTerminalInput,
               applicationKind == .terminal {
                try await Task.sleep(for: Self.terminalChunkDelay)
            }
        }
    }

    private func resolveCurrentEditableElement(
        for target: FocusedTextTarget
    ) async throws -> AXUIElement? {
        for attempt in 0..<3 {
            if let element = try validate(target) { return element }
            if attempt < 2 {
                try await Task.sleep(for: .milliseconds(40))
            }
        }
        return nil
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
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let workspaceFocusBelongsToTarget = frontmostApplication?
            .processIdentifier == target.processIdentifier
        let natterTemporarilyOwnsFocus = frontmostApplication?
            .bundleIdentifier == AppInfo.bundleIdentifier
        guard workspaceFocusBelongsToTarget || natterTemporarilyOwnsFocus else {
            let frontmostBundle = frontmostApplication?.bundleIdentifier ?? "none"
            let systemProcess = systemFocusedElement
                .flatMap(processIdentifier(of:))
                .map(String.init) ?? "none"
            NatterLog.delivery.error(
                "focus validation rejected target_pid=\(target.processIdentifier, privacy: .public) frontmost=\(frontmostBundle, privacy: .public) system_focus_pid=\(systemProcess, privacy: .public)"
            )
            throw FocusedTextInsertionError.focusChanged
        }

        let appElement = AXUIElementCreateApplication(target.processIdentifier)
        let current = systemFocusBelongsToTarget
            ? systemFocusedElement
            : (try? copyFocusedElement(from: appElement))
        let currentEditable = current.flatMap { isEditableTextControl($0) ? $0 : nil }

        // Web editors may replace their accessibility node during dictation.
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

    private func copyStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }
}
