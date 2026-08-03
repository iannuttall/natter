import DictationCore
import Foundation
import HuggingFace
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

actor WritingEngine {
    private var container: ModelContainer?
    private var loadedDirectory: URL?
    private var loadingTask: Task<ModelContainer, Error>?
    private var loadingDirectory: URL?
    private var agentGrammar: AgentGrammar?
    private var inferenceBusy = false
    private var inferenceWaiters: [CheckedContinuation<Void, Never>] = []

    private struct AgentGrammar: @unchecked Sendable {
        let tokenizer: GrammarTokenizer
        let hostTokenizer: any MLXLMCommon.Tokenizer
    }

    private struct AgentChunkResult: Sendable {
        let output: String
        let reusableBulkEdits: [TranscriptEdit]
    }

    func warmAgent(modelDirectory: URL) async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        _ = try? await transform(
            transcript: "No changes are needed.",
            mode: .agent,
            markdownRules: WritingRules.defaultMarkdown(for: .agent),
            modelDirectory: nil,
            agentModelDirectory: modelDirectory,
            agentContext: AgentWritingContext.production(
                destinationApplicationName: nil,
                corrections: []
            )
        )
        let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        NatterLog.model.notice(
            "fast Agent model warm elapsed_ms=\(String(format: "%.1f", milliseconds), privacy: .public)"
        )
    }

    func extractPersonalCorrection(
        command: String,
        previousTranscript: String,
        modelDirectory: URL
    ) async throws -> PersonalCorrection? {
        await acquireInference()
        defer { releaseInference() }
        let container = try await loadIfNeeded(from: modelDirectory)
        let grammar = try await loadAgentGrammarIfNeeded(container: container)
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
        markdownRules: String,
        modelDirectory: URL?,
        agentModelDirectory: URL? = nil,
        agentContext: AgentWritingContext = AgentWritingContext()
    ) async throws -> String {
        await acquireInference()
        defer { releaseInference() }
        let deterministicInput = DeterministicTranscriptCleaner.clean(transcript)
        if mode == .agent {
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
                    "Agent cleanup failed; using safe input error=\(error.localizedDescription, privacy: .public)"
                )
                return correctedInput
            }
        }

        guard let modelDirectory else { throw WritingEngineError.modelMissing }
        let container = try await loadIfNeeded(from: modelDirectory)
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
                transcript: deterministicInput,
                mode: mode,
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

    private func transformAgentSelectively(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        container: ModelContainer
    ) async throws -> String {
        var output = ""
        for segment in AgentRewriteSegmenter.segments(transcript) {
            guard segment.requiresRewrite else {
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
                    temperature: 0,
                    seed: 42
                ),
                additionalContext: ["enable_thinking": false]
            )
            do {
                let response = try await session.respond(to: WritingBenchmark.selectiveAgentRewritePrompt(
                    transcript: body,
                    markdownRules: markdownRules,
                    context: context
                ))
                let cleaned = WritingBenchmark.cleanMinimalFormattingEnvelope(response)
                let rewritten = WritingOutputPolicy.enforce(
                    cleaned,
                    markdownRules: markdownRules
                )
                guard !rewritten.isEmpty,
                      TranscriptWordingGuard.preservesWords(from: body, in: rewritten),
                      TranscriptFactGuard.preservesFacts(from: body, in: rewritten),
                      TranscriptTerminologyGuard.preserves(
                        context.protectedSpellings,
                        from: body,
                        in: rewritten
                      ) else {
                    NatterLog.model.error(
                        "selective Agent segment rejected; preserving safe segment words=\(AgentTranscriptChunker.wordCount(body), privacy: .public)"
                    )
                    output += segment.text
                    continue
                }
                output += leading + rewritten + trailing
            } catch {
                NatterLog.model.error(
                    "selective Agent segment failed; preserving safe segment words=\(AgentTranscriptChunker.wordCount(body), privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                output += segment.text
            }
        }

        output = ContextualTranscriptCorrector.correct(output, context: context)
        guard TranscriptWordingGuard.preservesWords(from: transcript, in: output),
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

    private func transformAgent(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        container: ModelContainer
    ) async throws -> String {
        let grammar = try await loadAgentGrammarIfNeeded(container: container)
        let chunks = AgentTranscriptChunker.chunks(transcript)
        var output = ""
        var reusableBulkEdits: [TranscriptEdit] = []
        for chunk in chunks {
            let result = await transformAgentChunk(
                chunk,
                markdownRules: markdownRules,
                context: context,
                container: container,
                grammar: grammar
            )
            output += result.output
            for edit in result.reusableBulkEdits {
                let isDuplicate = reusableBulkEdits.contains {
                    $0.source == edit.source && $0.replacement == edit.replacement
                }
                let reversesLearnedEdit = reusableBulkEdits.contains {
                    $0.source == edit.replacement && $0.replacement == edit.source
                }
                if !isDuplicate, !reversesLearnedEdit {
                    reusableBulkEdits.append(edit)
                }
            }
        }
        if !reusableBulkEdits.isEmpty {
            output = TranscriptEditApplier.applyRecovering(
                TranscriptEditPlan(edits: reusableBulkEdits),
                to: output,
                protectedTerms: context.protectedSpellings
            ).output
        }
        guard TranscriptFactGuard.preservesFacts(from: transcript, in: output) else {
            throw WritingEngineError.droppedProtectedFact
        }
        return output
    }

    private func transformAgentChunk(
        _ transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        container: ModelContainer,
        grammar: AgentGrammar
    ) async -> AgentChunkResult {
        do {
            return try await generateAgentChunk(
                transcript,
                markdownRules: markdownRules,
                context: context,
                container: container,
                grammar: grammar
            )
        } catch {
            let words = AgentTranscriptChunker.wordCount(transcript)
            if words > AgentTranscriptChunker.minimumRetryWords {
                let retrySize = max(
                    AgentTranscriptChunker.minimumRetryWords,
                    words / 2
                )
                let chunks = AgentTranscriptChunker.chunks(
                    transcript,
                    maximumWords: retrySize
                )
                if chunks.count > 1 {
                    NatterLog.model.notice(
                        "structured Agent chunk rejected; retrying smaller chunks words=\(words, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                    )
                    var output = ""
                    var reusableBulkEdits: [TranscriptEdit] = []
                    for chunk in chunks {
                        let result = await transformAgentChunk(
                            chunk,
                            markdownRules: markdownRules,
                            context: context,
                            container: container,
                            grammar: grammar
                        )
                        output += result.output
                        reusableBulkEdits += result.reusableBulkEdits
                    }
                    return AgentChunkResult(
                        output: output,
                        reusableBulkEdits: reusableBulkEdits
                    )
                }
            }
            NatterLog.model.error(
                "structured Agent leaf rejected; preserving safe chunk words=\(words, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return AgentChunkResult(output: transcript, reusableBulkEdits: [])
        }
    }

    private func generateAgentChunk(
        _ transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        container: ModelContainer,
        grammar: AgentGrammar
    ) async throws -> AgentChunkResult {
        let constraint = try GrammarConstraint(
            tokenizer: grammar.tokenizer,
            jsonSchema: WritingBenchmark.agentEditJSONSchema,
            fastForward: true,
            hostTokenizer: grammar.hostTokenizer
        )
        let prompt = WritingBenchmark.agentEditPrompt(
            transcript: transcript,
            markdownRules: markdownRules,
            context: context
        )
        let rawPlan = try await container.perform { modelContext in
            let input = try await modelContext.processor.prepare(input: UserInput(
                chat: [
                    .system(WritingBenchmark.agentEditInstructions),
                    .user(prompt)
                ],
                additionalContext: ["enable_thinking": false]
            ))
            var output = ""
            try GuidedGenerationLoop.run(
                input: input,
                context: modelContext,
                constraint: constraint,
                maxTokens: AgentEditGenerationBudget.maximumTokens(for: transcript),
                vocabSize: grammar.tokenizer.vocabSize
            ) { delta in
                output += delta
                return true
            }
            return output
        }
        let plan = try JSONDecoder().decode(
            TranscriptEditPlan.self,
            from: Data(rawPlan.utf8)
        )
        let application = TranscriptEditApplier.applyRecovering(
            plan,
            to: transcript,
            protectedTerms: context.protectedSpellings
        )
        if application.rejectedEdits > 0 {
            NatterLog.model.notice(
                "structured Agent discarded unsafe edits count=\(application.rejectedEdits, privacy: .public)"
            )
        }
        let output = application.output
        guard TranscriptFactGuard.preservesFacts(from: transcript, in: output) else {
            throw WritingEngineError.droppedProtectedFact
        }
        return AgentChunkResult(
            output: output,
            reusableBulkEdits: application.acceptedPlan.edits.filter {
                $0.allOccurrences == true
                    && $0.source.split(whereSeparator: \.isWhitespace).count >= 2
            }
        )
    }

    private func loadAgentGrammarIfNeeded(
        container: ModelContainer
    ) async throws -> AgentGrammar {
        if let agentGrammar { return agentGrammar }
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
        agentGrammar = loaded
        return loaded
    }

    private func loadIfNeeded(from directory: URL) async throws -> ModelContainer {
        if let container, loadedDirectory == directory { return container }

        if let loadingTask, loadingDirectory == directory {
            return try await loadingTask.value
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
                container = loaded
                loadedDirectory = directory
                loadingTask = nil
                loadingDirectory = nil
                agentGrammar = nil
            }
            return loaded
        } catch {
            if loadingDirectory == directory {
                loadingTask = nil
                loadingDirectory = nil
            }
            throw error
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
