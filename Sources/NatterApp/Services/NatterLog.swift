import Foundation
import OSLog

enum NatterLog {
    private static let subsystem = AppInfo.bundleIdentifier

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let delivery = Logger(subsystem: subsystem, category: "delivery")
    static let hotKey = Logger(subsystem: subsystem, category: "hotkey")
    static let model = Logger(subsystem: subsystem, category: "model")
    static let performance = Logger(subsystem: subsystem, category: "performance")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
}

@MainActor
final class DictationPerformanceTrace {
    enum Milestone: String {
        case overlayVisible = "overlay_visible"
        case modelReady = "model_ready"
        case captureStarted = "capture_started"
        case firstAudioBuffer = "first_audio_buffer"
        case firstPartial = "first_partial"
        case stopRequested = "stop_requested"
        case captureStopped = "capture_stopped"
        case finalTranscript = "final_transcript"
        case transformFinished = "transform_finished"
        case deliveryFinished = "delivery_finished"
    }

    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var recorded: Set<String> = []

    func mark(_ milestone: Milestone) {
        guard recorded.insert(milestone.rawValue).inserted else { return }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let formatted = String(format: "%.1f", milliseconds)
        NatterLog.performance.notice(
            "dictation milestone=\(milestone.rawValue, privacy: .public) elapsed_ms=\(formatted, privacy: .public)"
        )
    }
}
