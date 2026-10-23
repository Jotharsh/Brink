import Foundation

/// Turns a loudness number into "how much of a beat is this right now", 0...1.
///
/// Music is usually mastered loud and steady, so the raw level barely moves. What the eye wants is the
/// change: the kick that jumps above the recent floor. This measures each moment against the quietest and
/// loudest the music has been over the last couple of seconds, so every beat reaches the top and the gaps
/// between beats fall back, whatever the song's volume.
public struct BeatTracker {
    private var low: Float = 0
    private var high: Float = 0.1
    public private(set) var value: Float = 0

    public var attack: Float = 0.025      // seconds to jump to a beat
    public var release: Float = 0.16      // seconds to fall back after it
    public var memory: Float = 2.0        // seconds over which "recent loudest/quietest" fade

    public init() {}

    @discardableResult
    public mutating func update(_ level: Float, dt: Float) -> Float {
        let k = 1 - expf(-dt / memory)
        high = level > high ? level : high + (level - high) * k
        low = level < low ? level : low + (level - low) * k
        let range = max(high - low, 0.12)                     // a flat signal stays flat instead of being blown up
        var t = min(1, max(0, (level - low) / range))
        t *= t                                                // sharpen: only real peaks reach the top
        value += (t - value) * (1 - expf(-dt / (t > value ? attack : release)))
        return value
    }

    public mutating func reset() { low = 0; high = 0.1; value = 0 }
}
