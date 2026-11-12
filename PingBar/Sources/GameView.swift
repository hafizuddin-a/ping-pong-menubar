import AppKit
import QuartzCore

/// Draws the game and feeds it keyboard input. The model plays along its x axis; this view
/// stands it upright (model x -> screen y, model y -> screen x), so you sit at the bottom.
/// Everything is drawn in `labelColor`, so on glass it adapts to light and dark by itself.
@MainActor
final class GameView: NSView {
    /// On-screen size: the model's field turned on its end.
    static let size = NSSize(width: PongGame.height, height: PongGame.width)

    let game = PongGame()
    var onEscape: (() -> Void)?

    private var keys = Set<UInt16>()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    private enum Key {
        static let left: UInt16 = 123, right: UInt16 = 124, a: UInt16 = 0, d: UInt16 = 2
        static let space: UInt16 = 49, `return`: UInt16 = 36, escape: UInt16 = 53
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        game.onEvent = { [weak self] event in self?.handle(event) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { Self.size }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - loop

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        // NSView.displayLink follows the screen the window is on, and stops when it is hidden.
        let l = displayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        l.isPaused = true
        link = l
    }

    /// Called when the panel opens. A rally in progress waits for Space rather than resuming blind.
    func activate() {
        lastTimestamp = 0
        link?.isPaused = false
        needsDisplay = true
    }

    /// Called when the panel closes: stop the clock so the app costs nothing while hidden.
    func deactivate() {
        game.pause()
        keys.removeAll()
        link?.isPaused = true
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 : now - lastTimestamp
        lastTimestamp = now
        var input = 0.0
        if keys.contains(Key.left) || keys.contains(Key.a) { input -= 1 }
        if keys.contains(Key.right) || keys.contains(Key.d) { input += 1 }
        game.step(dt, input: input)
        needsDisplay = true
    }

    private func handle(_ event: GameEvent) {
        let haptics = NSHapticFeedbackManager.defaultPerformer
        switch event {
        case .paddleHit: haptics.perform(.alignment, performanceTime: .now)
        case .playerScored, .botScored: haptics.perform(.levelChange, performanceTime: .now)
        default: break
        }
    }

    // MARK: - keyboard

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case Key.space, Key.return:
            if !event.isARepeat { game.primaryAction() }
        case Key.escape:
            onEscape?()
        case Key.left, Key.right, Key.a, Key.d:
            keys.insert(event.keyCode)
            if game.phase == .paused { game.primaryAction() }     // moving is enough to resume
            if game.phase == .idle || game.phase == .over, !event.isARepeat { game.primaryAction() }
        default:
            break      // swallow everything else so the system doesn't beep
        }
    }

    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }

    // MARK: - drawing

    /// Model (along, across) -> screen point. Model x = 0 is the player's end, drawn at the bottom.
    private func pt(_ along: Double, _ across: Double) -> NSPoint {
        NSPoint(x: across, y: PongGame.width - along)
    }

    override func draw(_ dirtyRect: NSRect) {
        let g = game
        let ink = NSColor.labelColor
        let w = Self.size.width, h = Self.size.height
        let dimmed = g.phase == .paused

        // Dotted centre line.
        let dots = NSBezierPath()
        dots.move(to: NSPoint(x: 14, y: h / 2))
        dots.line(to: NSPoint(x: w - 14, y: h / 2))
        dots.lineWidth = 1.6
        dots.lineCapStyle = .round
        dots.setLineDash([0.01, 7], count: 2, phase: 0)
        ink.withAlphaComponent(0.16).setStroke()
        dots.stroke()

        // Scores: big, thin, quiet. Yours sits below the line, the bot's above.
        let scoreAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .ultraLight),
            .foregroundColor: ink.withAlphaComponent(0.30),
        ]
        drawCentered("\(g.playerScore)", at: NSPoint(x: w / 2, y: h / 2 + 42), attrs: scoreAttrs)
        drawCentered("\(g.botScore)", at: NSPoint(x: w / 2, y: h / 2 - 42), attrs: scoreAttrs)

        // Paddles. The bot's is a little fainter so yours is easy to find.
        let pw = PongGame.paddleW, ph = PongGame.paddleH
        let alpha: CGFloat = dimmed ? 0.45 : 1
        func paddle(along: Double, across: Double, a: CGFloat) {
            let c = pt(along, across)
            let r = NSRect(x: c.x - ph / 2, y: c.y - pw / 2, width: ph, height: pw)
            ink.withAlphaComponent(a * alpha).setFill()
            NSBezierPath(roundedRect: r, xRadius: pw / 2, yRadius: pw / 2).fill()
        }
        paddle(along: g.playerX, across: g.playerY, a: 0.92)
        paddle(along: g.botX, across: g.botY, a: 0.45)

        // Ball.
        if g.phase != .over {
            let r = PongGame.ballR
            let c = pt(g.ballX, g.ballY)
            let pulse: CGFloat = g.phase == .serving ? 0.55 : 1
            ink.withAlphaComponent(pulse * alpha).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)).fill()
        }

        // One line of hint text at most.
        let hint: String?
        switch g.phase {
        case .idle: hint = "SPACE TO PLAY"
        case .paused: hint = "SPACE TO RESUME"
        case .over: hint = g.playerWon ? "YOU WIN  ·  SPACE" : "BOT WINS  ·  SPACE"
        default: hint = nil
        }
        if let hint {
            let hintAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: ink.withAlphaComponent(0.5),
                .kern: 1.6,
            ]
            drawCentered(hint, at: NSPoint(x: w / 2, y: h / 2 + 90), attrs: hintAttrs)
        }
    }

    private func drawCentered(_ text: String, at p: NSPoint, attrs: [NSAttributedString.Key: Any]) {
        let s = NSAttributedString(string: text, attributes: attrs)
        let size = s.size()
        s.draw(at: NSPoint(x: p.x - size.width / 2, y: p.y - size.height / 2))
    }
}
