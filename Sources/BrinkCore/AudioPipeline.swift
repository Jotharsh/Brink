import Foundation

/// Collects audio in whatever chunk sizes the system hands over and produces fresh bands about 60 times a second.
/// Feed it from the audio thread; read `latest` from anywhere.
public final class AudioPipeline {
    public struct Reading { public var bands: [Float]; public var rms: Float }

    private let analyzer: SpectrumAnalyzer
    private let hop: Int
    private var ring: [Float]
    private var sinceLast = 0
    private let lock = NSLock()
    private var reading: Reading

    public init(sampleRate: Float = 48000, fftSize: Int = 1024, bandCount: Int = 32) {
        analyzer = SpectrumAnalyzer(fftSize: fftSize, bandCount: bandCount, sampleRate: sampleRate)
        hop = Int(sampleRate / 60)
        ring = [Float](repeating: 0, count: fftSize)
        reading = Reading(bands: [Float](repeating: 0, count: bandCount), rms: 0)
    }

    public var latest: Reading {
        lock.lock(); defer { lock.unlock() }
        return reading
    }

    public func feed(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        let n = ring.count
        if samples.count >= n {
            ring = Array(samples.suffix(n))
        } else {
            ring.removeFirst(samples.count)
            ring.append(contentsOf: samples)
        }
        sinceLast += samples.count
        guard sinceLast >= hop else { return }
        sinceLast = 0

        var sum: Float = 0
        for s in ring.suffix(hop) { sum += s * s }
        let rms = sqrtf(sum / Float(hop))
        let bands = analyzer.analyze(ring)
        lock.lock()
        reading = Reading(bands: bands, rms: rms)
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        reading = Reading(bands: [Float](repeating: 0, count: reading.bands.count), rms: 0)
        lock.unlock()
    }
}
