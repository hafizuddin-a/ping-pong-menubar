import Foundation

// Pure game model: no AppKit, so it can be simulated headless (see tools/simulate.sh).
// Coordinates are points, origin top-left, y grows downward.

enum Difficulty: Int, CaseIterable {
    case easy, normal, hard

    var title: String { ["Easy", "Normal", "Hard"][rawValue] }
    /// Bot paddle speed in points per second (the player's is 290).
    var botSpeed: Double { [100, 140, 195][rawValue] }
    /// How often the bot re-reads the ball, in seconds.
    var reaction: Double { [0.26, 0.16, 0.09][rawValue] }
    /// Aiming error, re-rolled after every player hit. Half a paddle is 22.
    var aimError: Double { [44, 33, 27][rawValue] }
}

enum GameEvent { case paddleHit, wallHit, playerScored, botScored, matchOver }

final class PongGame {
    static let width = 300.0
    static let height = 190.0
    static let paddleW = 5.0
    static let paddleH = 44.0
    static let ballR = 4.5
    static let margin = 16.0
    static let wallInset = 8.0
    static let winScore = 7

    static let playerSpeed = 290.0
    static let startSpeed = 185.0
    static let maxSpeed = 430.0

    enum Phase { case idle, serving, playing, paused, over }

    var difficulty: Difficulty = .normal
    var onEvent: ((GameEvent) -> Void)?

    private(set) var phase: Phase = .idle
    private(set) var playerScore = 0
    private(set) var botScore = 0
    private(set) var playerWon = false

    private(set) var playerY = height / 2
    private(set) var botY = height / 2
    private(set) var ballX = width / 2
    private(set) var ballY = height / 2
    private var vx = 0.0, vy = 0.0, speed = startSpeed
    private var playerVel = 0.0
    private var serveTimer = 0.0
    private(set) var serveToward = 1.0           // +1 = toward the bot
    private var botTarget = height / 2
    private var botThink = 0.0
    private var botError = 0.0

    var playerX: Double { Self.margin }
    var botX: Double { Self.width - Self.margin }

    // MARK: - control

    /// Space / Return: start, resume or play again.
    func primaryAction() {
        switch phase {
        case .idle, .over:
            playerScore = 0; botScore = 0
            centerPaddles()
            serve(toward: Bool.random() ? 1 : -1)
        case .paused:
            // Resume where we left off: a ball still waiting to be served must be launched, not just unfrozen.
            phase = resumePhase
        case .serving, .playing:
            break
        }
    }

    private var resumePhase: Phase = .playing

    func pause() {
        guard phase == .playing || phase == .serving else { return }
        resumePhase = phase
        phase = .paused
    }

    func resetScore() {
        playerScore = 0; botScore = 0
        phase = .idle
        centerPaddles()
        centerBall()
    }

    /// Every new match starts with both paddles in the middle, not wherever the last one stopped.
    private func centerPaddles() {
        playerY = Self.height / 2; botY = Self.height / 2
        playerVel = 0; botTarget = Self.height / 2
    }

    private func centerBall() {
        ballX = Self.width / 2; ballY = Self.height / 2; vx = 0; vy = 0
    }

    private func serve(toward dir: Double) {
        centerBall()
        speed = Self.startSpeed
        serveToward = dir
        serveTimer = 0.75
        // A serve to the bot is always returned (at every level); the aiming error only applies to rallies.
        let e = dir > 0 ? 5.0 : difficulty.aimError
        botError = Double.random(in: -e...e)
        phase = .serving
    }

    private func launch() {
        let angle = Double.random(in: -0.4...0.4)
        vx = serveToward * speed * cos(angle)
        vy = speed * sin(angle)
        phase = .playing
        botThink = 0                                    // read the serve immediately
    }

    // MARK: - step

    /// `input` is -1 (up), 0, or +1 (down).
    func step(_ rawDt: Double, input: Double) {
        let dt = min(rawDt, 1.0 / 30.0)
        movePlayer(dt, input: input)
        moveBot(dt)

        switch phase {
        case .serving:
            serveTimer -= dt
            if serveTimer <= 0 { launch() }
        case .playing:
            moveBall(dt)
        default:
            break
        }
    }

