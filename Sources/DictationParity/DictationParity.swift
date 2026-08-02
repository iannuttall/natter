import DictationCore
import Foundation
import HuggingFace
import MLXGuidedGeneration
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

private enum ParityError: Error, CustomStringConvertible {
    case arguments(String)

    var description: String {
        switch self {
        case .arguments(let message): message
        }
    }
}

private struct RecordedBaseline: Decodable {
    let id: String
    let latencySeconds: Double
    let output: String
}

private struct ParityFixtureDocument: Decodable {
    let version: Int
    let fixtures: [WritingFixture]
    let monologueBaselines: [RecordedBaseline]?
}

private struct Arguments {
    enum Strategy: String {
        case fullRewrite = "full-rewrite"
        case safeFullRewrite = "safe-full-rewrite"
        case selectiveSafeRewrite = "selective-safe-rewrite"
        case structuredEdits = "structured-edits"
        case deterministicAgent = "deterministic-agent"
        case recordedBaseline = "recorded-baseline"
    }

    var fixtures: URL?
    var formattingFixtures: URL?
    var output: URL?
    var modelDirectory: URL?
    var modelID = "mlx-community/Qwen3.5-9B-MLX-4bit"
    var revision = "938d8919941c6e7efd3c7150eff7fe9d12afa631"
    var repeatTranscript = 1
    var iterations = 1
    var limit: Int?
    var fixtureID: String?
    var strategy = Strategy.fullRewrite

    static func parse(_ values: [String]) throws -> Arguments {
        var parsed = Arguments()
        var index = 0
        while index < values.count {
            switch values[index] {
            case "--fixtures":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --fixtures path")
                }
                parsed.fixtures = URL(fileURLWithPath: values[index])
            case "--output":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --output path")
                }
                parsed.output = URL(fileURLWithPath: values[index])
            case "--formatting-fixtures":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --formatting-fixtures path")
                }
                parsed.formattingFixtures = URL(fileURLWithPath: values[index])
            case "--model":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --model value")
                }
                parsed.modelID = values[index]
            case "--model-directory":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --model-directory path")
                }
                parsed.modelDirectory = URL(fileURLWithPath: values[index])
            case "--revision":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --revision value")
                }
                parsed.revision = values[index]
            case "--repeat-transcript":
                index += 1
                guard index < values.count,
                      let value = Int(values[index]),
                      value > 0 else {
                    throw ParityError.arguments("--repeat-transcript must be positive")
                }
                parsed.repeatTranscript = value
            case "--iterations":
                index += 1
                guard index < values.count,
                      let value = Int(values[index]),
                      value > 0 else {
                    throw ParityError.arguments("--iterations must be positive")
                }
                parsed.iterations = value
            case "--strategy":
                index += 1
                guard index < values.count,
                      let value = Strategy(rawValue: values[index]) else {
                    throw ParityError.arguments(
                        "--strategy must be full-rewrite, safe-full-rewrite, selective-safe-rewrite, structured-edits, deterministic-agent, or recorded-baseline"
                    )
                }
                parsed.strategy = value
            case "--limit":
                index += 1
                guard index < values.count,
                      let value = Int(values[index]),
                      value > 0 else {
                    throw ParityError.arguments("--limit must be positive")
                }
                parsed.limit = value
            case "--fixture":
                index += 1
                guard index < values.count, !values[index].isEmpty else {
                    throw ParityError.arguments("Missing --fixture id")
                }
                parsed.fixtureID = values[index]
            default:
                throw ParityError.arguments("Unknown argument: \(values[index])")
            }
            index += 1
        }
        return parsed
    }
}

