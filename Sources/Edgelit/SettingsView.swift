import AppKit
import EdgelitCore
import SwiftUI

private extension RGB {
    var color: Color { Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b)) }
    init(_ color: Color) {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(c.redComponent, c.greenComponent, c.blueComponent)
    }
}

/// Holds what the settings window edits and writes every change straight to `Settings`.
final class SettingsModel: ObservableObject {
    private let s = Settings.shared

    @Published var musicAnimation: MusicAnimation { didSet { s.musicAnimation = musicAnimation } }
    @Published var colorCount: Int { didSet { save() } }
    @Published var c1: Color { didSet { save() } }
    @Published var c2: Color { didSet { save() } }
    @Published var c3: Color { didSet { save() } }
    @Published var alertAnimation: AlertAnimation { didSet { s.alertAnimation = alertAnimation } }
    @Published var matchApp: Bool { didSet { s.matchAppColour = matchApp } }
    @Published var notificationColor: Color { didSet { s.notificationColor = RGB(notificationColor) } }
    @Published var callColor: Color { didSet { s.callColor = RGB(callColor) } }
    @Published var thickness: Double { didSet { s.thickness = thickness } }
    @Published var brightness: Double { didSet { s.brightness = brightness } }
    private var loading = false

    init() {
        let colors = Settings.shared.musicColors
        musicAnimation = Settings.shared.musicAnimation
        colorCount = colors.count
        c1 = colors[0].color
        c2 = (colors.count > 1 ? colors[1] : GlowStyle.aurora.colors[1]).color
        c3 = (colors.count > 2 ? colors[2] : RGB(1.0, 0.35, 0.7)).color
        alertAnimation = Settings.shared.alertAnimation
        matchApp = Settings.shared.matchAppColour
        notificationColor = Settings.shared.notificationColor.color
        callColor = Settings.shared.callColor.color
        thickness = Settings.shared.thickness
        brightness = Settings.shared.brightness
    }

    private func save() {
        guard !loading else { return }
        s.musicColors = Array([RGB(c1), RGB(c2), RGB(c3)].prefix(colorCount))
    }

    func apply(_ style: GlowStyle) {
        loading = true
        let cols = style.colors
        colorCount = cols.count
        c1 = cols[0].color
        if cols.count > 1 { c2 = cols[1].color }
        if cols.count > 2 { c3 = cols[2].color }
        loading = false
        save()
    }

    func reset() {
        s.resetLook()
        let fresh = SettingsModel()
        loading = true
        musicAnimation = fresh.musicAnimation; colorCount = fresh.colorCount
        c1 = fresh.c1; c2 = fresh.c2; c3 = fresh.c3
        alertAnimation = fresh.alertAnimation; matchApp = fresh.matchApp
        notificationColor = fresh.notificationColor; callColor = fresh.callColor
        thickness = fresh.thickness; brightness = fresh.brightness
        loading = false
    }
}

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    var tryMusic: () -> Void
    var tryNotification: () -> Void
    var tryCall: () -> Void
    var stopCall: () -> Void

    var body: some View {
        Form {
            Section("Music") {
                Picker("Animation", selection: $m.musicAnimation) {
                    ForEach(MusicAnimation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(m.musicAnimation.blurb).font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Colours")
                    Spacer()
                    ForEach(GlowStyle.allCases, id: \.self) { style in
                        Button { m.apply(style) } label: { swatch(style) }
                            .buttonStyle(.plain)
                            .help(style.title)
                    }
                }
                Picker("Number of colours", selection: $m.colorCount) {
                    Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
                }
                .pickerStyle(.segmented)
                ColorPicker("Colour 1", selection: $m.c1, supportsOpacity: false)
                if m.colorCount > 1 { ColorPicker("Colour 2", selection: $m.c2, supportsOpacity: false) }
                if m.colorCount > 2 { ColorPicker("Colour 3", selection: $m.c3, supportsOpacity: false) }
            }

            Section("Notifications and calls") {
                Picker("Animation", selection: $m.alertAnimation) {
                    ForEach(AlertAnimation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(m.alertAnimation.blurb).font(.caption).foregroundStyle(.secondary)
                Toggle("Use each app's own colour for notifications", isOn: $m.matchApp)
                ColorPicker("Notification colour", selection: $m.notificationColor, supportsOpacity: false).disabled(m.matchApp)
                ColorPicker("Call colour", selection: $m.callColor, supportsOpacity: false)
            }

            Section("Size and brightness") {
                LabeledContent("Thickness") { Slider(value: $m.thickness, in: 0.4...2.5) }
                LabeledContent("Brightness") { Slider(value: $m.brightness, in: 0.2...1) }
            }

            Section("Try it") {
                HStack {
                    Button("Music", action: tryMusic)
                    Button("Notification", action: tryNotification)
                    Button("Call", action: tryCall)
                    Button("Stop call", action: stopCall)
                    Spacer()
                    Button("Reset look") { m.reset() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func swatch(_ style: GlowStyle) -> some View {
        let cols = style.colors.map(\.color)
        return RoundedRectangle(cornerRadius: 5)
            .fill(LinearGradient(colors: cols.count > 1 ? cols : [cols[0], cols[0]], startPoint: .leading, endPoint: .trailing))
            .frame(width: 26, height: 18)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.25), lineWidth: 1))
    }
}
