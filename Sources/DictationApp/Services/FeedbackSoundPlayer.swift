import AppKit
import Foundation

@MainActor
final class FeedbackSoundPlayer {
    enum Signal {
        case started
        case stopped
    }

    private var activeSound: NSSound?

    func play(_ signal: Signal) {
        let frequencies: [Double]
        switch signal {
        case .started:
            frequencies = [660, 990]
        case .stopped:
            frequencies = [880, 550]
        }

        guard let sound = NSSound(data: Self.waveData(frequencies: frequencies)) else {
            return
        }
        activeSound = sound
        sound.volume = 0.22
        sound.play()
    }

    private static func waveData(frequencies: [Double]) -> Data {
        let sampleRate = 44_100
        let noteFrames = Int(Double(sampleRate) * 0.055)
        let gapFrames = Int(Double(sampleRate) * 0.012)
        let fadeFrames = Int(Double(sampleRate) * 0.008)
        var samples: [Int16] = []

        for (index, frequency) in frequencies.enumerated() {
            for frame in 0..<noteFrames {
                let fadeIn = min(1, Double(frame) / Double(fadeFrames))
                let fadeOut = min(1, Double(noteFrames - frame - 1) / Double(fadeFrames))
                let envelope = min(fadeIn, fadeOut)
                let phase = 2 * Double.pi * frequency * Double(frame) / Double(sampleRate)
                samples.append(Int16(sin(phase) * envelope * Double(Int16.max) * 0.42))
            }
            if index < frequencies.count - 1 {
                samples.append(contentsOf: repeatElement(0, count: gapFrames))
            }
        }

        var data = Data()
        let pcmByteCount = UInt32(samples.count * MemoryLayout<Int16>.size)
        appendASCII("RIFF", to: &data)
        appendLittleEndian(UInt32(36) + pcmByteCount, to: &data)
        appendASCII("WAVEfmt ", to: &data)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(UInt32(sampleRate), to: &data)
        appendLittleEndian(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &data)
        appendLittleEndian(UInt16(MemoryLayout<Int16>.size), to: &data)
        appendLittleEndian(UInt16(16), to: &data)
        appendASCII("data", to: &data)
        appendLittleEndian(pcmByteCount, to: &data)
        for sample in samples { appendLittleEndian(sample, to: &data) }
        return data
    }

    private static func appendASCII(_ string: String, to data: inout Data) {
        data.append(contentsOf: string.utf8)
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(
        _ value: T,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
