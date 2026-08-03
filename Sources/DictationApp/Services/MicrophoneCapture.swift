import AudioToolbox
import AVFoundation
import CoreAudio
import DictationCore
import Foundation

struct AudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double

    var level: Float {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0) { $0 + ($1 * $1) } / Float(samples.count)
        guard meanSquare > 0 else { return 0 }

        let decibels = 10 * log10(meanSquare)
        let noiseFloor: Float = -55
        let speechCeiling: Float = -15
        return min(1, max(0, (decibels - noiseFloor) / (speechCeiling - noiseFloor)))
    }

    var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(samples.count) / sampleRate
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

/// Converts tap buffers to the 16 kHz mono format every downstream consumer
/// expects, using one long-lived stateful `AVAudioConverter` per engine start.
/// A fresh converter per buffer (the previous behavior, via FluidAudio's
/// stateless per-call conversion) injects a warm-up transient at every buffer
/// boundary — ~47 discontinuities per second in the signal the mel extractor
/// sees. Instances are only touched from the audio tap thread.
final class CaptureFormatConverter {
    static let targetSampleRate: Double = 16_000

    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat

    init?(inputFormat: AVAudioFormat) {
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.targetSampleRate,
                channels: 1,
                interleaved: false
            )
        else { return nil }
        self.outputFormat = outputFormat

        if inputFormat.sampleRate == Self.targetSampleRate,
           inputFormat.channelCount == 1,
           inputFormat.commonFormat == .pcmFormatFloat32 {
            converter = nil
        } else if let converter = AVAudioConverter(from: inputFormat, to: outputFormat) {
            self.converter = converter
        } else {
            return nil
        }
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let converter else {
            guard let channel = buffer.floatChannelData?[0] else { return nil }
            return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }
        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let channel = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

enum MicrophoneCaptureError: LocalizedError {
    case noInputChannel
    case selectedDeviceUnavailable
    case unsupportedAudioFormat
    case unableToSelectDevice(OSStatus)

    var errorDescription: String? {
        switch self {
        case .noInputChannel: "No microphone input is available."
        case .selectedDeviceUnavailable:
            "The selected microphone is unavailable. Natter used the system default instead."
        case .unsupportedAudioFormat: "The microphone audio format is unsupported."
        case let .unableToSelectDevice(status):
            "Natter could not select that microphone (Core Audio error \(status))."
        }
    }
}

private final class AudioCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var preRoll: TimedPreRollBuffer<AudioChunk>
    private var continuation: AsyncStream<AudioChunk>.Continuation?
    private var levelHandler: (@MainActor @Sendable (Float, [Float]?) -> Void)?
    private var firstBufferHandler: (@MainActor @Sendable () -> Void)?
    private var routeFailureHandler: (@MainActor @Sendable (Error) -> Void)?
    private var deliveredFirstBuffer = false
    private var observedAnyBuffer = false
    private var stopTiming = AdaptiveStopTimingEstimator()

    init(maximumPreRollDuration: TimeInterval) {
        preRoll = TimedPreRollBuffer(maximumDuration: maximumPreRollDuration)
    }

    func resetForArm(generation: Int) {
        lock.withLock {
            self.generation = generation
            preRoll.removeAll()
            continuation = nil
            levelHandler = nil
            firstBufferHandler = nil
            routeFailureHandler = nil
            deliveredFirstBuffer = false
            observedAnyBuffer = false
            stopTiming.reset()
        }
    }

    func updateGeneration(_ generation: Int) {
        lock.withLock { self.generation = generation }
    }

