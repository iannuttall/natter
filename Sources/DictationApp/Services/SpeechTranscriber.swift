import AVFoundation
import DictationCore
import FluidAudio
import Foundation

actor SpeechTranscriber {
    private let manager = StreamingNemotronAsrManager(requestedChunkSize: .ms560)
    private var loadedDirectory: URL?
    private var preparationTask: Task<Void, Error>?

    func prepare(modelDirectory: URL) async throws {
        guard loadedDirectory != modelDirectory else { return }
        if let preparationTask {
            try await preparationTask.value
            return
        }

        let task = Task { try await manager.loadModels(from: modelDirectory) }
        preparationTask = task
        do {
            try await task.value
            loadedDirectory = modelDirectory
            preparationTask = nil
        } catch {
            preparationTask = nil
            throw error
        }
    }

    func install(
        to modelsDirectory: URL,
        progressHandler: @escaping ProgressHandler
    ) async throws {
        try await manager.loadModels(
            to: modelsDirectory,
            progressHandler: progressHandler
        )
        loadedDirectory = modelsDirectory.appendingPathComponent(
            SpeechModelLocation.relativePath,
            isDirectory: true
        )
    }

    func unload() async {
        preparationTask?.cancel()
        preparationTask = nil
        await manager.cleanup()
        loadedDirectory = nil
    }

    func reset() async {
        await manager.reset()
    }

    func consume(_ chunk: AudioChunk) async throws -> String {
        let buffer = try chunk.makeBuffer()
        try await manager.appendAudio(buffer)
        try await manager.processBufferedAudio()
        return await manager.getPartialTranscript()
    }

    func finish() async throws -> String {
        let silence = AudioChunk(samples: [Float](repeating: 0, count: 4_000), sampleRate: 16_000)
        try await manager.appendAudio(silence.makeBuffer())
        try await manager.processBufferedAudio()
        let transcript = try await manager.finish()
        await manager.reset()
        return transcript
    }
}