private actor MLXWritingGenerator {
    private let container: ModelContainer
    private var agentGrammar: AgentGrammar?

    private struct AgentGrammar: @unchecked Sendable {
        let tokenizer: GrammarTokenizer
        let hostTokenizer: any MLXLMCommon.Tokenizer
    }

    struct StructuredGenerationResult: Sendable {
        let output: String
        let outcome: String
    }

    private struct ChunkResult {
        let output: String
        let fallbackCount: Int
        let reusableBulkEdits: [TranscriptEdit]
    }

    init(modelID: String, revision: String, modelDirectory: URL?) async throws {
        let configuration = if let modelDirectory {
            ModelConfiguration(
                directory: modelDirectory,
                extraEOSTokens: ["<|im_end|>"]
            )
        } else {
            ModelConfiguration(
                id: modelID,
                revision: revision,
                extraEOSTokens: ["<|im_end|>"]
            )
        }
        container = try await #huggingFaceLoadModelContainer(
            configuration: configuration
        ) { progress in
            let percent = Int(progress.fractionCompleted * 100)
            writeError("Downloading/loading model: \(percent)%")
        }
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(
                maxTokens: 1_200,
                temperature: 0,
                seed: 42
            ),
            additionalContext: ["enable_thinking": false]
        )
        return try await session.respond(to: prompt)
    }

    func generateSafeAgentRewrite(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext
    ) async -> StructuredGenerationResult {
        let deterministicInput = DeterministicTranscriptCleaner.clean(transcript)
        let inputTranscript = ContextualTranscriptCorrector.correct(
            deterministicInput,
            context: context
        )
        do {
            let response = try await generate(
                instructions: WritingBenchmark.baseInstructions + "\n"
                    + WritingBenchmark.minimalFormattingInstructions + "\n"
                    + WritingBenchmark.agentRewriteCompletionInstructions,
                prompt: WritingRules.prompt(
                    transcript: inputTranscript,
                    mode: .agent,
                    markdownRules: markdownRules,
                    agentContext: context
                )
            )
            let cleaned = WritingBenchmark.cleanMinimalFormattingEnvelope(response)
            let output = WritingOutputPolicy.enforce(
                cleaned,
                markdownRules: markdownRules
            )
            guard !output.isEmpty,
                  TranscriptFactGuard.preservesFacts(from: inputTranscript, in: output),
                  TranscriptTerminologyGuard.preserves(
                    context.protectedSpellings,
                    from: inputTranscript,
                    in: output
                  ) else {
                return StructuredGenerationResult(
                    output: inputTranscript,
                    outcome: "fallback: fact-guard"
                )
            }
            return StructuredGenerationResult(output: output, outcome: "accepted")
        } catch {
            return StructuredGenerationResult(
                output: inputTranscript,
                outcome: "fallback: \(String(describing: type(of: error)))"
            )
        }
    }

    func generateSelectiveSafeAgentRewrite(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext
    ) async -> StructuredGenerationResult {
        let deterministicInput = DeterministicTranscriptCleaner.clean(transcript)
        let inputTranscript = ContextualTranscriptCorrector.correct(
            deterministicInput,
            context: context
        )
        var output = ""
        var fallbackCount = 0
        let segments = AgentRewriteSegmenter.segments(inputTranscript)
        writeError(
            "[selective-segments] "
                + segments.map {
                    "\(AgentTranscriptChunker.wordCount($0.text)):\($0.requiresRewrite ? "rewrite" : "keep")"
                }.joined(separator: ",")
        )
        for segment in segments {
            guard segment.requiresRewrite else {
                output += segment.text
                continue
            }
            let leading = String(segment.text.prefix(while: \.isWhitespace))
            let trailing = String(segment.text.reversed().prefix(while: \.isWhitespace).reversed())
            let body = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else {
                output += segment.text
                continue
            }
            do {
                let response = try await generate(
                    instructions: WritingBenchmark.selectiveAgentRewriteInstructions,
                    prompt: WritingBenchmark.selectiveAgentRewritePrompt(
                        transcript: body,
                        markdownRules: markdownRules,
                        context: context
                    )
                )
                let cleaned = WritingBenchmark.cleanMinimalFormattingEnvelope(response)
                guard !cleaned.isEmpty,
                      TranscriptWordingGuard.preservesWords(from: body, in: cleaned),
                      TranscriptFactGuard.preservesFacts(from: body, in: cleaned),
                      TranscriptTerminologyGuard.preserves(
                        context.protectedSpellings,
                        from: body,
                        in: cleaned
                      ) else {
                    let sourceWords = WritingBenchmark.normalizedWords(body)
                    let outputWords = WritingBenchmark.normalizedWords(cleaned)
                    let mismatches = zip(sourceWords, outputWords).enumerated().compactMap {
                        index, pair -> String? in
                        pair.0 == pair.1 ? nil : "\(index):\(pair.0)>\(pair.1)"
                    }.prefix(8).joined(separator: ",")
                    writeError(
                        "[selective-segment-fallback] words=\(sourceWords.count) "
                            + "outputWords=\(outputWords.count) mismatches=\(mismatches)"
                    )
                    output += segment.text
                    fallbackCount += 1
                    continue
                }
                output += leading + cleaned + trailing
            } catch {
                output += segment.text
                fallbackCount += 1
            }
        }
        output = ContextualTranscriptCorrector.correct(output, context: context)
        guard TranscriptFactGuard.preservesFacts(from: inputTranscript, in: output),
              TranscriptWordingGuard.preservesWords(from: inputTranscript, in: output),
              TranscriptTerminologyGuard.preserves(
                context.protectedSpellings,
                from: inputTranscript,
                in: output
              ) else {
            return StructuredGenerationResult(
                output: inputTranscript,
                outcome: "fallback: fact-guard"
            )
        }
        return StructuredGenerationResult(
            output: output,
            outcome: fallbackCount == 0
                ? "accepted"
                : "fallback-segments: \(fallbackCount)"
        )
    }

    func generateStructuredEdits(
        transcript: String,
        markdownRules: String,
        context: AgentWritingContext
    ) async -> StructuredGenerationResult {
        let deterministicInput = DeterministicTranscriptCleaner.clean(transcript)
        let inputTranscript = ContextualTranscriptCorrector.correct(
            deterministicInput,
            context: context
        )
        do {
            let grammar = try await loadAgentGrammarIfNeeded()
            let chunks = AgentTranscriptChunker.chunks(inputTranscript)
            var output = ""
            var reusableBulkEdits: [TranscriptEdit] = []
            var fallbackCount = 0
            for chunk in chunks {
                let result = await transformStructuredChunk(
                    chunk,
                    markdownRules: markdownRules,
                    context: context,
                    grammar: grammar
                )
                output += result.output
                fallbackCount += result.fallbackCount
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
            guard TranscriptFactGuard.preservesFacts(from: inputTranscript, in: output) else {
                throw ParityError.arguments("Structured edits dropped a protected fact")
            }
            return StructuredGenerationResult(
                output: output,
                outcome: fallbackCount == 0
                    ? "accepted"
                    : "fallback-chunks: \(fallbackCount)"
            )
        } catch {
            writeError("[structured-fallback] \(error)")
            return StructuredGenerationResult(
                output: inputTranscript,
                outcome: "fallback: \(String(describing: type(of: error)))"
            )
        }
    }

    private func transformStructuredChunk(
        _ transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        grammar: AgentGrammar
    ) async -> ChunkResult {
        do {
            return try await generateStructuredChunk(
                transcript,
                markdownRules: markdownRules,
                context: context,
                grammar: grammar
            )
        } catch {
            let words = AgentTranscriptChunker.wordCount(transcript)
            if words > AgentTranscriptChunker.minimumRetryWords {
                let chunks = AgentTranscriptChunker.chunks(
                    transcript,
                    maximumWords: max(
                        AgentTranscriptChunker.minimumRetryWords,
                        words / 2
                    )
                )
                if chunks.count > 1 {
                    writeError(
                        "[structured-retry] words=\(words) chunks=\(chunks.count) error=\(error)"
                    )
                    var output = ""
                    var fallbackCount = 0
                    var reusableBulkEdits: [TranscriptEdit] = []
                    for chunk in chunks {
                        let result = await transformStructuredChunk(
                            chunk,
                            markdownRules: markdownRules,
                            context: context,
                            grammar: grammar
                        )
                        output += result.output
                        fallbackCount += result.fallbackCount
                        reusableBulkEdits += result.reusableBulkEdits
                    }
                    return ChunkResult(
                        output: output,
                        fallbackCount: fallbackCount,
                        reusableBulkEdits: reusableBulkEdits
                    )
                }
            }
            writeError("[structured-leaf-fallback] words=\(words) error=\(error)")
            return ChunkResult(
                output: transcript,
                fallbackCount: 1,
                reusableBulkEdits: []
            )
        }
    }

    private func generateStructuredChunk(
        _ transcript: String,
        markdownRules: String,
        context: AgentWritingContext,
        grammar: AgentGrammar
    ) async throws -> ChunkResult {
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
        writeError("[structured-plan] \(rawPlan)")
        let application = TranscriptEditApplier.applyRecovering(
            plan,
            to: transcript,
            protectedTerms: context.protectedSpellings
        )
        if application.rejectedEdits > 0 {
            writeError("[structured-rejected-edits] count=\(application.rejectedEdits)")
        }
        let output = application.output
        guard TranscriptFactGuard.preservesFacts(from: transcript, in: output) else {
            throw ParityError.arguments("Structured edits dropped a protected fact")
        }
        return ChunkResult(
            output: output,
            fallbackCount: 0,
            reusableBulkEdits: application.acceptedPlan.edits.filter {
                $0.allOccurrences == true
                    && $0.source.split(whereSeparator: \.isWhitespace).count >= 2
            }
        )
    }

    private func loadAgentGrammarIfNeeded() async throws -> AgentGrammar {
        if let agentGrammar { return agentGrammar }
        let loaded = try await container.perform { context in
            let vocabulary = TokenizerVocabExtractor.extractForGrammar(from: context.tokenizer)
            let tokenizer = try GrammarTokenizer(
                vocab: vocabulary.vocab,
                vocabType: vocabulary.vocabType,
                eosTokenId: Int32(context.tokenizer.eosTokenId ?? 0)
            )
            return AgentGrammar(
                tokenizer: tokenizer,
                hostTokenizer: context.tokenizer
            )
        }
        agentGrammar = loaded
        return loaded
    }
}

