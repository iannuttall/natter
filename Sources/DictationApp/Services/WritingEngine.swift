import DictationCore
import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor WritingEngine {
    private var container: ModelContainer?
    private var loadedDirectory: URL?

    func transform(
        transcript: String,
        mode: DictationMode,
        markdownRules: String,
        modelDirectory: URL
    ) async throws -> String {
        let container = try await loadIfNeeded(from: modelDirectory)
        let cleanedInput = DeterministicTranscriptCleaner.removeFillers(from: transcript)
        let session = ChatSession(
            container,
            instructions: WritingBenchmark.baseInstructions,
            generateParameters: GenerateParameters(
                maxTokens: 1_800,
                temperature: 0,
                seed: 42
            ),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await session.respond(
            to: WritingRules.prompt(
                transcript: cleanedInput,
                mode: mode,
                markdownRules: markdownRules
            )
        )
        let output = WritingBenchmark.cleanEnvelope(response)
        guard !output.isEmpty else { throw WritingEngineError.emptyOutput }
        guard TranscriptFactGuard.preservesFacts(from: cleanedInput, in: output) else {
            throw WritingEngineError.droppedProtectedFact
        }
        return output
    }

    private func loadIfNeeded(from directory: URL) async throws -> ModelContainer {
        if let container, loadedDirectory == directory { return container }

        let configuration = ModelConfiguration(
            directory: directory,
            extraEOSTokens: ["<|im_end|>"]
        )
        let loaded = try await #huggingFaceLoadModelContainer(
            configuration: configuration
        )
        container = loaded
        loadedDirectory = directory
        return loaded
    }
}

enum WritingEngineError: LocalizedError {
    case emptyOutput
    case droppedProtectedFact

    var errorDescription: String? {
        switch self {
        case .emptyOutput: "The writing model returned an empty result."
        case .droppedProtectedFact:
            "The writing model dropped a protected number, URL, email address or path."
        }
    }
}
