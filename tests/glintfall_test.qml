import QtQuick
import Quickshell
import Quickshell.Io
import "pieces.js" as Pieces

// Headless rules test for Glintfall. tests/run.sh copies games/glintfall/ and this
// file into one temp folder, runs it with QT_QPA_PLATFORM=offscreen quickshell -p,
// and reads the JSON it writes to $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }

  // Run the game for `seconds` in 1/240 s steps (only while it is in play).
  function run(g, seconds) {
    var steps = Math.round(seconds * 240)
    for (var i = 0; i < steps; i++) {
      if (g.phase !== "play") return
      g.step(1 / 240)
    }
  }
  // A fresh seeded game in play.
  function fresh(g) { g.seed = 1234; g.newGame(); g.start() }
  // Replace the falling piece with a chosen one at a chosen place.
  function place(g, kind, rot, x, y, glint) {
    g.curKind = kind; g.curRot = rot; g.curX = x; g.curY = y
    g.curGlint = glint === undefined ? -1 : glint
    g.fallAcc = 0; g.lockTimer = 0; g.lockResets = 0
  }
  function at(g, x, y) { return g.board[g.idx(x, y)] }
  // Fill a row with "flag" cells except the listed columns.
  function fillRow(g, y, except) {
    for (var x = 0; x < g.cols; x++) if (except.indexOf(x) < 0) g.setCell(x, y, "flag", false)
  }
  function queueKey(g) {
    var s = []
    for (var i = 0; i < g.queue.length; i++) s.push(g.queue[i].kind + ":" + g.queue[i].glint)
    return s.join(",")
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
      try { root.tests() } catch (e) { root.failures.push("exception: " + e + " @" + e.lineNumber) }
      out.setText(JSON.stringify({ passed: root.passed, failed: root.failures }) + "\n")
      Qt.quit()
    }
  }

  function tests() {
    var before, n, i, ok

    // ---- the well and the piece family -------------------------------------------------
    check("the well is 12 wide and 22 tall, with 2 hidden rows", g.cols === 12 && g.rows === 22 && g.hidden === 2, g.cols + "x" + g.rows)
    ok = true
    var detail = ""
    for (i = 0; i < Pieces.SHAPES.length; i++) {
      var id = Pieces.SHAPES[i].id, size = Pieces.size(id), count = Pieces.cells(id, 0).length
      if (count !== 3 && count !== 5) { ok = false; detail = id + " has " + count }
      for (var r = 0; r < 4; r++) {
        var c = Pieces.cells(id, r)
        if (c.length !== count) { ok = false; detail = id + " rot " + r }
        for (var k = 0; k < c.length; k++)
          if (c[k][0] < 0 || c[k][0] >= size || c[k][1] < 0 || c[k][1] >= size) { ok = false; detail = id + " out of box" }
      }
    }
    check("every piece has 3 or 5 cells and turns inside its box", ok, detail)
    check("four turns come back to the start", JSON.stringify(Pieces.cells("stair", 4)) === JSON.stringify(Pieces.cells("stair", 0))
          && JSON.stringify(Pieces.cells("stair", 1)) !== JSON.stringify(Pieces.cells("stair", 0)))
    check("gravity quickens with the level", Pieces.fallInterval(5) < Pieces.fallInterval(1) && Pieces.fallInterval(99) >= 0.06)

    // ---- seeded dice and the bag ----------------------------------------------------------
    g.seed = 4242; g.newGame()
    var q1 = queueKey(g)
    g.newGame()
    check("the same seed deals the same pieces", queueKey(g) === q1 && q1 !== "", q1)
    var seen = {}
    for (i = 0; i < g.queue.length; i++) seen[g.queue[i].kind] = (seen[g.queue[i].kind] || 0) + 1
    for (i = 0; i < g.bag.length; i++) seen[g.bag[i]] = (seen[g.bag[i]] || 0) + 1
    ok = Object.keys(seen).length === Pieces.SHAPES.length
    for (var s in seen) if (seen[s] !== 1) ok = false
    check("a bag holds every piece exactly once", ok, JSON.stringify(seen))
    ok = true
    for (i = 0; i < g.queue.length; i++)
      if (g.queue[i].glint < -1 || g.queue[i].glint >= Pieces.cells(g.queue[i].kind, 0).length) ok = false
    check("a glint is one of the piece's own cells", ok, q1)

    // ---- start and gravity ----------------------------------------------------------------
    g.seed = 1234; g.newGame()
    check("a new game waits to start", g.phase === "ready" && g.curKind === "", g.phase)
    var firstKind = g.queueAt(0).kind
    g.start()
    check("start brings on the first queued piece", g.phase === "play" && g.curKind === firstKind, g.curKind + " vs " + firstKind)
    place(g, "pip", 0, 4, 0)
    run(g, 0.75)
    check("gravity waits a whole interval", g.curY === 0, g.curY)
    run(g, 0.1)
    check("then drops the piece one row", g.curY === 1, g.curY)

    fresh(g); place(g, "pip", 0, 4, 0)
    before = g.score
    g.downHeld = true
    run(g, 0.2)
    g.downHeld = false
    check("soft drop falls fast and scores a point a row", g.curY >= 4 && g.score - before === g.curY, g.curY + " rows, " + (g.score - before))

    // ---- moving, walls, collisions ---------------------------------------------------------
    fresh(g); place(g, "pip", 0, 4, 5)
    n = 0
    while (g.move(-1, 0)) n++
    check("the left wall stops a piece", n === 4 && g.curX === 0, n)
    g.setCell(3, 6, "flag", false)
    check("a piece can't move into the stack", !g.move(1, 0) && g.curX === 0, g.curX)
    check("a piece can't move through the floor", (function () { place(g, "pip", 0, 4, 22); return !g.move(0, 1) && g.curY === 22 })())

    // ---- turning and kicks -----------------------------------------------------------------
    fresh(g); place(g, "pip", 0, 4, 8)
    check("turning a pip stands it up", g.rotate(1) && g.pieceCells()[0].x === 5 && g.pieceCells()[0].y === 8
          && g.pieceCells()[2].x === 5 && g.pieceCells()[2].y === 10, JSON.stringify(g.pieceCells()))
    check("turning back lays it down", g.rotate(-1) && g.curRot === 0 && g.pieceCells()[0].y === 9)
    place(g, "pip", 1, -1, 8)                 // standing in column 0; lying down would poke out
    check("a turn at the left wall kicks right", g.rotate(1) && g.curX === 0 && g.curRot === 2, g.curX)
    fresh(g)
    for (var y = 21; y < 24; y++) fillRow(g, y, [5])
    place(g, "pip", 1, 4, 21)                  // standing in the only gap
    check("a turn with no room for any kick fails", !g.rotate(1) && g.curRot === 1 && g.curX === 4)

    // ---- landing and lock delay ------------------------------------------------------------
    fresh(g); place(g, "pip", 0, 4, 0)
    before = g.score
    g.hardDrop()
    check("hard drop lands on the floor and locks", at(g, 4, 23) && at(g, 6, 23) && at(g, 4, 23).k === "pip")
    check("hard drop scores 2 a row", g.score - before === 44, g.score - before)
    check("hard drop brings on the next piece", g.curKind !== "" && g.curY === 0 && !g.holdUsed)

    fresh(g); place(g, "pip", 0, 4, 22)
    run(g, 0.45)
    check("a resting piece waits before it locks", g.curKind === "pip" && !at(g, 4, 23), g.lockTimer)
    run(g, 0.1)
    check("then locks after the lock delay", !!at(g, 4, 23))

    fresh(g); place(g, "pip", 0, 4, 22)
    run(g, 0.4)
    g.move(1, 0)
    run(g, 0.3)
    check("moving a resting piece restarts the lock delay", g.curKind === "pip" && g.curX === 5 && !at(g, 5, 23), g.lockTimer)
    g.lockResets = g.maxLockResets
    g.move(-1, 0)                              // lock timer is at 0.3 and no longer restarts
    run(g, 0.25)
    check("the restarts run out", !!at(g, 4, 23), g.lockResets)

    // Hopping off a ledge and back must not buy a fresh lock delay once the restarts are spent.
    fresh(g)
    g.setCell(4, 23, "flag", false)            // a one-cell pillar
    place(g, "pip", 0, 4, 21)                  // cells in row 22, cols 4..6, resting on the pillar
    run(g, 0.3)
    g.lockResets = g.maxLockResets
    ok = g.move(1, 0) && !g.resting()          // off the pillar, in the air
    run(g, 0.05)
    ok = ok && g.move(-1, 0) && g.resting()    // back onto it
    run(g, 0.25)                               // 0.3 + 0.25 is past the delay; a fresh one would need 0.5
    check("hopping off a ledge doesn't restart a spent lock delay", ok && !!at(g, 5, 22), g.lockTimer)
    fresh(g); place(g, "pip", 0, 4, 22)
    check("a turn on the floor kicks up and stays resting", g.rotate(1) && g.curY === 21 && g.curRot === 1 && g.resting(), g.curY)

    // ---- clearing rows ----------------------------------------------------------------------
    fresh(g)
    fillRow(g, 23, [4, 5, 6])
    g.setCell(0, 22, "arch", false)
    place(g, "pip", 0, 4, 0)
    g.hardDrop()
    check("a full row scores 100 a level", g.lastClear.rows === 1 && g.lastClear.points === 100, JSON.stringify(g.lastClear))
    check("clearing cells flash before they go", g.clearTimer > 0 && g.curKind === "" && g.clearMask[g.idx(0, 23)] === true && !!at(g, 0, 23))
    run(g, 0.34)
    check("then the row is gone and the stack drops", g.lines === 1 && at(g, 0, 23) && at(g, 0, 23).k === "arch" && !at(g, 5, 23) && !at(g, 0, 22))
    check("and the next piece comes on", g.curKind !== "" && g.clearTimer <= 0)

    fresh(g)
    fillRow(g, 23, [10]); fillRow(g, 22, [10, 11])
    place(g, "flag", 0, 10, 0)                 // "##.", "##.", "#..": two columns wide at the top
    g.hardDrop()
    check("two rows at once score 250", g.lastClear.rows === 2 && g.lastClear.points === 250, JSON.stringify(g.lastClear))

    fresh(g); g.level = 3
    fillRow(g, 23, [4, 5, 6])
    place(g, "pip", 0, 4, 0)
    g.hardDrop()
    check("row points grow with the level", g.lastClear.points === 300, g.lastClear.points)

    fresh(g); g.lines = 7
    var slow = g.gravityInterval()
    fillRow(g, 23, [4, 5, 6])
    place(g, "pip", 0, 4, 0)
    g.hardDrop()
    run(g, 0.34)
    check("every 8 rows is a level, and it falls faster", g.level === 2 && g.gravityInterval() < slow, g.level)

    // ---- glints --------------------------------------------------------------------------------
    fresh(g)
    fillRow(g, 23, [4, 5, 6])
    g.setCell(2, 23, "arch", true)             // a glint in the row that will clear
    g.setCell(1, 22, "star", false); g.setCell(3, 22, "star", false)   // beside it, one row up
    g.setCell(9, 22, "zig", false)             // out of reach
    place(g, "pip", 0, 4, 0)
    before = g.bursts
    g.hardDrop()
    check("a glint in a cleared row bursts", g.lastClear.bursts === 1 && g.bursts === before + 1, JSON.stringify(g.lastClear))
    check("a burst scores its cells on top of the row", g.lastClear.extra === 2 && g.lastClear.points === 100 + 50 + 2 * 20, JSON.stringify(g.lastClear))
    run(g, 0.34)
    check("a burst takes its 3×3 block", !at(g, 1, 23) && !at(g, 3, 23), JSON.stringify([at(g, 1, 23), at(g, 3, 23)]))
    check("cells out of reach stay and drop", at(g, 9, 23) && at(g, 9, 23).k === "zig")

    fresh(g)
    fillRow(g, 23, [9, 10, 11])
    g.setCell(2, 23, "arch", true)             // bursts first
    g.setCell(3, 22, "star", true)             // caught in the blast, bursts too
    g.setCell(4, 21, "zig", false)             // only the second blast reaches this
    g.setCell(6, 21, "hook", false)            // nothing reaches this
    place(g, "pip", 0, 9, 0)
    g.hardDrop()
    check("a glint caught in a blast bursts too", g.lastClear.bursts === 2 && g.lastClear.extra === 2, JSON.stringify(g.lastClear))
    run(g, 0.34)
    check("a chain reaches past the first blast", !at(g, 4, 22) && at(g, 6, 22) && at(g, 6, 22).k === "hook")

    fresh(g)
    fillRow(g, 23, [4, 5, 6])
    g.setCell(0, 22, "arch", true)             // a glint not in a full row
    place(g, "pip", 0, 4, 0, 1)                // the pip's middle cell glints
    g.hardDrop()
    check("a piece's own glint bursts when its row clears", g.lastClear.bursts === 1, JSON.stringify(g.lastClear))
    run(g, 0.34)
    check("a glint outside cleared rows waits its turn", at(g, 0, 23) && at(g, 0, 23).g === true)

    // ---- hold --------------------------------------------------------------------------------
    fresh(g)
    var k0 = g.curKind, k1 = g.queueAt(0).kind
    check("hold sets the piece aside and brings on the next", g.hold() && g.holdKind === k0 && g.curKind === k1, g.holdKind + " " + g.curKind)
    check("hold works once per piece", !g.hold() && g.curKind === k1)
    g.hardDrop()
    check("after a lock, hold swaps back", g.hold() && g.curKind === k0 && g.curY === 0, g.curKind)

    // ---- key repeat -------------------------------------------------------------------------
    fresh(g); place(g, "pip", 0, 6, 2)
    g.pressLeft()
    check("pressing left moves at once", g.curX === 5, g.curX)
    run(g, 0.12)
    check("holding left waits before repeating", g.curX === 5, g.curX)
    run(g, 0.1)
    check("then repeats", g.curX <= 3, g.curX)
    g.leftHeld = false

    // ---- top out ----------------------------------------------------------------------------
    fresh(g); place(g, "pip", 0, 0, 20)
    for (y = 0; y < 4; y++) for (var x = 4; x < 8; x++) g.setCell(x, y, "flag", false)
    g.hardDrop()
    check("no room for the next piece ends the game", g.phase === "over" && g.curKind === "", g.phase)

    fresh(g)
    for (y = 2; y < 24; y++) { g.setCell(0, y, "flag", false); g.setCell(1, y, "flag", false) }
    place(g, "hook", 0, 0, 0)                  // entirely in the hidden rows, resting on the stack
    g.hardDrop()
    check("locking entirely above the well ends the game", g.phase === "over", g.phase)

    // ---- pause and focus ---------------------------------------------------------------------
    fresh(g); place(g, "pip", 0, 4, 3)
    g.togglePause()
    g.step(1)
    check("pause freezes the piece", g.phase === "paused" && g.curY === 3, g.curY)
    check("a paused piece doesn't move", !g.move(1, 0) && !g.rotate(1) && !g.hardDrop() && g.curX === 4)
    g.togglePause()
    check("resume plays", g.phase === "play", g.phase)
    g.leftHeld = true; g.downHeld = true
    g.lostFocus()
    check("losing focus pauses and forgets held keys", g.phase === "paused" && !g.leftHeld && !g.rightHeld && !g.downHeld, g.phase)

    // ---- drawing follows the state -----------------------------------------------------------
    fresh(g); place(g, "pip", 0, 4, 5)
    g.publish()
    var a0 = g.activeView.itemAt(0)
    check("the drawn piece is where the piece is", !!a0 && a0.x === 4 * g.cellSize && a0.y === (6 - g.hidden) * g.cellSize, a0 ? a0.x + "," + a0.y : "no item")
    g.move(1, 0); g.publish()
    a0 = g.activeView.itemAt(0)
    check("the drawn piece moves when the piece does", !!a0 && a0.x === 5 * g.cellSize, a0 ? a0.x : "no item")
    var vi = (23 - g.hidden) * g.cols + 5
    check("an empty board cell draws nothing", g.boardView.itemAt(vi) && !g.boardView.itemAt(vi).visible)
    g.hardDrop()
    var bv = g.boardView.itemAt(vi)
    check("a locked piece is drawn in the well", !!bv && bv.visible && bv.kind === "pip", bv ? bv.kind : "no item")

    // ---- high score and new game --------------------------------------------------------------
    g.newGame()
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)

    fresh(g); g.lines = 20; g.level = 3; g.bursts = 4
    g.setCell(3, 23, "flag", true); g.hold()
    g.newGame()
    ok = g.score === 0 && g.level === 1 && g.lines === 0 && g.bursts === 0 && g.phase === "ready" && !g.beatHigh
         && g.holdKind === "" && !at(g, 3, 23) && g.curKind === "" && g.queue.length >= g.queueShown
    check("a new game resets everything", ok)
  }
}
