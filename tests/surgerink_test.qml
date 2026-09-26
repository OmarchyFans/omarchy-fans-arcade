import QtQuick
import Quickshell
import Quickshell.Io
import "physics.js" as Physics
import "cpu.js" as Cpu

// Headless rules test for Surge Rink. tests/run.sh copies games/surgerink/ and this
// file into one temp folder, runs it offscreen and reads the JSON it writes to
// $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }

  readonly property real dt: 1 / 240
  // Run the game for `seconds` in fixed 1/240 s steps, or until `until()` holds.
  function run(seconds, until) {
    var steps = Math.ceil(seconds * 240)
    for (var i = 0; i < steps; i++) {
      g.step(dt)
      if (until && until()) return true
    }
    return false
  }
  // Pure puck physics for `seconds`; returns the first goal (0 = none).
  function glide(p, seconds, t) {
    var goal = 0
    for (var i = 0; i < Math.ceil(seconds * 240) && !goal; i++) goal = Physics.stepPuck(p, dt, t).goal
    return goal
  }
  function mk(x, y, vx, vy) { return { x: x, y: y, vx: vx, vy: vy, spin: 0, hot: 0, owner: -1, rot: 0 } }
  function put(x, y, vx, vy) { var p = g.puck(); p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.spin = 0; p.hot = 0; p.owner = -1 }
  function spd(o) { return Math.hypot(o.vx, o.vy) }
  function versus() { g.seed = 1234; g.newGame(); g.startRun("versus") }
  function solo(level) { g.seed = 1234; g.newGame(); g.startRun("cpu", level); }
  // Park both strikers out of the way so only the puck matters.
  function park() {
    g.strikers[0].x = g.table.L + g.table.sr; g.strikers[0].y = g.table.T + g.table.sr
    g.strikers[1].x = g.table.R - g.table.sr; g.strikers[1].y = g.table.B - g.table.sr
  }

  FloatingWindow {
    implicitWidth: 960; implicitHeight: 600
    visible: false
    Game { id: g; anchors.fill: parent; seed: 1234 }
  }

  FileView { id: out; path: Quickshell.env("ARCADE_TEST_OUT") || "/dev/null"; printErrors: false }

  Timer {
    interval: 50; running: true
    onTriggered: {
      try { root.tests() } catch (e) { root.failures.push("exception: " + e + " @" + e.lineNumber) }
      out.setText(JSON.stringify({ passed: root.passed, failed: root.failures }) + "\n")
      Qt.quit()
    }
  }

  function tests() {
    var t = g.table, mid = (t.L + t.R) / 2
    var p, s, goal, before

    // ---- puck physics, fixed dt ------------------------------------------------------
    p = mk(300, t.cy, 400, 0)
    glide(p, 0.5, t)
    check("the puck glides by its velocity", p.x > 300 + 180 && p.x < 300 + 200 && p.vy === 0, p.x)
    check("friction slows the puck without stopping it", spd(p) < 400 && spd(p) > 300, spd(p))

    p = mk(400, t.T + 40, 0, -500)
    glide(p, 0.1, t)
    check("the top rail bounces the puck back into the table", p.vy > 0 && p.y >= t.T + t.r, p.vy + " @" + p.y)
    check("a rail bounce loses a little speed", p.vy < 500 && p.vy > 350, p.vy)

    p = mk(90, t.cy - t.mouth - 50, -500, 0)
    goal = glide(p, 0.3, t)
    check("the end rail beside the mouth bounces, no goal", goal === 0 && p.vx > 0, goal + "/" + p.vx)

    p = mk(120, t.cy, -600, 0)
    goal = glide(p, 0.3, t)
    check("a puck through the left mouth is P2's goal", goal === 2, goal)
    p = mk(840, t.cy + 30, 600, 0)
    check("a puck through the right mouth is P1's goal", glide(p, 0.3, t) === 1)

    p = mk(110, t.cy - t.mouth + 5, -500, 0)
    goal = glide(p, 0.4, t)
    check("the goal post turns a puck away", goal === 0 && p.vx > 0, goal + "/" + p.vx)

    var cold = mk(300, t.cy, 600, 0), hot = mk(300, t.cy, 600, 0)
    hot.hot = 1.6
    glide(cold, 0.8, t); glide(hot, 0.8, t)
    check("a hot (surged) puck keeps its speed far better", spd(hot) > spd(cold) + 100 && spd(hot) > 560, spd(hot) + " vs " + spd(cold))

    p = mk(300, t.cy, 500, 0); p.spin = 1.5
    glide(p, 0.3, t)
    check("SWERVE: a spinning puck curves", p.vy > 60 && Math.abs(p.y - t.cy) > 5, p.vy)

    // ---- striker against puck ----------------------------------------------------------
    s = { x: 300, y: t.cy, vx: 0, vy: 0 }
    p = mk(300 + t.r + t.sr - 2, t.cy, -400, 0)
    check("a still striker is struck", Physics.strike(p, s, t, 1))
    check("a still striker returns the puck with restitution", Math.abs(p.vx - 360) < 1 && p.x >= s.x + t.r + t.sr - 0.01, p.vx)

    s = { x: 300, y: t.cy, vx: 300, vy: 0 }
    p = mk(300 + t.r + t.sr - 1, t.cy, 0, 0)
    Physics.strike(p, s, t, 1)
    var plain = p.vx
    check("a moving striker hands the puck its speed (x1.9)", Math.abs(plain - 570) < 1, plain)
    p = mk(300 + t.r + t.sr - 1, t.cy, 0, 0)
    Physics.strike(p, s, t, 1.9)
    check("a surge multiplier makes the strike faster", p.vx > plain * 1.8, p.vx)

    s = { x: 300, y: t.cy, vx: 0, vy: 600 }
    p = mk(300 + t.r + t.sr - 2, t.cy + 10, 0, 0)
    Physics.strike(p, s, t, 1)
    check("SWERVE: a glancing strike spins the puck", Math.abs(p.spin) > 0.3, p.spin)

    s = { x: 300, y: t.cy, vx: 0, vy: 0 }
    p = mk(300 + t.r + t.sr - 2, t.cy, 300, 0)
    check("a puck already leaving is pushed out, not struck", !Physics.strike(p, s, t, 1) && p.vx === 300, p.vx)

    // ---- the game: serve, goals, match -------------------------------------------------
    g.newGame()
    check("a new game opens on the menu", g.phase === "select" && g.score === 0 && g.goals1 === 0, g.phase)
    versus()
    p = g.puck()
    check("a match starts with a serve at rest in the server's half",
          g.phase === "serve" && spd(p) === 0 && (g.server === 0 ? p.x < mid : p.x > mid), g.phase + " " + p.x)

    g.serveTo(0)
    g.press(0, "right")
    var touched = run(1.5, function () { return g.phase === "play" })
    g.release(0, "right")
    check("the serve becomes play when the server strikes", touched && g.puck().vx > 0, g.phase + " " + g.puck().vx)

    g.serveTo(0)
    g.press(0, "right")
    g.puck().y = t.T + t.r   // out of the way
    run(2.5)
    g.release(0, "right")
    check("a striker can't cross the centre line", g.strikers[0].x <= mid - t.sr + 0.01, g.strikers[0].x)

    versus(); park()
    g.phase = "play"
    put(120, t.cy, -800, 0)
    run(0.5, function () { return g.phase === "goal" })
    check("a goal counts for the scorer and pauses play", g.phase === "goal" && g.goals2 === 1 && g.goals1 === 0, g.phase + " " + g.goals2)
    run(1.5, function () { return g.phase === "serve" })
    p = g.puck()
    check("the side that conceded serves after the goal", g.phase === "serve" && g.server === 0 && p.x < mid && spd(p) === 0,
          g.phase + " " + g.server + " " + p.x)
    check("strikers go home for the serve", Math.abs(g.strikers[1].x - g.homeX(1)) < 0.01 && Math.abs(g.strikers[0].y - t.cy) < 0.01)

    versus(); park()
    g.phase = "play"; g.goals1 = 6; g.goals2 = 5
    put(840, t.cy, 800, 0)
    run(0.5, function () { return g.phase !== "play" })
    check("the 7th goal wins the match", g.phase === "over" && g.winner === 0 && g.goals1 === 7, g.phase + " " + g.goals1)
    check("2P matches never touch the high score", g.score === 0 && g.highScore === 0, g.score)

    // ---- 1P run: score, tiers, losing -------------------------------------------------
    solo(0)
    check("Easy starts the CPU at tier 1", g.tier === 1 && g.mode === "cpu", g.tier)
    park(); g.phase = "play"
    put(840, t.cy, 800, 0)
    run(0.5, function () { return g.phase === "goal" })
    check("a goal vs the CPU scores 10 x tier", g.score === 10, g.score)
    run(1.5, function () { return g.phase === "serve" })
    park(); g.phase = "play"
    put(840, t.cy, 800, 0); g.puck().hot = 1; g.puck().owner = 0
    run(0.5, function () { return g.phase === "goal" })
    check("a hot goal scores double", g.score === 30, g.score)
    run(1.5, function () { return g.phase === "serve" })
    g.goals1 = 6; g.goals2 = 1
    park(); g.phase = "play"
    put(840, t.cy, 800, 0)
    run(0.5, function () { return g.phase !== "play" })
    check("winning a 1P match banks 100 x tier + 20 x margin", g.phase === "won" && g.score === 40 + 100 + 20 * 6, g.phase + " " + g.score)
    g.nextMatch()
    check("the next match is a tier harder, from 0-0", g.tier === 2 && g.matchNo === 2 && g.goals1 === 0 && g.goals2 === 0 && g.phase === "serve",
          g.tier + " " + g.phase)
    g.goals2 = 6; park(); g.phase = "play"
    put(120, t.cy, -800, 0)
    run(0.5, function () { return g.phase !== "play" })
    check("losing a 1P match ends the run", g.phase === "over" && g.winner === 1 && g.score === 260, g.phase + " " + g.score)

    // ---- CPU ------------------------------------------------------------------------
    var k1 = Cpu.params(1), k5 = Cpu.params(5)
    check("higher CPU tiers are faster, quicker and more accurate", k5.speed > k1.speed && k5.react < k1.react && k5.err < k1.err && k5.surge > k1.surge)

    solo(1)
    g.phase = "play"
    put(700, 230, 0, 0)
    var s1 = g.strikers[1], d0 = Math.hypot(s1.x - 700, s1.y - 230)
    var hit = run(1.2, function () { return spd(g.puck()) > 50 })
    check("the CPU goes for a loose puck in its half and hits it", hit && g.puck().vx < 0, d0 + " " + g.puck().vx)

    solo(1)
    g.phase = "play"
    put(250, 450, 0, 0)
    g.strikers[1].x = 560; g.strikers[1].y = 150
    run(1.2)
    check("with the puck away, the CPU falls back to guard its mouth",
          g.strikers[1].x > t.R - 110 && Math.abs(g.strikers[1].y - t.cy) <= t.mouth + 12, g.strikers[1].x + "," + g.strikers[1].y)

    function cpuReplay() {
      g.seed = 99; g.newGame(); g.startRun("cpu", 2)
      g.phase = "play"; put(650, 200, 120, 90)
      run(2)
      return g.strikers[1].x.toFixed(3) + "," + g.strikers[1].y.toFixed(3) + "," + g.puck().x.toFixed(3)
    }
    var r1 = cpuReplay(), r2 = cpuReplay()
    check("the CPU replays exactly with the same seed", r1 === r2, r1 + " vs " + r2)

    versus(); g.serveTo(0)
    run(g.shotClock - 0.5)
    check("the shot clock runs while the puck sits in one half", g.phase === "serve" && g.server === 0 && g.halfT > 6, g.halfT)
    run(0.6)
    check("the shot clock hands the serve over after 7 s", g.phase === "serve" && g.server === 1 && g.puck().x > mid && g.halfT < 0.2,
          g.server + " " + g.puck().x)

    // Whole matches with the CPU: it must finish one against an absent P1 (striker
    // parked in a corner), beat a P1 who just stands in the mouth at least once,
    // and the puck must never leave the table (outside a mouth) on the way.
    var escaped = 0
    function contained() {
      var q = g.puck()
      if (q.y < t.T + t.r - 0.5 || q.y > t.B - t.r + 0.5) escaped++
      if (Math.abs(q.y - t.cy) >= t.mouth && (q.x < t.L + t.r - 0.5 || q.x > t.R - t.r + 0.5)) escaped++
    }
    g.seed = 7; g.newGame(); g.startRun("cpu", 1)
    var done = run(150, function () {
      contained()
      g.strikers[0].x = t.L + t.sr; g.strikers[0].y = t.T + t.sr
      return g.phase === "over"
    })
    check("the CPU plays a whole match to 7", done && g.goals2 === 7 && g.winner === 1, g.goals1 + "-" + g.goals2 + " " + g.phase + " t=" + g.clock.toFixed(0))
    g.seed = 8; g.newGame(); g.startRun("cpu", 1)
    run(90, function () { contained(); return g.goals2 > 0 })
    check("the CPU can score past a P1 standing in the mouth", g.goals2 > 0 && g.goals1 === 0, g.goals1 + "-" + g.goals2 + " t=" + g.clock.toFixed(0))
    check("the puck never leaves the table in long play", escaped === 0, escaped)

    // ---- SURGE --------------------------------------------------------------------------
    versus(); park(); g.phase = "play"
    g.puck().y = t.T + t.r; g.puck().x = mid + 200
    g.strikers[0].x = 200; g.strikers[0].y = t.cy
    g.press(0, "surge")
    run(0.8)
    check("SURGE: holding the key charges to full in 0.7 s", g.strikers[0].charge >= 0.999, g.strikers[0].charge)
    g.press(0, "right")
    var x0 = g.strikers[0].x
    run(0.25)
    var charged = g.strikers[0].x - x0
    g.release(0, "surge"); g.release(0, "right")
    g.step(dt)
    check("SURGE: letting go arms a smash for a moment", g.strikers[0].armed > 0 && g.strikers[0].charge === 0, g.strikers[0].armed)
    run(0.4)
    check("SURGE: an unused smash fades", g.strikers[0].armed === 0 && g.surgeMul(g.strikers[0]) === 1)
    g.strikers[0].x = 200; g.strikers[0].kvx = 0
    g.press(0, "right")
    run(0.25)
    g.release(0, "right")
    check("SURGE: charging slows the striker", charged < (g.strikers[0].x - 200) * 0.85, charged + " vs " + (g.strikers[0].x - 200))

    // The same strike, plain and surged.
    function strikeTest(surged) {
      versus(); g.phase = "play"
      park()
      g.strikers[0].x = 200; g.strikers[0].y = t.cy
      put(260, t.cy, 0, 0)
      if (surged) { g.press(0, "surge"); run(0.8) }
      g.press(0, "right")
      run(0.6, function () { return spd(g.puck()) > 10 })
      g.release(0, "right"); g.release(0, "surge")
      return g.puck().vx
    }
    var plainV = strikeTest(false)
    var surgeV = strikeTest(true)
    p = g.puck()
    check("SURGE: a charged strike smashes the puck much faster", surgeV > plainV * 1.4, surgeV + " vs " + plainV)
    check("SURGE: the smashed puck runs hot in the smasher's color", p.hot > 1.4 && p.owner === 0, p.hot + " " + p.owner)
    check("SURGE: a smash spends the charge and starts a cooldown", g.strikers[0].charge === 0 && g.strikers[0].cool > 0, g.strikers[0].cool)

    // ---- pause, focus, reset ------------------------------------------------------------
    versus(); g.phase = "play"; park()
    put(400, t.cy, 300, 0)
    g.togglePause()
    var px = g.puck().x
    run(0.2)
    check("pause freezes the puck", g.phase === "paused" && g.puck().x === px, g.phase)
    g.togglePause()
    check("resume returns to play", g.phase === "play", g.phase)

    g.strikers[0].x = 200; g.strikers[0].y = t.cy
    g.press(0, "down"); g.press(0, "surge")
    run(0.1)
    g.lostFocus()
    check("losing focus pauses and forgets held keys and charge",
          g.phase === "paused" && !g.strikers[0].held.down && !g.strikers[0].held.surge && g.strikers[0].charge === 0, g.phase)
    g.resume()
    var sy = g.strikers[0].y
    run(0.3)
    check("after focus returns the striker doesn't drift", Math.abs(g.strikers[0].y - sy) < 0.01, g.strikers[0].y - sy)

    solo(2); g.score = 250; g.goals1 = 3; g.beatHigh = true
    g.newGame()
    check("a new game resets score, goals, tier and phase",
          g.score === 0 && g.goals1 === 0 && g.goals2 === 0 && g.tier === 1 && g.phase === "select" && !g.beatHigh)

    // ---- high score: tie rule ----------------------------------------------------------
    g.highScore = 30
    solo(0)
    g.addScore(30)
    check("equalling the high score is not a new high score", !g.beatHigh && g.highScore === 30, g.beatHigh)
    g.addScore(10)
    check("going past it is", g.beatHigh && g.highScore === 40, g.highScore)
    g.highScore = 0

    // ---- controls ------------------------------------------------------------------------
    solo(0)
    check("1P: the arrows and Enter drive P1", g.keyAction(Qt.Key_Up).player === 0 && g.keyAction(Qt.Key_Return).player === 0)
    versus()
    check("2P: the arrows and Enter are P2's", g.keyAction(Qt.Key_Up).player === 1 && g.keyAction(Qt.Key_Return).act === "surge"
          && g.keyAction(Qt.Key_W).player === 0)

    // ---- render rules --------------------------------------------------------------------
    versus(); g.phase = "play"; park()
    put(400, 300, 0, 0)
    g.publish()
    var pv = g.puckView.itemAt(0)
    check("the drawn puck sits where the puck is", pv && Math.abs(pv.x - (400 - t.r)) < 0.01 && Math.abs(pv.y - (300 - t.r)) < 0.01, pv ? pv.x : "none")
    put(520, 310, 0, 0)
    g.publish()
    check("the drawn puck moves when the puck does", Math.abs(g.puckView.itemAt(0).x - (520 - t.r)) < 0.01, g.puckView.itemAt(0).x)
    g.strikers[1].x = 700; g.strikers[1].y = 200
    g.publish()
    var sv = g.strikerView.itemAt(1)
    check("the drawn striker follows its model", sv && Math.abs(sv.x - (700 - t.sr)) < 0.01 && Math.abs(sv.y - (200 - t.sr)) < 0.01, sv ? sv.x : "none")
    g.burst(400, 300, 0, 5)
    g.publish()
    check("sparks are drawn", g.sparkView.count === 5 && Math.abs(g.sparkView.itemAt(0).x - (400 - 2.5)) < 0.01, g.sparkView.count)
  }
}
