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
        ("Messages", RGB(0.20, 0.60, 1.00)),
        ("Mail", RGB(0.29, 0.66, 1.00)),
        ("Slack", RGB(0.92, 0.25, 0.60)),
        ("Discord", RGB(0.35, 0.40, 0.95)),
        ("WhatsApp", RGB(0.15, 0.83, 0.40)),
        ("Telegram", RGB(0.16, 0.67, 0.93)),
        ("Calendar", RGB(1.00, 0.30, 0.25)),
        ("Reminders", RGB(1.00, 0.60, 0.15)),
        ("Teams", RGB(0.45, 0.45, 0.90)),
        ("Zoom", RGB(0.18, 0.55, 1.00)),
    ]
    static let callApps = ["FaceTime", "Phone"]
    static let callPhrases = ["incoming call", "is calling", "calling…", "calling...", "facetime audio", "facetime video"]
    public static let call = RGB(0.20, 0.85, 0.40)
    public static let fallback = RGB(0.80, 0.88, 1.00)

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
