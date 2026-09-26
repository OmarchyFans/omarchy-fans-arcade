import QtQuick
import Quickshell
import Quickshell.Io
import "levels.js" as Levels
import "powerups.js" as PowerUps

// Headless rules test for Brick Blitz. Quickshell only imports from inside the
// config folder, so tests/run.sh copies game/ and this file into one temp folder,
// runs it with QT_QPA_PLATFORM=offscreen quickshell -p <that folder>/game_test.qml,
// and reads the JSON it writes to $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }

  // Run the physics for `seconds` in 1/240 s steps, or until `until()` holds.
  function run(g, seconds, until) {
    var steps = Math.ceil(seconds * 240)
    for (var i = 0; i < steps; i++) {
      if (g.phase !== "play" && g.phase !== "serve") return
      g.step(1 / 240)
      if (until && until()) return
    }
  }

  function ball(g) { return g.balls[0] }
  function put(b, x, y, vx, vy) { b.x = x; b.y = y; b.vx = vx; b.vy = vy; b.stuck = false }
  function dead(m) { var n = 0; for (var i = 0; i < m.count; i++) if (!m.get(i).alive) n++; return n }
  function lastAliveIn(m) {
    for (var i = m.count - 1; i >= 0; i--) if (m.get(i).alive) return i   // bottom row: nothing below it
    return -1
  }
  // A fresh level-1 rally with no random capsules.
  function fresh(g) { g.newGame(); g.dropChance = 0; g.launch() }

  FloatingWindow {
    implicitWidth: 800; implicitHeight: 600
    visible: false
    Game { id: g; anchors.fill: parent }
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
    var m = g.brickModel, b, i

    // ---- layouts ------------------------------------------------------------
    var okRows = true
    for (var l = 0; l < Levels.LAYOUTS.length; l++)
      for (var r = 0; r < Levels.LAYOUTS[l].rows.length; r++)
        if (Levels.LAYOUTS[l].rows[r].length !== Levels.COLS || /[^.a-e#*]/.test(Levels.LAYOUTS[l].rows[r])) okRows = false
    check("layouts are 12 columns of known bricks", okRows)
    check("five layouts", Levels.LAYOUTS.length === 5, Levels.LAYOUTS.length)

    // ---- a new game and the serve -------------------------------------------
    g.newGame(); g.dropChance = 0
    check("new game serves", g.phase === "serve", g.phase)
    check("three lives", g.lives === 3, g.lives)
    check("level 1 has 60 bricks", g.bricksLeft === 60 && m.count === 60, g.bricksLeft + "/" + m.count)
    check("one ball, stuck on the paddle", g.balls.length === 1 && ball(g).stuck
          && Math.abs(ball(g).x - g.paddleCenter()) < 0.01 && Math.abs(ball(g).y - (g.paddleY - g.ballR)) < 0.01)
    g.paddleX = 100; g.step(1 / 240)
    check("serve ball follows paddle", Math.abs(ball(g).x - (100 + g.paddleW / 2)) < 0.01, ball(g).x)

    g.launch()
    check("launch starts play", g.phase === "play", g.phase)
    check("launch goes upward", ball(g).vy < 0 && !ball(g).stuck, ball(g).vy)
    check("launch keeps the level speed", Math.abs(Math.hypot(ball(g).vx, ball(g).vy) - g.baseSpeed()) < 0.5)

    g.togglePause()
    var px = ball(g).x
    g.step(1 / 60)
    check("pause freezes the ball", g.phase === "paused" && ball(g).x === px, g.phase)
    g.togglePause()
    check("resume plays", g.phase === "play", g.phase)

    // ---- bricks, walls, paddle -----------------------------------------------
    i = lastAliveIn(m)
    var bk = m.get(i)
    var scoreBefore = g.score, leftBefore = g.bricksLeft
    put(ball(g), bk.bx + g.brickW / 2, bk.by + g.brickH + g.ballR + 2, 0, -300)
    run(g, 0.2, function () { return !m.get(i).alive })
    check("brick breaks", !m.get(i).alive)
    check("brick scores", g.score > scoreBefore, g.score)
    check("bricks left drops by one", g.bricksLeft === leftBefore - 1, g.bricksLeft)
    check("ball bounces down off a brick", ball(g).vy > 0, ball(g).vy)
    check("drop chance 0: no capsule", g.capsules.length === 0, g.capsules.length)

    put(ball(g), g.ballR + 1, 400, -300, 50)
    run(g, 0.05)
    check("left wall bounces", ball(g).vx > 0, ball(g).vx)

    g.paddleX = 300
    put(ball(g), 300 + g.paddleW * 0.9, g.paddleY - g.ballR - 3, 0, 300)
    run(g, 0.05, function () { return ball(g).vy < 0 })
    check("paddle returns the ball", ball(g).vy < 0, ball(g).vy)
    check("paddle edge angles right", ball(g).vx > 0, ball(g).vx)

    g.paddleX = 0
    put(ball(g), 700, g.fieldH - 5, 0, 400)
    run(g, 0.5)
    check("missed ball costs a life", g.lives === 2, g.lives)
    check("missed ball serves again", g.phase === "serve" && g.balls.length === 1 && ball(g).stuck, g.phase)

    // Tough bricks take more than one hit. Fortress's "*" bricks have open space below.
    g.level = 4; g.loadLevel(); g.launch()
    var t = -1
    for (var s = 0; s < m.count && t < 0; s++) if (m.get(s).ch === "*") t = s
    check("fortress has a three-hit brick", t >= 0 && m.get(t).hits === 3, t)
    var crackBefore = g.score
    put(ball(g), m.get(t).bx + g.brickW / 2, m.get(t).by + g.brickH + g.ballR + 2, 0, -300)
    run(g, 0.2, function () { return m.get(t).hits === 2 })
    check("first hit cracks a tough brick", m.get(t).alive && m.get(t).hits === 2, m.get(t).hits)
    check("cracking scores 10", g.score === crackBefore + 10, g.score - crackBefore)

    // Clearing the last brick advances the level and gives a ball back.
    g.level = 1; g.loadLevel(); g.launch()
    for (var k = 1; k < m.count; k++) m.setProperty(k, "alive", false)
    g.bricksLeft = 1
    var livesBefore = g.lives
    bk = m.get(0)
    put(ball(g), bk.bx + g.brickW / 2, bk.by + g.brickH + g.ballR + 2, 0, -300)
    run(g, 0.3, function () { return g.level === 2 })
    check("clearing advances the level", g.level === 2, g.level)
    check("level clear gives a ball", g.lives === Math.min(livesBefore + 1, g.maxLives), g.lives)
    var want = Levels.layout(2).rows.join("").replace(/\./g, "").length
    check("level 2 loads every pyramid brick", m.count === want && g.bricksLeft === want, m.count + " vs " + want)
    check("level 2 is faster", g.baseSpeed() > 340, g.baseSpeed())

    // No tunneling: a max-speed ball straight up into a full brick wall stops at the first row it meets.
    g.level = 1; g.loadLevel(); g.launch()
    var bottom = m.get(48)                  // row 5 (index 4), column 0
    put(ball(g), bottom.bx + g.brickW / 2, bottom.by + g.brickH + g.ballR + 1, 0, -760)
    run(g, 0.05, function () { return ball(g).vy > 0 })
    check("fast ball breaks exactly one brick", dead(m) === 1, dead(m))
    check("fast ball broke the bottom-row brick", !m.get(48).alive && m.get(36).alive)

    // ---- power-ups: drops ----------------------------------------------------
    PowerUps.TYPES.forEach(function (p) { check("power-up " + p.id + " has a label and color", !!p.label && !!p.color && p.weight > 0) })
    check("pick(0) is the first type", PowerUps.pick(0) === PowerUps.TYPES[0].id)
    check("pick(near 1) is the last type", PowerUps.pick(0.99999) === PowerUps.TYPES[PowerUps.TYPES.length - 1].id)

    fresh(g); g.dropChance = 1
    i = lastAliveIn(m); bk = m.get(i)
    put(ball(g), bk.bx + g.brickW / 2, bk.by + g.brickH + g.ballR + 2, 0, -300)
    run(g, 0.2, function () { return !m.get(i).alive })
    check("a broken brick can drop a capsule", g.capsules.length === 1, g.capsules.length)
    check("the capsule starts at the brick", g.capsules.length === 1
          && Math.abs(g.capsules[0].x + g.capsuleW / 2 - (bk.bx + g.brickW / 2)) < 0.01, g.capsules.length ? g.capsules[0].x : "none")
    i = lastAliveIn(m); bk = m.get(i)
    put(ball(g), bk.bx + g.brickW / 2, bk.by + g.brickH + g.ballR + 2, 0, -300)
    run(g, 0.2, function () { return !m.get(i).alive })
    check("only one capsule falls at a time", g.capsules.length === 1, g.capsules.length)

    fresh(g); g.dropChance = 1
    g.balls.push({ x: 50, y: 400, vx: 0, vy: -10, stuck: false, offset: 0, speed: 10 })
    i = lastAliveIn(m); bk = m.get(i)
    put(ball(g), bk.bx + g.brickW / 2, bk.by + g.brickH + g.ballR + 2, 0, -300)
    run(g, 0.2, function () { return !m.get(i).alive })
    check("no capsules during multi-ball", g.capsules.length === 0, g.capsules.length)

    // ---- power-ups: catching capsules ----------------------------------------
    fresh(g)
    g.paddleX = 300
    put(ball(g), 100, 300, 0, -50)          // keep the ball busy elsewhere
    g.spawnCapsule("wide", g.paddleCenter(), g.paddleY - 40)
    scoreBefore = g.score
    run(g, 0.5, function () { return g.capsules.length === 0 })
    check("a caught capsule is used", g.paddleMode === "wide", g.paddleMode)
    check("a caught capsule scores 100", g.score === scoreBefore + 100, g.score - scoreBefore)

    fresh(g)
    g.paddleX = 0
    put(ball(g), 700, 300, 0, -50)
    g.spawnCapsule("laser", 700, g.paddleY - 40)
    run(g, 0.8, function () { return g.capsules.length === 0 })
    check("a missed capsule falls away unused", g.capsules.length === 0 && g.paddleMode === "", g.paddleMode)

    // ---- power-ups: each one --------------------------------------------------
    fresh(g)
    g.paddleX = g.fieldW - g.normalPaddleW
    g.applyPowerUp("wide")
    check("wide widens the paddle", g.paddleW === g.widePaddleW, g.paddleW)
    check("wide stays on the field", g.paddleX >= 0 && g.paddleX + g.paddleW <= g.fieldW + 0.01, g.paddleX + g.paddleW)

    fresh(g)
    g.applyPowerUp("catch")
    g.paddleX = 300
    put(ball(g), 300 + g.paddleW * 0.8, g.paddleY - g.ballR - 3, 0, 300)
    run(g, 0.1, function () { return ball(g).stuck })
    check("catch holds the ball on the paddle", ball(g).stuck && ball(g).vy === 0 && g.phase === "play", ball(g).stuck)
    g.paddleX = 200; g.step(1 / 240)
    check("a caught ball rides the paddle", Math.abs(ball(g).x - (g.paddleCenter() + ball(g).offset)) < 0.01)
    g.action(true)
    check("Space lets a caught ball go, not pause", g.phase === "play" && !ball(g).stuck && ball(g).vy < 0, g.phase)
    check("a caught ball leaves at its offset angle", ball(g).vx > 0, ball(g).vx)
    g.applyPowerUp("wide")
    check("a new mode replaces catch", g.paddleMode === "wide", g.paddleMode)

    // A pause holds a caught ball's release countdown; resuming restarts it.
    fresh(g)
    g.applyPowerUp("catch")
    g.paddleX = 300
    put(ball(g), 300 + g.paddleW / 2, g.paddleY - g.ballR - 3, 0, 300)
    run(g, 0.1, function () { return ball(g).stuck })
    check("catching starts the release countdown", ball(g).stuck && g.catchCountdown)
    g.togglePause()
    check("a pause stops the countdown", g.phase === "paused" && !g.catchCountdown)
    g.togglePause()
    check("resuming restarts the countdown", g.phase === "play" && g.catchCountdown)

    // Losing focus pauses and forgets held keys.
    fresh(g)
    g.leftHeld = true
    g.lostFocus()
    check("losing focus pauses", g.phase === "paused", g.phase)
    check("losing focus forgets held keys", !g.leftHeld && !g.rightHeld)

    fresh(g)
    g.applyPowerUp("laser")
    g.paddleX = 300
    put(ball(g), 60, 300, 0, -40)
    var deadBefore = dead(m)
    check("laser fires two bolts", g.fireLaser() && g.bolts.length === 2, g.bolts.length)
    check("laser needs a moment between shots", !g.fireLaser() && g.bolts.length === 2)
    run(g, 0.6, function () { return g.bolts.length === 0 })
    check("laser bolts break bricks", dead(m) >= deadBefore + 2, dead(m) - deadBefore)
    g.laserReady = true
    g.action(true)
    check("Space fires the laser, not pause", g.phase === "play" && g.bolts.length === 2, g.phase + " " + g.bolts.length)

    g.level = 4; g.loadLevel(); g.launch(); g.dropChance = 0
    g.applyPowerUp("laser")
    g.paddleX = g.sideMargin + 20            // left bolt (paddleX + 6) under column 0: Fortress's bottom "#"
    put(ball(g), 400, 300, 0, -40)
    var col0 = -1
    for (i = 0; i < m.count; i++) if (m.get(i).bx === g.sideMargin && (col0 < 0 || m.get(i).by > m.get(col0).by)) col0 = i
    g.fireLaser()
    run(g, 0.6, function () { return g.bolts.length === 0 })
    check("a bolt cracks a tough brick", m.get(col0).ch === "#" && m.get(col0).alive && m.get(col0).hits === 1, m.get(col0).hits)

    fresh(g)
    put(ball(g), 400, 300, 0, -600)
    g.applyPowerUp("slow")
    check("slow slows the ball", Math.abs(Math.hypot(ball(g).vx, ball(g).vy) - g.baseSpeed() * 0.7) < 0.5, Math.hypot(ball(g).vx, ball(g).vy))

    fresh(g)
    put(ball(g), 400, 300, 0, -300)
    g.applyPowerUp("multi")
    check("multi makes three balls", g.balls.length === 3, g.balls.length)
    check("multi balls spread out", g.balls[1].vx < 0 && g.balls[2].vx > 0, g.balls[1].vx + " " + g.balls[2].vx)
    livesBefore = g.lives
    put(g.balls[2], 700, g.fieldH - 5, 0, 400)
    g.paddleX = 0
    run(g, 0.2, function () { return g.balls.length === 2 })
    check("losing one of several balls costs nothing", g.balls.length === 2 && g.lives === livesBefore, g.lives)

    fresh(g)
    g.applyPowerUp("laser"); g.fireLaser(); g.spawnCapsule("wide", 700, 200)
    g.paddleX = 0
    put(ball(g), 700, g.fieldH - 5, 0, 400)
    run(g, 0.2, function () { return g.phase === "serve" })
    check("losing the last ball ends power-ups", g.paddleMode === "" && g.capsules.length === 0 && g.bolts.length === 0, g.paddleMode)

    fresh(g)
    g.lives = 4; g.applyPowerUp("life")
    check("+1 adds a ball in reserve", g.lives === 5, g.lives)
    g.applyPowerUp("life")
    check("+1 stops at the maximum", g.lives === g.maxLives, g.lives)

    fresh(g)
    var lvl = g.level
    g.applyPowerUp("warp")
    check("warp goes to the next level", g.level === lvl + 1 && g.phase === "serve", g.level)

    // Space with nothing to release and no laser pauses; a click never does.
    fresh(g)
    g.action(false)
    check("a click in play doesn't pause", g.phase === "play", g.phase)
    g.action(true)
    check("Space in play pauses", g.phase === "paused", g.phase)
    g.action(true)

    // ---- drawing follows the physics (a frozen drawing passed every rule above) ----
    fresh(g)
    put(ball(g), 222, 333, 0, -100)
    g.spawnCapsule("slow", 400, 200)
    g.publish()
    var bv = g.ballView.itemAt(0), cv = g.capsuleView.itemAt(0)
    check("the drawn ball is where the ball is", !!bv && Math.abs(bv.x - (222 - g.ballR)) < 0.01, bv ? bv.x : "no item")
    check("the drawn capsule is where the capsule is", !!cv && Math.abs(cv.y - (200 - g.capsuleH / 2)) < 0.01, cv ? cv.y : "no item")
    ball(g).x = 444; g.capsules[0].y = 250
    g.publish()
    check("the drawn ball moves when the ball does", Math.abs(g.ballView.itemAt(0).x - (444 - g.ballR)) < 0.01, g.ballView.itemAt(0).x)
    check("the drawn capsule falls when the capsule does", Math.abs(g.capsuleView.itemAt(0).y - 250) < 0.01, g.capsuleView.itemAt(0).y)

    // ---- game over and high score --------------------------------------------
    fresh(g)
    g.lives = 1
    g.paddleX = 0; put(ball(g), 700, g.fieldH - 5, 0, 400)
    run(g, 0.5)
    check("last ball ends the game", g.phase === "over", g.phase)

    g.newGame()
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)
    g.newGame()
    check("a new game clears the new-high-score flag", !g.beatHigh)
    check("new game resets", g.level === 1 && g.lives === 3 && g.score === 0 && g.phase === "serve" && g.paddleMode === "")
  }
}
