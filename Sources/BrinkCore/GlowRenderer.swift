import CoreGraphics
import Foundation

/// How the light reacts to music. The strip itself always stays a clean, even band; only its brightness and colour move.
public enum MusicAnimation: String, CaseIterable {
    case pulse, flow, segments
    public var title: String { rawValue.capitalized }
    public var blurb: String {
        switch self {
        case .pulse: return "The whole edge breathes gently with the beat"
        case .flow: return "A slow band of colour drifts around the screen"
        case .segments: return "The edge is split into small lights that follow the pitch"
        }
    }
}

public enum AlertAnimation: String, CaseIterable {
    case pulse, sweep, blink
    public var title: String { rawValue.capitalized }
    public var blurb: String {
        switch self {
        case .pulse: return "One soft swell around the whole screen"
        case .sweep: return "A short streak of light travels around the edges"
        case .blink: return "Two quick, soft flashes"
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
    /// 1 is a slim strip (about 2.8% of the screen's shorter side).
    public var thickness: CGFloat
    /// 0.2...1.
    public var brightness: CGFloat
    /// One smoothed loudness number, 0...1 (mostly bass). The app smooths it over time so the light never jitters.
    public var energy: Float
    /// 0...1 and wrapping: how far the flow animation has drifted.
    public var phase: Double

    public init(time: Double, bands: [Float], musicLevel: Float, pulses: [GlowPulse],
                musicColors: [RGB] = GlowStyle.aurora.colors, musicAnimation: MusicAnimation = .pulse,
                alertAnimation: AlertAnimation = .pulse, thickness: CGFloat = 1, brightness: CGFloat = 0.9,
                energy: Float? = nil, phase: Double? = nil) {
        self.time = time; self.bands = bands; self.musicLevel = musicLevel; self.pulses = pulses
        self.musicColors = musicColors; self.musicAnimation = musicAnimation; self.alertAnimation = alertAnimation
        self.thickness = thickness; self.brightness = brightness
        self.energy = energy ?? GlowFrame.energy(of: bands)
        self.phase = phase ?? time * 0.06
    }

    public static func energy(of bands: [Float]) -> Float {
        guard !bands.isEmpty else { return 0 }
        let bass = bands.prefix(7).reduce(0, +) / Float(min(7, bands.count))
        let all = bands.reduce(0, +) / Float(bands.count)
        return min(1, bass * 0.7 + all * 0.5)
    }
}

/// Draws a thin, even strip of light along each of the four screen edges. Pure CoreGraphics, so it can draw into a window or a PNG.
public enum GlowRenderer {
    enum Side: CaseIterable { case bottom, top, left, right }

    public static func draw(_ f: GlowFrame, in ctx: CGContext, size: CGSize) {
        ctx.saveGState()
        // Normal blending keeps each colour true. Adding light instead washes colours out towards white.
        ctx.setBlendMode(.normal)
        let base = min(size.width, size.height) * 0.034 * f.thickness
        if f.musicLevel > 0.005 { drawMusic(f, ctx, size, base: base) }
        for pulse in f.pulses { drawAlert(pulse, f, ctx, size, base: base) }
        ctx.restoreGState()
    }

    // MARK: music

    private static func drawMusic(_ f: GlowFrame, _ ctx: CGContext, _ size: CGSize, base: CGFloat) {
        let level = CGFloat(f.musicLevel)
        let energy = CGFloat(f.energy)
        for side in Side.allCases {
            let horizontal = side == .bottom || side == .top
            let length = horizontal ? size.width : size.height
            let along: [CGFloat]
            var colours = f.musicColors
            var depth = base
            var brightness = f.brightness

            switch f.musicAnimation {
            case .pulse:
                along = [CGFloat](repeating: 1, count: 2)
                depth = base * (0.85 + 0.40 * energy)
                brightness *= 0.14 + 0.86 * energy
                colours = alongEdge(f.musicColors, phase: f.phase * 0.5, spread: 0.6)
            case .flow:
                // One soft highlight travelling round the screen over a steady, dimmer glow.
                along = samples(count: 48) { u in
                    let s = (u * Double(length) + sideOffset(side, size)) / Double(perimeter(size))
                    return CGFloat(0.55 + 0.45 * cos(2 * .pi * (s - f.phase)))
                }
                brightness *= 0.18 + 0.82 * energy
                colours = alongEdge(f.musicColors, phase: f.phase, spread: 1)
            case .segments:
                let n = 14
                along = samples(count: 14 * 8) { u in
                    let cell = min(n - 1, Int(u * Double(n)))
                    let within = u * Double(n) - Double(cell)
                    let band = CGFloat(sample(f.bands, at: abs(2 * (CGFloat(cell) + 0.5) / CGFloat(n) - 1)))   // bass in the middle
                    let gap = within < 0.08 || within > 0.92 ? 0.0 : 1.0
                    return gap * (0.12 + 0.88 * pow(band, 1.2))
                }
                colours = alongEdge(f.musicColors, phase: f.phase * 0.5, spread: 0.6)
            }
            strip(ctx, side, size, depth: depth, colours: colours, along: along, alpha: min(1, 0.9 * brightness * level))
        }
    }

    // MARK: notification and call

    /// How bright an alert is at a moment, 0...1 (for the sweep it is only the fade; see `sweepHead`).
    public static func envelope(of p: GlowPulse, animation: AlertAnimation, at t: Double) -> CGFloat {
        let age = t - p.start
        if age < 0 { return 0 }
        let fadeIn = p.kind == .call ? min(1, age / 0.3) : 1
        switch animation {
        case .pulse:
            if p.kind == .call { return CGFloat(fadeIn * (0.55 + 0.45 * sin(2 * .pi * age / 2.0 - .pi / 2))) }
            let x = age / p.duration
            if x >= 1 { return 0 }
            let s = sin(.pi * x)
            return CGFloat(s * s)                                           // one smooth swell
        case .blink:
            let x: Double
            if p.kind == .call { x = age.truncatingRemainder(dividingBy: 1.8) / 1.8 } else {
                x = age / p.duration
                if x >= 1 { return 0 }
            }
            func bump(_ c: Double) -> Double { exp(-pow((x - c) / 0.075, 2)) }
            return CGFloat(fadeIn * max(bump(0.18), bump(0.42)))
        case .sweep:
            if p.kind == .call { return CGFloat(fadeIn) }
            let x = age / p.duration
            return x >= 1 ? 0 : CGFloat(min(1, (1 - x) / 0.15, x / 0.05))
        }
    }

    /// Where the streak's head is around the screen's outline, 0...1.
    public static func sweepHead(of p: GlowPulse, at t: Double) -> Double {
        let age = t - p.start
        let lap = p.kind == .call ? 2.4 : p.duration * 0.85
        let x = p.kind == .call ? age.truncatingRemainder(dividingBy: lap) / lap : min(1, age / lap)
        return x * x * (3 - 2 * x)                                          // ease in and out
    }

    private static func drawAlert(_ p: GlowPulse, _ f: GlowFrame, _ ctx: CGContext, _ size: CGSize, base: CGFloat) {
        let e = envelope(of: p, animation: f.alertAnimation, at: f.time)
        if e < 0.01 { return }
        let total = Double(perimeter(size))
        let head = sweepHead(of: p, at: f.time) * total
        let tail = total * 0.20, lead = total * 0.03

        for side in Side.allCases {
            let length = (side == .bottom || side == .top) ? size.width : size.height
            let along: [CGFloat]
            switch f.alertAnimation {
            case .pulse, .blink:
                along = [1, 1]
            case .sweep:
                along = samples(count: 64) { u in
                    let s = u * Double(length) + sideOffset(side, size)
                    var d = (head - s + lead).truncatingRemainder(dividingBy: total)
                    if d < 0 { d += total }
                    let k = d < lead ? d / lead : (d < lead + tail ? 1 - (d - lead) / tail : 0)
                    return CGFloat(k * k * (3 - 2 * k))                     // smooth both ends
                }
            }
            let strength = f.alertAnimation == .sweep ? 1 : e
            strip(ctx, side, size, depth: base * 1.7, colours: [p.color, p.color], along: along,
                  alpha: min(1, 0.95 * strength * f.brightness * (f.alertAnimation == .sweep ? e : 1)))
        }
    }

    // MARK: drawing one edge

    /// One clean strip along an edge: `colours` run along it, `along` (0...1 samples) is the brightness along it,
    /// and the light fades smoothly from the edge inwards over `depth`.
    private static func strip(_ ctx: CGContext, _ side: Side, _ size: CGSize, depth: CGFloat,
                              colours: [RGB], along: [CGFloat], alpha: CGFloat) {
        guard alpha > 0.01, depth > 0.5, along.contains(where: { $0 > 0.01 }) else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let length = (side == .bottom || side == .top) ? size.width : size.height

        func ramp(_ c: [RGB]) -> CGGradient? {
            CGGradient(colorsSpace: space, colors: c.map { $0.cgColor(alpha: 1) } as CFArray,
                       locations: c.indices.map { CGFloat($0) / CGFloat(max(1, c.count - 1)) })
        }
        func mask(_ values: [CGFloat], ends: Bool = false) -> CGGradient? {
            var v = values
            if v.count == 1 { v.append(v[0]) }
            let cols = v.map { CGColor(gray: 1, alpha: $0) }
            return CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: cols as CFArray,
                              locations: v.indices.map { CGFloat($0) / CGFloat(v.count - 1) })
        }
        // Smooth fall-off into the screen: bright at the edge, gone by `depth`, no visible steps.
        let falloff: [CGFloat] = [1, 0.88, 0.68, 0.46, 0.26, 0.11, 0.03, 0]
        // The two strips that meet at a corner would add up to double brightness, so ease each strip's last bit.
        let cornerFade = min(0.5, depth * 1.5 / length)

        guard let color = ramp(colours.count > 1 ? colours : [colours.first ?? RGB(1, 1, 1), colours.first ?? RGB(1, 1, 1)]),
              let vertical = mask(falloff), let horizontal = mask(along),
              let ends = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                    colors: [CGColor(gray: 1, alpha: 0.5), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.5)] as CFArray,
                                    locations: [0, cornerFade, 1 - cornerFade, 1]) else { return }

