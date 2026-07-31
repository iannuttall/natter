import AVFoundation
import Foundation

struct AudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double

    var level: Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0) { $0 + ($1 * $1) } / Float(samples.count)
        return min(1, sqrt(meanSquare) * 8)
    }

    func makeBuffer() throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let destination = buffer.floatChannelData?[0] else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        destination.update(from: samples, count: samples.count)
        return buffer
    }
}

enum MicrophoneCaptureError: LocalizedError {
    case noInputChannel
    case unsupportedAudioFormat

    var errorDescription: String? {
        switch self {
        case .noInputChannel: "No microphone input is available."
        case .unsupportedAudioFormat: "The microphone audio format is unsupported."
        }
    }
}

@MainActor
final class MicrophoneCapture {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AudioChunk>.Continuation?

    func start(
        levelHandler: @escaping @MainActor @Sendable (Float) -> Void
    ) throws -> AsyncStream<AudioChunk> {
        stop()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw MicrophoneCaptureError.noInputChannel }

        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
        self.continuation = continuation

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeTapHandler(
                continuation: continuation,
                levelHandler: levelHandler
            )
        )

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            continuation.finish()
            self.continuation = nil
            throw error
        }
        return stream
    }

    nonisolated private static func makeTapHandler(
        continuation: AsyncStream<AudioChunk>.Continuation,
        levelHandler: @escaping @MainActor @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = Array(
                UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            )
            let chunk = AudioChunk(samples: samples, sampleRate: buffer.format.sampleRate)
            continuation.yield(chunk)
            Task { @MainActor in levelHandler(chunk.level) }
        }
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        continuation?.finish()
        continuation = nil
    }
}
