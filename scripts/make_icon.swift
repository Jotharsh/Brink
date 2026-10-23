// swift scripts/make_icon.swift  ->  Resources/AppIcon.icns and docs/logo.png
// The icon: a screen drawn as a thin frame of light, with a small bright streak running along its corner.
import AppKit

let S: CGFloat = 1024
func render(_ px: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    // Tile
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 184, cornerHeight: 184, transform: nil)
    ctx.addPath(tile); ctx.setFillColor(c(0.045, 0.047, 0.058)); ctx.fillPath()
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()

    // The screen
    let screen = CGRect(x: 232, y: 330, width: 560, height: 364)
    let frame = CGPath(roundedRect: screen, cornerWidth: 64, cornerHeight: 64, transform: nil)
    let ring = frame.copy(strokingWithWidth: 30, lineCap: .round, lineJoin: .round, miterLimit: 10)

    // Soft glow behind the frame, and a faint tint inside it
    ctx.addPath(frame); ctx.setFillColor(c(0.10, 0.09, 0.16, 0.55)); ctx.fillPath()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 70, color: c(0.45, 0.30, 1.0, 0.95))
    ctx.addPath(ring); ctx.setFillColor(c(0.30, 0.45, 0.95)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: c(0.10, 0.85, 0.75, 0.8))
    ctx.addPath(ring); ctx.setFillColor(c(0.30, 0.45, 0.95)); ctx.fillPath()
    ctx.restoreGState()

    // The frame itself, teal at the bottom left to violet at the top right
    ctx.saveGState(); ctx.addPath(ring); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [c(0.05, 0.85, 0.72), c(0.30, 0.50, 1.0), c(0.62, 0.32, 1.0)] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: screen.minX, y: screen.minY), end: CGPoint(x: screen.maxX, y: screen.maxY), options: [])
    ctx.restoreGState()

    // The streak: a short, brighter run of light round the top left corner
    ctx.saveGState(); ctx.addPath(ring); ctx.clip()
    let glint = CGGradient(colorsSpace: space, colors: [c(1, 1, 1, 0.95), c(1, 1, 1, 0.45), c(1, 1, 1, 0)] as CFArray, locations: [0, 0.4, 1])!
    let at = CGPoint(x: screen.minX + 70, y: screen.maxY - 12)
    ctx.drawRadialGradient(glint, startCenter: at, startRadius: 0, endCenter: at, endRadius: 210, options: [])
    ctx.restoreGState()

    ctx.restoreGState()
    return ctx.makeImage()!
}

func png(_ img: CGImage) -> Data { NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])! }

let dir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! png(render(px)).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
try? FileManager.default.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try! png(render(512)).write(to: URL(fileURLWithPath: "docs/logo.png"))
