import Foundation

/// Makes raw band levels look good on screen: quick to rise, slow to fall, and
/// scaled so quiet and loud songs both fill the edges.
public struct BandSmoother {
    public private(set) var values: [Float]
    private var peak: Float = 0.35
    public var attack: Float = 0.035     // seconds to follow a rise
    public var release: Float = 0.24     // seconds to follow a fall

    public init(bandCount: Int) { values = [Float](repeating: 0, count: bandCount) }

    @discardableResult
    public mutating func update(_ target: [Float], dt: Float) -> [Float] {
        guard target.count == values.count else { return values }
        let top = target.max() ?? 0
        // Auto gain: peak follows loud moments up quickly and drifts down slowly, never below a floor.
        peak = top > peak ? peak + (top - peak) * (1 - expf(-dt / 0.05)) : max(0.35, peak - dt * 0.08)
        let gain = 1 / peak
        for i in 0..<values.count {
            let t = min(1, target[i] * gain)
            let tau = t > values[i] ? attack : release
            values[i] += (t - values[i]) * (1 - expf(-dt / tau))
        }
        return values
    }

    public mutating func reset() {
        for i in 0..<values.count { values[i] = 0 }
        peak = 0.35
    }
}
