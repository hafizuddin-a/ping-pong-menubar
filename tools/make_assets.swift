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

    let sceneW = 520, sceneH = 532      // a crop of the top right of a Mac screen, like a screenshot
    let scale: CGFloat = 1.45
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

    /// A system symbol in white, centred on a point.
    func symbol(_ name: String, size: CGFloat, at c: NSPoint) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        img.draw(in: NSRect(x: c.x - img.size.width / 2, y: c.y - img.size.height / 2, width: img.size.width, height: img.size.height))
    }

    // The desktop never changes, so draw it once.
    let desktop: CGImage = {
        let rep = bitmap(sceneW, sceneH)
        draw(into: rep) {
            let W = CGFloat(sceneW), H = CGFloat(sceneH)
            // A flat desktop: gradients band badly in a 256-colour GIF.
            NSColor(white: 0.07, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: W, height: H).fill()
            // translucent menu bar
            NSColor.black.withAlphaComponent(0.30).setFill()
            NSRect(x: 0, y: H - 48, width: W, height: 48).fill()
        }
        return rep.cgImage!
    }()

    func scene(panel: NSImage) -> CGImage {
        let rep = bitmap(sceneW, sceneH)
        draw(into: rep) {
            let W = CGFloat(sceneW), H = CGFloat(sceneH)
            NSImage(cgImage: desktop, size: NSSize(width: W, height: H)).draw(in: NSRect(x: 0, y: 0, width: W, height: H))
            let cy = H - 24

            // The other menu bar items: Wi-Fi, Spotlight, Control Centre, clock.
            let iconX = W - 339
            symbol("wifi", size: 21, at: NSPoint(x: W - 271, y: cy))
            symbol("magnifyingglass", size: 21, at: NSPoint(x: W - 203, y: cy))
            symbol("switch.2", size: 21, at: NSPoint(x: W - 135, y: cy))
            let clock = NSAttributedString(string: "9:41", attributes: [
                .font: NSFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: NSColor.white])
            clock.draw(at: NSPoint(x: W - 22 - clock.size().width, y: cy - clock.size().height / 2))

            // Ping's own icon (same drawing as AppDelegate), shown pressed.
            NSColor.white.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: iconX - 29, y: cy - 17, width: 58, height: 34), xRadius: 9, yRadius: 9).fill()
            let t = NSAffineTransform(); t.translateX(by: iconX - 17.1, yBy: cy - 15.2); t.scale(by: 1.9); t.concat()
            NSColor.white.setFill()
            pill(NSRect(x: 7, y: 12.6, width: 8, height: 2.4))
            pill(NSRect(x: 3, y: 1, width: 8, height: 2.4))
            NSBezierPath(ovalIn: NSRect(x: 7.2, y: 6.2, width: 3.6, height: 3.6)).fill()
            t.invert(); t.concat()

            // The glass panel under the icon, with a soft shadow.
            let pw = view.bounds.width * scale, ph = view.bounds.height * scale
            let panelRect = NSRect(x: iconX - pw / 2, y: H - 48 - 10 - ph, width: pw, height: ph)
            let shape = NSBezierPath(roundedRect: panelRect, xRadius: 26 * scale, yRadius: 26 * scale)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.55); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.set()
            NSColor(white: 0.13, alpha: 0.86).setFill(); shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting: NSColor.white.withAlphaComponent(0.09), ending: NSColor.white.withAlphaComponent(0.02))!
                .draw(in: shape, angle: -90)
            NSColor.white.withAlphaComponent(0.20).setStroke(); shape.lineWidth = 1.2; shape.stroke()
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
    let fps = 15.0, total = 200
    var i = -1
    // Play at least `total` frames, and on until both a point or two has been scored (capped), so the score moves.
    while i + 1 < total || (g.playerScore + g.botScore < 2 && i < 420) {
        i += 1
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
