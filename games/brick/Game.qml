import QtQuick
import "levels.js" as Levels
import "powerups.js" as PowerUps

// Brick Blitz: the whole game. It plays in a fixed 800×600 field that is scaled
// to fit the window, so physics and layouts never depend on the window size.
//
// Controls: ←/→ or A/D (or the mouse) move the paddle. Space or a click launches
// the ball, lets a caught ball go, or fires the laser; P pauses; Esc quits;
// Enter starts over after a game over.
//
// Broken bricks sometimes drop a power-up capsule (see powerups.js). A ball
// waiting on the paddle is "stuck": that is how a serve works, and how the Catch
// power-up works, so both are released the same way.
FocusScope {
  id: game
  focus: true

  // Colors come from the host (the active Omarchy theme, or a fallback).
  property var theme: ({})
  property int highScore: 0
  property int seed: 1                         // tests set it; the host sets autoSeed
  property bool autoSeed: false                // true: every new game seeds from the clock
  property int rngState: 1
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
  readonly property real normalPaddleW: 112
  readonly property real widePaddleW: 168
  readonly property real paddleW: paddleMode === "wide" ? widePaddleW : normalPaddleW
  readonly property real paddleH: 14
  readonly property real paddleY: fieldH - 42
  readonly property real paddleSpeed: 640      // px/s from the keyboard
  readonly property real maxAngle: 60 * Math.PI / 180
  readonly property int maxLives: 5
  readonly property int maxBalls: 3
  readonly property real capsuleW: 54
  readonly property real capsuleH: 18
  readonly property real capsuleSpeed: 150     // px/s
  readonly property real boltW: 4
  readonly property real boltH: 14
  readonly property real boltSpeed: 720        // px/s
  property real dropChance: 0.18               // per broken brick; the host may change it

  // ---- state --------------------------------------------------------------------
  property string phase: "serve"               // serve | play | paused | over
  property int level: 1
  property int lives: 3
  property int score: 0
  property real paddleX: (fieldW - normalPaddleW) / 2
  property string paddleMode: ""               // "" | wide | catch | laser
  property var balls: []                       // { x, y, vx, vy, stuck, offset, speed }
  property var capsules: []                    // { x, y, type }
  property var bolts: []                       // { x, y }
  property real laserCooldown: 0               // seconds until the laser can fire again
  readonly property bool laserReady: laserCooldown <= 0
  property real catchLeft: 0                   // seconds until a caught ball releases itself
  property bool leftHeld: false
  property bool rightHeld: false
  property real mouseTarget: -1                // paddle x the mouse asked for, -1 = keyboard
  property int bricksLeft: 0
  property string banner: ""                   // short message over the field
  property bool beatHigh: false                // this game went past the old high score

  // mulberry32: the only randomness in the rules. Math.random() is not used.
  function rand() {
    var t = (rngState + 0x6D2B79F5) | 0
    rngState = t
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  function color(key, fallback) { return theme[key] || fallback }
  // Ink for text drawn on an arbitrary fill color (e.g. a capsule's hue pill):
  // dark ink on a light fill, light ink on a dark one, by perceived luminance.
  function inkOn(c) { var q = Qt.color(c); return (0.299*q.r + 0.587*q.g + 0.114*q.b) > 0.55 ? "#13141c" : "#f5f5f5" }
  function baseSpeed() { return Math.min(340 * Math.pow(1.08, level - 1), 620) }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function paddleCenter() { return paddleX + paddleW / 2 }
  function anyStuck() {
    for (var i = 0; i < balls.length; i++) if (balls[i].stuck) return true
    return false
  }
  // The Repeaters redraw when these arrays are replaced; physics mutates them in
  // place, so this runs once per frame (not per physics step).
  function publish() { balls = balls.slice(); capsules = capsules.slice(); bolts = bolts.slice() }
  function flash(text) { banner = text; bannerTimer.restart() }
  // What the Repeaters draw. Reading the arrays inside these functions makes a
  // delegate's bindings depend on them, so each publish() repaints. (Holding the
  // object in a delegate property would not: re-setting a var to the same object
  // signals no change, and the drawing would freeze.) An index can run past the
  // end for one frame when a ball is lost, hence the fallback.
  readonly property var offField: ({ x: -200, y: -200, type: "" })
  function ballAt(i) { return balls[i] || offField }
  function capsuleAt(i) { return capsules[i] || offField }
  function boltAt(i) { return bolts[i] || offField }

  ListModel { id: bricks }                     // { ch, hits, alive, bx, by }
  readonly property alias brickModel: bricks   // for tests/game_test.qml
  readonly property alias ballView: ballView
  readonly property alias capsuleView: capsuleView
  readonly property alias messageBackdrop: messageBackdrop
  readonly property bool catchCountdown: catchLeft > 0

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
    paddleMode = ""
    serve()
  }

  // One ball waiting on the paddle; capsules and bolts are cleared.
  function serve() {
    phase = "serve"
    paddleX = clamp(paddleX, 0, fieldW - paddleW)
    balls = [{ x: paddleCenter(), y: paddleY - ballR, vx: 0, vy: 0, stuck: true, offset: 0, speed: baseSpeed() }]
    capsules = []
    bolts = []
    catchLeft = 0
  }

  // Let every stuck ball go: a serve leaves at a small random angle, a caught
  // ball at the angle of where it sits on the paddle.
  function releaseStuck() {
    var serving = phase === "serve"
    for (var i = 0; i < balls.length; i++) {
      var b = balls[i]
      if (!b.stuck) continue
      var a = serving ? (rand() * 40 - 20) * Math.PI / 180
                      : clamp(b.offset / (paddleW / 2), -1, 1) * maxAngle
      var s = b.speed || baseSpeed()
      b.vx = s * Math.sin(a)
      b.vy = -s * Math.cos(a)
      b.stuck = false
    }
    if (serving) { phase = "play"; banner = "" }
    catchLeft = 0
    publish()
  }

  function launch() { if (phase === "serve") releaseStuck() }

  function newGame() {
    if (autoSeed) seed = (Date.now() % 2147483646) + 1
    rngState = seed | 0
    level = 1; lives = 3; score = 0; beatHigh = false
    paddleX = (fieldW - normalPaddleW) / 2
    flash(Levels.layout(1).name)
    loadLevel()
  }

  // A caught ball's release countdown is a number decremented in step(dt), which
  // only runs while phase === "play", so a pause freezes it for free.
  function pause() {
    if (phase !== "play") return
    phase = "paused"
  }
  function resume() {
    if (phase !== "paused") return
    phase = "play"
  }
  function togglePause() {
    if (phase === "play") pause()
    else if (phase === "paused") resume()
  }

  function addScore(points) {
    score += points
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  // The last ball is gone: power-ups end with it.
  function loseLife() {
    lives--
    paddleMode = ""
    if (lives <= 0) { phase = "over"; banner = ""; balls = []; capsules = []; bolts = []; return }
    flash(lives === 1 ? "Last ball!" : lives + " balls left")
    serve()
  }

  function levelClear() {
    level++
    if (lives < maxLives) lives++
    flash("Level " + level + " · " + Levels.layout(level).name)
    loadLevel()
  }

  // ---- bricks -----------------------------------------------------------------
  // One hit: a tough brick cracks (10 points), anything else breaks and may drop
  // a capsule.
  function damageBrick(i) {
    var b = bricks.get(i)
    if (b.hits > 1) {
      bricks.setProperty(i, "hits", b.hits - 1)
      addScore(10)
      return
    }
    bricks.setProperty(i, "alive", false)
    addScore(Levels.pointsFor(b.ch))
    bricksLeft--
    maybeDrop(b.bx + brickW / 2, b.by + brickH / 2)
  }

  // One brick per ball per step: reflect on the axis of least penetration and
  // push the ball out, so it can never tunnel into or stick inside a brick.
  function hitBricks(ball) {
    for (var i = 0; i < bricks.count; i++) {
      var b = bricks.get(i)
      if (!b.alive) continue
      var cx = clamp(ball.x, b.bx, b.bx + brickW)
      var cy = clamp(ball.y, b.by, b.by + brickH)
      var dx = ball.x - cx, dy = ball.y - cy
      if (dx * dx + dy * dy >= ballR * ballR) continue
      var overX = Math.min(ball.x + ballR - b.bx, b.bx + brickW - (ball.x - ballR))
      var overY = Math.min(ball.y + ballR - b.by, b.by + brickH - (ball.y - ballR))
      if (overX < overY) {
        if (ball.x < b.bx + brickW / 2) { ball.x = b.bx - ballR; ball.vx = -Math.abs(ball.vx) }
        else { ball.x = b.bx + brickW + ballR; ball.vx = Math.abs(ball.vx) }
      } else {
        if (ball.y < b.by + brickH / 2) { ball.y = b.by - ballR; ball.vy = -Math.abs(ball.vy) }
        else { ball.y = b.by + brickH + ballR; ball.vy = Math.abs(ball.vy) }
      }
      damageBrick(i)
      // A little faster with every hit, up to a cap.
      var s = Math.min(Math.hypot(ball.vx, ball.vy) + 3, 760)
      var k = s / Math.max(1, Math.hypot(ball.vx, ball.vy))
      ball.vx *= k; ball.vy *= k
      return true
    }
    return false
  }

  function brickUnder(x, y, w, h) { // first live brick overlapping the rectangle, or -1
    for (var i = 0; i < bricks.count; i++) {
      var b = bricks.get(i)
      if (b.alive && x < b.bx + brickW && x + w > b.bx && y < b.by + brickH && y + h > b.by) return i
    }
    return -1
  }

  // ---- power-ups --------------------------------------------------------------
  function maybeDrop(x, y) {
    if (capsules.length > 0 || balls.length > 1) return   // one at a time, none in multi-ball
    if (rand() >= dropChance) return
    spawnCapsule(PowerUps.pick(rand()), x, y)
  }

  function spawnCapsule(type, x, y) {
    capsules.push({ x: x - capsuleW / 2, y: y - capsuleH / 2, type: type })
  }

  // A paddle mode replaces the previous one; the paddle keeps its center.
  function setMode(mode) {
    var center = paddleCenter()
    if (paddleMode === "catch" && mode !== "catch") releaseStuck()
    paddleMode = mode
    paddleX = clamp(center - paddleW / 2, 0, fieldW - paddleW)
  }

  function applyPowerUp(type) {
    var p = PowerUps.byId(type)
    if (!p) return
    addScore(100)
    switch (type) {
    case "wide": case "catch": setMode(type); break
    case "laser": setMode("laser"); laserCooldown = 0; break
    case "slow":
      var slow = baseSpeed() * 0.7
      for (var i = 0; i < balls.length; i++) {
        var b = balls[i], s = Math.hypot(b.vx, b.vy)
        if (s > 0) { b.vx *= slow / s; b.vy *= slow / s }
        b.speed = slow
      }
      break
    case "multi": split(); break
    case "life": lives = Math.min(lives + 1, maxLives); break
    case "warp": levelClear(); return        // its own banner
    }
    flash(p.banner)
  }

  // The first free ball splits into three: itself and two copies 25° either side.
  function split() {
    if (anyStuck()) releaseStuck()
    var base = null
    for (var i = 0; i < balls.length && !base; i++) if (!balls[i].stuck) base = balls[i]
    if (!base) return
    var s = Math.hypot(base.vx, base.vy)
    var a = Math.atan2(base.vx, -base.vy)
    var spread = [-25, 25]
    for (var k = 0; k < spread.length && balls.length < maxBalls; k++) {
      var na = a + spread[k] * Math.PI / 180
      balls.push({ x: base.x, y: base.y, vx: s * Math.sin(na), vy: -s * Math.cos(na), stuck: false, offset: 0, speed: s })
    }
  }

  function fireLaser() {
    if (paddleMode !== "laser" || !laserReady || phase !== "play") return false
    bolts.push({ x: paddleX + 6, y: paddleY - boltH }, { x: paddleX + paddleW - 6 - boltW, y: paddleY - boltH })
    laserCooldown = 0.28
    return true
  }

  // Space, Enter and a click: launch, let a caught ball go, fire, or pause.
  function action(pauseToo) {
    if (phase === "serve") launch()
    else if (phase === "play") {
      if (anyStuck()) releaseStuck()
      else if (paddleMode === "laser") fireLaser()
      else if (pauseToo) togglePause()
    }
    else if (phase === "paused") togglePause()
  }

  // ---- physics ----------------------------------------------------------------
  function step(dt) {
    // Paddle: the keyboard wins while held, the mouse otherwise.
    if (leftHeld || rightHeld) {
      mouseTarget = -1
      paddleX += (rightHeld - leftHeld) * paddleSpeed * dt
    } else if (mouseTarget >= 0) {
      paddleX = mouseTarget
    }
    paddleX = clamp(paddleX, 0, fieldW - paddleW)
    var cx = paddleCenter()

    // Stuck balls ride on the paddle: a serve, or a caught ball.
    var i
    for (i = 0; i < balls.length; i++) {
      if (!balls[i].stuck) continue
      balls[i].x = clamp(cx + balls[i].offset, ballR, fieldW - ballR)
      balls[i].y = paddleY - ballR
    }
    if (phase !== "play") return

    // Countdowns: numbers decremented here, not Timers, so a pause (which stops
    // step() from running at all) freezes them for free.
    if (laserCooldown > 0) laserCooldown -= dt
    if (catchLeft > 0) {
      catchLeft -= dt
      if (catchLeft <= 0) { catchLeft = 0; if (anyStuck()) releaseStuck() }
    }

    for (i = balls.length - 1; i >= 0; i--) {
      var b = balls[i]
      if (b.stuck) continue
      b.x += b.vx * dt
      b.y += b.vy * dt

      // Walls and ceiling.
      if (b.x - ballR < 0) { b.x = ballR; b.vx = Math.abs(b.vx) }
      if (b.x + ballR > fieldW) { b.x = fieldW - ballR; b.vx = -Math.abs(b.vx) }
      if (b.y - ballR < hudH) { b.y = hudH + ballR; b.vy = Math.abs(b.vy) }

      // Paddle: the further from the center it lands, the sharper the angle.
      if (b.vy > 0 && b.y + ballR >= paddleY && b.y + ballR <= paddleY + paddleH + 8
          && b.x >= paddleX - ballR && b.x <= paddleX + paddleW + ballR) {
        var s = Math.hypot(b.vx, b.vy)
        b.y = paddleY - ballR
        if (paddleMode === "catch") {
          b.stuck = true; b.offset = b.x - cx; b.speed = s; b.vx = 0; b.vy = 0
          catchLeft = 3
          continue
        }
        var rel = clamp((b.x - cx) / (paddleW / 2), -1, 1)
        b.vx = s * Math.sin(rel * maxAngle)
        b.vy = -s * Math.cos(rel * maxAngle)
      }

      if (hitBricks(b) && bricksLeft <= 0) { levelClear(); return }
      if (b.y - ballR > fieldH) balls.splice(i, 1)
    }

    // Capsules fall; the paddle catches them.
    for (i = capsules.length - 1; i >= 0; i--) {
      var c = capsules[i]
      c.y += capsuleSpeed * dt
      if (c.y + capsuleH >= paddleY && c.y <= paddleY + paddleH
          && c.x + capsuleW >= paddleX && c.x <= paddleX + paddleW) {
        capsules.splice(i, 1)
        var before = level
        applyPowerUp(c.type)
        if (level !== before) return          // Warp loaded the next level
        continue
      }
      if (c.y > fieldH) capsules.splice(i, 1)
    }

    // Laser bolts fly up and hit the first brick in their way.
    for (i = bolts.length - 1; i >= 0; i--) {
      var t = bolts[i]
      t.y -= boltSpeed * dt
      if (t.y + boltH < hudH) { bolts.splice(i, 1); continue }
      var hit = brickUnder(t.x, t.y, boltW, boltH)
      if (hit >= 0) {
        bolts.splice(i, 1)
        damageBrick(hit)
        if (bricksLeft <= 0) { levelClear(); return }
      }
    }

    if (balls.length === 0) loseLife()
  }

  FrameAnimation {
    running: game.phase === "play" || game.phase === "serve"
    onTriggered: {
      // Small fixed steps keep a fast ball from skipping through a brick.
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n && (game.phase === "play" || game.phase === "serve"); i++) game.step(dt / n)
      game.publish()
    }
  }

  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  // Pause when the window loses focus mid-rally.
  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }
  // Key releases don't arrive while away: forget held keys, or the paddle would
  // keep drifting after the game resumes.
  function lostFocus() {
    leftHeld = false
    rightHeld = false
    pause()
  }

  Keys.onPressed: function (e) {
    if (e.isAutoRepeat) {
      // Holding Space keeps the laser firing.
      if (e.key === Qt.Key_Space && phase === "play" && paddleMode === "laser") fireLaser()
      e.accepted = true
      return
    }
    switch (e.key) {
    case Qt.Key_Left: case Qt.Key_A: leftHeld = true; break
    case Qt.Key_Right: case Qt.Key_D: rightHeld = true; break
    case Qt.Key_Space: action(true); break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter: if (phase === "over") newGame(); else action(false); break
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
        Text {
          visible: game.paddleMode !== ""
          anchors.verticalCenter: parent.verticalCenter
          text: game.paddleMode === "" ? "" : PowerUps.byId(game.paddleMode).label
          color: {
            var p = PowerUps.byId(game.paddleMode)
            return p ? game.color(p.color, p.fallback) : "transparent"
          }
          font.pixelSize: 14; font.bold: true; font.family: "monospace"
          rightPadding: 8
        }
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

    // Capsules
    Repeater {
      id: capsuleView
      model: game.capsules.length
      delegate: Rectangle {
        id: capsule
        required property int index
        readonly property var p: PowerUps.byId(game.capsuleAt(index).type)
        x: game.capsuleAt(index).x; y: game.capsuleAt(index).y
        width: game.capsuleW; height: game.capsuleH
        radius: height / 2
        color: p ? game.color(p.color, p.fallback) : "transparent"
        border.width: 2
        border.color: game.color("bright_foreground", "#c0caf5")
        Text {
          anchors.centerIn: parent
          text: capsule.p ? capsule.p.label : ""
          color: game.inkOn(capsule.color)
          font.pixelSize: 11; font.bold: true; font.family: "monospace"
        }
      }
    }

    // Laser bolts
    Repeater {
      model: game.bolts.length
      delegate: Rectangle {
        required property int index
        x: game.boltAt(index).x; y: game.boltAt(index).y
        width: game.boltW; height: game.boltH
        radius: 2
        color: game.color("red", "#f7768e")
      }
    }

    // Paddle, colored by its mode; the laser adds a cannon at each end.
    Rectangle {
      id: paddle
      x: game.paddleX; y: game.paddleY
      width: game.paddleW; height: game.paddleH
      radius: game.paddleH / 2
      color: game.paddleMode === "catch" ? game.color("green", "#9ece6a")
           : game.paddleMode === "laser" ? game.color("red", "#f7768e")
           : game.color("accent", "#7aa2f7")
      Behavior on width { NumberAnimation { duration: 120 } }
      Repeater {
        model: game.paddleMode === "laser" ? 2 : 0
        delegate: Rectangle {
          required property int index
          width: 6; height: 8; radius: 1
          y: -6
          x: index === 0 ? 4 : paddle.width - 10
          color: game.color("bright_foreground", "#c0caf5")
        }
      }
    }

    // Balls
    Repeater {
      id: ballView
      model: game.balls.length
      delegate: Rectangle {
        required property int index
        x: game.ballAt(index).x - game.ballR; y: game.ballAt(index).y - game.ballR
        width: game.ballR * 2; height: width; radius: game.ballR
        color: game.color("bright_foreground", "#c0caf5")
      }
    }

    // Messages. Paused and game-over messages get a backdrop so a frozen ball
    // can't sit on top of the text.
    Rectangle {
      id: messageBackdrop
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 32
      radius: 8
      // Also behind the title on the very first serve, but not on a respawn
      // (banner still showing, or the score already moved).
      visible: game.phase === "paused" || game.phase === "over"
             || (game.phase === "serve" && game.banner === "" && game.score === 0)
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
        text: game.phase === "over" ? "Score " + game.score + (game.beatHigh ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "serve" ? "Space or click to launch  ·  ← → or mouse to move  ·  P pause\nCatch the falling capsules for power-ups" : ""
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
        if (game.phase === "over") game.newGame()
        else game.action(false)
      }
    }
  }
}
