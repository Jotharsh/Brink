import AppKit
import BrinkCore

enum Preview {
    static func write(to folder: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let size = CGSize(width: 1440, height: 900)
        var smoother = BandSmoother(bandCount: 32)
        var bands: [Float] = []
        // Run the demo beat for a couple of seconds so the bands settle the way they do live.
        var t = 10.0
        for _ in 0..<158 { bands = smoother.update(GlowEngine.demoBands(at: t), dt: 1 / 60); t += 1 / 60 }

        func png(_ name: String, _ frame: GlowFrame, light: Bool = false) {
            let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(light ? CGColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1) : CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1))     // stand-in desktop
            ctx.fill(CGRect(origin: .zero, size: size))
            GlowRenderer.draw(frame, in: ctx, size: size)
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder + "/" + name + ".png"))
        }

        let soft = { (f: GlowFrame) -> GlowFrame in var g = f; g.brightness = 0.65; return g }
        png("light-pulse", soft(GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicAnimation: .pulse)), light: true)
        png("dark-pulse", soft(GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicAnimation: .pulse)))
        png("light-call", soft(GlowFrame(time: 1.1, bands: [], musicLevel: 0, pulses: [GlowPulse(kind: .call, color: NotificationClassifier.call, start: 0)])), light: true)
        for anim in MusicAnimation.allCases {
            png("music-\(anim.rawValue)", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicAnimation: anim))
        }
        for style in GlowStyle.allCases {
            png("colours-\(style.rawValue)", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicColors: style.colors, musicAnimation: .flow))
        }
        let blue = NotificationClassifier.classify(["Messages"]).color
        for anim in AlertAnimation.allCases {
            let n = GlowPulse(kind: .notification, color: blue, start: 0, duration: 2.4)
            png("notification-\(anim.rawValue)", GlowFrame(time: anim == .blink ? 0.4 : 1.1, bands: [], musicLevel: 0, pulses: [n], alertAnimation: anim))
            let c = GlowPulse(kind: .call, color: NotificationClassifier.call, start: 0)
            png("call-\(anim.rawValue)", GlowFrame(time: 1.1, bands: [], musicLevel: 0, pulses: [c], alertAnimation: anim))
        }
    }
}

extension Preview {
    /// Times the renderer at Retina size, to be sure a frame fits comfortably inside 1/60 s.
    static func bench() {
        let w = 720, h = 450   // the live view draws at a quarter of Retina size; the GPU scales it up
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bands = GlowEngine.demoBands(at: 0.125)
        let n = 60
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<n {
            ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
            GlowRenderer.draw(GlowFrame(time: Double(i) / 60, bands: bands, musicLevel: 1, pulses: []), in: ctx, size: CGSize(width: w, height: h))
        }
        print(String(format: "%.1f ms per frame at %dx%d (the size drawn live)", (CFAbsoluteTimeGetCurrent() - start) / Double(n) * 1000, w, h))
    }
}

