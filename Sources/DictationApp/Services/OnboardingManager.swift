import DictationCore
import Foundation
import Observation

@MainActor
@Observable
final class OnboardingManager {
    static let currentVersion = 1

    private let defaults: UserDefaults

    private(set) var welcomed: Bool
    private(set) var practiceCompleted: Bool
    private(set) var writingChoiceCompleted: Bool
    private(set) var completedVersion: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        welcomed = defaults.bool(forKey: Keys.welcomed)
        practiceCompleted = defaults.bool(forKey: Keys.practiceCompleted)
        writingChoiceCompleted = defaults.bool(forKey: Keys.writingChoiceCompleted)
        completedVersion = defaults.integer(forKey: Keys.completedVersion)
    }

    func snapshot(
        modelManager: ModelManager,
        permissions: PermissionController
    ) -> OnboardingSnapshot {
        OnboardingSnapshot(
            welcomed: welcomed,
            speechModelInstalled: modelManager.speechInstalled,
            microphoneGranted: permissions.microphoneGranted,
            accessibilityGranted: permissions.accessibilityGranted,
            inputMonitoringGranted: permissions.inputMonitoringGranted,
            practiceCompleted: practiceCompleted,
            writingChoiceCompleted: writingChoiceCompleted || modelManager.writingInstalled
        )
    }

    func needsAttention(
        modelManager: ModelManager,
        permissions: PermissionController
    ) -> Bool {
        completedVersion < Self.currentVersion
            || !snapshot(modelManager: modelManager, permissions: permissions)
                .essentialSetupIsValid
    }

    func acceptWelcome() {
        welcomed = true
        defaults.set(true, forKey: Keys.welcomed)
    }

    func completePractice() {
        practiceCompleted = true
        defaults.set(true, forKey: Keys.practiceCompleted)
    }

    func deferWritingModel() {
        writingChoiceCompleted = true
        defaults.set(true, forKey: Keys.writingChoiceCompleted)
    }

    func complete() {
        completedVersion = Self.currentVersion
        defaults.set(Self.currentVersion, forKey: Keys.completedVersion)
    }

    private enum Keys {
        static let welcomed = "onboarding.welcomed"
        static let practiceCompleted = "onboarding.practiceCompleted"
        static let writingChoiceCompleted = "onboarding.writingChoiceCompleted"
        static let completedVersion = "onboarding.completedVersion"
    }
}
