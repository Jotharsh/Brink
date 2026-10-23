// swift scripts/make_icon.swift  ->  Resources/AppIcon.icns
import AppKit

let S: CGFloat = 1024
func render(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(px) / S, y: CGFloat(px) / S)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 184, cornerHeight: 184, transform: nil)
    ctx.addPath(shape); ctx.setFillColor(CGColor(srgbRed: 0.06, green: 0.06, blue: 0.07, alpha: 1)); ctx.fillPath()
    // Light spilling inwards from all four edges, in aurora colours.
    ctx.saveGState(); ctx.addPath(shape); ctx.clip(); ctx.setBlendMode(.plusLighter)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func edge(_ c: [CGFloat], _ a: CGPoint, _ b: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: [CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 0.95),
                                                         CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 0.28),
                                                         CGColor(srgbRed: c[0], green: c[1], blue: c[2], alpha: 0)] as CFArray, locations: [0, 0.4, 1])!
        ctx.drawLinearGradient(g, start: a, end: b, options: [])
    }
    edge([0.10, 0.90, 0.70], CGPoint(x: 0, y: 100), CGPoint(x: 0, y: 360))          // bottom
    edge([1.00, 0.35, 0.70], CGPoint(x: 0, y: 924), CGPoint(x: 0, y: 664))          // top
    edge([0.25, 0.55, 1.00], CGPoint(x: 100, y: 0), CGPoint(x: 360, y: 0))          // left
    edge([0.65, 0.35, 1.00], CGPoint(x: 924, y: 0), CGPoint(x: 664, y: 0))          // right
    ctx.restoreGState()
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

let dir = "build/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
