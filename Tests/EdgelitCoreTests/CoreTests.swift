import XCTest
@testable import EdgelitCore

final class CoreTests: XCTestCase {
    func sine(_ hz: Float, count: Int = 1024, rate: Float = 48000, amp: Float = 0.5) -> [Float] {
        (0..<count).map { amp * sinf(2 * .pi * hz * Float($0) / rate) }
    }

    func testSilenceGivesZeroBands() {
        let a = SpectrumAnalyzer()
        XCTAssertEqual(a.analyze([Float](repeating: 0, count: 1024)).max(), 0)
    }

    func testSinePeaksInTheRightBand() {
        let a = SpectrumAnalyzer()
        for hz: Float in [100, 440, 1000, 4000, 10000] {
            let bands = a.analyze(sine(hz))
            let peak = bands.firstIndex(of: bands.max()!)!
            XCTAssertLessThanOrEqual(abs(peak - a.band(forHz: hz)), 1, "\(hz) Hz landed in band \(peak)")
            XCTAssertGreaterThan(bands.max()!, 0.4, "\(hz) Hz is too quiet")
        }
    }

    func testLouderIsBrighter() {
        let a = SpectrumAnalyzer()
        let quiet = a.analyze(sine(440, amp: 0.02)).max()!
        let loud = a.analyze(sine(440, amp: 0.8)).max()!
        XCTAssertGreaterThan(loud, quiet + 0.2)
    }

    func testTooFewSamplesIsSafe() {
        XCTAssertEqual(SpectrumAnalyzer().analyze([0.1, 0.2]).count, 32)
    }

    func testSmootherRisesFastFallsSlow() {
        var s = BandSmoother(bandCount: 1)
        let up = (0..<3).map { _ in s.update([1], dt: 1 / 60)[0] }.last!
        XCTAssertGreaterThan(up, 0.5)
        let afterThree = (0..<3).map { _ in s.update([0], dt: 1 / 60)[0] }.last!
        XCTAssertGreaterThan(afterThree, up * 0.6, "should fall more slowly than it rose")
    }

    func testSmootherNormalisesQuietMusic() {
        var s = BandSmoother(bandCount: 1)
        for _ in 0..<120 { s.update([0.5], dt: 1 / 60) }
        XCTAssertGreaterThan(s.values[0], 0.9, "a steady 0.5 should be scaled up to fill the edge")
    }

    func testPipelineProducesBandsFromChunks() {
        let p = AudioPipeline()
        let tone = sine(440, count: 48000)
        var i = 0
        while i < tone.count { p.feed(Array(tone[i..<min(i + 480, tone.count)])); i += 480 }
        XCTAssertGreaterThan(p.latest.rms, 0.3)
        XCTAssertGreaterThan(p.latest.bands.max()!, 0.4)
    }

    func testColorLoop() {
        let one = ColorLoop.color([RGB(1, 0, 0)], at: 0.37)
        XCTAssertEqual(one, RGB(1, 0, 0), "one colour stays solid")
        let two = [RGB(0, 0, 0), RGB(1, 1, 1)]
        XCTAssertEqual(ColorLoop.color(two, at: 0).r, ColorLoop.color(two, at: 1).r, accuracy: 1e-9)
        XCTAssertEqual(ColorLoop.color(two, at: 0.25).r, 0.5, accuracy: 1e-9)
        XCTAssertEqual(ColorLoop.color(two, at: 0.3).g, ColorLoop.color(two, at: 7.3).g, accuracy: 1e-9)
        XCTAssertEqual(ColorLoop.color([], at: 0.5), RGB(1, 1, 1))
    }

    func testHexRoundTrip() {
        XCTAssertEqual(RGB(hex: "#1ae6b3")?.hex, "#1AE6B3")
        XCTAssertEqual(RGB(hex: "FF0000"), RGB(1, 0, 0))
        XCTAssertNil(RGB(hex: "nope")); XCTAssertNil(RGB(hex: "#12345"))
        for style in GlowStyle.allCases { XCTAssertFalse(style.colors.isEmpty); XCTAssertLessThanOrEqual(style.colors.count, 3) }
    }

    func testClassifier() {
        XCTAssertEqual(NotificationClassifier.classify(["FaceTime", "Mum", "Incoming call"]).kind, .call)
        XCTAssertEqual(NotificationClassifier.classify(["Phone", "Dad"]).kind, .call)
        XCTAssertEqual(NotificationClassifier.classify(["Zoom", "Someone is calling"]).kind, .call)
        let m = NotificationClassifier.classify(["Messages", "Sam", "lunch?"])
        XCTAssertEqual(m.kind, .notification); XCTAssertEqual(m.app, "Messages")
        XCTAssertEqual(NotificationClassifier.classify(["Some App", "hello"]).color, NotificationClassifier.fallback)
        XCTAssertEqual(NotificationClassifier.classify([]).kind, .notification)
    }

