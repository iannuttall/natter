import AVFoundation
import FluidAudio
import Foundation
import Speech

// Standalone ASR evaluation harness. Feeds manifest audio through the engine
// configurations Natter ships (or is considering) and reports WER plus the
// latency the user actually feels: time from stop to final transcript.
//
// Usage:
//   dictation-asr-eval --mode <mode> --manifest manifest.json --output out.json
//     [--nemotron-dir DIR] [--unified-dir DIR]
//
// Modes:
//   nemotron-stream      current app pipeline: 48 kHz mic-sized buffers into
//                        StreamingNemotronAsrManager(.ms560); FluidAudio
//                        resamples each buffer with a fresh converter
//   nemotron-stream-16k  same engine, but audio pre-converted to 16 kHz with a
//                        single stateful converter (isolates resampler damage)
//   unified-batch        proposed pipeline: capture-time stateful conversion to
//                        16 kHz, one UnifiedAsrManager.transcribe at stop
//   unified-stream-322   StreamingUnifiedAsrManager 70_2_2 (320 ms latency)
//   unified-stream-771   StreamingUnifiedAsrManager 70_7_1 (640 ms latency)
//   speechanalyzer       Apple SpeechAnalyzer (macOS 26+)

struct ManifestEntry: Codable {
    let id: String
    let audio: String
    let reference: String
    let bucket: String
}

struct FileResult: Codable {
    let id: String
    let bucket: String
    let audioSeconds: Double
    let reference: String
    let hypothesis: String
    let wer: Double
    let feedSeconds: Double
    let stopToFinalSeconds: Double
}

struct EvalOutput: Codable {
    let mode: String
    let modelLoadSeconds: Double
    let results: [FileResult]
}

// MARK: - WER

func normalizeTokens(_ text: String) -> [String] {
    let lowered = text.lowercased()
    var cleaned = ""
    cleaned.reserveCapacity(lowered.count)
    for scalar in lowered.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
            cleaned.unicodeScalars.append(scalar)
        } else {
            cleaned.append(" ")
        }
    }
    return cleaned.split(separator: " ").map(String.init)
}

func wordErrorRate(reference: String, hypothesis: String) -> Double {
    let ref = normalizeTokens(reference)
    let hyp = normalizeTokens(hypothesis)
    guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }

    var previous = Array(0...hyp.count)
    var current = [Int](repeating: 0, count: hyp.count + 1)
    for i in 1...ref.count {
        current[0] = i
        for j in 1...hyp.count {
            let substitution = previous[j - 1] + (ref[i - 1] == hyp[j - 1] ? 0 : 1)
            current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
        }
        swap(&previous, &current)
    }
    return Double(previous[hyp.count]) / Double(ref.count)
}

// MARK: - Audio helpers

struct LoadedAudio {
    let samples: [Float]
    let sampleRate: Double

    var duration: Double { Double(samples.count) / sampleRate }
}

func loadAudio(path: String) throws -> LoadedAudio {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: file.processingFormat.sampleRate,
        channels: 1,
        interleaved: false
    )!
    let frameCount = AVAudioFrameCount(file.length)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
        throw EvalError.audio("cannot allocate buffer for \(path)")
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else {
        throw EvalError.audio("no channel data in \(path)")
    }
    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    return LoadedAudio(samples: samples, sampleRate: file.processingFormat.sampleRate)
}

func makeBuffer(samples: ArraySlice<Float>, sampleRate: Double) throws -> AVAudioPCMBuffer {
    guard
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
        let destination = buffer.floatChannelData?[0]
    else { throw EvalError.audio("cannot build buffer") }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    samples.withUnsafeBufferPointer { destination.update(from: $0.baseAddress!, count: $0.count) }
    return buffer
}