    func begin(
        continuation: AsyncStream<AudioChunk>.Continuation,
        levelHandler: @escaping @MainActor @Sendable (Float, [Float]?) -> Void,
        firstBufferHandler: @escaping @MainActor @Sendable () -> Void,
        routeFailureHandler: @escaping @MainActor @Sendable (Error) -> Void
    ) -> TimeInterval {
        var shouldMarkFirstBuffer = false
        var bufferedDuration: TimeInterval = 0
        lock.lock()
        self.continuation = continuation
        self.levelHandler = levelHandler
        self.firstBufferHandler = firstBufferHandler
        self.routeFailureHandler = routeFailureHandler
        bufferedDuration = preRoll.duration
        let bufferedChunks = preRoll.drain()
        for chunk in bufferedChunks { continuation.yield(chunk) }
        if !bufferedChunks.isEmpty {
            deliveredFirstBuffer = true
            shouldMarkFirstBuffer = true
        }
        lock.unlock()

        if shouldMarkFirstBuffer {
            Task { @MainActor in firstBufferHandler() }
        }
        return bufferedDuration
    }

    func receive(_ chunk: AudioChunk, bands: [Float]?, generation: Int) {
        var levelHandler: (@MainActor @Sendable (Float, [Float]?) -> Void)?
        var firstBufferHandler: (@MainActor @Sendable () -> Void)?
        var continuation: AsyncStream<AudioChunk>.Continuation?

        lock.lock()
        guard generation == self.generation else {
            lock.unlock()
            return
        }
        if !observedAnyBuffer {
            observedAnyBuffer = true
            NatterLog.audio.notice(
                "first capture buffer frames=\(chunk.samples.count) sample_rate=\(String(format: "%.0f", chunk.sampleRate), privacy: .public)"
            )
        }
        recordTiming(for: chunk)
        if let activeContinuation = self.continuation {
            continuation = activeContinuation
            levelHandler = self.levelHandler
            if !deliveredFirstBuffer {
                deliveredFirstBuffer = true
                firstBufferHandler = self.firstBufferHandler
            }
        } else {
            preRoll.append(chunk, duration: chunk.duration)
        }
        lock.unlock()

        continuation?.yield(chunk)
        if let levelHandler {
            let level = chunk.level
            Task { @MainActor in levelHandler(level, bands) }
        }
        if let firstBufferHandler {
            Task { @MainActor in firstBufferHandler() }
        }
    }

    func stopTimingEstimate() -> TimeInterval {
        lock.withLock {
            stopTiming.gracePeriod
        }
    }

    func finish() {
        let continuation = lock.withLock { () -> AsyncStream<AudioChunk>.Continuation? in
            let continuation = self.continuation
            self.continuation = nil
            levelHandler = nil
            firstBufferHandler = nil
            routeFailureHandler = nil
            preRoll.removeAll()
            return continuation
        }
        continuation?.finish()
    }

    func failRouteChange(_ error: Error) {
        let handler = lock.withLock { routeFailureHandler }
        finish()
        if let handler { Task { @MainActor in handler(error) } }
    }

    private func recordTiming(for chunk: AudioChunk) {
        stopTiming.observe(
            callbackAt: ProcessInfo.processInfo.systemUptime,
            bufferDuration: chunk.duration
        )
    }
}

@MainActor
final class MicrophoneCapture {
    private let inputDevices: AudioInputDeviceManager
    // Long enough to survive a cold speech-model load without losing the
    // opening words; 3 s of 16 kHz mono float is under 200 KB.
    private let state = AudioCaptureState(maximumPreRollDuration: 3.0)
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var selectionObserver: NSObjectProtocol?
    private var generation = 0
    private var tapInstalled = false
    private(set) var isRecording = false

