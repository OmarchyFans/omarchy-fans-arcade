import QtQuick
import "board.js" as Board
import "levels.js" as Levels

// Solder Snap: the whole game. An 8×8 circuit board of components in a fixed
// 800×600 field, scaled to fit the window.
//
// Swap two neighbouring components to line up three or more of a kind; they are
// soldered off the board, everything above drops down, and new parts feed in from
// the top. Lines of four build a Bus (clears a row or a column), crossing lines
// build a Surge (clears a diamond around it) and five in a row builds a Core (a
// wild chip: swap it with any part to clear every part of that kind).
//
// Our own twist, Flux and Reroute: cascades and specials charge a flux meter; a
// full meter banks a Reroute charge (at most two). Press R, or right-click, to
// rotate the 2×2 block at the cursor a quarter turn clockwise. It costs no move,
// and a rotation that makes no line turns back and keeps the charge. It can move
// fried parts, which a swap can't.
//
// Controls: arrows/WASD move the cursor, Space picks a part up and an arrow (or
// Space on a neighbour) swaps it; or click two parts, or drag one. R reroutes,
// H shows a hint, P pauses, Esc quits, Enter starts over after a game over.
//
// Everything runs from step(dt): swaps, falls, clears and level changes are
// counted down there, never by Timers, so the headless test can drive it.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real fieldW: 800
  readonly property real fieldH: 600
  readonly property real hudH: 48
  readonly property int n: Board.N
  readonly property real cell: 64
  readonly property real boardX: 24
  readonly property real boardY: 68
  readonly property real swapSpeed: 520      // px/s for swaps, rotations, shuffles
  readonly property real fallAccel: 3200     // px/s² for falling parts
  readonly property real fallMax: 1400
  readonly property real clearTime: 0.22     // s a cleared part takes to fade
  readonly property real hintDelay: 5        // s idle before the hint shows
  readonly property real levelPause: 1.8     // s between a won level and the next
  readonly property int fluxPerCharge: 100
  readonly property int maxCharges: 2

  // ---- state --------------------------------------------------------------------
  property string phase: "ready"             // ready | play | paused | over
  // What the board is doing inside "play": idle (waiting for the player) | swap |
  // unswap | rotate | unrotate | clear | fall | shuffle | levelup
  property string busy: "idle"
  property int seed: 1
  property int rngState: 1
  property int level: 1
  property var levelInfo: Levels.level(1)
  property int score: 0
  property int levelScore: 0
  property int moves: 0
  property int cascade: 0                    // 1 for the player's own match, 2+ for chain reactions
  property int maxCascade: 0
  property var cascadeLog: []                // this move: [{ cascade, cleared, points }]
  property int lastBonus: 0                  // moves-left bonus of the last won level
  property int fluxMeter: 0
  property int charges: 1
  property int shuffles: 0
  property int friedLeft: 0
  property var goalCounts: []
  property bool beatHigh: false
  property string banner: ""
  property string comboText: ""
  property real comboT: 0
  property real idleTime: 0
  property var hint: []
  property int cursor: 0
  property int selected: -1
  property bool dragging: false
  property int dragFrom: -1
  property real levelT: 0
  property real clearT: 0

  // The board, as plain arrays mutated in place (publish() copies them into the
  // cells model once per frame).
  property var kinds: []
  property var specials: []
  property var offX: []                      // drawing offset from the cell, px
  property var offY: []
  property var velY: []
  property var popT: []                      // fade-out time left for a cleared part
  property var pending: []                   // cells being cleared
  property int swapA: -1
  property int swapB: -1
  property var rotCells: []

  function color(key, fallback) { return theme[key] || fallback }
  function kindColor(k) {
    if (k >= 0 && k < Levels.KINDS.length) return color(Levels.KINDS[k].color, Levels.KINDS[k].fallback)
    if (k === Board.CORE) return color("accent", "#7aa2f7")
    return color("foreground", "#a9b1d6")
  }
  function rand() { var r = Board.mulberry(rngState); rngState = r.state; return r.value }
  function randInt(m) { return Math.floor(rand() * m) }
  function board() { return { k: kinds, s: specials } }
  function rowOf(i) { return Board.rowOf(i) }
  function colOf(i) { return Board.colOf(i) }
  function flash(text) { banner = text; bannerTimer.restart() }

  ListModel { id: cells }                    // one entry per cell: { k, s, ox, oy, pop }
  readonly property alias cellModel: cells
  readonly property alias tileView: tileView

  function resetAnim() {
    var z = []
    for (var i = 0; i < n * n; i++) z.push(0)
    offX = z.slice(); offY = z.slice(); velY = z.slice(); popT = z.slice()
    pending = []
  }

  // Copy the board into the model; only cells that changed are touched.
  function publish() {
    for (var i = 0; i < n * n; i++) {
      var m = cells.get(i)
      if (m.k !== kinds[i]) cells.setProperty(i, "k", kinds[i])
      if (m.s !== specials[i]) cells.setProperty(i, "s", specials[i])
      if (m.ox !== offX[i]) cells.setProperty(i, "ox", offX[i])
      if (m.oy !== offY[i]) cells.setProperty(i, "oy", offY[i])
      if (m.pop !== popT[i]) cells.setProperty(i, "pop", popT[i])
    }
  }

  // ---- boards -------------------------------------------------------------------
  function makesLine(k, i, kind) {
    var r = rowOf(i), c = colOf(i)
    if (c >= 2 && k[i - 1] === kind && k[i - 2] === kind) return true
    if (r >= 2 && k[i - n] === kind && k[i - 2 * n] === kind) return true
    return false
  }

  // A fresh board: no line already made, at least one move, fried parts in the
  // lower half.
  function generateBoard() {
    for (var attempt = 0; attempt < 60; attempt++) {
      var k = [], s = [], i
      for (i = 0; i < n * n; i++) {
        var kind
        do { kind = randInt(levelInfo.kinds) } while (makesLine(k, i, kind))
        k.push(kind); s.push("")
      }
      var placed = 0
      while (placed < levelInfo.fried) {
        var at = Board.idx(3 + randInt(n - 3), randInt(n))
        if (k[at] === Board.FRIED) continue
        k[at] = Board.FRIED
        placed++
      }
      if (Board.findMove({ k: k, s: s })) break
    }
    kinds = k; specials = s
  }

  function countFried() {
    var f = 0
    for (var i = 0; i < n * n; i++) if (kinds[i] === Board.FRIED) f++
    return f
  }

  // Tests and debugging: rows of 8 characters, "0".."5" a component, "C" a Core,
  // "F" a fried part, "." empty; optional rows of specials ("h", "v", "x", ".").
  function setBoard(rows, specialRows) {
    var k = [], s = []
    for (var r = 0; r < n; r++)
      for (var c = 0; c < n; c++) {
        var ch = rows[r].charAt(c)
        k.push(ch === "C" ? Board.CORE : ch === "F" ? Board.FRIED : ch === "." ? Board.EMPTY : parseInt(ch, 10))
        var sp = specialRows ? specialRows[r].charAt(c) : "."
        s.push(sp === "." ? "" : sp)
      }
    kinds = k; specials = s
    friedLeft = countFried()
    resetAnim()
    busy = "idle"; hint = []; idleTime = 0; selected = -1
    publish()
  }

  function loadLevel() {
    levelInfo = Levels.level(level)
    moves = levelInfo.moves
    levelScore = 0
    var gc = []
    for (var g = 0; g < levelInfo.goals.length; g++) gc.push(0)
    goalCounts = gc
    generateBoard()
    friedLeft = countFried()
    resetAnim()
    busy = "idle"; hint = []; idleTime = 0; selected = -1; cascade = 0; cascadeLog = []
    publish()
  }

  function newGame() {
    rngState = seed
    level = 1; score = 0; beatHigh = false
    charges = 1; fluxMeter = 0; shuffles = 0; lastBonus = 0
    maxCascade = 0; comboText = ""; comboT = 0
    cursor = Board.idx(3, 3); dragging = false; dragFrom = -1
    banner = ""
    loadLevel()
    phase = "ready"
  }

  // Live play seeds from the clock; tests set `seed` and call newGame().
  function restart() { seed = (Date.now() % 2147483647) | 0; newGame() }

  function start() {
    if (phase !== "ready") return
    phase = "play"
    idleTime = 0
    flash("Level 1 · " + levelInfo.name)
  }

  // ---- scoring and goals -------------------------------------------------------
  function addScore(points) {
    score += points
    levelScore += points
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  function addFlux(points) {
    fluxMeter += points
    while (fluxMeter >= fluxPerCharge) {
      if (charges >= maxCharges) { fluxMeter = fluxPerCharge; break }
      charges++
      fluxMeter -= fluxPerCharge
    }
  }

  function goalsMet() {
    if (levelScore < levelInfo.target || friedLeft > 0) return false
    for (var g = 0; g < levelInfo.goals.length; g++) if (goalCounts[g] < levelInfo.goals[g].n) return false
    return true
  }

  // ---- moves ----------------------------------------------------------------------
  function clearHint() { hint = []; idleTime = 0 }

  // Swap the parts in a and b now; they are drawn sliding from where they were.
  function swapCells(a, b) {
    var k = kinds[a], s = specials[a]
    kinds[a] = kinds[b]; specials[a] = specials[b]
    kinds[b] = k; specials[b] = s
    offX[a] = (colOf(b) - colOf(a)) * cell; offY[a] = (rowOf(b) - rowOf(a)) * cell
    offX[b] = (colOf(a) - colOf(b)) * cell; offY[b] = (rowOf(a) - rowOf(b)) * cell
    velY[a] = 0; velY[b] = 0
  }

  // The player swaps a and b. Returns whether the swap started; a swap that makes
  // no line slides back afterwards and costs nothing.
  function trySwap(a, b) {
    if (phase !== "play" || busy !== "idle") return false
    if (!Board.adjacent(a, b)) return false
    if (kinds[a] < 0 || kinds[b] < 0 || kinds[a] === Board.FRIED || kinds[b] === Board.FRIED) return false
    clearHint()
    selected = -1
    swapCells(a, b)
    swapA = a; swapB = b
    busy = "swap"
    return true
  }

  function afterSwap() {
    var a = swapA, b = swapB, ka = kinds[a], kb = kinds[b]
    var forced = null, done = {}, i
    if (ka === Board.CORE && kb === Board.CORE) {
      // Two Cores: the whole board goes.
      forced = []
      for (i = 0; i < n * n; i++) forced.push(i)
      done[a] = true; done[b] = true
    } else if (ka === Board.CORE || kb === Board.CORE) {
      // A Core takes every part of the kind it was swapped with.
      var core = ka === Board.CORE ? a : b, other = core === a ? b : a, target = kinds[other]
      forced = [core]
      for (i = 0; i < n * n; i++) if (kinds[i] === target) forced.push(i)
      done[core] = true
    } else if (specials[a] && specials[b]) {
      forced = [a, b]                        // two specials go off together
    }
    if (!forced && !Board.hasMatch(kinds)) {
      swapCells(a, b)                        // no line: slide back
      busy = "unswap"
      return
    }
    moves--
    cascade = 1
    cascadeLog = []
    resolve([b, a], forced, done)
  }

  // Reroute: turn the 2×2 block whose top-left cell is `tl` a quarter turn
  // clockwise. Needs a charge; costs no move; turns back if nothing lines up.
  function quad(tl) { return [tl, tl + 1, tl + n + 1, tl + n] }   // clockwise
  function rotateCells(q, clockwise) {
    var k = [], s = [], j
    for (j = 0; j < 4; j++) { k.push(kinds[q[j]]); s.push(specials[q[j]]) }
    for (j = 0; j < 4; j++) {
      var from = clockwise ? (j + 3) % 4 : (j + 1) % 4          // who moves into q[j]
      kinds[q[j]] = k[from]; specials[q[j]] = s[from]
      offX[q[j]] = (colOf(q[from]) - colOf(q[j])) * cell
      offY[q[j]] = (rowOf(q[from]) - rowOf(q[j])) * cell
      velY[q[j]] = 0
    }
  }
  function rerouteCorner() {
    return Board.idx(Math.min(rowOf(cursor), n - 2), Math.min(colOf(cursor), n - 2))
  }
  function reroute(tl) {
    if (phase !== "play" || busy !== "idle" || charges <= 0) return false
    if (tl < 0 || rowOf(tl) >= n - 1 || colOf(tl) >= n - 1) return false
    var q = quad(tl)
    for (var j = 0; j < 4; j++) if (kinds[q[j]] < 0) return false
    clearHint()
    selected = -1
    rotateCells(q, true)
    rotCells = q
    busy = "rotate"
    return true
  }
  function afterRotate() {
    if (!Board.hasMatch(kinds)) { rotateCells(rotCells, false); busy = "unrotate"; return }
    charges--
    cascade = 1
    cascadeLog = []
    resolve(rotCells, null, null)
  }

  // Find every line on the board, build specials, set off blasts, score, and start
  // the clear. `pref`: cells a new special should sit on; `forced`: cells to clear
  // anyway (a Core or special swap); `done`: cells that must not go off. Returns
  // false when there was nothing to clear.
  function resolve(pref, forced, done) {
    var groups = Board.groupRuns(Board.findRuns(kinds))
    if (groups.length === 0 && !forced) return false
    var start = [], seen = {}, made = [], g, j
    function add(i) { if (!seen[i]) { seen[i] = true; start.push(i) } }
    for (g = 0; g < groups.length; g++) {
      for (j = 0; j < groups[g].cells.length; j++) add(groups[g].cells[j])
      var sp = Board.specialFor(groups[g], pref || [])
      if (sp) made.push(sp)
    }
    // A line repairs every fried part it touches, corners included.
    for (g = 0; g < groups.length; g++)
      for (j = 0; j < groups[g].cells.length; j++) {
        var nb = Board.touching(groups[g].cells[j])
        for (var q = 0; q < nb.length; q++) if (kinds[nb[q]] === Board.FRIED) add(nb[q])
      }
    if (forced) for (j = 0; j < forced.length; j++) add(forced[j])

    var hit = Board.blast(board(), start, done || {})
    var keep = {}
    for (j = 0; j < made.length; j++) keep[made[j].at] = true
    var cleared = [], gc = goalCounts.slice()
    for (j = 0; j < hit.length; j++) {
      var i = hit[j]
      if (keep[i]) continue
      cleared.push(i)
      if (kinds[i] === Board.FRIED) friedLeft--
      for (var t = 0; t < levelInfo.goals.length; t++) if (levelInfo.goals[t].kind === kinds[i]) gc[t]++
    }
    goalCounts = gc

    var points = cleared.length * Levels.POINTS_PER_TILE * cascade
    for (j = 0; j < made.length; j++) points += Levels.SPECIAL_BONUS[made[j].type]
    addScore(points)
    var log = cascadeLog.slice()
    log.push({ cascade: cascade, cleared: cleared.length, points: points })
    cascadeLog = log
    if (cascade > maxCascade) maxCascade = cascade
    if (cascade >= 2) { addFlux(25); comboText = "CASCADE ×" + cascade; comboT = 1.2 }
    addFlux(20 * made.length)

    for (j = 0; j < made.length; j++) {
      var m = made[j]
      kinds[m.at] = m.type === "core" ? Board.CORE : m.kind
      specials[m.at] = m.type === "core" ? "" : m.type
    }
    for (j = 0; j < cleared.length; j++) popT[cleared[j]] = clearTime
    pending = cleared
    clearT = clearTime
    busy = "clear"
    return true
  }

  function finishClear() {
    for (var j = 0; j < pending.length; j++) {
      kinds[pending[j]] = Board.EMPTY
      specials[pending[j]] = ""
      popT[pending[j]] = 0
    }
    pending = []
    gravity()
    busy = "fall"
  }

  // Parts drop straight down into holes; new parts (seeded) feed in from above.
  // Each moved part is drawn from where it was and falls into place.
  function gravity() {
    for (var c = 0; c < n; c++) {
      var w = n - 1
      for (var r = n - 1; r >= 0; r--) {
        var i = Board.idx(r, c)
        if (kinds[i] === Board.EMPTY) continue
        if (r !== w) {
          var to = Board.idx(w, c)
          kinds[to] = kinds[i]; specials[to] = specials[i]
          offY[to] = (r - w) * cell; velY[to] = 0; offX[to] = 0
          kinds[i] = Board.EMPTY; specials[i] = ""
        }
        w--
      }
      var holes = w + 1
      for (var rr = w; rr >= 0; rr--) {
        var ni = Board.idx(rr, c)
        kinds[ni] = randInt(levelInfo.kinds)
        specials[ni] = ""
        offY[ni] = -holes * cell; velY[ni] = 0; offX[ni] = 0
      }
    }
  }

  // Test hook: empty these cells and let gravity fill them.
  function dropCells(list) {
    for (var j = 0; j < list.length; j++) { kinds[list[j]] = Board.EMPTY; specials[list[j]] = "" }
    gravity()
  }

  // The board has settled after the player's move: won, out of moves, stuck, or
  // the player's turn again.
  function endTurn() {
    cascade = 0
    if (goalsMet()) { levelClear(); return }
    if (moves <= 0) { gameOver(); return }
    if (!Board.findMove(board())) { shuffleBoard(); return }
    busy = "idle"
    idleTime = 0
  }

  function gameOver() {
    phase = "over"
    busy = "idle"
    banner = ""
    selected = -1
    hint = []
  }

  function levelClear() {
    lastBonus = moves * Levels.MOVE_BONUS
    addScore(lastBonus)
    busy = "levelup"
    levelT = levelPause
    flash("Board " + level + " done · +" + lastBonus)
  }

  function nextLevel() {
    level++
    loadLevel()
    flash("Level " + level + " · " + levelInfo.name)
  }

  // No move left: shuffle the movable parts (fried parts stay put) until there is
  // a move and no ready-made line. Every part slides to its new place.
  function shuffleBoard() {
    var slots = [], j, i
    for (i = 0; i < n * n; i++) if (kinds[i] >= 0 && kinds[i] !== Board.FRIED) slots.push(i)
    var k0 = kinds.slice(), s0 = specials.slice(), found = null
    for (var attempt = 0; attempt < 200 && !found; attempt++) {
      var perm = slots.slice()
      for (j = perm.length - 1; j > 0; j--) { var r = randInt(j + 1); var tmp = perm[j]; perm[j] = perm[r]; perm[r] = tmp }
      var k = k0.slice(), s = s0.slice()
      for (j = 0; j < slots.length; j++) { k[slots[j]] = k0[perm[j]]; s[slots[j]] = s0[perm[j]] }
      if (!Board.hasMatch(k) && Board.findMove({ k: k, s: s })) found = perm
    }
    if (!found) {
      // Hopeless mix (almost never): fresh parts for every movable cell. Fried
      // parts stay exactly where they are and no new ones appear, so the repair
      // count still matches the board.
      var fk, fs
      for (attempt = 0; attempt < 100; attempt++) {
        fk = kinds.slice(); fs = specials.slice()
        for (j = 0; j < slots.length; j++) { fk[slots[j]] = Board.EMPTY; fs[slots[j]] = "" }
        for (j = 0; j < slots.length; j++) {
          var kind
          do { kind = randInt(levelInfo.kinds) } while (makesLine(fk, slots[j], kind))
          fk[slots[j]] = kind
        }
        if (!Board.hasMatch(fk) && Board.findMove({ k: fk, s: fs })) break
      }
      for (j = 0; j < slots.length; j++) {
        kinds[slots[j]] = fk[slots[j]]; specials[slots[j]] = fs[slots[j]]
        offX[slots[j]] = 0; offY[slots[j]] = -cell; velY[slots[j]] = 0
      }
      friedLeft = countFried()
    } else {
      for (j = 0; j < slots.length; j++) {
        kinds[slots[j]] = k0[found[j]]; specials[slots[j]] = s0[found[j]]
        offX[slots[j]] = (colOf(found[j]) - colOf(slots[j])) * cell
        offY[slots[j]] = (rowOf(found[j]) - rowOf(slots[j])) * cell
        velY[slots[j]] = 0
      }
    }
    shuffles++
    busy = "shuffle"
    flash("No moves left · reshuffled")
  }

  // ---- the step -------------------------------------------------------------------
  // Slide every offset back toward its cell. Falls accelerate; everything else
  // moves at a steady speed. Returns whether anything is still moving.
  function animate(dt) {
    var moving = false, d = swapSpeed * dt
    for (var i = 0; i < n * n; i++) {
      if (offX[i] !== 0) {
        offX[i] = Math.abs(offX[i]) <= d ? 0 : offX[i] - Math.sign(offX[i]) * d
        moving = true
      }
      if (offY[i] !== 0) {
        if (busy === "fall" && offY[i] < 0) {
          velY[i] = Math.min(velY[i] + fallAccel * dt, fallMax)
          offY[i] += velY[i] * dt
          if (offY[i] >= 0) { offY[i] = 0; velY[i] = 0 }
        } else {
          offY[i] = Math.abs(offY[i]) <= d ? 0 : offY[i] - Math.sign(offY[i]) * d
        }
        moving = true
      }
      if (popT[i] > 0) popT[i] = Math.max(0, popT[i] - dt)
    }
    return moving
  }

  function step(dt) {
    if (phase !== "play") return
    if (comboT > 0) { comboT = Math.max(0, comboT - dt); if (comboT === 0) comboText = "" }
    var moving = animate(dt)
    switch (busy) {
    case "idle":
      idleTime += dt
      if (idleTime >= hintDelay && hint.length === 0) {
        var m = Board.findMove(board())
        if (m) hint = m
      }
      break
    case "swap": if (!moving) afterSwap(); break
    case "rotate": if (!moving) afterRotate(); break
    case "unswap": case "unrotate": case "shuffle": if (!moving) { busy = "idle"; idleTime = 0 } break
    case "clear":
      clearT -= dt
      if (clearT <= 0) finishClear()
      break
    case "fall":
      if (!moving) {
        cascade++
        if (!resolve(null, null, null)) endTurn()
      }
      break
    case "levelup":
      levelT -= dt
      if (levelT <= 0) nextLevel()
      break
    }
  }

  FrameAnimation {
    running: game.phase === "play"
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var steps = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < steps && game.phase === "play"; i++) game.step(dt / steps)
      game.publish()
    }
  }

  // The only Timer: it just fades the banner text.
  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  // ---- input ------------------------------------------------------------------------
  function pause() { if (phase === "play") { phase = "paused"; dragging = false } }
  function resume() { if (phase === "paused") { phase = "play"; idleTime = 0 } }
  function togglePause() { if (phase === "play") pause(); else if (phase === "paused") resume() }

  // Arrows: with a part picked up, swap it that way; otherwise move the cursor
  // (it stops at the edges).
  function moveCursor(dr, dc) {
    if (phase !== "play") return
    clearHint()
    if (selected >= 0) {
      var t = Board.neighbor(selected, dr, dc)
      if (t >= 0 && trySwap(selected, t)) cursor = t
      return
    }
    var nc = Board.neighbor(cursor, dr, dc)
    if (nc >= 0) cursor = nc
  }

  // Space: start; resume; pick up the part under the cursor, put it down again,
  // or swap it with the part picked up next to it.
  function action() {
    if (phase === "ready") { start(); return }
    if (phase === "paused") { resume(); return }
    if (phase !== "play") return
    clickCell(cursor)
  }

  // A click (or Space) on a cell.
  function clickCell(i) {
    if (phase !== "play") return
    clearHint()
    cursor = i
    if (selected === i) { selected = -1; return }
    if (selected >= 0 && Board.adjacent(selected, i)) { trySwap(selected, i); return }
    selected = (kinds[i] >= 0 && kinds[i] !== Board.FRIED) ? i : -1
  }

  function showHint() {
    if (phase !== "play" || busy !== "idle") return
    var m = Board.findMove(board())
    if (m) hint = m
  }

  // Pause when the window loses focus; a drag in progress is forgotten (its
  // release never arrives).
  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }
  function lostFocus() {
    dragging = false
    dragFrom = -1
    pause()
  }

  // Held arrows repeat cursor moves; a repeat never swaps, selects or pauses.
  Keys.onPressed: function (e) {
    var rep = e.isAutoRepeat
    switch (e.key) {
    case Qt.Key_Left: case Qt.Key_A: if (!rep || selected < 0) moveCursor(0, -1); break
    case Qt.Key_Right: case Qt.Key_D: if (!rep || selected < 0) moveCursor(0, 1); break
    case Qt.Key_Up: case Qt.Key_W: if (!rep || selected < 0) moveCursor(-1, 0); break
    case Qt.Key_Down: case Qt.Key_S: if (!rep || selected < 0) moveCursor(1, 0); break
    case Qt.Key_Space: if (!rep) action(); break
    case Qt.Key_R: if (!rep) reroute(rerouteCorner()); break
    case Qt.Key_H: if (!rep) showHint(); break
    case Qt.Key_P: if (!rep) togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter: if (!rep) { if (phase === "over") restart(); else action() } break
    case Qt.Key_Escape: quitRequested(); break
    default: return
    }
    e.accepted = true
  }

  Component.onCompleted: {
    for (var i = 0; i < n * n; i++) cells.append({ k: -1, s: "", ox: 0.0, oy: 0.0, pop: 0.0 })
    restart()
  }

  // ---- drawing ----------------------------------------------------------------------
  // A slow pulse for glows and hints (drawing only; the rules never read it).
  property real glow: 0.6
  SequentialAnimation on glow {
    running: game.phase === "play"
    loops: Animation.Infinite
    NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
  }


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
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 18
        text: "LEVEL " + game.level + " · " + game.levelInfo.name.toUpperCase()
        color: game.color("accent", "#7aa2f7"); font.pixelSize: 16; font.bold: true; font.family: "monospace"
      }
    }

    // The board: a circuit board with vias between the cells.
    Rectangle {
      x: game.boardX - 6; y: game.boardY - 6
      width: game.n * game.cell + 12; height: game.n * game.cell + 12
      radius: 12
      color: game.color("background", "#1a1b26")
      border.width: 2
      border.color: game.color("lighter_background", "#24283b")
    }
    Item {
      id: boardArea
      x: game.boardX; y: game.boardY
      width: game.n * game.cell; height: game.n * game.cell
      clip: true

      Repeater {
        model: 49
        delegate: Rectangle {
          required property int index
          x: (index % 7 + 1) * game.cell - 3; y: (Math.floor(index / 7) + 1) * game.cell - 3
          width: 6; height: 6; radius: 3
          color: game.color("lighter_background", "#24283b")
        }
      }

      // The Reroute block at the cursor, when a charge is banked.
      Rectangle {
        readonly property int tl: game.rerouteCorner()
        visible: game.charges > 0 && game.phase === "play"
        x: game.colOf(tl) * game.cell + 1; y: game.rowOf(tl) * game.cell + 1
        width: 2 * game.cell - 2; height: 2 * game.cell - 2
        radius: 12
        color: "transparent"
        border.width: 2
        border.color: game.color("accent", "#7aa2f7")
        opacity: 0.25 + 0.2 * game.glow
      }

      Repeater {
        id: tileView
        model: cells
        delegate: Item {
          id: tile
          required property int index
          required property int k
          required property string s
          required property real ox
          required property real oy
          required property real pop
          x: (index % game.n) * game.cell + ox
          y: Math.floor(index / game.n) * game.cell + oy
          width: game.cell; height: game.cell
          visible: k >= 0
          opacity: pop > 0 ? pop / game.clearTime : 1
          scale: pop > 0 ? 1 + 0.35 * (1 - pop / game.clearTime) : 1
          z: pop > 0 ? 2 : 1
          TileArt { host: game; x: 3; y: 3; kind: tile.k; special: tile.s }
        }
      }

      // Hint: the two parts to swap pulse.
      Repeater {
        model: game.hint.length === 2 && game.busy === "idle" && game.phase === "play" ? 2 : 0
        delegate: Rectangle {
          required property int index
          z: 3
          x: game.colOf(game.hint[index]) * game.cell + 2; y: game.rowOf(game.hint[index]) * game.cell + 2
          width: game.cell - 4; height: game.cell - 4; radius: 12
          color: "transparent"
          border.width: 3
          border.color: game.color("yellow", "#e0af68")
          opacity: game.glow
        }
      }

      // The part picked up, and the cursor.
      Rectangle {
        z: 3
        visible: game.selected >= 0
        x: game.colOf(game.selected) * game.cell + 1; y: game.rowOf(game.selected) * game.cell + 1
        width: game.cell - 2; height: game.cell - 2; radius: 12
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 3
        border.color: game.color("accent", "#7aa2f7")
      }
      Rectangle {
        z: 3
        visible: game.phase === "play"
        x: game.colOf(game.cursor) * game.cell + 4; y: game.rowOf(game.cursor) * game.cell + 4
        width: game.cell - 8; height: game.cell - 8; radius: 9
        color: "transparent"
        border.width: 2
        border.color: game.color("bright_foreground", "#c0caf5")
        opacity: 0.8
      }

      Text {
        z: 4
        anchors.horizontalCenter: parent.horizontalCenter
        y: 18
        visible: game.comboText !== "" && game.phase === "play"
        text: game.comboText
        color: game.color("yellow", "#e0af68")
        style: Text.Outline; styleColor: game.color("dark_background", "#13141c")
        font.pixelSize: 30; font.bold: true; font.family: "monospace"
        opacity: Math.min(1, game.comboT * 2)
      }

      // Mouse: click two neighbours, or drag a part onto its neighbour. Hovering
      // moves the cursor, so a right-click reroutes the block under the mouse.
      MouseArea {
        anchors.fill: parent
        z: 5
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real pressX: 0
        property real pressY: 0
        function cellAt(mx, my) {
          var c = Math.max(0, Math.min(game.n - 1, Math.floor(mx / game.cell)))
          var r = Math.max(0, Math.min(game.n - 1, Math.floor(my / game.cell)))
          return r * game.n + c
        }
        onPositionChanged: function (m) {
          if (game.phase === "play" && !game.dragging && game.selected < 0) game.cursor = cellAt(m.x, m.y)
          if (!game.dragging) return
          var dx = m.x - pressX, dy = m.y - pressY
          if (Math.max(Math.abs(dx), Math.abs(dy)) < game.cell * 0.45) return
          var dr = Math.abs(dy) > Math.abs(dx) ? (dy > 0 ? 1 : -1) : 0
          var dc = dr === 0 ? (dx > 0 ? 1 : -1) : 0
          var t = Board.neighbor(game.dragFrom, dr, dc)
          game.dragging = false
          if (t >= 0 && game.trySwap(game.dragFrom, t)) game.cursor = t
        }
        onPressed: function (m) {
          game.forceActiveFocus()
          if (game.phase === "ready") { game.start(); return }
          if (game.phase === "over") { game.restart(); return }
          if (game.phase === "paused") { game.resume(); return }
          var i = cellAt(m.x, m.y)
          if (m.button === Qt.RightButton) { game.cursor = i; game.reroute(game.rerouteCorner()); return }
          pressX = m.x; pressY = m.y
          game.dragFrom = i
          game.dragging = true
        }
        onReleased: function (m) {
          if (!game.dragging) return
          game.dragging = false
          game.clickCell(game.dragFrom)
        }
      }
    }

    // Side panel: moves, goals, flux.
    Column {
      x: game.boardX + game.n * game.cell + 28
      y: game.boardY
      width: game.fieldW - x - 20
      spacing: 12

      Text { text: "MOVES"; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 14; font.family: "monospace" }
      Text {
        text: game.moves
        color: game.moves <= 3 ? game.color("red", "#f7768e") : game.color("bright_foreground", "#c0caf5")
        font.pixelSize: 44; font.bold: true; font.family: "monospace"
      }

      Text { text: "TARGET " + game.levelInfo.target; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 14; font.family: "monospace" }
      Rectangle {
        width: parent.width; height: 10; radius: 5
        color: game.color("lighter_background", "#24283b")
        Rectangle {
          width: parent.width * Math.min(1, game.levelScore / Math.max(1, game.levelInfo.target)); height: parent.height; radius: 5
          color: game.levelScore >= game.levelInfo.target ? game.color("green", "#9ece6a") : game.color("accent", "#7aa2f7")
        }
      }

      Text { text: "SALVAGE"; visible: game.levelInfo.goals.length > 0; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 14; font.family: "monospace" }
      Repeater {
        model: game.levelInfo.goals.length
        delegate: Row {
          required property int index
          spacing: 10
          Item {
            width: 29; height: 29
            TileArt { host: game; kind: game.levelInfo.goals[index].kind; scale: 0.5; transformOrigin: Item.TopLeft }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            readonly property int got: Math.min(game.goalCounts[index] || 0, game.levelInfo.goals[index].n)
            text: got + " / " + game.levelInfo.goals[index].n
            color: got >= game.levelInfo.goals[index].n ? game.color("green", "#9ece6a") : game.color("bright_foreground", "#c0caf5")
            font.pixelSize: 18; font.bold: true; font.family: "monospace"
          }
        }
      }
      Row {
        visible: game.levelInfo.fried > 0
        spacing: 10
        Item {
          width: 29; height: 29
          TileArt { host: game; kind: Board.FRIED; scale: 0.5; transformOrigin: Item.TopLeft }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: game.friedLeft > 0 ? "repair " + game.friedLeft : "repaired"
          color: game.friedLeft > 0 ? game.color("bright_foreground", "#c0caf5") : game.color("green", "#9ece6a")
          font.pixelSize: 18; font.bold: true; font.family: "monospace"
        }
      }

      Item { width: 1; height: 4 }
      Text { text: "FLUX"; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 14; font.family: "monospace" }
      Rectangle {
        width: parent.width; height: 10; radius: 5
        color: game.color("lighter_background", "#24283b")
        Rectangle {
          width: parent.width * Math.min(1, game.fluxMeter / game.fluxPerCharge); height: parent.height; radius: 5
          color: game.color("cyan", "#7dcfff")
        }
      }
      Row {
        spacing: 8
        Repeater {
          model: game.maxCharges
          delegate: Rectangle {
            required property int index
            width: 22; height: 22; radius: 6
            color: index < game.charges ? game.color("accent", "#7aa2f7") : "transparent"
            border.width: 2
            border.color: game.color("accent", "#7aa2f7")
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "REROUTE"
          color: game.charges > 0 ? game.color("bright_foreground", "#c0caf5") : game.color("foreground", "#a9b1d6")
          font.pixelSize: 14; font.bold: true; font.family: "monospace"
        }
      }
      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "R or right-click turns the 2×2 block. No move used."
        color: game.color("foreground", "#a9b1d6"); opacity: 0.8
        font.pixelSize: 12; font.family: "monospace"
      }
    }

    // Messages over the board, with a backdrop for pause and game over.
    Rectangle {
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 32
      radius: 8
      visible: messages.visible && (game.phase !== "play")
      z: 6
      color: game.color("dark_background", "#13141c")
      opacity: 0.97
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      z: 6
      x: game.boardX + (game.n * game.cell - width) / 2
      y: game.boardY + (game.n * game.cell - height) / 2
      spacing: 10
      visible: title.text !== ""
      Text {
        id: title
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : game.phase === "ready" ? "SOLDER SNAP"
            : game.banner
        color: game.color("bright_foreground", "#c0caf5")
        style: game.phase === "play" ? Text.Outline : Text.Normal
        styleColor: game.color("dark_background", "#13141c")
        font.pixelSize: game.phase === "play" ? 26 : 40; font.bold: true; font.family: "monospace"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: text !== ""
        text: game.phase === "over" ? "Score " + game.score + (game.beatHigh ? "  ·  new high score!" : "") + "\nlevel " + game.level + " · Enter to play again · Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "ready" ? "Line up 3+ parts to solder them off.\nSwap: drag, click two, or Space + arrows\nMeet the goals before the moves run out.\nSpace or click to start"
            : ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 15; font.family: "monospace"
      }
    }
  }
}
