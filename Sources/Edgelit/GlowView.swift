import AppKit
import EdgelitCore

/// Shows the current frame. The glow is soft by nature, so it is drawn small (a quarter of the screen's
/// size in each direction) and the GPU stretches it to fit. That keeps each frame cheap enough for 60 fps.
final class GlowView: NSView {
    private static let scale: CGFloat = 0.25
    private var context: CGContext?
    private var contextSize = CGSize.zero

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .linear
        layer?.isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ frame: GlowFrame) {
        let small = CGSize(width: max(8, (bounds.width * Self.scale).rounded()), height: max(8, (bounds.height * Self.scale).rounded()))
        if context == nil || contextSize != small {
            context = CGContext(data: nil, width: Int(small.width), height: Int(small.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            contextSize = small
        }
        guard let ctx = context else { return }
        ctx.clear(CGRect(origin: .zero, size: small))
        GlowRenderer.draw(frame, in: ctx, size: small)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = ctx.makeImage()
        CATransaction.commit()
    }
}

/// One borderless window per screen, above everything, ignoring the mouse.
final class OverlayWindow: NSWindow {
    let glow: GlowView

    init(screen: NSScreen) {
        glow = GlowView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        contentView = glow
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