    init(inputDevices: AudioInputDeviceManager = .shared) {
        self.inputDevices = inputDevices
        selectionObserver = NotificationCenter.default.addObserver(
            forName: .natterAudioInputSelectionDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartForRouteChange(reason: "selection") }
        }
    }

    func arm() throws {
        guard engine?.isRunning != true else { return }
        let startedAt = ProcessInfo.processInfo.systemUptime
        generation += 1
        state.resetForArm(generation: generation)
        try startEngine(reason: "first-tap")
        let elapsed = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        NatterLog.performance.notice(
            "capture arm elapsed_ms=\(String(format: "%.1f", elapsed), privacy: .public)"
        )
    }

    func start(
        levelHandler: @escaping @MainActor @Sendable (Float, [Float]?) -> Void,
        firstBufferHandler: @escaping @MainActor @Sendable () -> Void = {},
        routeFailureHandler: @escaping @MainActor @Sendable (Error) -> Void = { _ in }
    ) throws -> AsyncStream<AudioChunk> {
        if engine?.isRunning != true { try arm() }

        // Unbounded so a MainActor stall can never silently drop audio from
        // the middle of an utterance; each buffered chunk is ~1.4 KB.
        let (stream, continuation) = AsyncStream<AudioChunk>.makeStream(
            bufferingPolicy: .unbounded
        )
        let preRollDuration = state.begin(
            continuation: continuation,
            levelHandler: levelHandler,
            firstBufferHandler: firstBufferHandler,
            routeFailureHandler: routeFailureHandler
        )
        NatterLog.performance.notice(
            "capture pre_roll_ms=\(String(format: "%.1f", preRollDuration * 1_000), privacy: .public)"
        )
        isRecording = true
        return stream
    }

    func stopDrainingTail() async {
        let grace = state.stopTimingEstimate()
        NatterLog.audio.notice(
            "draining capture tail grace_ms=\(String(format: "%.1f", grace * 1_000), privacy: .public)"
        )
        try? await Task.sleep(for: .seconds(grace))
        stopImmediately()
    }

    func disarmIfIdle() {
        guard !isRecording else { return }
        stopImmediately()
    }

    func stopImmediately() {
        generation += 1
        state.updateGeneration(generation)
        state.finish()
        detachEngine()
        isRecording = false
    }

    private func startEngine(reason: String) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        try selectConfiguredDevice(on: input)
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw MicrophoneCaptureError.noInputChannel }
        guard let converter = CaptureFormatConverter(inputFormat: format) else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }
        let callbackGeneration = generation

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format,
            block: Self.makeTapHandler(
                state: state,
                converter: converter,
                generation: callbackGeneration
            )
        )
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw error
        }
        self.engine = engine
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartForRouteChange(reason: "engine-configuration") }
        }
        NatterLog.audio.notice(
            "capture engine active reason=\(reason, privacy: .public) sample_rate=\(String(format: "%.0f", format.sampleRate), privacy: .public) channels=\(format.channelCount)"
        )
    }

    nonisolated private static func makeTapHandler(
        state: AudioCaptureState,
        converter: CaptureFormatConverter,
        generation: Int
    ) -> AVAudioNodeTapBlock {
        // The tap block runs serially on the audio thread; the converter and
        // analyzer are touched nowhere else, so their single-threaded
        // contracts hold.
        nonisolated(unsafe) let converter = converter
        nonisolated(unsafe) let analyzer = SpectrumAnalyzer()
        return { @Sendable buffer, _ in
            guard let samples = converter.convert(buffer), !samples.isEmpty else { return }
            state.receive(
                AudioChunk(samples: samples, sampleRate: CaptureFormatConverter.targetSampleRate),
                bands: analyzer?.bands(appending: samples),
                generation: generation
            )
        }
    }

    private func restartForRouteChange(reason: String) {
        guard engine != nil else { return }
        generation += 1
        state.updateGeneration(generation)
        detachEngine()
        do {
            try startEngine(reason: reason)
            NatterLog.audio.notice("capture route recovered reason=\(reason, privacy: .public)")
        } catch {
            isRecording = false
            state.failRouteChange(error)
            NatterLog.audio.error(
                "capture route recovery failed error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func detachEngine() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        if tapInstalled, let input = engine?.inputNode {
            input.removeTap(onBus: 0)
        }
        tapInstalled = false
        engine?.stop()
        engine = nil
    }

    private func selectConfiguredDevice(on input: AVAudioInputNode) throws {
        guard !inputDevices.selectedDeviceUID.isEmpty else { return }
        guard let deviceID = inputDevices.selectedDeviceID else {
            NatterLog.audio.error("selected microphone unavailable; using system default")
            return
        }
        guard let audioUnit = input.audioUnit else {
            throw MicrophoneCaptureError.unsupportedAudioFormat
        }
        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw MicrophoneCaptureError.unableToSelectDevice(status)
        }
    }
}
