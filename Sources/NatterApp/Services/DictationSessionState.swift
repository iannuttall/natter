import Foundation
import NatterCore

struct DictationSessionState {
    var focusTarget: FocusedTextTarget?
    var sourceBundleIdentifier: String?
    var sourceApplicationName: String?
    var emitter = StableTranscriptEmitter()
    var stabilizer = StableTranscriptStabilizer(trailingTokenCount: 1)
    var deliveryIssue: String?
    var liveTranscriptConflict = false
    var corrections: [PersonalCorrection] = []
    var commandCandidate = false
    var forcesLowercaseInitial = false
    var pendingVoiceSubmit = false
    var lastHandledPartial = ""
    var previousTranscript: String?
    var recordingStartedAt: Date?
    var recordingStoppedAt: Date?
    var historyWasRecorded = false
    var performanceTrace: DictationPerformanceTrace?

    mutating func reset(
        previousTranscript: String?,
        corrections: [PersonalCorrection]
    ) {
        self.previousTranscript = previousTranscript
        self.corrections = corrections
        focusTarget = nil
        sourceBundleIdentifier = nil
        sourceApplicationName = nil
        emitter.reset()
        stabilizer = StableTranscriptStabilizer(trailingTokenCount: 3)
        deliveryIssue = nil
        liveTranscriptConflict = false
        commandCandidate = false
        forcesLowercaseInitial = false
        pendingVoiceSubmit = false
        lastHandledPartial = ""
        recordingStartedAt = nil
        recordingStoppedAt = nil
        historyWasRecorded = false
    }
}
