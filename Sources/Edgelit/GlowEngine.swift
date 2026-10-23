import AppKit
import EdgelitCore

/// Owns the overlay windows and the animation clock. It only ticks while there is something to show,
/// so an idle Edgelit costs next to nothing.
final class GlowEngine {
    private var windows: [OverlayWindow] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var idleSince: Double?

    private let pipeline: AudioPipeline
    private var smoother = BandSmoother(bandCount: 32)
    private var musicLevel: Float = 0
    private var pulses: [GlowPulse] = []
    private var demoUntil: Double = 0
    private let settings = Settings.shared

    /// Set by the audio tap when sound is flowing.
    private var audioActive = false
    private var lastLoud: Double = 0

    init(pipeline: AudioPipeline) {
        self.pipeline = pipeline
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.rebuildWindows() }
    }

    // MARK: events

    func wake() {
        guard timer == nil else { return }
        if windows.isEmpty { rebuildWindows() }
        lastTick = CACurrentMediaTime()
        idleSince = nil
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        windows.forEach { $0.orderFrontRegardless() }
    }

    func audioChanged() { if settings.music { wake() } }

    func pulse(kind: GlowKind, color: RGB, duration: Double? = nil) {
        if kind == .call && !settings.calls { return }
        if kind == .notification && !settings.notifications { return }
        // A new notification replaces a still-running one instead of stacking brighter and brighter.
        pulses.removeAll { $0.kind == .notification && kind == .notification }
        pulses.append(GlowPulse(kind: kind, color: color, start: CACurrentMediaTime(), duration: duration ?? (settings.alertAnimation == .sweep ? 2.6 : 2.4)))
        wake()
    }

    func clearCalls() { pulses.removeAll { $0.kind == .call } }
    var callActive: Bool { pulses.contains { $0.kind == .call } }

    func runMusicDemo(seconds: Double = 10) {
        demoUntil = CACurrentMediaTime() + seconds
        wake()
    }

    // MARK: windows

    func rebuildWindows() {
        windows.forEach { $0.orderOut(nil) }
        let screens = settings.allDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        windows = screens.map { OverlayWindow(screen: $0) }
        if timer != nil { windows.forEach { $0.orderFrontRegardless() } }
    }

    // MARK: clock

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.1, now - lastTick))
        lastTick = now

        let reading = pipeline.latest
        let demo = now < demoUntil
        if reading.rms > 0.004 { lastLoud = now }
        let sounding = settings.music && (demo || now - lastLoud < 1.5)

        let target: [Float] = demo ? Self.demoBands(at: now) : (sounding ? reading.bands : [Float](repeating: 0, count: 32))
        let bands = smoother.update(target, dt: dt)
        let goal: Float = sounding ? 1 : 0
        let tau: Float = goal > musicLevel ? 0.35 : 0.9
        musicLevel += (goal - musicLevel) * (1 - expf(-dt / tau))

        pulses.removeAll { $0.kind == .notification && now - $0.start > $0.duration }
        if !settings.calls { clearCalls() }
        if pulses.contains(where: { $0.kind == .call && now - $0.start > 90 }) { clearCalls() }   // never stuck forever

        let frame = GlowFrame(time: now, bands: bands, musicLevel: musicLevel, pulses: pulses,
                              musicColors: settings.musicColors, musicAnimation: settings.musicAnimation,
                              alertAnimation: settings.alertAnimation,
                              thickness: CGFloat(settings.thickness), brightness: CGFloat(settings.brightness))
        for w in windows {
            w.glow.show(frame)
        }

        if musicLevel < 0.01 && pulses.isEmpty && !sounding {
            if idleSince == nil { idleSince = now }
            if now - idleSince! > 0.3 { sleep() }
        } else {
            idleSince = nil
        }
    }

    private func sleep() {
        timer?.invalidate(); timer = nil
        smoother.reset()
        windows.forEach { $0.orderOut(nil) }
    }

    /// A made-up beat so the animation can be tried without any music playing.
    static func demoBands(at t: Double) -> [Float] {
        let beat = Float(pow(max(0, sin(t * 2 * .pi * 2.0)), 6))                  // kick at 120 bpm
        let hat = Float(pow(max(0, sin(t * 2 * .pi * 4.0 + 1.0)), 10))
        return (0..<32).map { i in
            let x = Float(i) / 31
            let bass = beat * expf(-x * 5)
            let mid = 0.35 * (0.5 + 0.5 * sinf(Float(t) * 3.1 + x * 9)) * (1 - abs(x - 0.4))
            let treble = hat * 0.8 * x
            return min(1, bass + mid + treble)
        }
    }
}
