import Foundation
var serves = 0, botMissedServe = 0, matchesOver = 0
var problems: [String] = []
func note(_ s: String) { if problems.count < 15 { problems.append(s) } }

for diff in Difficulty.allCases {
  for seed in 0..<600 {
    let g = PongGame(); g.difficulty = diff
    var tracking = false          // currently watching a serve toward the bot
    var hits = 0
    g.onEvent = { e in
      switch e {
      case .paddleHit: hits += 1
      case .playerScored: if tracking && hits == 0 { botMissedServe += 1; note("bot missed serve diff \(diff) seed \(seed) botY \(g.botY)") }; tracking = false
      case .botScored: tracking = false
      default: break
      }
    }
    var lastPhase = g.phase
    g.primaryAction()
    var input = 0.0
    let dt = [1.0/60, 1.0/30, 1.0/120][seed % 3]
    var t = 0.0
    while t < 300 && g.phase != .over {
      if Int.random(in: 0..<15) == 0 { input = [-1.0, 0, 1][Int.random(in: 0..<3)] }
      // random disruptive actions
      let roll = Int.random(in: 0..<400)
      if roll == 0 { g.pause() }
      else if roll == 1 && g.phase == .paused { g.primaryAction() }
      else if roll == 2 { g.resetScore(); if g.phase != .idle || g.playerScore != 0 || g.botScore != 0 { note("reset state wrong") }; g.primaryAction() ; tracking = false}
      g.step(dt, input: input); t += dt
      if g.phase == .serving && lastPhase != .serving { tracking = g.serveToward > 0; hits = 0; serves += tracking ? 1 : 0 }
      lastPhase = g.phase
      if g.playerScore > 7 || g.botScore > 7 { note("score overflow \(g.playerScore)-\(g.botScore)") }
      if !(g.ballX.isFinite && g.ballY.isFinite && g.playerY.isFinite && g.botY.isFinite) { note("NaN") }
      if g.playerY < 30 - 1e-6 || g.playerY > PongGame.height - 30 + 1e-6 { note("player paddle out of range \(g.playerY)") }
      if g.botY < 30 - 1e-6 || g.botY > PongGame.height - 30 + 1e-6 { note("bot paddle out of range \(g.botY)") }
    }
    if g.phase == .over { matchesOver += 1
      if !(g.playerScore == 7 || g.botScore == 7) || (g.playerScore == 7 && g.botScore == 7) { note("bad final score \(g.playerScore)-\(g.botScore)") }
      if g.playerWon != (g.playerScore > g.botScore) { note("playerWon wrong") }
    }
  }
}
print("serves to bot \(serves), bot missed first serve \(botMissedServe), matches finished \(matchesOver)")
problems.forEach { print($0) }