/// Single stateful streaming resampler — the capture-path design Natter is
/// moving to. Feeding chunks through one converter avoids the per-buffer
/// warm-up transients of FluidAudio's stateless per-call conversion.
final class StatefulResampler {
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    init(inputRate: Double, outputRate: Double = 16_000) throws {
        guard
            let input = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: inputRate, channels: 1, interleaved: false),
            let output = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: input, to: output)
        else { throw EvalError.audio("cannot create converter") }
        self.inputFormat = input
        self.outputFormat = output
        self.converter = converter
    }

    func convert(_ samples: ArraySlice<Float>, drain: Bool = false) throws -> [Float] {
        let inputBuffer = try makeBuffer(samples: samples, sampleRate: inputFormat.sampleRate)
        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw EvalError.audio("cannot allocate output buffer")
        }
        var fed = false
        var conversionError: NSError?
        converter.convert(to: outputBuffer, error: &conversionError) { _, status in
            if fed {
                status.pointee = drain ? .endOfStream : .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return inputBuffer
        }
        if let conversionError { throw conversionError }
        guard let channel = outputBuffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
    }
}

enum EvalError: Error, CustomStringConvertible {
    case usage(String)
    case audio(String)
    case engine(String)

    var description: String {
        switch self {
        case .usage(let message), .audio(let message), .engine(let message): message
        }
    }
}

// MARK: - Engine runners

let micBufferFrames = 1_024  // AVAudioEngine tap size Natter uses

protocol EngineRunner {
    mutating func load() async throws -> Double
    mutating func run(_ audio: LoadedAudio) async throws -> (String, Double, Double)
}

/// Replicates SpeechTranscriber/DictationCoordinator behavior: mic-sized
/// buffers appended one at a time, partial fetched per buffer, 250 ms of
/// silence appended before finish, reset after.
struct NemotronRunner: EngineRunner {
    let modelDirectory: URL
    let preconvertTo16k: Bool
    var manager: StreamingNemotronAsrManager?

    mutating func load() async throws -> Double {
        let manager = StreamingNemotronAsrManager(requestedChunkSize: .ms560)
        let start = ContinuousClock.now
        try await manager.loadModels(from: modelDirectory)
        self.manager = manager
        return seconds(since: start)
    }

    mutating func run(_ audio: LoadedAudio) async throws -> (String, Double, Double) {
        guard let manager else { throw EvalError.engine("nemotron not loaded") }
        let resampler = preconvertTo16k
            ? try StatefulResampler(inputRate: audio.sampleRate) : nil

        let feedStart = ContinuousClock.now
        var index = 0
        while index < audio.samples.count {
            let end = min(index + micBufferFrames, audio.samples.count)
            let slice = audio.samples[index..<end]
            index = end
            if let resampler {
                let converted = try resampler.convert(slice)
                if converted.isEmpty { continue }
                try await manager.appendAudio(
                    try makeBuffer(samples: converted[...], sampleRate: 16_000))
            } else {
                try await manager.appendAudio(
                    try makeBuffer(samples: slice, sampleRate: audio.sampleRate))
            }
            try await manager.processBufferedAudio()
            _ = await manager.getPartialTranscript()
        }
        let feed = seconds(since: feedStart)

        let stopStart = ContinuousClock.now
        let silence = [Float](repeating: 0, count: 4_000)
        try await manager.appendAudio(try makeBuffer(samples: silence[...], sampleRate: 16_000))
        try await manager.processBufferedAudio()
        let transcript = try await manager.finish()
        let stopToFinal = seconds(since: stopStart)
        try? await manager.reset()
        return (transcript, feed, stopToFinal)
    }
}

/// Proposed pipeline: stateful conversion during capture, batch decode at stop.
struct UnifiedBatchRunner: EngineRunner {
    let modelDirectory: URL
    var manager: UnifiedAsrManager?

    mutating func load() async throws -> Double {
        let manager = UnifiedAsrManager()
        let start = ContinuousClock.now
        try await manager.loadModels(from: modelDirectory)
        self.manager = manager
        return seconds(since: start)
    }

    mutating func run(_ audio: LoadedAudio) async throws -> (String, Double, Double) {
        guard let manager else { throw EvalError.engine("unified not loaded") }
        // Conversion happens incrementally during capture in the real app, so
        // it counts as feed time, not stop latency.
        let feedStart = ContinuousClock.now
        var samples16k: [Float] = []
        samples16k.reserveCapacity(Int(audio.duration * 16_000) + 16)
        if audio.sampleRate == 16_000 {
            samples16k = audio.samples
        } else {
            let resampler = try StatefulResampler(inputRate: audio.sampleRate)
            var index = 0
            while index < audio.samples.count {
                let end = min(index + micBufferFrames, audio.samples.count)
                samples16k.append(contentsOf: try resampler.convert(audio.samples[index..<end]))
                index = end
            }
            samples16k.append(contentsOf: try resampler.convert([][...], drain: true))
        }
        let feed = seconds(since: feedStart)

        let stopStart = ContinuousClock.now
        let transcript = try await manager.transcribe(samples16k)
        let stopToFinal = seconds(since: stopStart)
        try? await manager.reset()
        return (transcript, feed, stopToFinal)
    }
}

