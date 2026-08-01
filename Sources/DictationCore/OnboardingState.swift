import Foundation

public enum OnboardingStep: String, CaseIterable, Identifiable, Sendable {
    case welcome
    case speechModel
    case permissions
    case practice
    case writingModel
    case ready

    public var id: String { rawValue }
}

public struct OnboardingSnapshot: Equatable, Sendable {
    public let welcomed: Bool
    public let speechModelInstalled: Bool
    public let microphoneGranted: Bool
    public let accessibilityGranted: Bool
    public let inputMonitoringGranted: Bool
    public let practiceCompleted: Bool
    public let writingChoiceCompleted: Bool

    public init(
        welcomed: Bool,
        speechModelInstalled: Bool,
        microphoneGranted: Bool,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        practiceCompleted: Bool,
        writingChoiceCompleted: Bool
    ) {
        self.welcomed = welcomed
        self.speechModelInstalled = speechModelInstalled
        self.microphoneGranted = microphoneGranted
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.practiceCompleted = practiceCompleted
        self.writingChoiceCompleted = writingChoiceCompleted
    }

    public var allPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted && inputMonitoringGranted
    }

    public var currentStep: OnboardingStep {
        if !welcomed { return .welcome }
        if !speechModelInstalled { return .speechModel }
        if !allPermissionsGranted { return .permissions }
        if !practiceCompleted { return .practice }
        if !writingChoiceCompleted { return .writingModel }
        return .ready
    }

    public var isReadyToComplete: Bool {
        currentStep == .ready
    }

    public var essentialSetupIsValid: Bool {
        speechModelInstalled && allPermissionsGranted
    }
}
