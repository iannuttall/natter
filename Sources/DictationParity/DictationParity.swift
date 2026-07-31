import DictationCore
import Foundation
import HuggingFace
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

private struct Arguments {
    var fixtures: URL?
    var output: URL?
    var modelID = "mlx-community/Qwen3.5-9B-MLX-4bit"
    var revision = "938d8919941c6e7efd3c7150eff7fe9d12afa631"
    var repeatTranscript = 1
    var limit: Int?

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
            case "--model":
                index += 1
                guard index < values.count else {
                    throw ParityError.arguments("Missing --model value")
                }
                parsed.modelID = values[index]
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
            case "--limit":
                index += 1
                guard index < values.count,
                      let value = Int(values[index]),
                      value > 0 else {
                    throw ParityError.arguments("--limit must be positive")
                }
                parsed.limit = value
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

    init(modelID: String, revision: String) async throws {
        let configuration = ModelConfiguration(
            id: modelID,
            revision: revision,
            extraEOSTokens: ["<|im_end|>"]
        )
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
}

@main
private enum DictationParity {
    static func main() async {
        do {
            let arguments = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
            guard let fixturesURL = arguments.fixtures else {
                throw ParityError.arguments("--fixtures is required")
            }

            let fixtureSet = try JSONDecoder().decode(
                WritingFixtureSet.self,
                from: Data(contentsOf: fixturesURL)
            )
            let fixtures = arguments.limit.map { Array(fixtureSet.fixtures.prefix($0)) }
                ?? fixtureSet.fixtures
            let generator = try await MLXWritingGenerator(
                modelID: arguments.modelID,
                revision: arguments.revision
            )

            var results: [WritingFixtureResult] = []
            for fixture in fixtures {
                let prompt = WritingBenchmark.prompt(
                    for: fixture,
                    repeatTranscript: arguments.repeatTranscript
                )
                let started = ContinuousClock.now
                let output = try await generator.generate(
                    instructions: WritingBenchmark.baseInstructions,
                    prompt: prompt
                )
                let latency = started.duration(to: .now).seconds
                results.append(WritingBenchmark.evaluate(
                    fixture: fixture,
                    rawOutput: output,
                    latencySeconds: latency
                ))
                writeError(
                    "[direct-mlx] \(results.count)/\(fixtures.count) "
                        + "\(fixture.id) \(String(format: "%.2fs", latency))"
                )
            }

            let summary = WritingBenchmark.summarize(
                provider: "direct-mlx-swift",
                model: "\(arguments.modelID)@\(arguments.revision)",
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
            print(String(format: "Latency p50/p95: %.2fs / %.2fs", summary.p50LatencySeconds, summary.p95LatencySeconds))
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
