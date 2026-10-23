import AppKit
import EdgelitCore

enum Preview {
    static func write(to folder: String) {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let size = CGSize(width: 1440, height: 900)
        var smoother = BandSmoother(bandCount: 32)
        var bands: [Float] = []
        // Run the demo beat for a couple of seconds so the bands settle the way they do live.
        var t = 10.0
        for _ in 0..<158 { bands = smoother.update(GlowEngine.demoBands(at: t), dt: 1 / 60); t += 1 / 60 }

        func png(_ name: String, _ frame: GlowFrame) {
            let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1))     // stand-in desktop
            ctx.fill(CGRect(origin: .zero, size: size))
            GlowRenderer.draw(frame, in: ctx, size: size)
            let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder + "/" + name + ".png"))
        }

        for anim in MusicAnimation.allCases {
            png("music-\(anim.rawValue)", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicAnimation: anim))
        }
        for style in GlowStyle.allCases {
            png("colours-\(style.rawValue)", GlowFrame(time: 3, bands: bands, musicLevel: 1, pulses: [], musicColors: style.colors, musicAnimation: .pulse))
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
