import Accelerate
import Foundation

/// Turns a block of mono audio samples into a handful of log-spaced loudness bands, each 0...1.
public final class SpectrumAnalyzer {
    public let fftSize: Int
    public let bandCount: Int
    public let sampleRate: Float

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var bandEdges: [Int] = []
    private var tiltDB: [Float] = []

    public init(fftSize: Int = 1024, bandCount: Int = 32, sampleRate: Float = 48000,
                minHz: Float = 40, maxHz: Float = 14000) {
        precondition(fftSize.nonzeroBitCount == 1, "fftSize must be a power of two")
        self.fftSize = fftSize
        self.bandCount = bandCount
        self.sampleRate = sampleRate
        log2n = vDSP_Length(log2(Float(fftSize)))
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var w = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&w, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        window = w

        // Log-spaced band edges, expressed as FFT bin numbers, each band at least one bin wide.
        let binHz = sampleRate / Float(fftSize)
        let maxBin = fftSize / 2 - 1
        var edges: [Int] = []
        for i in 0...bandCount {
            let hz = minHz * powf(maxHz / minHz, Float(i) / Float(bandCount))
            var bin = Int((hz / binHz).rounded())
            bin = max(1, min(maxBin, bin))
            if let last = edges.last, bin <= last { bin = last + 1 }
            edges.append(bin)
        }
        // If the top edges ran past the spectrum, squeeze them back in.
        for i in stride(from: edges.count - 1, through: 0, by: -1) where edges[i] > maxBin + 1 {
            edges[i] = maxBin + 1 - (edges.count - 1 - i)
        }
        bandEdges = edges
        // Music loses about 3 dB per octave towards the treble; give it back so highs are visible.
        tiltDB = (0..<bandCount).map { i in
            let centre = minHz * powf(maxHz / minHz, (Float(i) + 0.5) / Float(bandCount))
            return 3 * log2f(max(centre, 50) / 200)
        }
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Uses the most recent `fftSize` samples. Returns `bandCount` values in 0...1.
    public func analyze(_ samples: [Float]) -> [Float] {
        guard samples.count >= fftSize else { return [Float](repeating: 0, count: bandCount) }
        var windowed = [Float](repeating: 0, count: fftSize)
        samples.withUnsafeBufferPointer { src in
            vDSP_vmul(src.baseAddress! + (samples.count - fftSize), 1, window, 1, &windowed, 1, vDSP_Length(fftSize))
        }

        let half = fftSize / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }

        // zrip scales by 2; a full-scale sine then reads about fftSize/2 per bin.
        let norm = 2 / Float(fftSize)
        var out = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let lo = bandEdges[b], hi = max(bandEdges[b + 1], lo + 1)
            var peak: Float = 0
            for k in lo..<min(hi, half) { peak = max(peak, mags[k]) }
            let amplitude = sqrtf(peak) * norm
            let db = 20 * log10f(max(amplitude, 1e-7)) + tiltDB[b]
            out[b] = min(1, max(0, (db + 72) / 62))   // -72 dB = nothing, -10 dB = full
        }
        return out
    }

    /// Which band a given frequency falls in. Used by tests and by the demo.
    public func band(forHz hz: Float) -> Int {
        let bin = Int((hz / (sampleRate / Float(fftSize))).rounded())
        for b in 0..<bandCount where bin < bandEdges[b + 1] { return b }
        return bandCount - 1
    }
}