    private func movePlayer(_ dt: Double, input: Double) {
        // Slight easing so the paddle feels like it has weight.
        playerVel += (input * Self.playerSpeed - playerVel) * min(1, dt * 20)
        playerY = clampPaddle(playerY + playerVel * dt)
    }

    private func clampPaddle(_ y: Double) -> Double {
        // Keep a few points clear of the walls so a paddle never sits in a rounded corner of the glass.
        let lo = Self.paddleH / 2 + Self.wallInset
        return min(max(y, lo), Self.height - lo)
    }

    private func moveBot(_ dt: Double) {
        botThink -= dt
        if botThink <= 0 {
            botThink = difficulty.reaction
            botTarget = (phase == .playing && vx > 0) ? predictY() + botError : Self.height / 2
        }
        let dy = botTarget - botY
        if abs(dy) > 2 {
            let stepDist = min(abs(dy), difficulty.botSpeed * dt)
            botY = clampPaddle(botY + (dy > 0 ? stepDist : -stepDist))
        }
    }

    /// Where the ball will cross the bot's x, folding wall bounces.
    private func predictY() -> Double {
        let r = Self.ballR
        let face = botX - Self.paddleW / 2 - r
        let t = max(0, (face - ballX) / max(vx, 1))
        let span = Self.height - 2 * r
        var m = (ballY + vy * t - r).truncatingRemainder(dividingBy: 2 * span)
        if m < 0 { m += 2 * span }
        if m > span { m = 2 * span - m }
        return m + r
    }

    private func moveBall(_ dt: Double) {
        let r = Self.ballR
        let prevX = ballX
        ballX += vx * dt
        ballY += vy * dt

        if ballY < r { ballY = r; vy = abs(vy); onEvent?(.wallHit) }
        if ballY > Self.height - r { ballY = Self.height - r; vy = -abs(vy); onEvent?(.wallHit) }

        let reach = Self.paddleH / 2 + r * 0.6

        // Player paddle (left).
        let pFace = playerX + Self.paddleW / 2
        if vx < 0, prevX - r >= pFace, ballX - r <= pFace, abs(ballY - playerY) <= reach {
            bounce(off: playerY, dir: 1, paddleVel: playerVel)
            ballX = pFace + r
            botError = Double.random(in: -difficulty.aimError...difficulty.aimError)
            botThink = 0
            onEvent?(.paddleHit)
        }

        // Bot paddle (right).
        let bFace = botX - Self.paddleW / 2
        if vx > 0, prevX + r <= bFace, ballX + r >= bFace, abs(ballY - botY) <= reach {
            bounce(off: botY, dir: -1, paddleVel: 0)
            ballX = bFace - r
            onEvent?(.paddleHit)
        }

        if ballX < -r * 2 { point(forPlayer: false) }
        else if ballX > Self.width + r * 2 { point(forPlayer: true) }
    }

    private func bounce(off paddleY: Double, dir: Double, paddleVel: Double) {
        let offset = max(-1, min(1, (ballY - paddleY) / (Self.paddleH / 2)))
        speed = min(speed * 1.055, Self.maxSpeed)
        let angle = offset * 0.85
        vx = dir * speed * cos(angle)
        vy = speed * sin(angle) + paddleVel * 0.18      // a moving paddle adds a little spin
        let total = hypot(vx, vy)                       // spin must not push the ball past the speed cap
        if total > Self.maxSpeed { vx *= Self.maxSpeed / total; vy *= Self.maxSpeed / total }
    }

    private func point(forPlayer: Bool) {
        if forPlayer { playerScore += 1 } else { botScore += 1 }
        onEvent?(forPlayer ? .playerScored : .botScored)
        if playerScore >= Self.winScore || botScore >= Self.winScore {
            playerWon = playerScore > botScore
            phase = .over
            centerBall()
            onEvent?(.matchOver)
        } else {
            serve(toward: forPlayer ? 1 : -1)           // the side that conceded receives
        }
    }
}
