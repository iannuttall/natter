import AVFoundation
import FluidAudio
import Foundation

actor SpeechTranscriber {
    private let manager = StreamingNemotronAsrManager(requestedChunkSize: .ms560)
    private var loadedDirectory: URL?

    func prepare(modelDirectory: URL) async throws {
        guard loadedDirectory != modelDirectory else { return }
        try await manager.loadModels(from: modelDirectory)
        loadedDirectory = modelDirectory
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
