import CoreGraphics
import Foundation

public struct RGB: Equatable {
    public var r: CGFloat, g: CGFloat, b: CGFloat
    public init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) { self.r = r; self.g = g; self.b = b }
    public func cgColor(alpha: CGFloat) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: alpha) }
    public static func mix(_ a: RGB, _ b: RGB, _ t: CGFloat) -> RGB {
        RGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    /// "#RRGGBB" <-> RGB, for saving.
    public var hex: String {
        func c(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(r), c(g), c(b))
    }
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(CGFloat((v >> 16) & 255) / 255, CGFloat((v >> 8) & 255) / 255, CGFloat(v & 255) / 255)
    }
}

/// A smooth, repeating blend through one to three colours. One colour stays solid.
public enum ColorLoop {
    public static func color(_ colors: [RGB], at t: CGFloat) -> RGB {
        guard let first = colors.first else { return RGB(1, 1, 1) }
        if colors.count == 1 { return first }
        let wrapped = t - floor(t)
        let scaled = wrapped * CGFloat(colors.count)
        let i = Int(scaled) % colors.count
        return RGB.mix(colors[i], colors[(i + 1) % colors.count], scaled - floor(scaled))
    }
}

/// Ready-made colour sets. Anyone can also pick their own.
public enum GlowStyle: String, CaseIterable {
    case aurora, ember, ocean, mono

    public var title: String {
        switch self {
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .ocean: return "Ocean"
        case .mono: return "Mono"
        }
    }

    public var colors: [RGB] {
        switch self {
        case .aurora: return [RGB(0.10, 0.90, 0.70), RGB(0.65, 0.35, 1.00)]
        case .ember: return [RGB(1.00, 0.30, 0.20), RGB(1.00, 0.70, 0.20)]
        case .ocean: return [RGB(0.10, 0.50, 1.00), RGB(0.10, 0.90, 0.95)]
        case .mono: return [RGB(1, 1, 1)]
        }
    }
}