@main
private enum DictationParity {
    static func main() async {
        do {
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            if arguments.fixtures != nil, arguments.formattingFixtures != nil {
                throw ParityError.arguments(
                    "Use either --fixtures or --formatting-fixtures, not both"
                )
            }
            let fixtureSet: WritingFixtureSet
            var recordedBaselines: [String: RecordedBaseline] = [:]
            if let fixturesURL = arguments.fixtures {
                let document = try JSONDecoder().decode(
                    ParityFixtureDocument.self,
                    from: Data(contentsOf: fixturesURL)
                )
                fixtureSet = WritingFixtureSet(
                    version: document.version,
                    fixtures: document.fixtures
                )
                recordedBaselines = Dictionary(
                    uniqueKeysWithValues: (document.monologueBaselines ?? []).map {
                        ($0.id, $0)
                    }
                )
            } else if let formattingURL = arguments.formattingFixtures {
                let formatting = try JSONDecoder().decode(
                    FormattingFixtureSet.self,
                    from: Data(contentsOf: formattingURL)
                )
                fixtureSet = WritingFixtureSet(
                    version: formatting.version,
                    fixtures: formatting.fixtures.compactMap {
                        FormattingBenchmark.smartWritingFixture(from: $0)
                    }
                )
            } else {
                throw ParityError.arguments(
                    "--fixtures or --formatting-fixtures is required"
                )
            }
            var fixtures = fixtureSet.fixtures
            if let fixtureID = arguments.fixtureID {
                fixtures = fixtures.filter { $0.id == fixtureID }
                guard !fixtures.isEmpty else {
                    throw ParityError.arguments("Unknown fixture id: \(fixtureID)")
                }
            }
            if let limit = arguments.limit {
                fixtures = Array(fixtures.prefix(limit))
            }
            let generator: MLXWritingGenerator? = if arguments.strategy == .deterministicAgent
                || arguments.strategy == .recordedBaseline {
                nil
            } else {
                try await MLXWritingGenerator(
                    modelID: arguments.modelID,
                    revision: arguments.revision,
                    modelDirectory: arguments.modelDirectory
                )
            }

            var results: [WritingFixtureResult] = []
            let totalRuns = fixtures.count * arguments.iterations
            for iteration in 1...arguments.iterations {
                for fixture in fixtures {
                    let repeatedTranscript = WritingBenchmark.expanded(
                        fixture.transcript,
                        count: arguments.repeatTranscript
                    )
                    let started = ContinuousClock.now
                    let output: String
                    let pipelineOutcome: String
                    let productionContext = AgentWritingContext.production(
                        destinationApplicationName: "Benchmark",
                        corrections: []
                    )
                    let benchmarkContext = AgentWritingContext(
                        destinationApplicationName: "Benchmark",
                        terminology: productionContext.terminology
                            + (fixture.terminology ?? [])
                    )
                    switch arguments.strategy {
                    case .recordedBaseline:
                        guard let baseline = recordedBaselines[fixture.id] else {
                            throw ParityError.arguments(
                                "Missing recorded baseline for fixture: \(fixture.id)"
                            )
                        }
                        output = baseline.output
                        pipelineOutcome = "recorded"
                    case .fullRewrite:
                        output = try await generator!.generate(
                            instructions: WritingBenchmark.systemInstructions(for: fixture),
                            prompt: WritingBenchmark.prompt(
                                for: fixture,
                                repeatTranscript: arguments.repeatTranscript
                            )
                        )
                        pipelineOutcome = "completed"
                    case .safeFullRewrite:
                        let rewritten = await generator!.generateSafeAgentRewrite(
                            transcript: repeatedTranscript,
                            markdownRules: fixture.instructions + "\n\n"
                                + WritingRules.defaultMarkdown(for: .agent),
                            context: benchmarkContext
                        )
                        output = rewritten.output
                        pipelineOutcome = rewritten.outcome
                    case .selectiveSafeRewrite:
                        let rewritten = await generator!.generateSelectiveSafeAgentRewrite(
                            transcript: repeatedTranscript,
                            markdownRules: WritingRules.defaultMarkdown(for: .agent),
                            context: benchmarkContext
                        )
                        output = rewritten.output
                        pipelineOutcome = rewritten.outcome
                    case .structuredEdits:
                        let structured = await generator!.generateStructuredEdits(
                            transcript: repeatedTranscript,
                            markdownRules: fixture.instructions + "\n\n"
                                + WritingRules.defaultMarkdown(for: .agent),
                            context: benchmarkContext
                        )
                        output = structured.output
                        pipelineOutcome = structured.outcome
                    case .deterministicAgent:
                        output = ContextualTranscriptCorrector.correct(
                            DeterministicTranscriptCleaner.clean(repeatedTranscript),
                            context: benchmarkContext
                        )
                        pipelineOutcome = "deterministic"
                    }
                    let measuredLatency = started.duration(to: .now).seconds
                    let latency = if arguments.strategy == .recordedBaseline {
                        recordedBaselines[fixture.id]!.latencySeconds
                    } else {
                        measuredLatency
                    }
                    results.append(WritingBenchmark.evaluate(
                        fixture: fixture,
                        rawOutput: output,
                        latencySeconds: latency,
                        repeatExpected: arguments.repeatTranscript,
                        pipelineOutcome: pipelineOutcome
                    ))
                    writeError(
                        "[\(arguments.strategy.rawValue)] \(results.count)/\(totalRuns) "
                            + "\(fixture.id) run=\(iteration) "
                            + "words=\(WritingBenchmark.normalizedWords(repeatedTranscript).count) "
                            + String(format: "%.2fs", latency)
                    )
                }
            }

            let modelDescription = switch arguments.strategy {
            case .deterministicAgent: "DictationCore deterministic Agent"
            case .recordedBaseline: "Recorded Monologue local history"
            default:
                arguments.modelDirectory?.path
                    ?? "\(arguments.modelID)@\(arguments.revision)"
            }
            let summary = WritingBenchmark.summarize(
                provider: "direct-mlx-swift-\(arguments.strategy.rawValue)",
                model: modelDescription,
                results: results
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(summary)

            if let outputURL = arguments.output {
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: outputURL, options: .atomic)
                print("Wrote \(outputURL.path)")
            } else {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }

            print(String(format: "Required facts: %.1f%%", summary.requiredPassRate * 100))
            print(String(format: "Forbidden removed: %.1f%%", summary.forbiddenPassRate * 100))
            print(String(format: "Reference edit: %.1f%%", summary.meanExpectedWordErrorRate * 100))
            print("Fallbacks: \(summary.fallbackCount)/\(summary.fixtures)")
            print(String(format: "Latency p50/p95: %.2fs / %.2fs", summary.p50LatencySeconds, summary.p95LatencySeconds))
            for bucket in summary.latencyByLength {
                print(String(
                    format: "%@ (%d–%d words) p50/p95: %.2fs / %.2fs",
                    bucket.bucket.rawValue,
                    bucket.minimumInputWords,
                    bucket.maximumInputWords,
                    bucket.p50LatencySeconds,
                    bucket.p95LatencySeconds
                ))
            }
        } catch {
            writeError("dictation-parity: \(error)")
            exit(1)
        }
    }
}

private func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
