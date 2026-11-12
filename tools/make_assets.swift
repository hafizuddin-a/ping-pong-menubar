import AppKit
import ImageIO
import UniformTypeIdentifiers

// Draws assets/logo.png and assets/demo-play.gif in black and white, using the app's real GameView and bot.
// Run through tools/make_assets.sh.

let out = CommandLine.arguments.dropFirst()
let logoPath = out.first!, gifPath = out.dropFirst().first!, iconPath = out.dropFirst(2).first!
let debugDir = out.dropFirst(3).first      // optional: also write a few still frames here

func bitmap(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func pill(_ r: NSRect) { NSBezierPath(roundedRect: r, xRadius: min(r.width, r.height) / 2, yRadius: min(r.width, r.height) / 2).fill() }

// MARK: - logo: a black tile with the game's vertical layout in white

/// `inset` leaves the transparent margin macOS app icons have; the README logo uses none.
func makeLogo(to path: String, inset: CGFloat) {
    let s = 1024
    let rep = bitmap(s, s)
    draw(into: rep) {
        let f = CGFloat(s)
        let t = NSAffineTransform()
        t.translateX(by: f * inset, yBy: f * inset)
        t.scale(by: 1 - 2 * inset)
        t.concat()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: f, height: f), xRadius: f * 0.225, yRadius: f * 0.225).fill()
        // dotted centre line
        let dots = NSBezierPath()
        dots.move(to: NSPoint(x: f * 0.18, y: f / 2)); dots.line(to: NSPoint(x: f * 0.82, y: f / 2))
        dots.lineWidth = f * 0.018; dots.lineCapStyle = .round; dots.setLineDash([0.01, f * 0.05], count: 2, phase: 0)
        NSColor.white.withAlphaComponent(0.28).setStroke(); dots.stroke()
        // paddles and ball
        NSColor.white.withAlphaComponent(0.5).setFill()
        pill(NSRect(x: f * 0.50, y: f * 0.80, width: f * 0.30, height: f * 0.05))
        NSColor.white.setFill()
        pill(NSRect(x: f * 0.20, y: f * 0.15, width: f * 0.30, height: f * 0.05))
        let r = f * 0.045
        NSBezierPath(ovalIn: NSRect(x: f * 0.585 - r, y: f * 0.60 - r, width: r * 2, height: r * 2)).fill()
    }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - demo gif

MainActor.assumeIsolated {
    _ = NSApplication.shared
    makeLogo(to: logoPath, inset: 0)
    makeLogo(to: iconPath, inset: 0.098)

    let sceneW = 520, sceneH = 420
    let scale: CGFloat = 1.15
    let view = GameView(frame: NSRect(origin: .zero, size: GameView.size))
    view.appearance = NSAppearance(named: .darkAqua)
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.appearance = view.appearance
    window.contentView = view

    func panelImage() -> NSImage {
        let rep = bitmap(Int(view.bounds.width) * 2, Int(view.bounds.height) * 2)
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: view.bounds.size)
        img.addRepresentation(rep)
        return img
    }

    func scene(panel: NSImage) -> CGImage {
        let rep = bitmap(sceneW, sceneH)
        draw(into: rep) {
            let W = CGFloat(sceneW), H = CGFloat(sceneH)
            NSColor.black.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
            // menu bar strip, with the app's icon pressed
            NSColor.white.withAlphaComponent(0.07).setFill(); NSRect(x: 0, y: H - 26, width: W, height: 26).fill()
            // the app's menu bar icon (same drawing as AppDelegate), enlarged a little, shown pressed
            let iconX = W / 2 - 9, iconY = H - 26
            NSColor.white.withAlphaComponent(0.2).setFill(); pill(NSRect(x: iconX - 8, y: iconY + 2, width: 34, height: 22))
            let t = NSAffineTransform(); t.translateX(by: iconX - 4.5, yBy: iconY + 1.5); t.scale(by: 1.4); t.concat()
            NSColor.white.setFill()
            pill(NSRect(x: 7, y: 12.6, width: 8, height: 2.4))
            pill(NSRect(x: 3, y: 1, width: 8, height: 2.4))
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 6.2, width: 3.6, height: 3.6)).fill()
            t.invert(); t.concat()
            // glass panel under the icon
            let pw = view.bounds.width * scale, ph = view.bounds.height * scale
            let panelRect = NSRect(x: iconX + 4.5 - pw / 2, y: iconY - 6 - ph, width: pw, height: ph)
            let shape = NSBezierPath(roundedRect: panelRect, xRadius: 26 * scale, yRadius: 26 * scale)
            NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0.05))!
                .draw(in: shape, angle: -90)
            NSColor.white.withAlphaComponent(0.22).setStroke(); shape.lineWidth = 1; shape.stroke()
            panel.draw(in: panelRect)
        }
        return rep.cgImage!
    }

    // Play a real match: a scripted player against the Normal bot.
    let g = view.game
    g.difficulty = .normal
    var frames: [CGImage] = []
    var wobble = 0.0
    var lastRally = 0
    g.onEvent = { e in if e == .paddleHit { wobble = Double.random(in: -13...13) } }
    func hold(_ n: Int) { for _ in 0..<n { frames.append(scene(panel: panelImage())) } }

    hold(10)                                  // "SPACE TO PLAY"
    g.primaryAction()
    let fps = 15.0, total = 270
    for i in 0..<total {
        for _ in 0..<2 {
            let aim = (g.botY > 95 ? -15.0 : 15.0) + wobble
            let err = g.ballY - g.playerY - aim
            g.step(1.0 / (fps * 2), input: abs(err) < 3 ? 0 : (err > 0 ? 1 : -1))
        }
        frames.append(scene(panel: panelImage()))
        if let d = debugDir, [20, 130, 260].contains(i) {
            let rep = NSBitmapImageRep(cgImage: frames.last!)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(d)/frame\(i).png"))
        }
        _ = lastRally
    }

    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: gifPath) as CFURL, UTType.gif.identifier as CFString, frames.count, nil)!
    CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for f in frames {
        CGImageDestinationAddImage(dest, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary)
    }
    CGImageDestinationFinalize(dest)
    print("final score \(g.playerScore)-\(g.botScore)")
}
