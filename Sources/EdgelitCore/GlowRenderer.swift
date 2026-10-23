import CoreGraphics
import Foundation

public enum MusicAnimation: String, CaseIterable {
    case spectrum, pulse, flow
    public var title: String { rawValue.capitalized }
    public var blurb: String {
        switch self {
        case .spectrum: return "Each part of the edge follows a different pitch"
        case .pulse: return "The whole edge breathes with the beat"
        case .flow: return "Light drifts around the screen, faster when louder"
        }
    }
}

public enum AlertAnimation: String, CaseIterable {
    case pulse, sweep, blink
    public var title: String { rawValue.capitalized }
    public var blurb: String {
        switch self {
        case .pulse: return "A soft swell around the whole screen"
        case .sweep: return "A streak of light runs around the edges"
        case .blink: return "Two quick flashes"
        }
    }
}

public struct GlowPulse: Equatable {
    public var id: UUID
    public var kind: GlowKind
    public var color: RGB
    public var start: Double
    /// Notifications end after this long. Calls repeat their animation until they are cleared.
    public var duration: Double

    public init(id: UUID = UUID(), kind: GlowKind, color: RGB, start: Double, duration: Double = 2.4) {
        self.id = id; self.kind = kind; self.color = color; self.start = start; self.duration = duration
    }
}

public struct GlowFrame {
    public var time: Double
    public var bands: [Float]
    /// 0...1, how much of the music light is showing (fades in and out).
    public var musicLevel: Float
    public var pulses: [GlowPulse]
    public var musicColors: [RGB]
    public var musicAnimation: MusicAnimation
    public var alertAnimation: AlertAnimation
    /// 1 is a slim glow (about 4.5% of the screen's shorter side). Scales the reach of every effect.
    public var thickness: CGFloat
    /// 0.2...1, scales how bright everything is.
    public var brightness: CGFloat

    public init(time: Double, bands: [Float], musicLevel: Float, pulses: [GlowPulse],
                musicColors: [RGB] = GlowStyle.aurora.colors, musicAnimation: MusicAnimation = .spectrum,
                alertAnimation: AlertAnimation = .pulse, thickness: CGFloat = 1, brightness: CGFloat = 0.9) {
        self.time = time; self.bands = bands; self.musicLevel = musicLevel; self.pulses = pulses
        self.musicColors = musicColors; self.musicAnimation = musicAnimation; self.alertAnimation = alertAnimation
        self.thickness = thickness; self.brightness = brightness
    }
}

/// Draws the light along the four edges of a screen. Pure CoreGraphics, so it can draw into a window or a PNG.
public enum GlowRenderer {
    enum Side: CaseIterable { case bottom, top, left, right }

    public static func draw(_ f: GlowFrame, in ctx: CGContext, size: CGSize) {
        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let base = min(size.width, size.height) * 0.045 * f.thickness
        if f.musicLevel > 0.005 { drawMusic(f, ctx, size, base: base) }
        for pulse in f.pulses { drawAlert(pulse, f, ctx, size, base: base) }
        ctx.restoreGState()
    }

    // MARK: music

    private static func drawMusic(_ f: GlowFrame, _ ctx: CGContext, _ size: CGSize, base: CGFloat) {
        let level = CGFloat(f.musicLevel)
        let bass = CGFloat(mean(f.bands.prefix(7)))
        let overall = CGFloat(mean(f.bands))
        let perimeter = 2 * (size.width + size.height)

        for side in Side.allCases {
            let horizontal = side == .bottom || side == .top
            let length = horizontal ? size.width : size.height
            let heights = heightsAlong(side, size, length: length) { u, s in
                switch f.musicAnimation {
                case .spectrum:
                    let v = CGFloat(sample(f.bands, at: abs(2 * u - 1)))          // bass in the middle of every edge
                    return base * 2.0 * (0.12 + 0.88 * pow(v, 1.1))
                case .pulse:
                    return base * 1.8 * (0.18 + 0.82 * min(1, bass * 1.15))
                case .flow:
                    let speed = 0.08 + 0.45 * Double(overall)
                    let wave = 0.5 + 0.5 * sin(2 * .pi * (Double(s / perimeter) * 2 - f.time * speed))
                    return base * 1.8 * (0.16 + 0.84 * CGFloat(wave) * min(1, overall * 1.4 + 0.15))
                }
            }.map { $0 * level * (horizontal ? 1 : 0.85) }

            let colors = alongEdge(f.musicColors, time: f.time, spread: f.musicColors.count > 1 ? 0.7 : 0)
            strip(ctx, side, size, heights: heights, colors: colors, alpha: 0.8 * f.brightness * level)
        }
    }

