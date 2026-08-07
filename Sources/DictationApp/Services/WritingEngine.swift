import DictationCore
import Foundation
import HuggingFace
import MLX
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor WritingEngine {
    private var containers: [URL: ModelContainer] = [:]
    private var containerOrder: [URL] = []
    private var loadingTask: Task<ModelContainer, Error>?
    private var loadingDirectory: URL?
    private var agentGrammar: (directory: URL, grammar: AgentGrammar)?
    private var configuredGPULimits = false
    private var inferenceBusy = false
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []

    /// With enough unified memory both Qwen packs stay resident; alternating
    /// Clean and Email otherwise reload 3–6 GB from disk inside the
    /// user-visible stop path. Below that, keep the old single-slot behavior.
    private static let maximumResidentContainers =
        ProcessInfo.processInfo.physicalMemory >= 24 * 1_073_741_824 ? 2 : 1

    private struct AgentGrammar: @unchecked Sendable {
        let tokenizer: GrammarTokenizer
        let hostTokenizer: any MLXLMCommon.Tokenizer
    }

    func warmRefine(modelDirectory: URL) async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        _ = try? await transform(
            transcript: "No changes are needed.",
            mode: .clean,
            markdownRules: WritingRules.defaultMarkdown(for: .clean),
            modelDirectory: nil,
            agentModelDirectory: modelDirectory,
            agentContext: AgentWritingContext.production(
                destinationApplicationName: nil,
                corrections: []
            )
        )
        let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        NatterLog.model.notice(
            "Refine model warm elapsed_ms=\(String(format: "%.1f", milliseconds), privacy: .public)"
        )
    }

    /// Loads and touches the 9B writing model so the first Email or Article
    /// after launch doesn't pay the multi-second cold load synchronously.
    /// Only runs on machines with room for both packs, since warming the 9B
    /// on a single-slot machine would evict the far more frequently used 4B.
    func warmWriting(modelDirectory: URL) async {
        guard Self.maximumResidentContainers > 1 else { return }
        await acquireInference()
        defer { releaseInference() }
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let container = try await loadIfNeeded(from: modelDirectory)
            let session = ChatSession(
                container,
                generateParameters: GenerateParameters(maxTokens: 1, temperature: 0),
                additionalContext: ["enable_thinking": false]
            )
            _ = try await session.respond(to: "Ready.")
            let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            NatterLog.model.notice(
                "writing model warm elapsed_ms=\(String(format: "%.1f", milliseconds), privacy: .public)"
            )
        } catch {
            NatterLog.model.error(
                "writing model warm-up failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    func extractPersonalCorrection(
        command: String,
        previousTranscript: String,
        modelDirectory: URL
    ) async throws -> PersonalCorrection? {
        await acquireInference()
        defer { releaseInference() }
        let container = try await loadIfNeeded(from: modelDirectory)
        let grammar = try await loadAgentGrammarIfNeeded(
            container: container,
            directory: modelDirectory
        )
        let constraint = try GrammarConstraint(
            tokenizer: grammar.tokenizer,
            jsonSchema: SpokenCorrectionCommand.jsonSchema,
            fastForward: true,
            hostTokenizer: grammar.hostTokenizer
        )
        let rawExtraction = try await container.perform { modelContext in
            let input = try await modelContext.processor.prepare(input: UserInput(
                chat: [
                    .system(SpokenCorrectionCommand.instructions),
                    .user(SpokenCorrectionCommand.prompt(
                        command: command,
                        previousTranscript: previousTranscript
                    ))
                ],
                additionalContext: ["enable_thinking": false]
            ))
            var output = ""
            try GuidedGenerationLoop.run(
                input: input,
                context: modelContext,
                constraint: constraint,
                maxTokens: 160,
                vocabSize: grammar.tokenizer.vocabSize
            ) { delta in
                output += delta
                return true
            }
            return output
        }
        let extraction = try JSONDecoder().decode(
            SpokenCorrectionExtraction.self,
            from: Data(rawExtraction.utf8)
        )
        return SpokenCorrectionCommand.validatedCorrection(
            from: extraction,
            command: command,
            previousTranscript: previousTranscript
        )
    }

    func transform(
        transcript: String,
        mode: DictationMode,
        modeName: String? = nil,
        processing: ModeProcessing? = nil,
        markdownRules: String,
        modelDirectory: URL?,
        agentModelDirectory: URL? = nil,
        agentContext: AgentWritingContext = AgentWritingContext()
    ) async throws -> String {
        await acquireInference()
        defer { releaseInference() }
        if mode == .raw { return transcript }
        let selectedProcessing = processing ?? mode.defaultProcessing
        let deterministicInput = ContextualTranscriptCorrector.correctTechnical(
            DeterministicTranscriptCleaner.clean(transcript),
            context: agentContext
        )
        if selectedProcessing == .fast { return deterministicInput }

        if selectedProcessing == .refine {
            let correctedInput = ContextualTranscriptCorrector.correct(
                deterministicInput,
                context: agentContext
            )
            guard let agentModelDirectory else { return correctedInput }
            do {
                let container = try await loadIfNeeded(from: agentModelDirectory)
                return try await transformAgentSelectively(
                    transcript: correctedInput,
                    markdownRules: markdownRules,
                    context: agentContext,
                    container: container
                )
            } catch {
                NatterLog.model.error(
                    "Refine failed; using deterministic output error=\(error.localizedDescription, privacy: .public)"
                )
                return correctedInput
            }
        }

        guard let modelDirectory else { throw WritingEngineError.modelMissing }
        let container = try await loadIfNeeded(from: modelDirectory)
        // 8-bit KV keeps the 9B's cache memory in check on long Article
        // generations at negligible quality cost.
        var writingParameters = GenerateParameters(maxTokens: 1_800, temperature: 0)
        writingParameters.kvBits = 8
        let session = ChatSession(
            container,
            instructions: WritingBenchmark.baseInstructions,
            generateParameters: writingParameters,
            additionalContext: ["enable_thinking": false]
        )
        let response = try await session.respond(
            to: WritingRules.prompt(
                transcript: deterministicInput,
                mode: mode,
                modeName: modeName,
                markdownRules: markdownRules
            )
        )
        let cleanedOutput = WritingBenchmark.cleanEnvelope(response)
        let output = WritingOutputPolicy.enforce(
            cleanedOutput,
            markdownRules: markdownRules
        )
        guard !output.isEmpty else { throw WritingEngineError.emptyOutput }
        guard TranscriptFactGuard.preservesFacts(from: deterministicInput, in: output) else {
            throw WritingEngineError.droppedProtectedFact
        }
        return output
    }

    private func applyAgentSelfEditsIfNeeded(
        to transcript: String,
        container: ModelContainer
    ) async throws -> String {
        guard AgentSelfEditPolicy.containsCorrectionCue(transcript) else { return transcript }
        let session = ChatSession(
            container,
            instructions: WritingBenchmark.agentSelfEditInstructions,
            generateParameters: GenerateParameters(
                maxTokens: AgentEditGenerationBudget.maximumTokens(for: transcript),
                temperature: 0
            ),
            additionalContext: ["enable_thinking": false]
        )
        let response = try await session.respond(
            to: WritingBenchmark.agentSelfEditPrompt(transcript: transcript)
        )
        guard let output = AgentSelfEditPolicy.safeOutput(
            input: transcript,
            proposedOutput: WritingBenchmark.cleanEnvelope(response)
        ) else {
            NatterLog.model.notice(
                "Refine self-edit discarded an unsafe response"
            )
            return transcript
        }
        return output
    }

    private func transformAgentSelectively(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        container: ModelContainer
    ) async throws -> String {
        if AgentSelfEditPolicy.containsCorrectionCue(transcript) {
            return try await applyAgentSelfEditsIfNeeded(
                to: transcript,
                container: container
            )
        }
        var output = ""
        for segment in AgentRewriteSegmenter.segments(transcript) {
            // A false-start cue makes an otherwise-clean segment eligible so
            // abandoned thoughts inside well-punctuated text can be removed.
            let removesFalseStarts = context.removesFalseStarts
                && FalseStartCues.containsCue(segment.text)
            guard segment.requiresRewrite || removesFalseStarts else {
                output += segment.text
                continue
            }

            let leading = String(segment.text.prefix(while: \.isWhitespace))
            let trailing = String(
                segment.text.reversed().prefix(while: \.isWhitespace).reversed()
            )
            let body = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                output += segment.text
                continue
            }

            let session = ChatSession(
                container,
                instructions: WritingBenchmark.selectiveAgentRewriteInstructions,
                generateParameters: GenerateParameters(
                    maxTokens: 1_200,
                    temperature: 0
                ),
                additionalContext: ["enable_thinking": false]
            )
            do {
                let response = try await session.respond(to: WritingBenchmark.selectiveAgentRewritePrompt(
                    transcript: body,
                    markdownRules: markdownRules,
                    context: context,
                    allowsFalseStartRemoval: removesFalseStarts
                ))
                let cleaned = WritingBenchmark.cleanMinimalFormattingEnvelope(response)
                let rewritten = WritingOutputPolicy.enforce(
                    cleaned,
                    markdownRules: markdownRules
                )
                let initialWordingHolds = removesFalseStarts
                    ? TranscriptWordingGuard.allowsOnlyDeletions(from: body, in: rewritten)
                    : TranscriptWordingGuard.preservesWords(from: body, in: rewritten)
                let safeRewrite = if initialWordingHolds || removesFalseStarts {
                    rewritten
                } else {
                    TranscriptFormattingProjection.project(from: body, onto: rewritten)
                        ?? rewritten
                }
                let wordingHolds = removesFalseStarts
                    ? TranscriptWordingGuard.allowsOnlyDeletions(from: body, in: safeRewrite)
                    : TranscriptWordingGuard.preservesWords(from: body, in: safeRewrite)
                let factsHold = TranscriptFactGuard.preservesFacts(
                    from: body,
                    in: safeRewrite
                )
                let terminologyHolds = TranscriptTerminologyGuard.preserves(
                    context.protectedSpellings,
                    from: body,
                    in: safeRewrite
                )
                guard !safeRewrite.isEmpty,
                      wordingHolds,
                      factsHold,
                      terminologyHolds else {
                    NatterLog.model.error(
                        "Refine segment rejected; preserving deterministic output words=\(AgentTranscriptChunker.wordCount(body), privacy: .public) wording=\(wordingHolds, privacy: .public) facts=\(factsHold, privacy: .public) terminology=\(terminologyHolds, privacy: .public)"
                    )
                    output += segment.text
                    continue
                }
                if !initialWordingHolds, safeRewrite != rewritten {
                    NatterLog.model.notice(
                        "Refine segment projected onto source words words=\(AgentTranscriptChunker.wordCount(body), privacy: .public)"
                    )
                }
                output += leading + safeRewrite + trailing
            } catch {
                NatterLog.model.error(
                    "Refine segment failed; preserving deterministic output words=\(AgentTranscriptChunker.wordCount(body), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                output += segment.text
            }
        }

        output = ContextualTranscriptCorrector.correct(output, context: context)
        let transcriptWordingHolds = context.removesFalseStarts
            ? TranscriptWordingGuard.allowsOnlyDeletions(from: transcript, in: output)
            : TranscriptWordingGuard.preservesWords(from: transcript, in: output)
        guard transcriptWordingHolds,
              TranscriptFactGuard.preservesFacts(from: transcript, in: output),
              TranscriptTerminologyGuard.preserves(
                context.protectedSpellings,
                from: transcript,
                in: output
              ) else {
            throw WritingEngineError.droppedProtectedFact
        }
        return output
    }

    private func loadAgentGrammarIfNeeded(
        container: ModelContainer,
        directory: URL
    ) async throws -> AgentGrammar {
        if let agentGrammar, agentGrammar.directory == directory {
            return agentGrammar.grammar
        }
        let loaded = try await container.perform { context in
            let vocabulary = TokenizerVocabExtractor.extractForGrammar(
                from: context.tokenizer
            )
            let tokenizer = try GrammarTokenizer(
                vocab: vocabulary.vocab,
                vocabType: vocabulary.vocabType,
                eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0)
            )
            return AgentGrammar(tokenizer: tokenizer, hostTokenizer: context.tokenizer)
        }
        agentGrammar = (directory, loaded)
        return loaded
    }

    private func loadIfNeeded(from directory: URL) async throws -> ModelContainer {
        if let cached = containers[directory] {
            containerOrder.removeAll { $0 == directory }
            containerOrder.append(directory)
            return cached
        }

        if let loadingTask, loadingDirectory == directory {
            return try await loadingTask.value
        }

        if !configuredGPULimits {
            configuredGPULimits = true
            // Bound MLX's buffer-recycling pool; the process default lets it
            // grow with the largest generation seen.
            MLX.GPU.set(cacheLimit: 512 * 1_024 * 1_024)
        }

        let configuration = ModelConfiguration(
            directory: directory,
            extraEOSTokens: ["<|im_end|>"]
        )
        let task = Task {
            try await #huggingFaceLoadModelContainer(configuration: configuration)
        }
        loadingTask = task
        loadingDirectory = directory

        do {
            let loaded = try await task.value
            if loadingDirectory == directory {
                loadingTask = nil
                loadingDirectory = nil
            }
            store(loaded, for: directory)
            return loaded
        } catch {
            if loadingDirectory == directory {
                loadingTask = nil
                loadingDirectory = nil
            }
            throw error
        }
    }

    private func store(_ container: ModelContainer, for directory: URL) {
        containers[directory] = container
        containerOrder.removeAll { $0 == directory }
        containerOrder.append(directory)
        while containerOrder.count > Self.maximumResidentContainers {
            let evicted = containerOrder.removeFirst()
            containers[evicted] = nil
            if agentGrammar?.directory == evicted { agentGrammar = nil }
            NatterLog.model.notice(
                "writing model evicted directory=\(evicted.lastPathComponent, privacy: .public)"
            )
        }
    }

    private func acquireInference() async {
        guard inferenceBusy else {
            inferenceBusy = true
            return
        }
        await withCheckedContinuation { continuation in
            inferenceWaiters.append(continuation)
        }
    }

    private func releaseInference() {
        guard !inferenceWaiters.isEmpty else {
            inferenceBusy = false
            return
        }
        inferenceWaiters.removeFirst().resume()
    }
}

enum WritingEngineError: LocalizedError {
    case emptyOutput
    case droppedProtectedFact
    case modelMissing

    var errorDescription: String? {
        switch self {
        case .emptyOutput: "The writing model returned an empty result."
        case .droppedProtectedFact:
            "The writing model dropped a protected number, URL, email address or path."
        case .modelMissing: "The writing model is not installed."
        }
    }
}
