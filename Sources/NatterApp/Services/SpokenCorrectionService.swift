import Foundation
import NatterCore

enum SpokenCorrectionResolution {
    case modelMissing
    case unverified
    case added(PersonalCorrection)
}

@MainActor
final class SpokenCorrectionService {
    private let writingEngine: WritingEngine
    private let rules: RulesManager

    init(writingEngine: WritingEngine, rules: RulesManager) {
        self.writingEngine = writingEngine
        self.rules = rules
    }

    func resolve(
        command: String,
        previousTranscript: String
    ) async throws -> SpokenCorrectionResolution {
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard
            let modelDirectory = WritingModelLocation.resolve(in: paths)
                ?? AgentWritingModelLocation.resolve(in: paths)
        else {
            return .modelMissing
        }
        guard
            let correction = try await writingEngine.extractPersonalCorrection(
                command: command,
                previousTranscript: previousTranscript,
                modelDirectory: modelDirectory
            )
        else {
            return .unverified
        }

        rules.add(
            PersonalCorrection(
                heard: correction.heard,
                replacement: correction.replacement,
                scope: .everywhere
            ))
        return .added(correction)
    }
}
