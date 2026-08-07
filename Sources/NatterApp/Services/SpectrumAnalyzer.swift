import Accelerate
import Foundation

/// Log-spaced speech-band spectrum for the overlay meter, computed from the
/// same 16 kHz mono samples the recognizer consumes. Produces one frame per
/// 512 samples (~32 ms), so the meter tracks what the microphone actually
/// hears instead of pulsing every bar from a single loudness number.
/// Instances are only touched from the audio tap thread.
final class SpectrumAnalyzer {
    static let bandCount = 7

    private static let fftSize = 512
    private static let halfSize = fftSize / 2
    private static let sampleRate: Float = 16_000

    private let fftSetup: FFTSetup
    private let window: [Float]
    private let bandBinRanges: [Range<Int>]
    private var pending: [Float] = []
    private var realBuffer = [Float](repeating: 0, count: SpectrumAnalyzer.halfSize)
    private var imagBuffer = [Float](repeating: 0, count: SpectrumAnalyzer.halfSize)

    init?() {
        guard let setup = vDSP_create_fftsetup(9, FFTRadix(kFFTRadix2)) else { return nil }
        fftSetup = setup
        var hann = [Float](repeating: 0, count: Self.fftSize)
        vDSP_hann_window(&hann, vDSP_Length(Self.fftSize), Int32(vDSP_HANN_NORM))
        window = hann

        // Log-spaced edges across the speech band; bin width is 31.25 Hz.
        let lowHz: Float = 80, highHz: Float = 6_400
        let binWidth = Self.sampleRate / Float(Self.fftSize)
        var ranges: [Range<Int>] = []
        for band in 0..<Self.bandCount {
            let startHz = lowHz * pow(highHz / lowHz, Float(band) / Float(Self.bandCount))
            let endHz = lowHz * pow(highHz / lowHz, Float(band + 1) / Float(Self.bandCount))
            let startBin = max(1, Int(startHz / binWidth))
            let endBin = min(Self.halfSize - 1, max(startBin + 1, Int(endHz / binWidth)))
            ranges.append(startBin..<endBin)
        }
        bandBinRanges = ranges
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    /// Buffers converted capture samples and returns a normalized 0…1 level
    /// per band whenever a full analysis frame has accumulated, nil otherwise.
    func bands(appending samples: [Float]) -> [Float]? {
        pending.append(contentsOf: samples)
        guard pending.count >= Self.fftSize else { return nil }

        var frame = Array(pending.suffix(Self.fftSize))
        pending.removeAll(keepingCapacity: true)
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(Self.fftSize))

        var magnitudes = [Float](repeating: 0, count: Self.halfSize)
        realBuffer.withUnsafeMutableBufferPointer { real in
            imagBuffer.withUnsafeMutableBufferPointer { imag in
                var split = DSPSplitComplex(
                    realp: real.baseAddress!,
                    imagp: imag.baseAddress!
                )
                frame.withUnsafeBytes {
                    vDSP_ctoz(
                        $0.bindMemory(to: DSPComplex.self).baseAddress!, 2,
                        &split, 1,
                        vDSP_Length(Self.halfSize)
                    )
                }
                vDSP_fft_zrip(fftSetup, &split, 1, 9, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(Self.halfSize))
            }
        }

        return bandBinRanges.map { range in
            var meanPower: Float = 0
            magnitudes.withUnsafeBufferPointer {
                vDSP_meanv($0.baseAddress! + range.lowerBound, 1, &meanPower, vDSP_Length(range.count))
            }
            // Same perceptual mapping as AudioChunk.level, per band.
            let decibels = 10 * log10(max(meanPower, .leastNormalMagnitude))
            let noiseFloor: Float = -58
            let speechCeiling: Float = -8
            return min(1, max(0, (decibels - noiseFloor) / (speechCeiling - noiseFloor)))
        }
    }
}
