import AVFoundation
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
    private(set) var microphoneGranted = false
    private(set) var accessibilityGranted = false
    private(set) var inputMonitoringGranted = false

    init() {
        refresh()
    }

    func isGranted(_ permission: AppPermission) -> Bool {
        switch permission {
        case .microphone: microphoneGranted
        case .accessibility: accessibilityGranted
        case .inputMonitoring: inputMonitoringGranted
        }
    }

    func request(_ permission: AppPermission) {
        switch permission {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            scheduleRefresh()
        case .inputMonitoring:
            CGRequestListenEventAccess()
            scheduleRefresh()
        }
    }

    func refresh() {
        microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        inputMonitoringGranted = CGPreflightListenEventAccess()
    }

    private func scheduleRefresh() {
        Task {
            try? await Task.sleep(for: .seconds(1))
            refresh()
        }
    }
}
