import EdgelitCore
import Foundation

/// User choices, kept in UserDefaults. The engine reads these every frame, so changes show up instantly.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    // What is switched on
    var music: Bool { get { bool("music", true) } set { d.set(newValue, forKey: "music") } }
    var notifications: Bool { get { bool("notifications", true) } set { d.set(newValue, forKey: "notifications") } }
    var calls: Bool { get { bool("calls", true) } set { d.set(newValue, forKey: "calls") } }
    var allDisplays: Bool { get { bool("allDisplays", true) } set { d.set(newValue, forKey: "allDisplays") } }

    // Music look
    var musicColors: [RGB] {
        get {
            let saved = (d.stringArray(forKey: "musicColors") ?? []).compactMap { RGB(hex: $0) }
            return saved.isEmpty ? GlowStyle.aurora.colors : Array(saved.prefix(3))
        }
        set { d.set(newValue.prefix(3).map(\.hex), forKey: "musicColors") }
    }
    var musicAnimation: MusicAnimation {
        get { MusicAnimation(rawValue: d.string(forKey: "musicAnimation") ?? "") ?? .pulse }
        set { d.set(newValue.rawValue, forKey: "musicAnimation") }
    }

    // Notification and call look
    var alertAnimation: AlertAnimation {
        get { AlertAnimation(rawValue: d.string(forKey: "alertAnimation") ?? "") ?? .pulse }
        set { d.set(newValue.rawValue, forKey: "alertAnimation") }
    }
    var matchAppColour: Bool { get { bool("matchAppColour", true) } set { d.set(newValue, forKey: "matchAppColour") } }
    var notificationColor: RGB {
        get { RGB(hex: d.string(forKey: "notificationColor") ?? "") ?? NotificationClassifier.fallback }
        set { d.set(newValue.hex, forKey: "notificationColor") }
    }
    var callColor: RGB {
        get { RGB(hex: d.string(forKey: "callColor") ?? "") ?? NotificationClassifier.call }
        set { d.set(newValue.hex, forKey: "callColor") }
    }

    // Size and brightness
    var thickness: Double { get { number("thickness", 1.0) } set { d.set(newValue, forKey: "thickness") } }
    var brightness: Double { get { number("brightness", 0.65) } set { d.set(newValue, forKey: "brightness") } }

    func resetLook() {
        for k in ["musicColors", "musicAnimation", "alertAnimation", "matchAppColour", "notificationColor", "callColor", "thickness", "brightness"] {
            d.removeObject(forKey: k)
        }
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: key) == nil ? fallback : d.bool(forKey: key) }
    private func number(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) == nil ? fallback : d.double(forKey: key) }
}