struct UnifiedStreamRunner: EngineRunner {
    let modelDirectory: URL
    let chunkFrames: Int
    let rightFrames: Int
    var manager: StreamingUnifiedAsrManager?

    mutating func load() async throws -> Double {
        let config = UnifiedConfig(leftFrames: 70, chunkFrames: chunkFrames, rightFrames: rightFrames)
        let manager = StreamingUnifiedAsrManager(config: config)
        let start = ContinuousClock.now
        try await manager.loadModels(from: modelDirectory)
        self.manager = manager
        return seconds(since: start)
    }

    mutating func run(_ audio: LoadedAudio) async throws -> (String, Double, Double) {
        guard let manager else { throw EvalError.engine("unified-stream not loaded") }
        let resampler = try StatefulResampler(inputRate: audio.sampleRate)

        let feedStart = ContinuousClock.now
        var index = 0
        while index < audio.samples.count {
            let end = min(index + micBufferFrames, audio.samples.count)
            let converted = audio.sampleRate == 16_000
                ? Array(audio.samples[index..<end])
                : try resampler.convert(audio.samples[index..<end])
            index = end
            guard !converted.isEmpty else { continue }
            try await manager.appendAudio(try makeBuffer(samples: converted[...], sampleRate: 16_000))
            try await manager.processBufferedAudio()
            _ = await manager.getPartialTranscript()
        }
        let feed = seconds(since: feedStart)

        let stopStart = ContinuousClock.now
        let transcript = try await manager.finish()
        let stopToFinal = seconds(since: stopStart)
        try? await manager.reset()
        return (transcript, feed, stopToFinal)
    }
}

struct SpeechAnalyzerRunner: EngineRunner {
    mutating func load() async throws -> Double {
        guard #available(macOS 26.0, *) else {
            throw EvalError.engine("speechanalyzer requires macOS 26")
        }
        let start = ContinuousClock.now
        let locale = Locale(identifier: "en_US")
        let transcriber = Speech.SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return seconds(since: start)
    }

    mutating func run(_ audio: LoadedAudio) async throws -> (String, Double, Double) {
        guard #available(macOS 26.0, *) else {
            throw EvalError.engine("speechanalyzer requires macOS 26")
        }
        let locale = Locale(identifier: "en_US")
        let transcriber = Speech.SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard
            let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
                compatibleWith: [transcriber])
        else { throw EvalError.engine("no compatible SpeechAnalyzer format") }

        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: stream)

        let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: audio.sampleRate, channels: 1,
            interleaved: false)!
        guard let converter = AVAudioConverter(from: sourceFormat, to: analyzerFormat) else {
            throw EvalError.engine("cannot convert to SpeechAnalyzer format")
        }

        let feedStart = ContinuousClock.now
        var index = 0
        while index < audio.samples.count {
            let end = min(index + micBufferFrames, audio.samples.count)
            let input = try makeBuffer(samples: audio.samples[index..<end], sampleRate: audio.sampleRate)
            index = end
            let ratio = analyzerFormat.sampleRate / audio.sampleRate
            let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
            guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity)
            else { throw EvalError.engine("cannot allocate analyzer buffer") }
            var fed = false
            var conversionError: NSError?
            converter.convert(to: output, error: &conversionError) { _, status in
                if fed {
                    status.pointee = .noDataNow
                    return nil
                }
                fed = true
                status.pointee = .haveData
                return input
            }
            if let conversionError { throw conversionError }
            if output.frameLength > 0 {
                continuation.yield(AnalyzerInput(buffer: output))
            }
        }
        let feed = seconds(since: feedStart)

        let stopStart = ContinuousClock.now
        continuation.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let transcript = try await collector.value
        let stopToFinal = seconds(since: stopStart)
        return (transcript, feed, stopToFinal)
    }
}