        let rect = CGRect(x: 0, y: 0, width: length, height: depth + 3)   // a little past the fade, so no hard edge shows
        ctx.saveGState()
        ctx.concatenate(transform(for: side, size))
        ctx.setAlpha(alpha)
        ctx.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        ctx.drawLinearGradient(color, start: .zero, end: CGPoint(x: length, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.setBlendMode(.destinationIn)
        ctx.drawLinearGradient(vertical, start: .zero, end: CGPoint(x: 0, y: depth), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.drawLinearGradient(horizontal, start: .zero, end: CGPoint(x: length, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.drawLinearGradient(ends, start: .zero, end: CGPoint(x: length, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    // MARK: helpers

    static func perimeter(_ size: CGSize) -> CGFloat { 2 * (size.width + size.height) }

    /// Distance round the screen outline at which an edge begins (bottom edge left to right, up the right, back along the top, down the left).
    static func sideOffset(_ side: Side, _ size: CGSize) -> Double {
        switch side {
        case .bottom: return 0
        case .right: return Double(size.width)
        case .top: return Double(size.width + size.height)
        case .left: return Double(2 * size.width + size.height)
        }
    }

    private static func samples(count: Int, _ f: (Double) -> CGFloat) -> [CGFloat] {
        (0..<count).map { f(Double($0) / Double(count - 1)) }
    }

    /// Colours along an edge. `phase` slides the whole colour loop; `spread` is how much of the loop one edge shows.
    private static func alongEdge(_ colors: [RGB], phase: Double, spread: CGFloat) -> [RGB] {
        guard colors.count > 1 else { return [colors.first ?? RGB(1, 1, 1)] }
        return (0..<14).map { k in ColorLoop.color(colors, at: CGFloat(k) / 13 * spread + CGFloat(phase)) }
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
}
