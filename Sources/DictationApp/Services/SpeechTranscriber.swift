import AVFoundation
import DictationCore
import FluidAudio
import Foundation

/// One Parakeet Unified checkpoint, two decode paths: a chunked-attention
/// streaming encoder feeds the live overlay preview, and the full-attention
/// offline encoder decodes the retained session audio at stop to produce the
/// transcript that is actually delivered (better WER than any streaming pass).
actor SpeechTranscriber {
    private let finalizer = UnifiedAsrManager()
    private let preview = StreamingUnifiedAsrManager(
        config: UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 1)
    )
    private var retainedSamples: [Float] = []
    private var lastPreviewTranscript = ""
    private var previewFailed = false
    private var loadedDirectory: URL?
    private var preparationTask: Task<Void, Error>?

    func prepare(modelDirectory: URL) async throws {
        guard loadedDirectory != modelDirectory else { return }
        if let preparationTask {
            try await preparationTask.value
            return
        }

        let task = Task {
            try await finalizer.loadModels(from: modelDirectory)
            try await preview.loadModels(from: modelDirectory)
        }
        preparationTask = task
        do {
            try await task.value
            loadedDirectory = modelDirectory
            preparationTask = nil
            await warmUp()
        } catch {
            preparationTask = nil
            throw error
        }
    }

    func install(
        to modelsDirectory: URL,
        progressHandler: @escaping ProgressHandler
    ) async throws {
        try await finalizer.loadModels(to: modelsDirectory, progressHandler: progressHandler)
        try await preview.loadModels(to: modelsDirectory, progressHandler: progressHandler)
        loadedDirectory = modelsDirectory.appendingPathComponent(
            SpeechModelLocation.relativePath,
            isDirectory: true
        )
        await warmUp()
    }

    func unload() async {
        preparationTask?.cancel()
        preparationTask = nil
        await finalizer.cleanup()
        await preview.cleanup()
        retainedSamples.removeAll()
        lastPreviewTranscript = ""
        loadedDirectory = nil
    }

    func reset() async {
        retainedSamples.removeAll()
        lastPreviewTranscript = ""
        previewFailed = false
        try? await finalizer.reset()
        try? await preview.reset()
    }

    /// Buffers session audio for the batch pass and advances the streaming
    /// preview. Preview failures are non-fatal: the final transcript only
    /// depends on the retained audio, so a broken preview must never kill a
    /// dictation that the batch decode could still rescue.
    func consume(_ chunk: AudioChunk) async throws -> String {
        retainedSamples.append(contentsOf: chunk.samples)
        guard !previewFailed else { return lastPreviewTranscript }
        do {
            try await preview.appendAudio(chunk.makeBuffer())
            try await preview.processBufferedAudio()
            lastPreviewTranscript = await preview.getPartialTranscript()
        } catch {
            previewFailed = true
            NatterLog.model.error(
                "speech preview failed, batch decode still active error=\(error.localizedDescription, privacy: .public)"
            )
        }
        return lastPreviewTranscript
    }

    func finish() async throws -> String {
        let transcript = try await finalizer.transcribe(retainedSamples)
        await reset()
        return transcript
    }

    /// Runs one synthetic pass through both encoders so ANE graph
    /// materialization happens at warm-up instead of on the first dictation.
    private func warmUp() async {
        let silence = [Float](repeating: 0, count: 16_000)
        _ = try? await finalizer.transcribe(silence)
        try? await finalizer.reset()
        if let buffer = try? AudioChunk(samples: silence, sampleRate: 16_000).makeBuffer() {
            try? await preview.appendAudio(buffer)
            try? await preview.processBufferedAudio()
            try? await preview.reset()
        }
    }
}
