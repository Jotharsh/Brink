import Foundation

public enum GlowKind: Equatable { case notification, call }

public struct Classified: Equatable {
    public var kind: GlowKind
    public var color: RGB
    public var app: String
}

/// Decides what a notification banner is and what colour its glow should be, from the text on the banner.
public enum NotificationClassifier {
    static let apps: [(name: String, color: RGB)] = [
        ("Messages", RGB(0.10, 0.40, 0.90)),
        ("Mail", RGB(0.12, 0.42, 0.85)),
        ("Slack", RGB(0.75, 0.12, 0.45)),
        ("Discord", RGB(0.25, 0.28, 0.80)),
        ("WhatsApp", RGB(0.05, 0.60, 0.28)),
        ("Telegram", RGB(0.05, 0.45, 0.75)),
        ("Calendar", RGB(0.85, 0.15, 0.12)),
        ("Reminders", RGB(0.88, 0.42, 0.05)),
        ("Teams", RGB(0.30, 0.30, 0.75)),
        ("Zoom", RGB(0.08, 0.35, 0.85)),
    ]
    static let callApps = ["FaceTime", "Phone"]
    static let callPhrases = ["incoming call", "is calling", "calling…", "calling...", "facetime audio", "facetime video"]
    public static let call = RGB(0.08, 0.62, 0.28)
    public static let fallback = RGB(0.30, 0.45, 0.80)

    public static func classify(_ texts: [String]) -> Classified {
        let joined = texts.joined(separator: " \n ").lowercased()
        let head = texts.prefix(2).joined(separator: " ").lowercased()

        for name in callApps where head.contains(name.lowercased()) {
            return Classified(kind: .call, color: call, app: name)
        }
        if callPhrases.contains(where: { joined.contains($0) }) {
            return Classified(kind: .call, color: call, app: texts.first ?? "Call")
        }
        for (name, color) in apps where head.contains(name.lowercased()) {
            return Classified(kind: .notification, color: color, app: name)
        }
        return Classified(kind: .notification, color: fallback, app: texts.first ?? "Notification")
    }

    /// True if any of the texts look like a live incoming call (used to decide when a call glow should end).
    public static func isLiveCall(_ texts: [String]) -> Bool {
        let c = classify(texts)
        return c.kind == .call
    }
}