    func testAlertEnvelopes() {
        let n = GlowPulse(kind: .notification, color: RGB(1, 1, 1), start: 10, duration: 2)
        let c = GlowPulse(kind: .call, color: RGB(0, 1, 0), start: 0)
        for anim in AlertAnimation.allCases {
            XCTAssertEqual(GlowRenderer.envelope(of: n, animation: anim, at: 9), 0, "\(anim) before it starts")
            XCTAssertEqual(GlowRenderer.envelope(of: n, animation: anim, at: 12.5), 0, "\(anim) after it ends")
            XCTAssertGreaterThan(GlowRenderer.envelope(of: n, animation: anim, at: 10.4), 0, "\(anim) while running")
            let mid = (0..<200).map { GlowRenderer.envelope(of: c, animation: anim, at: 300 + Double($0) * 0.02) }
            XCTAssertGreaterThan(mid.max()!, 0.5, "a call keeps animating until cleared (\(anim))")
        }
        XCTAssertGreaterThan(GlowRenderer.envelope(of: n, animation: .pulse, at: 11), 0.9)
        let head1 = GlowRenderer.sweepHead(of: n, at: 10.2), head2 = GlowRenderer.sweepHead(of: n, at: 11)
        XCTAssertLessThan(head1, head2, "the sweep moves forward")
    }

    func ctx400() -> CGContext {
        CGContext(data: nil, width: 400, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    func alpha(_ c: CGContext, _ x: Int, _ y: Int) -> UInt8 { c.data!.assumingMemoryBound(to: UInt8.self)[(y * c.bytesPerRow) + x * 4 + 3] }

    func testEveryMusicAnimationGlowsAtTheEdgeOnly() {
        for anim in MusicAnimation.allCases {
            let c = ctx400()
            let f = GlowFrame(time: 1, bands: [Float](repeating: 1, count: 32), musicLevel: 1, pulses: [], musicAnimation: anim)
            GlowRenderer.draw(f, in: c, size: CGSize(width: 400, height: 300))
            XCTAssertGreaterThan((0..<400).map { alpha(c, $0, 1) }.max()!, 60, "\(anim): bottom edge")
            XCTAssertGreaterThan((0..<300).map { alpha(c, 1, $0) }.max()!, 60, "\(anim): left edge")
            XCTAssertEqual(alpha(c, 200, 150), 0, "\(anim): middle must stay clear")
        }
    }

    func testThicknessAndBrightnessChangeTheLook() {
        func glowDepth(_ thickness: CGFloat, _ brightness: CGFloat) -> (Int, UInt8) {
            let c = ctx400()
            GlowRenderer.draw(GlowFrame(time: 1, bands: [Float](repeating: 1, count: 32), musicLevel: 1, pulses: [],
                                        musicAnimation: .pulse, thickness: thickness, brightness: brightness), in: c, size: CGSize(width: 400, height: 300))
            var depth = 0
            while depth < 150, alpha(c, 200, depth) > 8 { depth += 1 }
            return (depth, alpha(c, 200, 1))
        }
        XCTAssertGreaterThan(glowDepth(2, 0.9).0, glowDepth(1, 0.9).0 + 3, "thicker reaches further in")
        XCTAssertGreaterThan(glowDepth(1, 1.0).1, glowDepth(1, 0.3).1, "brighter is more opaque")
    }

    func testAlertAnimationsDraw() {
        for anim in AlertAnimation.allCases {
            let c = ctx400()
            let p = GlowPulse(kind: .call, color: RGB(0, 1, 0), start: 0)
            GlowRenderer.draw(GlowFrame(time: 0.9, bands: [], musicLevel: 0, pulses: [p], alertAnimation: anim), in: c, size: CGSize(width: 400, height: 300))
            var any = false
            for y in 0..<300 { for x in stride(from: 0, to: 400, by: 4) where alpha(c, x, y) > 20 { any = true } }
            XCTAssertTrue(any, "\(anim) should draw something")
            XCTAssertEqual(alpha(c, 200, 150), 0)
        }
    }
}

extension CoreTests {
    func testStripIsEvenAlongTheEdge() {
        // A neat strip: the same brightness along a straight run of the edge, never lumpy.
        let c = ctx400()
        GlowRenderer.draw(GlowFrame(time: 1, bands: [Float](repeating: 0.6, count: 32), musicLevel: 1, pulses: [],
                                    musicColors: [RGB(0, 1, 1)], musicAnimation: .pulse, energy: 0.6),
                          in: c, size: CGSize(width: 400, height: 300))
        let values = stride(from: 80, through: 320, by: 20).map { Int(alpha(c, $0, 1)) }
        XCTAssertLessThanOrEqual(values.max()! - values.min()!, 3, "brightness should not vary along a single-colour pulse strip: \(values)")
    }

    func testEnergyIsCalmAndBounded() {
        XCTAssertEqual(GlowFrame.energy(of: []), 0)
        XCTAssertEqual(GlowFrame.energy(of: [Float](repeating: 0, count: 32)), 0)
        XCTAssertLessThanOrEqual(GlowFrame.energy(of: [Float](repeating: 1, count: 32)), 1)
    }
}
