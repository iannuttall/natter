import AppKit
import Foundation
import NatterCore

extension DictationCoordinator {
    func prepareForDebug() {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await prepareTranscriber()
                store.statusMessage = "Speech model ready"
                FileHandle.standardError.write(Data("DICTATION_SPEECH_MODEL_READY\n".utf8))
            } catch {
                fail(error)
                FileHandle.standardError.write(
                    Data("DICTATION_SPEECH_MODEL_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

    func warmRefineModelIfInstalled() {
        guard modes.enabledModes.contains(where: { $0.processing == .refine }) else { return }
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let directory = AgentWritingModelLocation.resolve(in: paths) else { return }
        Task { await writingEngine.warmRefine(modelDirectory: directory) }
    }

    func warmWritingModelIfInstalled() {
        let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
        guard let directory = WritingModelLocation.resolve(in: paths) else { return }
        Task { await writingEngine.warmWriting(modelDirectory: directory) }
    }

    func testWritingForDebug(
        _ transcript: String,
        mode: DictationMode,
        iterations: Int = 1,
        delay: Duration = .zero
    ) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await Task.sleep(for: delay)
                let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
                let qualityDirectory = WritingModelLocation.resolve(in: paths)
                let agentDirectory = AgentWritingModelLocation.resolve(in: paths)
                let definition = modes.definition(for: mode)
                if definition.processing == .rewrite, qualityDirectory == nil {
                    throw DictationCoordinatorError.writingModelMissing
                }
                for iteration in 1...max(iterations, 1) {
                    let startedAt = ProcessInfo.processInfo.systemUptime
                    let output = try await writingEngine.transform(
                        transcript: transcript,
                        mode: mode,
                        modeName: modes.name(for: mode),
                        processing: definition.processing,
                        markdownRules: definition.instructions,
                        modelDirectory: qualityDirectory,
                        agentModelDirectory: agentDirectory,
                        agentContext: AgentWritingContext.production(
                            destinationApplicationName: "Debug",
                            corrections: DictationTranscriptPipeline.applicableCorrections(
                                rules.corrections,
                                for: mode
                            )
                        )
                    )
                    let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                    let result =
                        "DICTATION_WRITING_RESULT run=\(iteration) "
                        + "elapsed_ms=\(String(format: "%.1f", milliseconds)): \(output)\n"
                    FileHandle.standardError.write(Data(result.utf8))
                }
                if ProcessInfo.processInfo.environment["DICTATION_EXIT_AFTER_WRITING"] == "1" {
                    NSApp.terminate(nil)
                }
            } catch {
                FileHandle.standardError.write(
                    Data("DICTATION_WRITING_ERROR: \(error.localizedDescription)\n".utf8)
                )
                if ProcessInfo.processInfo.environment["DICTATION_EXIT_AFTER_WRITING"] == "1" {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func testCorrectionForDebug(command: String, previousTranscript: String) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                let paths = AppPaths.live(bundleIdentifier: AppInfo.bundleIdentifier)
                guard
                    let modelDirectory = WritingModelLocation.resolve(in: paths)
                        ?? AgentWritingModelLocation.resolve(in: paths)
                else {
                    throw WritingEngineError.modelMissing
                }
                let correction = try await writingEngine.extractPersonalCorrection(
                    command: command,
                    previousTranscript: previousTranscript,
                    modelDirectory: modelDirectory
                )
                let result = correction.map { "\($0.heard) -> \($0.replacement)" } ?? "none"
                FileHandle.standardError.write(
                    Data("DICTATION_CORRECTION_RESULT: \(result)\n".utf8)
                )
            } catch {
                FileHandle.standardError.write(
                    Data("DICTATION_CORRECTION_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
            if ProcessInfo.processInfo.environment["DICTATION_EXIT_AFTER_CORRECTION"] == "1" {
                NSApp.terminate(nil)
            }
        }
    }

    func testInsertionForDebug(_ text: String, delay: Duration = .seconds(2)) {
        sessionTask?.cancel()
        sessionTask = Task {
            do {
                try await Task.sleep(for: delay)
                let target = try textInserter.captureTarget()
                FileHandle.standardError.write(
                    Data(
                        ("NATTER_INSERT_TARGET: \(target.applicationName ?? "unknown") "
                            + "\(target.bundleIdentifier ?? "unknown") "
                            + "\(target.capturedElementRole ?? "app-fallback")\n").utf8))
                let startedAt = ProcessInfo.processInfo.systemUptime
                try await textInserter.insert(
                    text,
                    into: target,
                    paceTerminalInput: false
                )
                let milliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
                FileHandle.standardError.write(
                    Data(
                        "NATTER_INSERT_RESULT: success "
                            .appending("elapsed_ms=\(String(format: "%.1f", milliseconds))\n")
                            .utf8
                    )
                )
            } catch {
                FileHandle.standardError.write(
                    Data("NATTER_INSERT_ERROR: \(error.localizedDescription)\n".utf8)
                )
            }
        }
    }

}