extension Preview {
    /// A sheet of six looks, for the README. These are rendered by the real drawing code, on a stand-in desktop.
    static func hero(to path: String) {
        let tile = CGSize(width: 800, height: 500), gap: CGFloat = 40, label: CGFloat = 70
        let cols = 3, rows = 2
        let W = Int(CGFloat(cols) * tile.width + CGFloat(cols + 1) * gap)
        let H = Int(CGFloat(rows) * (tile.height + label) + CGFloat(rows + 1) * gap)
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.045, green: 0.047, blue: 0.058, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        var smoother = BandSmoother(bandCount: 32)
        var bands: [Float] = []
        var t = 10.0
        for _ in 0..<158 { bands = smoother.update(GlowEngine.demoBands(at: t), dt: 1 / 60); t += 1 / 60 }
        let blue = NotificationClassifier.classify(["Messages"]).color
        let n = GlowPulse(kind: .notification, color: blue, start: 0, duration: 2.4)
        let call = GlowPulse(kind: .call, color: NotificationClassifier.call, start: 0)

        let items: [(String, GlowFrame)] = [
            ("Music  ·  Pulse", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicAnimation: .pulse, energy: 0.9)),
            ("Music  ·  Flow", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicColors: GlowStyle.ocean.colors, musicAnimation: .flow, energy: 0.9, phase: 0.2)),
            ("Music  ·  Segments", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicColors: GlowStyle.ember.colors, musicAnimation: .segments, energy: 0.9)),
            ("Notification  ·  Sweep", GlowFrame(time: 0.7, bands: [], musicLevel: 0, pulses: [n], alertAnimation: .sweep)),
            ("Notification  ·  Pulse", GlowFrame(time: 1.2, bands: [], musicLevel: 0, pulses: [n], alertAnimation: .pulse)),
            ("Incoming call", GlowFrame(time: 1.1, bands: [], musicLevel: 0, pulses: [call], alertAnimation: .pulse)),
        ]
        for (i, item) in items.enumerated() {
            let col = i % cols, row = rows - 1 - i / cols
            let x = gap + CGFloat(col) * (tile.width + gap)
            let y = gap + CGFloat(row) * (tile.height + label + gap) + label
            let rect = CGRect(x: x, y: y, width: tile.width, height: tile.height)
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 18, cornerHeight: 18, transform: nil)); ctx.clip()
            ctx.setFillColor(CGColor(srgbRed: 0.075, green: 0.077, blue: 0.09, alpha: 1)); ctx.fill(rect)
            ctx.translateBy(x: x, y: y)
            var f = item.1; f.brightness = 1.0; f.thickness = 1.6
            GlowRenderer.draw(f, in: ctx, size: tile)
            ctx.restoreGState()

            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
            (item.0 as NSString).draw(at: CGPoint(x: x + 6, y: y - 52),
                                      withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor(white: 0.82, alpha: 1)])
            NSGraphicsContext.restoreGraphicsState()
        }
        try? NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])?
            .write(to: URL(fileURLWithPath: path))
    }
}

extension Preview {
    /// Renders a 15-second showcase as PNG frames (music in three styles, then a notification, then a call).
    /// Used to make demo videos with the real drawing code.
    static func frames(to folder: String, fps: Int = 30) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let size = CGSize(width: 960, height: 600)
        var smoother: BandSmoother = { var s = BandSmoother(bandCount: 32); s.release = 0.13; return s }()
        var beat = BeatTracker()
        var musicLevel: Float = 0, phase = 0.0
        let blue = NotificationClassifier.classify(["Messages"]).color
        let total = 15 * fps
        // BRINK_FRAME_THICKNESS=2.6 makes the showcase thicker and brighter, for small or busy places like a web page
        let thick = CGFloat(Double(ProcessInfo.processInfo.environment["BRINK_FRAME_THICKNESS"] ?? "") ?? 1.5)
        for i in 0..<total {
            let t = Double(i) / Double(fps), dt = Float(1.0 / Double(fps))
            let musicOn = t < 9.0
            let live = GlowEngine.demoBands(at: t + 20)
            let bands = smoother.update(musicOn ? live : [Float](repeating: 0, count: 32), dt: dt)
            let bass = live.prefix(8).reduce(0, +) / 8, body = live.dropFirst(8).prefix(8).reduce(0, +) / 8
            let energy = beat.update(musicOn ? bass * 0.75 + body * 0.25 : 0, dt: dt)
            phase = (phase + Double(dt) * Double(0.03 + 0.10 * energy)).truncatingRemainder(dividingBy: 1)
            let goal: Float = musicOn ? 1 : 0
            musicLevel += (goal - musicLevel) * (1 - expf(-dt / (goal > musicLevel ? 0.35 : 0.5)))

            let animation: MusicAnimation = t < 3 ? .pulse : (t < 6 ? .flow : .segments)
            let colours = t < 3 ? GlowStyle.aurora.colors : (t < 6 ? GlowStyle.ocean.colors : GlowStyle.ember.colors)
            var pulses: [GlowPulse] = []
            if t >= 9.4 && t < 11.8 { pulses.append(GlowPulse(kind: .notification, color: blue, start: 9.4, duration: 2.4)) }
            if t >= 12 { pulses.append(GlowPulse(kind: .call, color: NotificationClassifier.call, start: 12)) }
            let frame = GlowFrame(time: t, bands: bands, musicLevel: musicLevel, pulses: pulses, musicColors: colours,
                                  musicAnimation: animation, alertAnimation: .pulse, thickness: thick, brightness: 1.0,
                                  energy: energy, phase: phase)

            let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(srgbRed: 0.055, green: 0.058, blue: 0.072, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
            GlowRenderer.draw(frame, in: ctx, size: size)
            let name = String(format: "%@/%04d.png", folder, i)
            try? NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
        }
    }
}