    // MARK: notification and call

    /// How bright an alert is at a moment, 0...1 (for the sweep, this is the fade; see `sweepHead`).
    public static func envelope(of p: GlowPulse, animation: AlertAnimation, at t: Double) -> CGFloat {
        let age = t - p.start
        if age < 0 { return 0 }
        let fadeIn = p.kind == .call ? min(1, age / 0.3) : 1
        switch animation {
        case .pulse:
            if p.kind == .call { return CGFloat(fadeIn * (0.62 + 0.38 * sin(2 * .pi * age / 1.5 - .pi / 2))) }
            let x = age / p.duration
            if x >= 1 { return 0 }
            return CGFloat(sin(.pi * x) * (0.75 + 0.25 * cos(4 * .pi * x)))
        case .blink:
            let x: Double
            if p.kind == .call { x = age.truncatingRemainder(dividingBy: 1.7) / 1.7 } else {
                x = age / p.duration
                if x >= 1 { return 0 }
            }
            func bump(_ c: Double) -> Double { exp(-pow((x - c) / 0.07, 2)) }
            return CGFloat(fadeIn * max(bump(0.16), bump(0.40)))
        case .sweep:
            if p.kind == .call { return CGFloat(fadeIn) }
            let x = age / p.duration
            return x >= 1 ? 0 : CGFloat(min(1, (1 - x) / 0.2))
        }
    }

    /// Where the streak's head is on the screen's outline, 0...1 around, for the sweep animation.
    public static func sweepHead(of p: GlowPulse, at t: Double) -> Double {
        let age = t - p.start
        let lap = p.kind == .call ? 2.2 : p.duration * 0.8
        let x = p.kind == .call ? age.truncatingRemainder(dividingBy: lap) / lap : min(1, age / lap)
        return x * x * (3 - 2 * x)                                              // ease in and out
    }

    private static func drawAlert(_ p: GlowPulse, _ f: GlowFrame, _ ctx: CGContext, _ size: CGSize, base: CGFloat) {
        let e = envelope(of: p, animation: f.alertAnimation, at: f.time)
        if e < 0.01 { return }
        let perimeter = 2 * (size.width + size.height)
        let head = sweepHead(of: p, at: f.time) * Double(perimeter)
        let tail = Double(perimeter) * 0.16
        let lead = Double(perimeter) * 0.025

        for side in Side.allCases {
            let horizontal = side == .bottom || side == .top
            let length = horizontal ? size.width : size.height
            let heights = heightsAlong(side, size, length: length) { _, s in
                switch f.alertAnimation {
                case .pulse, .blink:
                    return base * 2.6 * (0.45 + 0.55 * e)
                case .sweep:
                    // A short soft lead in front of the head, then a long fading tail behind it.
                    var d = (head - Double(s) + lead).truncatingRemainder(dividingBy: Double(perimeter))
                    if d < 0 { d += Double(perimeter) }
                    let streak = d < lead ? pow(d / lead, 2) : (d < lead + tail ? pow(1 - (d - lead) / tail, 2) : 0)
                    return base * 3.2 * CGFloat(streak) * e
                }
            }
            let brightness: CGFloat = (f.alertAnimation == .sweep ? 1 : e) * f.brightness
            strip(ctx, side, size, heights: heights, colors: [p.color, p.color], alpha: min(1, 0.95 * brightness))
        }
    }

