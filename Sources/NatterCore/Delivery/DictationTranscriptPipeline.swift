import Foundation

public struct PreparedDictationTranscript: Equatable, Sendable {
    public let transcript: String
    public let shouldSubmit: Bool

    public init(transcript: String, shouldSubmit: Bool) {
        self.transcript = transcript
        self.shouldSubmit = shouldSubmit
    }
}

public enum DictationTranscriptPipeline {
    public static func preview(
        rawTranscript: String,
        mode: DictationMode,
        corrections: [PersonalCorrection]
    ) -> String {
        guard mode != .raw else { return rawTranscript }
        return PersonalCorrections.apply(
            corrections,
            to: SpokenTechnicalTextNormalizer.normalize(
                rawTranscript,
                context: .technical
            ),
            scope: correctionScope(for: mode)
        )
    }

    public static func prepareFinal(
        rawTranscript: String,
        mode: DictationMode,
        corrections: [PersonalCorrection],
        destinationApplicationName: String?,
        voiceSubmitEnabled: Bool
    ) -> PreparedDictationTranscript {
        let modeTranscript = preview(
            rawTranscript: rawTranscript,
            mode: mode,
            corrections: corrections
        )
        let voiceSubmit =
            voiceSubmitEnabled
            ? VoiceSubmitCommand.consume(from: modeTranscript)
            : VoiceSubmitResult(transcript: modeTranscript, shouldSubmit: false)
        guard mode != .raw else {
            return PreparedDictationTranscript(
                transcript: FinalTranscriptFormatter.punctuateRawProse(
                    voiceSubmit.transcript,
                    capitalizesInitial: false
                ),
                shouldSubmit: voiceSubmit.shouldSubmit
            )
        }

        let transcript = FinalTranscriptFormatter.punctuateRawProse(
            ContextualTranscriptCorrector.correctTechnical(
                DeterministicTranscriptCleaner.clean(voiceSubmit.transcript),
                context: AgentWritingContext.production(
                    destinationApplicationName: destinationApplicationName,
                    corrections: applicableCorrections(corrections, for: mode)
                )
            ),
            capitalizesInitial: false
        )
        return PreparedDictationTranscript(
            transcript: transcript,
            shouldSubmit: voiceSubmit.shouldSubmit
        )
    }

    public static func applicableCorrections(
        _ corrections: [PersonalCorrection],
        for mode: DictationMode
    ) -> [PersonalCorrection] {
        corrections.filter {
            $0.scope == .everywhere || (mode == .agent && $0.scope == .agent)
        }
    }

    private static func correctionScope(for mode: DictationMode) -> PersonalCorrectionScope {
        mode == .agent ? .agent : .everywhere
    }
}
