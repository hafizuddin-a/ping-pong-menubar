import Foundation

// Headless balance check: ./tools/simulate.sh
// A scripted "human" tracks the ball with a reaction delay and imperfect aim.

func play(_ difficulty: Difficulty, skill: Double) -> (won: Bool, seconds: Double) {
    let g = PongGame()
    g.difficulty = difficulty
    g.primaryAction()
    var t = 0.0
    var aimNoise = 0.0
    var lastVx = 0.0
    while g.phase != .over && t < 600 {
        // the scripted player re-aims whenever the ball turns toward it
        let toward = g.ballY - g.playerY
        _ = lastVx
        // aim to strike with the paddle edge (an angled shot), plus human wobble
        if g.ballX > 200 { aimNoise = (aimNoise >= 0 ? 1 : -1) * 15 }
        else if Int(t * 60) % 30 == 0 { aimNoise = (Bool.random() ? 1 : -1) * 15 + Double.random(in: -skill...skill) }
        let err = toward + aimNoise
        let input: Double = abs(err) < 4 ? 0 : (err > 0 ? 1 : -1)
        g.step(1.0 / 60.0, input: input)
        lastVx = g.ballX
        t += 1.0 / 60.0
    }
    return (g.playerWon, t)
}

for d in Difficulty.allCases {
    for skill in [2.0, 5.0, 8.0] {
        var wins = 0, total = 0.0
        let n = 400
        for _ in 0..<n {
            let r = play(d, skill: skill)
            if r.won { wins += 1 }
            total += r.seconds
        }
        print(String(format: "%-6@ player-noise ±%2.0f  player wins %3d%%  avg match %.0fs",
                     d.title as NSString, skill, wins * 100 / n, total / Double(n)))
    }
}