    // MARK: drawing one edge

    /// Draws one edge as a smooth shape made of soft, stacked layers, so it glows instead of showing a hard outline.
    private static func strip(_ ctx: CGContext, _ side: Side, _ size: CGSize, heights: [CGFloat], colors: [RGB], alpha: CGFloat) {
        guard heights.count > 2, (heights.max() ?? 0) > 0.8, alpha > 0.01,
              let across = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      colors: colors.map { $0.cgColor(alpha: 1) } as CFArray,
                                      locations: colors.indices.map { CGFloat($0) / CGFloat(max(1, colors.count - 1)) }) else { return }
        let length = (side == .bottom || side == .top) ? size.width : size.height
        let count = heights.count - 1
        let step = length / CGFloat(count)
        let layers = 12

        ctx.saveGState()
        ctx.concatenate(transform(for: side, size))
        ctx.setAlpha(min(1, alpha / CGFloat(layers) * 1.05))
        for layer in 0..<layers {
            let k = CGFloat(layers - layer) / CGFloat(layers)
            let path = CGMutablePath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: heights[0] * k))
            for i in 1...count {
                let prev = CGPoint(x: CGFloat(i - 1) * step, y: heights[i - 1] * k)
                let cur = CGPoint(x: CGFloat(i) * step, y: heights[i] * k)
                path.addQuadCurve(to: CGPoint(x: (prev.x + cur.x) / 2, y: (prev.y + cur.y) / 2), control: prev)
                if i == count { path.addLine(to: cur) }
            }
            path.addLine(to: CGPoint(x: length, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(across, start: .zero, end: CGPoint(x: length, y: 0), options: [])
            ctx.resetClip()
        }
        ctx.restoreGState()
    }

    /// Samples a height function along an edge. The function gets 0...1 along the edge and the distance
    /// travelled around the whole screen outline (bottom edge left to right, up the right, back along the top, down the left).
    private static func heightsAlong(_ side: Side, _ size: CGSize, length: CGFloat, _ h: (CGFloat, CGFloat) -> CGFloat) -> [CGFloat] {
        let count = max(16, Int(length / 12))
        return (0...count).map { i in
            let u = CGFloat(i) / CGFloat(count)
            let x = u * length
            let s: CGFloat
            switch side {
            case .bottom: s = x
            case .right: s = size.width + x
            case .top: s = size.width + size.height + (size.width - x)
            case .left: s = 2 * size.width + size.height + (size.height - x)
            }
            return h(u, s)
        }
    }

    /// Colours along an edge, drifting slowly. `spread` is how much of the colour loop one edge shows.
    private static func alongEdge(_ colors: [RGB], time: Double, spread: CGFloat) -> [RGB] {
        if colors.count <= 1 || spread == 0 { return [colors.first ?? RGB(1, 1, 1), colors.first ?? RGB(1, 1, 1)] }
        return (0..<14).map { k in ColorLoop.color(colors, at: CGFloat(k) / 13 * spread + CGFloat(time) * 0.03) }
    }

    /// Maps an edge's own coordinates (along it, then inward from it) onto the screen.
    private static func transform(for side: Side, _ size: CGSize) -> CGAffineTransform {
        switch side {
        case .bottom: return .identity
        case .top: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: size.height)
        case .left: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: size.width, ty: 0)
        }
    }

    /// Linear interpolation across the band array; `x` is 0...1.
    static func sample(_ bands: [Float], at x: CGFloat) -> Float {
        guard bands.count > 1 else { return bands.first ?? 0 }
        let pos = Float(min(1, max(0, x))) * Float(bands.count - 1)
        let i = Int(pos), frac = pos - Float(i)
        return bands[i] + (bands[min(i + 1, bands.count - 1)] - bands[i]) * frac
    }

    private static func mean<S: Sequence>(_ values: S) -> Float where S.Element == Float {
        var sum: Float = 0, n: Float = 0
        for v in values { sum += v; n += 1 }
        return n == 0 ? 0 : sum / n
    }
}
