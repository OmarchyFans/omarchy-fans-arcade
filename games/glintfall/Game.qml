import QtQuick
import "pieces.js" as Pieces

// Glintfall: the whole game. Pieces fall into a 12×22 well; a full row clears.
// The twist is the glint: some pieces carry one glinting cell. When a glint sits
// in a row that clears, it bursts and also takes the 3×3 block around it, and any
// glint caught in that blast bursts too, so glints left in the stack are charges
// you can set off later. Bursts score extra.
//
// It plays in a fixed 800×600 field scaled to fit the window. Everything that
// counts down (gravity, lock delay, key repeat, the clear flash) is a number
// decremented in step(dt), so the headless test can drive it by hand.
//
// Controls: ←/→ or A/D move, ↑/W/X turn clockwise, Z/Q turn the other way,
// ↓/S soft drop, Space hard drop, C or Shift hold, P pause, Esc quit,
// Enter starts (and starts over after a game over).
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  property int seed: 0                      // 0 = seed from the clock
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real fieldW: 800
  readonly property real fieldH: 600
  readonly property int cols: Pieces.COLS
  readonly property int rows: Pieces.ROWS
  readonly property int hidden: Pieces.HIDDEN
  readonly property int total: Pieces.TOTAL
  readonly property real cellSize: 24
  readonly property real wellX: (fieldW - cols * cellSize) / 2
  readonly property real wellY: 36
  readonly property real softInterval: 0.035   // s per row while ↓ is held
  readonly property real lockDelay: 0.5        // s a resting piece waits before it locks
  readonly property int maxLockResets: 12      // moves/turns that restart the lock delay, per piece
  readonly property real dasDelay: 0.16        // s before a held ←/→ repeats
  readonly property real dasRepeat: 0.05       // s between repeats
  readonly property real clearDelay: 0.32      // s the clearing cells flash
  readonly property int queueShown: 3

  // ---- state --------------------------------------------------------------------
  property string phase: "ready"               // ready | play | paused | over
  property int score: 0
  property int level: 1
  property int lines: 0
  property int bursts: 0                       // glint bursts this game
  property bool beatHigh: false
  property string banner: ""
  property bool clearBanner: false             // true when banner was set by this clear (resolve())
  property real rngState: 1

  // The well, rows 0..total-1 from the top (the first `hidden` rows are above the
  // visible well). Each cell is null or { k: shape id, g: glint }.
  property var board: []
  property var clearMask: []                   // per cell: flashing before it clears
  property var clearing: []                    // cell indexes to empty when the flash ends
  property var clearRows: []                   // full rows to remove when the flash ends
  property real clearTimer: 0
  property var lastClear: ({ rows: 0, bursts: 0, extra: 0, points: 0 })

  // The falling piece; curKind "" means none (between pieces, or game over).
  property string curKind: ""
  property int curRot: 0
  property int curX: 0
  property int curY: 0
  property int curGlint: -1                    // index of the glint cell, -1 = none
  property real fallAcc: 0
  property real lockTimer: 0
  property int lockResets: 0
  property int lowestY: 0                      // deepest row this piece has reached

  property var bag: []
  property var queue: []                       // [{ kind, glint }]
  property string holdKind: ""
  property int holdGlint: -1
  property bool holdUsed: false

  property bool leftHeld: false
  property bool rightHeld: false
  property bool downHeld: false
  property int dasDir: 0
  property real dasTimer: 0

  // What the Repeaters draw; publish() rebuilds it once per frame.
  property var activeCells: []
  property int guideMin: -1
  property int guideMax: -1
  property bool flashOn: true
  property real glow: 0.6

  readonly property var emptyCell: ({ k: "", g: false })
  readonly property var offField: ({ x: -10, y: -10, k: "", g: false })
  readonly property var noPiece: ({ kind: "", glint: -1 })
  readonly property alias boardView: boardView
  readonly property alias activeView: activeView

  function color(key, fallback) { return (theme && theme[key]) || fallback }
  function shapeColor(kind) {
    var s = Pieces.shape(kind)
    return s ? color(s.color, s.fallback) : "transparent"
  }
  function random() { var r = Pieces.rand(rngState); rngState = r.s; return r.v }
  function flash(text) { banner = text; bannerTimer.restart() }
  function gravityInterval() { return Pieces.fallInterval(level) }

  // Accessors for delegates (never hold an element in a delegate property).
  function cellAt(i) { return board[i + hidden * cols] || emptyCell }         // visible index
  function clearingAt(i) { return clearMask[i + hidden * cols] === true }
  function activeAt(i) { return activeCells[i] || offField }
  function queueAt(i) { return queue[i] || noPiece }
  function publish() {
    activeCells = pieceCells()
    var lo = 99, hi = -1
    for (var i = 0; i < activeCells.length; i++) { lo = Math.min(lo, activeCells[i].x); hi = Math.max(hi, activeCells[i].x) }
    guideMin = hi < 0 ? -1 : lo
    guideMax = hi
    flashOn = Math.floor(clearTimer * 18) % 2 === 0
  }
  function publishBoard() { board = board.slice(); clearMask = clearMask.slice() }

  // ---- the well -------------------------------------------------------------------
  function idx(x, y) { return y * cols + x }
  function blocked(x, y) {
    if (x < 0 || x >= cols || y < 0 || y >= total) return true
    return board[idx(x, y)] !== null
  }
  function fits(kind, rot, px, py) {
    var c = Pieces.cells(kind, rot)
    for (var i = 0; i < c.length; i++) if (blocked(px + c[i][0], py + c[i][1])) return false
    return true
  }
  // The falling piece's cells in well coordinates: [{ x, y, k, g }].
  function pieceCells() {
    if (curKind === "") return []
    var c = Pieces.cells(curKind, curRot), out = []
    for (var i = 0; i < c.length; i++) out.push({ x: curX + c[i][0], y: curY + c[i][1], k: curKind, g: i === curGlint })
    return out
  }
  function resting() { return curKind !== "" && !fits(curKind, curRot, curX, curY + 1) }
  function emptyBoard() {
    var b = [], m = []
    for (var i = 0; i < cols * total; i++) { b.push(null); m.push(false) }
    board = b; clearMask = m
  }
  // Put a cell into the well by hand (tests, and nothing else).
  function setCell(x, y, kind, glint) { board[idx(x, y)] = kind === "" ? null : { k: kind, g: !!glint } }
  function rowFull(y) {
    for (var x = 0; x < cols; x++) if (board[idx(x, y)] === null) return false
    return true
  }

  // ---- pieces ------------------------------------------------------------------------
  // Pieces come from a shuffled bag of the whole family, so no shape is starved.
  function refillQueue() {
    var q = queue.slice()
    while (q.length < queueShown + 1) {
      if (bag.length === 0) {
        var b = []
        for (var i = 0; i < Pieces.SHAPES.length; i++) b.push(Pieces.SHAPES[i].id)
        for (var j = b.length - 1; j > 0; j--) {
          var k = Math.floor(random() * (j + 1)), t = b[j]; b[j] = b[k]; b[k] = t
        }
        bag = b
      }
      var kind = bag[0]
      bag = bag.slice(1)
      var glint = random() < Pieces.glintChance(level) ? Math.floor(random() * Pieces.cells(kind, 0).length) : -1
      q.push({ kind: kind, glint: glint })
    }
    queue = q
  }

  // A new piece appears centered in the hidden rows; if it can't, the game is over.
  function spawn(kind, glint) {
    curKind = kind
    curRot = 0
    curGlint = glint
    curX = Math.floor((cols - Pieces.size(kind)) / 2)
    curY = 0
    fallAcc = 0
    lockTimer = 0
    lockResets = 0
    lowestY = curY
    if (!fits(kind, 0, curX, curY)) { gameOver(); return false }
    return true
  }
  function spawnNext() {
    refillQueue()
    var next = queue[0]
    queue = queue.slice(1)
    refillQueue()
    holdUsed = false
    return spawn(next.kind, next.glint)
  }

  // A move or turn while resting starts the lock delay over, a limited number of times.
  function touched() {
    if (lockTimer > 0 && lockResets < maxLockResets) { lockTimer = 0; lockResets++ }
  }
  function canControl() { return phase === "play" && curKind !== "" && clearTimer <= 0 }
  function move(dx, dy) {
    if (!canControl() || !fits(curKind, curRot, curX + dx, curY + dy)) return false
    curX += dx; curY += dy
    touched()
    return true
  }
  // Turn by dir (1 clockwise, -1 the other way), trying the kicks in order.
  function rotate(dir) {
    if (!canControl()) return false
    var nr = ((curRot + dir) % 4 + 4) % 4
    for (var i = 0; i < Pieces.KICKS.length; i++) {
      var dx = Pieces.KICKS[i][0], dy = Pieces.KICKS[i][1]
      if (fits(curKind, nr, curX + dx, curY + dy)) {
        curRot = nr; curX += dx; curY += dy
        touched()
        return true
      }
    }
    return false
  }
  function softDrop() { if (move(0, 1)) { addScore(1); fallAcc = 0; return true } return false }
  // Straight down and locked at once: 2 points a row.
  function hardDrop() {
    if (!canControl()) return false
    var n = 0
    while (fits(curKind, curRot, curX, curY + 1)) { curY++; n++ }
    addScore(2 * n)
    lockPiece()
    return true
  }
  // Put the piece aside, or swap with the one set aside; once per piece.
  function hold() {
    if (!canControl() || holdUsed) return false
    var k = curKind, gl = curGlint
    if (holdKind === "") {
      holdKind = k; holdGlint = gl
      spawnNext()
    } else {
      var hk = holdKind, hg = holdGlint
      holdKind = k; holdGlint = gl
      spawn(hk, hg)
    }
    holdUsed = true
    return true
  }

  // ---- locking and clearing -------------------------------------------------------------
  function lockPiece() {
    // The board Repeater only draws the visible rows, so a cell that locks in a
    // hidden row is invisible on screen even though it can still block later
    // moves. Treat locking any cell in a hidden row as a top-out, not only a
    // piece that locks entirely above the well.
    var c = pieceCells(), hiddenLock = false
    for (var i = 0; i < c.length; i++) {
      board[idx(c[i].x, c[i].y)] = { k: c[i].k, g: c[i].g }
      if (c[i].y < hidden) hiddenLock = true
    }
    curKind = ""
    lockTimer = 0
    if (hiddenLock) { publishBoard(); gameOver(); return }   // locked into a hidden row
    resolve()
    publishBoard()
  }

  // Full rows clear. Every glint in them bursts, taking its 3×3 block; a glint in a
  // blast bursts too. Points are counted now; the cells flash and go after clearDelay.
  function resolve() {
    var full = []
    for (var y = 0; y < total; y++) if (rowFull(y)) full.push(y)
    if (full.length === 0) { spawnNext(); return }

    var remove = {}, fullRow = {}, todo = [], done = {}
    for (var r = 0; r < full.length; r++) {
      fullRow[full[r]] = true
      for (var x = 0; x < cols; x++) {
        var i = idx(x, full[r])
        remove[i] = true
        if (board[i].g) todo.push(i)
      }
    }
    var nb = 0
    while (todo.length > 0) {
      var g = todo.shift()
      if (done[g]) continue
      done[g] = true
      nb++
      var gx = g % cols, gy = Math.floor(g / cols)
      for (var dy = -1; dy <= 1; dy++) for (var dx = -1; dx <= 1; dx++) {
        var nx = gx + dx, ny = gy + dy
        if (nx < 0 || nx >= cols || ny < 0 || ny >= total) continue
        var j = idx(nx, ny)
        if (board[j] === null) continue
        remove[j] = true
        if (board[j].g && !done[j]) todo.push(j)
      }
    }
    var list = [], extra = 0
    for (var key in remove) {
      var n = parseInt(key, 10)
      list.push(n)
      clearMask[n] = true
      if (!fullRow[Math.floor(n / cols)]) extra++
    }
    var points = (Pieces.rowPoints(full.length) + nb * Pieces.BURST_EACH + extra * Pieces.BURST_CELL) * level
    addScore(points)
    bursts += nb
    lastClear = { rows: full.length, bursts: nb, extra: extra, points: points }
    clearing = list
    clearRows = full
    clearTimer = clearDelay
    clearBanner = false
    if (nb > 1) { flash("Glint chain ×" + nb); clearBanner = true }
    else if (nb === 1) { flash("Glint burst"); clearBanner = true }
    else if (full.length >= 3) { flash(full.length + " rows!"); clearBanner = true }
  }

  // The flash is over: empty the burst cells, drop the rows above each full row,
  // count the rows and maybe level up, and bring on the next piece.
  function finishClear() {
    var i
    for (i = 0; i < clearing.length; i++) { board[clearing[i]] = null; clearMask[clearing[i]] = false }
    var gone = {}
    for (i = 0; i < clearRows.length; i++) gone[clearRows[i]] = true
    var nb = [], dst = total - 1
    for (i = 0; i < cols * total; i++) nb.push(null)
    for (var y = total - 1; y >= 0; y--) {
      if (gone[y]) continue
      for (var x = 0; x < cols; x++) nb[idx(x, dst)] = board[idx(x, y)]
      dst--
    }
    board = nb
    lines += clearRows.length
    clearing = []
    clearRows = []
    clearTimer = 0
    var want = 1 + Math.floor(lines / Pieces.LINES_PER_LEVEL)
    if (want > level) {
      level = want
      // A level-up can land on the same clear as a burst/chain/rows banner; combine
      // them instead of one replacing the other.
      if (clearBanner) { banner = banner + "  Level " + level; bannerTimer.restart() }
      else flash("Level " + level)
      clearBanner = false
    }
    spawnNext()
    publishBoard()
  }

  function addScore(points) {
    if (points <= 0) return
    score += points
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  // ---- game flow ---------------------------------------------------------------------------
  function newGame() {
    score = 0; level = 1; lines = 0; bursts = 0; beatHigh = false; banner = ""
    rngState = seed !== 0 ? seed : (Date.now() & 0x7fffffff)
    emptyBoard()
    clearing = []; clearRows = []; clearTimer = 0
    lastClear = { rows: 0, bursts: 0, extra: 0, points: 0 }
    curKind = ""; curGlint = -1
    bag = []; queue = []
    holdKind = ""; holdGlint = -1; holdUsed = false
    leftHeld = false; rightHeld = false; downHeld = false; dasDir = 0; dasTimer = 0
    refillQueue()
    phase = "ready"
    publish()
  }
  function start() {
    if (phase !== "ready") return
    phase = "play"
    spawnNext()
    publish()
  }
  function gameOver() {
    phase = "over"
    curKind = ""
    banner = ""
    leftHeld = false; rightHeld = false; downHeld = false; dasDir = 0
    publish()
  }
  function pause() { if (phase === "play") phase = "paused" }
  function resume() { if (phase === "paused") phase = "play" }
  function togglePause() { if (phase === "play") pause(); else if (phase === "paused") resume() }

  // ---- one fixed step -----------------------------------------------------------------------
  function step(dt) {
    if (phase !== "play") return
    if (clearTimer > 0) {
      clearTimer -= dt
      if (clearTimer <= 0) finishClear()
      return
    }
    if (curKind === "") return

    // Held ←/→ repeat after a delay; with both held, the last one pressed wins.
    var dir = leftHeld && rightHeld ? dasDir : (rightHeld ? 1 : (leftHeld ? -1 : 0))
    if (dir !== 0) {
      dasTimer -= dt
      while (dasTimer <= 0) {
        if (!move(dir, 0)) { dasTimer = 0; break }
        dasTimer += dasRepeat
      }
    }

    // Gravity, faster while ↓ is held (1 point a row).
    var interval = downHeld ? Math.min(gravityInterval(), softInterval) : gravityInterval()
    if (!resting()) {
      fallAcc += dt
      while (fallAcc >= interval) {
        fallAcc -= interval
        if (!fits(curKind, curRot, curX, curY + 1)) { fallAcc = 0; break }
        curY++
        if (downHeld) addScore(1)
      }
    }
    // Lock delay: a resting piece locks once it has rested long enough. Only a
    // new deepest row wipes the delay. Hopping sideways off a ledge into the air
    // and back does not, so once the restarts are spent it can't stall forever.
    if (curY > lowestY) { lowestY = curY; lockTimer = 0 }
    if (resting()) {
      lockTimer += dt
      if (lockTimer >= lockDelay) lockPiece()
    }
  }

  FrameAnimation {
    running: game.phase === "play"
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n && game.phase === "play"; i++) game.step(dt / n)
      game.publish()
    }
  }

  Timer { id: bannerTimer; interval: 1600; onTriggered: game.banner = "" }
  // Purely visual: the glints shimmer.
  SequentialAnimation on glow {
    loops: Animation.Infinite
    NumberAnimation { from: 0.45; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1.0; to: 0.45; duration: 700; easing.type: Easing.InOutSine }
  }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }
  // Key releases don't arrive while away: forget held keys and pause.
  function lostFocus() {
    leftHeld = false; rightHeld = false; downHeld = false; dasDir = 0
    pause()
  }

  function pressLeft() { leftHeld = true; dasDir = -1; dasTimer = dasDelay; move(-1, 0) }
  function pressRight() { rightHeld = true; dasDir = 1; dasTimer = dasDelay; move(1, 0) }

  // Handles one key; returns true when it did something (also used by the test
  // to drive input without a real key event).
  function handleKey(key) {
    switch (key) {
    case Qt.Key_Left: case Qt.Key_A: pressLeft(); break
    case Qt.Key_Right: case Qt.Key_D: pressRight(); break
    case Qt.Key_Down: case Qt.Key_S: downHeld = true; softDrop(); break
    case Qt.Key_Up: case Qt.Key_W: case Qt.Key_X: rotate(1); break
    case Qt.Key_Z: case Qt.Key_Q: rotate(-1); break
    case Qt.Key_C: case Qt.Key_Shift: hold(); break
    case Qt.Key_Space:
      if (phase === "ready") start()
      else if (phase === "play") hardDrop()
      else if (phase === "paused") resume()
      break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter:
      if (phase === "ready") start()
      else if (phase === "over") newGame()
      else if (phase === "paused") resume()
      break
    case Qt.Key_Escape: quitRequested(); break
    default: return false
    }
    return true
  }
  Keys.onPressed: function (e) {
    // Key repeat is ours (dasDelay/dasRepeat in step), not the keyboard's.
    if (e.isAutoRepeat) { e.accepted = true; return }
    if (handleKey(e.key)) e.accepted = true
  }
  // What a click on the field does; same landing spots as Enter/Space.
  function clicked() {
    if (phase === "ready") start()
    else if (phase === "over") newGame()
    else if (phase === "paused") resume()
  }
  Keys.onReleased: function (e) {
    if (e.isAutoRepeat) return
    switch (e.key) {
    case Qt.Key_Left: case Qt.Key_A:
      leftHeld = false
      if (rightHeld) { dasDir = 1; dasTimer = dasDelay }
      break
    case Qt.Key_Right: case Qt.Key_D:
      rightHeld = false
      if (leftHeld) { dasDir = -1; dasTimer = dasDelay }
      break
    case Qt.Key_Down: case Qt.Key_S: downHeld = false; break
    }
  }

  Component.onCompleted: newGame()

  // ---- drawing ------------------------------------------------------------------------------
  // One cell: a rounded tile with a highlight bar and a darker facet; a glint adds
  // a shimmering diamond.
  component Cell: Item {
    id: cellItem
    property string kind: ""
    property bool glint: false
    property bool flashing: false
    property real size: game.cellSize
    width: size; height: size
    visible: kind !== ""
    opacity: flashing ? (game.flashOn ? 1.0 : 0.25) : 1.0
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: cellItem.size * 0.3
      color: cellItem.flashing && game.flashOn ? game.color("bright_foreground", "#c0caf5") : game.shapeColor(cellItem.kind)
      Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.5; height: width
        radius: width * 0.3
        color: game.color("dark_background", "#16161e")
        opacity: 0.18
      }
      Rectangle {
        x: parent.width * 0.16; y: parent.height * 0.12
        width: parent.width * 0.42; height: Math.max(2, parent.height * 0.1)
        radius: height / 2
        color: game.color("bright_foreground", "#c0caf5")
        opacity: 0.45
      }
    }
    Rectangle {
      visible: cellItem.glint
      anchors.centerIn: parent
      width: cellItem.size * 0.36; height: width
      rotation: 45
      color: game.color("bright_foreground", "#c0caf5")
      border.width: 1
      border.color: game.color("dark_background", "#16161e")
      opacity: game.glow
    }
  }

  // A small piece drawing for the hold slot and the queue, centered in its box.
  component Preview: Item {
    id: pv
    property string kind: ""
    property int glint: -1
    property real size: 16
    property bool dim: false
    width: 4 * size; height: 3 * size
    opacity: dim ? 0.4 : 1.0
    readonly property var bb: kind === "" ? ({ minX: 0, maxX: 0, minY: 0, maxY: 0 }) : Pieces.bounds(kind, 0)
    Repeater {
      model: pv.kind === "" ? 0 : Pieces.cells(pv.kind, 0).length
      delegate: Cell {
        required property int index
        size: pv.size
        kind: pv.kind
        glint: index === pv.glint
        x: (pv.width - (pv.bb.maxX - pv.bb.minX + 1) * pv.size) / 2 + (Pieces.cells(pv.kind, 0)[index] || [0, 0])[0] * pv.size - pv.bb.minX * pv.size
        y: (pv.height - (pv.bb.maxY - pv.bb.minY + 1) * pv.size) / 2 + (Pieces.cells(pv.kind, 0)[index] || [0, 0])[1] * pv.size - pv.bb.minY * pv.size
      }
    }
  }

  component Stat: Column {
    property string label: ""
    property string value: ""
    property color tint: game.color("bright_foreground", "#c0caf5")
    spacing: 2
    Text { text: parent.label; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 12; font.family: "monospace"; font.letterSpacing: 2; opacity: 0.8 }
    Text { text: parent.value; color: parent.tint; font.pixelSize: 24; font.bold: true; font.family: "monospace" }
  }

  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)

    Rectangle { anchors.fill: parent; color: game.color("dark_background", "#16161e"); radius: 8 }

    // ---- left panel: title, score, hold ----
    Column {
      x: 36; y: 36
      width: 200
      spacing: 18
      Text {
        text: "GLINTFALL"
        color: game.color("accent", "#7aa2f7")
        font.pixelSize: 30; font.bold: true; font.family: "monospace"; font.letterSpacing: 3
      }
      Stat { label: "SCORE"; value: "" + game.score }
      Stat { label: "HIGH"; value: "" + game.highScore; tint: game.beatHigh ? game.color("accent", "#7aa2f7") : game.color("foreground", "#a9b1d6") }
      Column {
        spacing: 6
        Text { text: "HOLD  (C)"; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 12; font.family: "monospace"; font.letterSpacing: 2; opacity: 0.8 }
        Rectangle {
          width: 120; height: 90; radius: 10
          color: game.color("lighter_background", "#24283b")
          Preview { anchors.centerIn: parent; kind: game.holdKind; glint: game.holdGlint; size: 20; dim: game.holdUsed }
        }
      }
      // Bursts, chains and level-ups are announced here, off the well.
      Text {
        width: 200
        text: game.banner
        color: game.color("bright_foreground", "#c0caf5")
        font.pixelSize: 18; font.bold: true; font.family: "monospace"
        wrapMode: Text.WordWrap
      }
    }
    Text {
      x: 36; y: game.fieldH - 132
      width: 200
      text: "← → / A D  move\n↑ W X  turn   Z  back\n↓ S  soft drop\nSpace  hard drop\nC  hold   P  pause"
      color: game.color("foreground", "#a9b1d6")
      opacity: 0.85
      font.pixelSize: 13; font.family: "monospace"
      lineHeight: 1.2
    }

    // ---- right panel: next, level, rows, bursts ----
    Column {
      x: game.wellX + game.cols * game.cellSize + 36; y: 36
      width: 200
      spacing: 18
      Column {
        spacing: 6
        Text { text: "NEXT"; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 12; font.family: "monospace"; font.letterSpacing: 2; opacity: 0.8 }
        Rectangle {
          width: 120; height: 216; radius: 10
          color: game.color("lighter_background", "#24283b")
          Column {
            anchors.centerIn: parent
            spacing: 8
            Preview { kind: game.queueAt(0).kind; glint: game.queueAt(0).glint; size: 20 }
            Preview { kind: game.queueAt(1).kind; glint: game.queueAt(1).glint; size: 14; anchors.horizontalCenter: parent.horizontalCenter }
            Preview { kind: game.queueAt(2).kind; glint: game.queueAt(2).glint; size: 14; anchors.horizontalCenter: parent.horizontalCenter }
          }
        }
      }
      Stat { label: "LEVEL"; value: "" + game.level; tint: game.color("accent", "#7aa2f7") }
      Stat { label: "ROWS"; value: "" + game.lines }
      Stat { label: "BURSTS"; value: "" + game.bursts; tint: game.color("yellow", "#e0af68") }
    }

    // ---- the well ----
    Rectangle {
      x: game.wellX - 6; y: game.wellY - 6
      width: game.cols * game.cellSize + 12; height: game.rows * game.cellSize + 12
      radius: 12
      color: game.color("background", "#1a1b26")
      border.width: 2
      border.color: game.color("lighter_background", "#24283b")
    }
    Item {
      id: well
      x: game.wellX; y: game.wellY
      width: game.cols * game.cellSize; height: game.rows * game.cellSize

      // Faint dots mark the grid.
      Repeater {
        model: game.cols * game.rows
        delegate: Rectangle {
          required property int index
          x: (index % game.cols) * game.cellSize + game.cellSize / 2 - 1
          y: Math.floor(index / game.cols) * game.cellSize + game.cellSize / 2 - 1
          width: 2; height: 2; radius: 1
          color: game.color("foreground", "#a9b1d6")
          opacity: 0.12
        }
      }
      // A soft column band under the falling piece shows where it will land.
      Rectangle {
        visible: game.guideMax >= 0
        x: game.guideMin * game.cellSize
        width: (game.guideMax - game.guideMin + 1) * game.cellSize
        height: parent.height
        color: game.color("accent", "#7aa2f7")
        opacity: 0.07
      }
      Repeater {
        id: boardView
        model: game.cols * game.rows
        delegate: Cell {
          required property int index
          x: (index % game.cols) * game.cellSize
          y: Math.floor(index / game.cols) * game.cellSize
          kind: game.cellAt(index).k
          glint: game.cellAt(index).g
          flashing: game.clearingAt(index)
        }
      }
      Repeater {
        id: activeView
        model: game.activeCells.length
        delegate: Cell {
          required property int index
          x: game.activeAt(index).x * game.cellSize
          y: (game.activeAt(index).y - game.hidden) * game.cellSize
          kind: game.activeAt(index).y >= game.hidden ? game.activeAt(index).k : ""
          glint: game.activeAt(index).g
        }
      }
    }

    // ---- messages ----
    Rectangle {
      anchors.centerIn: messages
      width: Math.max(messages.width + 40, 240); height: messages.height + 32
      radius: 10
      visible: game.phase !== "play"
      color: game.color("dark_background", "#16161e")
      opacity: 0.92
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.horizontalCenter: well.horizontalCenter
      y: game.wellY + game.rows * game.cellSize * 0.36
      spacing: 10
      visible: game.phase !== "play"
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : "GLINTFALL"
        color: game.color("bright_foreground", "#c0caf5")
        font.pixelSize: 32; font.bold: true; font.family: "monospace"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: text !== ""
        text: game.phase === "over" ? "Score " + game.score + (game.beatHigh ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "ready" ? "Fill a row to clear it.\nGlints ◆ in a cleared row\nburst their neighbours.\n\nSpace or Enter to start" : ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 14; font.family: "monospace"
        lineHeight: 1.15
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: { game.forceActiveFocus(); game.clicked() }
    }
  }
}
