import QtQuick
import Quickshell
import Quickshell.Io
import "levels.js" as Levels

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

  FloatingWindow {
    implicitWidth: 800; implicitHeight: 600
    visible: false
    Game { id: g; anchors.fill: parent }
  }

  FileView { id: out; path: Quickshell.env("ARCADE_TEST_OUT") || "/dev/null"; printErrors: false }

  Timer {
    interval: 50; running: true
    onTriggered: {
      try { root.tests() } catch (e) { root.failures.push("exception: " + e) }
      out.setText(JSON.stringify({ passed: root.passed, failed: root.failures }) + "\n")
      Qt.quit()
    }
  }

  function tests() {
    var m = g.brickModel

    // Layouts are well formed.
    var okRows = true
    for (var l = 0; l < Levels.LAYOUTS.length; l++)
      for (var r = 0; r < Levels.LAYOUTS[l].rows.length; r++)
        if (Levels.LAYOUTS[l].rows[r].length !== Levels.COLS || /[^.a-e#*]/.test(Levels.LAYOUTS[l].rows[r])) okRows = false
    check("layouts are 12 columns of known bricks", okRows)
    check("five layouts", Levels.LAYOUTS.length === 5, Levels.LAYOUTS.length)

    // A new game.
    g.newGame()
    check("new game serves", g.phase === "serve", g.phase)
    check("three lives", g.lives === 3, g.lives)
    check("level 1 has 60 bricks", g.bricksLeft === 60 && m.count === 60, g.bricksLeft + "/" + m.count)
    check("ball rests on the paddle", Math.abs(g.ballX - (g.paddleX + g.paddleW / 2)) < 0.01 && Math.abs(g.ballY - (g.paddleY - g.ballR)) < 0.01)

    // The ball follows the paddle while serving.
    g.paddleX = 100; g.step(1 / 240)
    check("serve ball follows paddle", Math.abs(g.ballX - (100 + g.paddleW / 2)) < 0.01, g.ballX)

    // Launch goes up.
    g.launch()
    check("launch starts play", g.phase === "play", g.phase)
    check("launch goes upward", g.vy < 0, g.vy)
    check("launch keeps the level speed", Math.abs(Math.hypot(g.vx, g.vy) - g.baseSpeed()) < 0.5)

    // Pause and resume.
    g.togglePause()
    var px = g.ballX
    g.step(1 / 60)
    check("pause freezes the ball", g.phase === "paused" && g.ballX === px, g.phase)
    g.togglePause()
    check("resume plays", g.phase === "play", g.phase)

    // Hitting a one-hit brick from below: it breaks, scores, and the ball turns down.
    var i = firstAliveIn(m)
    var b = m.get(i)
    var scoreBefore = g.score, leftBefore = g.bricksLeft
    g.ballX = b.bx + g.brickW / 2; g.ballY = b.by + g.brickH + g.ballR + 2
    g.vx = 0; g.vy = -300
    run(g, 0.2, function () { return !m.get(i).alive })
    check("brick breaks", !m.get(i).alive)
    check("brick scores", g.score > scoreBefore, g.score)
    check("bricks left drops by one", g.bricksLeft === leftBefore - 1, g.bricksLeft)
    check("ball bounces down off a brick", g.vy > 0, g.vy)

    // Wall bounce.
    g.ballX = g.ballR + 1; g.ballY = 400; g.vx = -300; g.vy = 50
    run(g, 0.05)
    check("left wall bounces", g.vx > 0, g.vx)

    // The paddle: landing right of center sends the ball right and up.
    g.paddleX = 300
    g.ballX = 300 + g.paddleW * 0.9; g.ballY = g.paddleY - g.ballR - 3; g.vx = 0; g.vy = 300
    run(g, 0.05, function () { return g.vy < 0 })
    check("paddle returns the ball", g.vy < 0, g.vy)
    check("paddle edge angles right", g.vx > 0, g.vx)

    // Losing the ball costs a life and serves again.
    g.paddleX = 0
    g.ballX = 700; g.ballY = g.fieldH - 5; g.vx = 0; g.vy = 400
    run(g, 0.5)
    check("missed ball costs a life", g.lives === 2, g.lives)
    check("missed ball serves again", g.phase === "serve", g.phase)

    // Tough bricks take more than one hit. Fortress's "*" bricks have open space below.
    g.level = 4; g.loadLevel()
    g.launch()
    var t = -1
    for (var s = 0; s < m.count && t < 0; s++) if (m.get(s).ch === "*") t = s
    check("fortress has a three-hit brick", t >= 0 && m.get(t).hits === 3, t)
    var crackBefore = g.score
    g.ballX = m.get(t).bx + g.brickW / 2; g.ballY = m.get(t).by + g.brickH + g.ballR + 2; g.vx = 0; g.vy = -300
    run(g, 0.2, function () { return m.get(t).hits === 2 })
    check("first hit cracks a tough brick", m.get(t).alive && m.get(t).hits === 2, m.get(t).hits)
    check("cracking scores 10", g.score === crackBefore + 10, g.score - crackBefore)

    // Clearing the last brick advances the level and gives a ball back.
    g.level = 1; g.loadLevel(); g.launch()
    for (var k = 1; k < m.count; k++) m.setProperty(k, "alive", false)
    g.bricksLeft = 1
    var livesBefore = g.lives
    b = m.get(0)
    g.ballX = b.bx + g.brickW / 2; g.ballY = b.by + g.brickH + g.ballR + 2; g.vx = 0; g.vy = -300
    run(g, 0.3, function () { return g.level === 2 })
    check("clearing advances the level", g.level === 2, g.level)
    check("level clear gives a ball", g.lives === Math.min(livesBefore + 1, g.maxLives), g.lives)
    var want = Levels.layout(2).rows.join("").replace(/\./g, "").length
    check("level 2 loads every pyramid brick", m.count === want && g.bricksLeft === want, m.count + " vs " + want)
    check("level 2 is faster", g.baseSpeed() > 340, g.baseSpeed())

    // No tunneling: a max-speed ball straight up into a full brick wall stops at the first row it meets.
    g.level = 1; g.loadLevel(); g.launch()
    var bottom = m.get(48)                  // row 5 (index 4), column 0
    g.ballX = bottom.bx + g.brickW / 2; g.ballY = bottom.by + g.brickH + g.ballR + 1; g.vx = 0; g.vy = -760
    run(g, 0.05, function () { return g.vy > 0 })
    var broken = 0
    for (var q = 0; q < m.count; q++) if (!m.get(q).alive) broken++
    check("fast ball breaks exactly one brick", broken === 1, broken)
    check("fast ball broke the bottom-row brick", !m.get(48).alive && m.get(36).alive)

    // Game over on the last ball.
    g.lives = 1
    g.paddleX = 0; g.ballX = 700; g.ballY = g.fieldH - 5; g.vx = 0; g.vy = 400
    run(g, 0.5)
    check("last ball ends the game", g.phase === "over", g.phase)

    // High score tracking.
    g.highScore = 0
    g.addScore(120)
    check("score beats the high score", g.highScore === g.score && g.score > 0, g.highScore)

    // Enter after game over starts over.
    g.newGame()
    check("new game resets", g.level === 1 && g.lives === 3 && g.score === 0 && g.phase === "serve")
  }

  function firstAliveIn(m) {
    for (var i = m.count - 1; i >= 0; i--) if (m.get(i).alive) return i   // bottom row: nothing below it
    return -1
  }
}
