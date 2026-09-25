import QtQuick
import "levels.js" as Levels

// Brick Blitz: the whole game. It plays in a fixed 800×600 field that is scaled
// to fit the window, so physics and layouts never depend on the window size.
//
// Controls: ←/→ or A/D (or the mouse) move the paddle, Space or a click launches
// the ball, P pauses, Esc quits, Enter starts over after a game over.
FocusScope {
  id: game
  focus: true

  // Colors come from the host (the active Omarchy theme, or a fallback).
  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real fieldW: 800
  readonly property real fieldH: 600
  readonly property real hudH: 48
  readonly property real brickTop: 84
  readonly property real brickGap: 4
  readonly property real brickH: 22
  readonly property real sideMargin: 16
  readonly property real brickW: (fieldW - 2 * sideMargin - (Levels.COLS - 1) * brickGap) / Levels.COLS
  readonly property real ballR: 7
  readonly property real paddleW: 112
  readonly property real paddleH: 14
  readonly property real paddleY: fieldH - 42
  readonly property real paddleSpeed: 640      // px/s from the keyboard
  readonly property real maxAngle: 60 * Math.PI / 180
  readonly property int maxLives: 5

  // ---- state --------------------------------------------------------------------
  property string phase: "serve"               // serve | play | paused | over
  property int level: 1
  property int lives: 3
  property int score: 0
  property real speed: baseSpeed()
  property real paddleX: (fieldW - paddleW) / 2
  property real ballX: fieldW / 2
  property real ballY: paddleY - ballR
  property real vx: 0
  property real vy: 0
  property bool leftHeld: false
  property bool rightHeld: false
  property real mouseTarget: -1                // paddle x the mouse asked for, -1 = keyboard
  property int bricksLeft: 0
  property string banner: ""                   // short message over the field

  function color(key, fallback) { return theme[key] || fallback }
  function baseSpeed() { return Math.min(340 * Math.pow(1.08, level - 1), 620) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  ListModel { id: bricks }                     // { ch, hits, alive, bx, by }
  readonly property alias brickModel: bricks   // for tests/game_test.qml

  function loadLevel() {
    bricks.clear()
    var rows = Levels.layout(level).rows
    var n = 0
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < Levels.COLS; c++) {
        var ch = rows[r].charAt(c)
        if (ch === "." || ch === "") continue
        bricks.append({
          ch: ch, hits: Levels.hitsFor(ch), alive: true,
          bx: sideMargin + c * (brickW + brickGap),
          by: brickTop + r * (brickH + brickGap)
        })
        n++
      }
    }
    bricksLeft = n
    speed = baseSpeed()
    serve()
  }

  function serve() {
    phase = "serve"
    vx = 0; vy = 0
    ballX = paddleX + paddleW / 2
    ballY = paddleY - ballR
  }

  function launch() {
    if (phase !== "serve") return
    var a = (Math.random() * 40 - 20) * Math.PI / 180
    vx = speed * Math.sin(a)
    vy = -speed * Math.cos(a)
    phase = "play"
    banner = ""
  }

  function newGame() {
    level = 1; lives = 3; score = 0
    paddleX = (fieldW - paddleW) / 2
    banner = Levels.layout(1).name
    bannerTimer.restart()
    loadLevel()
  }

  function togglePause() {
    if (phase === "play") phase = "paused"
    else if (phase === "paused") phase = "play"
  }

  function addScore(points) {
    score += points
    if (score > highScore) { highScore = score; newHighScore(score) }
  }

  function loseLife() {
    lives--
    if (lives <= 0) { phase = "over"; banner = ""; return }
    banner = lives === 1 ? "Last ball!" : lives + " balls left"
    bannerTimer.restart()
    serve()
  }

  function levelClear() {
    level++
    if (lives < maxLives) lives++
    banner = "Level " + level + " · " + Levels.layout(level).name
    bannerTimer.restart()
    loadLevel()
  }

  // One brick hit per step: reflect on the axis of least penetration and push
  // the ball out, so it can never tunnel into or stick inside a brick.
  function hitBricks() {
    for (var i = 0; i < bricks.count; i++) {
      var b = bricks.get(i)
      if (!b.alive) continue
      var cx = clamp(ballX, b.bx, b.bx + brickW)
      var cy = clamp(ballY, b.by, b.by + brickH)
      var dx = ballX - cx, dy = ballY - cy
      if (dx * dx + dy * dy >= ballR * ballR) continue
      var overX = Math.min(ballX + ballR - b.bx, b.bx + brickW - (ballX - ballR))
      var overY = Math.min(ballY + ballR - b.by, b.by + brickH - (ballY - ballR))
      if (overX < overY) {
        if (ballX < b.bx + brickW / 2) { ballX = b.bx - ballR; vx = -Math.abs(vx) }
        else { ballX = b.bx + brickW + ballR; vx = Math.abs(vx) }
      } else {
        if (ballY < b.by + brickH / 2) { ballY = b.by - ballR; vy = -Math.abs(vy) }
        else { ballY = b.by + brickH + ballR; vy = Math.abs(vy) }
      }
      if (b.hits > 1) {
        bricks.setProperty(i, "hits", b.hits - 1)
        addScore(10)
      } else {
        bricks.setProperty(i, "alive", false)
        addScore(Levels.pointsFor(b.ch))
        bricksLeft--
      }
      // A little faster with every hit, up to a cap.
      var s = Math.min(Math.hypot(vx, vy) + 3, 760)
      var k = s / Math.max(1, Math.hypot(vx, vy))
      vx *= k; vy *= k
      return
    }
  }

  function step(dt) {
    // Paddle: the mouse wins while it is moving, the keyboard otherwise.
    if (leftHeld || rightHeld) {
      mouseTarget = -1
      paddleX = clamp(paddleX + (rightHeld - leftHeld) * paddleSpeed * dt, 0, fieldW - paddleW)
    } else if (mouseTarget >= 0) {
      paddleX = clamp(mouseTarget, 0, fieldW - paddleW)
    }
    if (phase === "serve") { ballX = paddleX + paddleW / 2; ballY = paddleY - ballR; return }
    if (phase !== "play") return

    ballX += vx * dt
    ballY += vy * dt

    // Walls and ceiling.
    if (ballX - ballR < 0) { ballX = ballR; vx = Math.abs(vx) }
    if (ballX + ballR > fieldW) { ballX = fieldW - ballR; vx = -Math.abs(vx) }
    if (ballY - ballR < hudH) { ballY = hudH + ballR; vy = Math.abs(vy) }

    // Paddle: the further from the center it lands, the sharper the angle.
    if (vy > 0 && ballY + ballR >= paddleY && ballY + ballR <= paddleY + paddleH + 8
        && ballX >= paddleX - ballR && ballX <= paddleX + paddleW + ballR) {
      var rel = clamp((ballX - (paddleX + paddleW / 2)) / (paddleW / 2), -1, 1)
      var s = Math.hypot(vx, vy)
      vx = s * Math.sin(rel * maxAngle)
      vy = -s * Math.cos(rel * maxAngle)
      ballY = paddleY - ballR
    }

    hitBricks()
    if (bricksLeft <= 0) { levelClear(); return }
    if (ballY - ballR > fieldH) loseLife()
  }

  FrameAnimation {
    running: game.phase === "play" || game.phase === "serve"
    onTriggered: {
      // Small fixed steps keep a fast ball from skipping through a brick.
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n && (game.phase === "play" || game.phase === "serve"); i++) game.step(dt / n)
    }
  }

  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  // Pause when the window loses focus mid-rally.
  Connections {
    target: Qt.application
    function onStateChanged() {
      if (Qt.application.state !== Qt.ApplicationActive && game.phase === "play") game.phase = "paused"
    }
  }

  Keys.onPressed: function (e) {
    if (e.isAutoRepeat) { e.accepted = true; return }
    switch (e.key) {
    case Qt.Key_Left: case Qt.Key_A: leftHeld = true; break
    case Qt.Key_Right: case Qt.Key_D: rightHeld = true; break
    case Qt.Key_Space: if (phase === "serve") launch(); else togglePause(); break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter: if (phase === "over") newGame(); else if (phase === "serve") launch(); break
    case Qt.Key_Escape: quitRequested(); break
    default: return
    }
    e.accepted = true
  }
  Keys.onReleased: function (e) {
    if (e.isAutoRepeat) return
    if (e.key === Qt.Key_Left || e.key === Qt.Key_A) leftHeld = false
    else if (e.key === Qt.Key_Right || e.key === Qt.Key_D) rightHeld = false
  }

  Component.onCompleted: newGame()

  // ---- drawing --------------------------------------------------------------------
  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)

    Rectangle { anchors.fill: parent; color: game.color("dark_background", "#13141c"); radius: 6 }

    // HUD
    Rectangle {
      width: parent.width; height: game.hudH
      color: game.color("lighter_background", "#24283b")
      radius: 6
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.leftMargin: 18
        spacing: 28
        Text { text: "SCORE " + game.score; color: game.color("bright_foreground", "#c0caf5"); font.pixelSize: 20; font.bold: true; font.family: "monospace" }
        Text { text: "HIGH " + game.highScore; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 20; font.family: "monospace" }
      }
      Text {
        anchors.centerIn: parent
        text: "LEVEL " + game.level + " · " + Levels.layout(game.level).name.toUpperCase()
        color: game.color("accent", "#7aa2f7"); font.pixelSize: 16; font.bold: true; font.family: "monospace"
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 18
        spacing: 8
        Repeater {
          model: game.lives
          delegate: Rectangle { width: 14; height: 14; radius: 7; color: game.color("accent", "#7aa2f7") }
        }
      }
    }

    // Bricks
    Repeater {
      model: bricks
      delegate: Rectangle {
        required property string ch
        required property int hits
        required property bool alive
        required property real bx
        required property real by
        visible: alive
        x: bx; y: by
        width: game.brickW; height: game.brickH
        radius: 3
        color: {
          switch (ch) {
          case "a": return game.color("red", "#f7768e")
          case "b": return game.color("orange", "#eb927b")
          case "c": return game.color("yellow", "#e0af68")
          case "d": return game.color("green", "#9ece6a")
          case "e": return game.color("blue", "#7aa2f7")
          case "#": return game.color("magenta", "#ad8ee6")
          default:  return game.color("cyan", "#449dab")
          }
        }
        opacity: hits >= 3 ? 1.0 : (hits === 2 ? 0.85 : (ch === "#" || ch === "*" ? 0.6 : 1.0))
        border.width: hits > 1 ? 2 : 0
        border.color: game.color("bright_foreground", "#c0caf5")
      }
    }

    // Paddle
    Rectangle {
      x: game.paddleX; y: game.paddleY
      width: game.paddleW; height: game.paddleH
      radius: game.paddleH / 2
      color: game.color("accent", "#7aa2f7")
    }

    // Ball
    Rectangle {
      x: game.ballX - game.ballR; y: game.ballY - game.ballR
      width: game.ballR * 2; height: width; radius: game.ballR
      color: game.color("bright_foreground", "#c0caf5")
    }

    // Messages. Paused and game-over messages get a backdrop so a frozen ball
    // can't sit on top of the text.
    Rectangle {
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 32
      radius: 8
      visible: game.phase === "paused" || game.phase === "over"
      color: game.color("dark_background", "#13141c")
      opacity: 0.92
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 70
      spacing: 10
      visible: text1.text !== ""
      Text {
        id: text1
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : game.banner !== "" ? game.banner
            : game.phase === "serve" ? "BRICK BLITZ" : ""
        color: game.color("bright_foreground", "#c0caf5")
        font.pixelSize: 40; font.bold: true; font.family: "monospace"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "Score " + game.score + (game.score > 0 && game.score >= game.highScore ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "serve" ? "Space or click to launch  ·  ← → or mouse to move  ·  P pause" : ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 16; font.family: "monospace"
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.BlankCursor
      onPositionChanged: function (m) { game.mouseTarget = m.x - game.paddleW / 2 }
      onClicked: {
        game.forceActiveFocus()
        if (game.phase === "serve") game.launch()
        else if (game.phase === "paused") game.phase = "play"
        else if (game.phase === "over") game.newGame()
      }
    }
  }
}
