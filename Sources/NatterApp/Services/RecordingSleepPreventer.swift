import Foundation
import IOKit.pwr_mgt
import Observation

@MainActor
final class RecordingSleepPreventer {
    private let store: DictationStore
    private var assertionID: IOPMAssertionID?
    private var isStopped = false

    init(store: DictationStore) {
        self.store = store
        observePreferencesAndPhase()
    }

    deinit {
        if let assertionID {
            IOPMAssertionRelease(assertionID)
        }
    }

    func stop() {
        isStopped = true
        endActivity()
    }

    private func observePreferencesAndPhase() {
        guard !isStopped else { return }

        withObservationTracking {
            updateActivity(
                isEnabled: store.preventSleepWhileRecording && store.phase.isBusy
            )
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observePreferencesAndPhase()
            }
        }
    }

    private func updateActivity(isEnabled: Bool) {
        if isEnabled {
            guard assertionID == nil else { return }
            var newAssertionID = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Natter is recording and preparing a transcript" as CFString,
                &newAssertionID
            )
            guard result == kIOReturnSuccess else {
                NatterLog.app.error(
                    "sleep prevention assertion rejected result=\(result, privacy: .public)"
                )
                return
            }
            assertionID = newAssertionID
        } else {
            endActivity()
        }
    }

    private func endActivity() {
        guard let assertionID else { return }
        IOPMAssertionRelease(assertionID)
        self.assertionID = nil
    }
}
