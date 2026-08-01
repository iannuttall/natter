import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import Observation

enum AppPermission: String, CaseIterable, Identifiable {
    case microphone
    case accessibility
    case inputMonitoring

    var id: String { rawValue }

    var label: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        }
    }

    var detail: String {
        switch self {
        case .microphone: "Capture speech only while dictation is active."
        case .accessibility: "Type into the text control you started from."
        case .inputMonitoring: "Hear the right-side modifier key outside this app."
        }
    }
}

@MainActor
@Observable
final class PermissionController {
    private let defaults: UserDefaults

    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false
    private(set) var requestedPermissions: Set<AppPermission> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        requestedPermissions = Set(
            defaults.stringArray(forKey: Keys.requestedPermissions)?
                .compactMap(AppPermission.init(rawValue:)) ?? []
        )
        refresh()
    }

    func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .microphone: microphoneGranted
        case .accessibility: accessibilityGranted
        case .inputMonitoring: inputMonitoringGranted
        }
    }

    var allRequiredPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted && inputMonitoringGranted
    }

    func request(_ permission: AppPermission) {
        markRequested(permission)
        switch permission {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                    Task { @MainActor in self?.refresh() }
                }
            } else {
                openSystemSettings(for: permission)
            }
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            CGRequestPostEventAccess()
            scheduleRefresh()
        case .inputMonitoring:
            CGRequestListenEventAccess()
            scheduleRefresh()
        }
    }

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted() && CGPreflightPostEventAccess()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    func wasRequested(_ permission: AppPermission) -> Bool {
        requestedPermissions.contains(permission)
    }

    func openSystemSettings(for permission: AppPermission) {
        let pane: String
        switch permission {
        case .microphone:
            pane = "Privacy_Microphone"
        case .accessibility:
            pane = "Privacy_Accessibility"
        case .inputMonitoring:
            pane = "Privacy_ListenEvent"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?" + pane
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }

    private func markRequested(_ permission: AppPermission) {
        requestedPermissions.insert(permission)
        defaults.set(requestedPermissions.map(\.rawValue).sorted(), forKey: Keys.requestedPermissions)
    }

    private enum Keys {
        static let requestedPermissions = "permissions.requested"
    }
}