func seconds(since start: ContinuousClock.Instant) -> Double {
    let elapsed = start.duration(to: .now)
    return Double(elapsed.components.seconds)
        + Double(elapsed.components.attoseconds) / 1e18
}

// MARK: - Main

func parseArguments() throws -> (mode: String, manifest: URL, output: URL, nemotronDir: URL, unifiedDir: URL) {
    var mode: String?
    var manifest: String?
    var output: String?
    let home = FileManager.default.homeDirectoryForCurrentUser
    var nemotronDir =
        home
        .appendingPathComponent("Library/Application Support/is.ian.natter/Models/nemotron-streaming/560ms")
    var unifiedDir =
        home
        .appendingPathComponent("Library/Application Support/FluidAudio/Models/parakeet-unified-en-0.6b")

    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--mode": mode = iterator.next()
        case "--manifest": manifest = iterator.next()
        case "--output": output = iterator.next()
        case "--nemotron-dir":
            if let value = iterator.next() { nemotronDir = URL(fileURLWithPath: value) }
        case "--unified-dir":
            if let value = iterator.next() { unifiedDir = URL(fileURLWithPath: value) }
        default: throw EvalError.usage("unknown argument \(argument)")
        }
    }
    guard let mode, let manifest, let output else {
        throw EvalError.usage("required: --mode --manifest --output")
    }
    return (mode, URL(fileURLWithPath: manifest), URL(fileURLWithPath: output), nemotronDir, unifiedDir)
}

let arguments = try parseArguments()
let manifestData = try Data(contentsOf: arguments.manifest)
let entries = try JSONDecoder().decode([ManifestEntry].self, from: manifestData)
let manifestDirectory = arguments.manifest.deletingLastPathComponent()

var runner: any EngineRunner
switch arguments.mode {
case "nemotron-stream":
    runner = NemotronRunner(modelDirectory: arguments.nemotronDir, preconvertTo16k: false)
case "nemotron-stream-16k":
    runner = NemotronRunner(modelDirectory: arguments.nemotronDir, preconvertTo16k: true)
case "unified-batch":
    runner = UnifiedBatchRunner(modelDirectory: arguments.unifiedDir)
case "unified-stream-322":
    runner = UnifiedStreamRunner(modelDirectory: arguments.unifiedDir, chunkFrames: 2, rightFrames: 2)
case "unified-stream-771":
    runner = UnifiedStreamRunner(modelDirectory: arguments.unifiedDir, chunkFrames: 7, rightFrames: 1)
case "speechanalyzer":
    runner = SpeechAnalyzerRunner()
default:
    throw EvalError.usage("unknown mode \(arguments.mode)")
}

let loadSeconds = try await runner.load()
FileHandle.standardError.write(Data("model load: \(String(format: "%.2f", loadSeconds))s\n".utf8))

var results: [FileResult] = []
for entry in entries {
    let audioPath =
        entry.audio.hasPrefix("/")
        ? entry.audio : manifestDirectory.appendingPathComponent(entry.audio).path
    let audio = try loadAudio(path: audioPath)
    let (hypothesis, feed, stopToFinal) = try await runner.run(audio)
    let wer = wordErrorRate(reference: entry.reference, hypothesis: hypothesis)
    results.append(
        FileResult(
            id: entry.id, bucket: entry.bucket, audioSeconds: audio.duration,
            reference: entry.reference, hypothesis: hypothesis, wer: wer,
            feedSeconds: feed, stopToFinalSeconds: stopToFinal))
    FileHandle.standardError.write(
        Data(
            "\(entry.id) [\(entry.bucket)] \(String(format: "%.1f", audio.duration))s wer=\(String(format: "%.3f", wer)) stop→final=\(String(format: "%.3f", stopToFinal))s\n"
                .utf8))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let outputData = try encoder.encode(
    EvalOutput(mode: arguments.mode, modelLoadSeconds: loadSeconds, results: results))
try outputData.write(to: arguments.output)
print("wrote \(arguments.output.path) (\(results.count) files)")
