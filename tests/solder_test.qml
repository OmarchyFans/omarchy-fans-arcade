import QtQuick
import Quickshell
import Quickshell.Io
import "board.js" as Board
import "levels.js" as Levels

// Headless rules test for Solder Snap. tests/run.sh copies games/solder/ and this
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

  // A board with no line and no move: kind (c + 2r) % 5 never repeats within two
  // cells along a row or a column.
  readonly property var filler: ["01234012", "23401234", "40123401", "12340123",
                                 "34012340", "01234012", "23401234", "40123401"]
  function rows(edits) {
    var out = filler.slice()
    for (var e = 0; e < edits.length; e++) {
      var r = edits[e][0], c = edits[e][1]
      out[r] = out[r].substring(0, c) + edits[e][2] + out[r].substring(c + 1)
    }
    return out
  }
  function blankSpecials(edits) {
    var out = []
    for (var r = 0; r < 8; r++) out.push("........")
    for (var e = 0; e < (edits || []).length; e++) {
      var rr = edits[e][0], c = edits[e][1]
      out[rr] = out[rr].substring(0, c) + edits[e][2] + out[rr].substring(c + 1)
    }
    return out
  }
  // The same edits as one special per cell ("" for none), as the rules use them.
  function cellSpecials(edits) {
    return blankSpecials(edits).join("").split("").map(function (ch) { return ch === "." ? "" : ch })
  }
  function at(r, c) { return Board.idx(r, c) }
  function kindsOf(rowsArr) {
    var k = []
    for (var r = 0; r < 8; r++) for (var c = 0; c < 8; c++) {
      var ch = rowsArr[r].charAt(c)
      k.push(ch === "C" ? Board.CORE : ch === "F" ? Board.FRIED : ch === "." ? -1 : parseInt(ch, 10))
    }
    return k
  }
  function same(a, b) { if (a.length !== b.length) return false; for (var i = 0; i < a.length; i++) if (a[i] !== b[i]) return false; return true }

  // Run the game until the board waits for the player (or the game stops).
  function settle(g, seconds) {
    var steps = Math.ceil((seconds || 20) * 240)
    for (var i = 0; i < steps; i++) {
      if (g.phase !== "play") return
      g.step(1 / 240)
      if (g.busy === "idle") return
    }
  }
  function stepUntil(g, cond, seconds) {
    var steps = Math.ceil((seconds || 5) * 240)
    for (var i = 0; i < steps && !cond(); i++) g.step(1 / 240)
  }
  function fresh(g) { g.seed = 7; g.newGame(); g.start() }

  // Row 7 gets 5 5 _ and a 5 above the gap: swapping (6,2) down makes 5 5 5.
  readonly property var lineA: [[7, 0, "5"], [7, 1, "5"], [6, 2, "5"]]

  // The move a greedy player would take: the swap that clears the most at once.
  function bestMove(g) {
    var moves = Board.allMoves(g.board()), best = null, bestN = -1
    for (var m = 0; m < moves.length; m++) {
      var b = Board.copy(g.board()), a = moves[m][0], c = moves[m][1]
      var t = b.k[a]; b.k[a] = b.k[c]; b.k[c] = t
      var t2 = b.s[a]; b.s[a] = b.s[c]; b.s[c] = t2
      var n = 0, groups = Board.groupRuns(Board.findRuns(b.k))
      for (var q = 0; q < groups.length; q++) n += groups[q].cells.length * groups[q].cells.length
      if (b.k[a] === Board.CORE || b.k[c] === Board.CORE) n += 40
      if (b.s[a] && b.s[c]) n += 30
      if (n > bestN) { bestN = n; best = moves[m] }
    }
    return best
  }
  function playLevel(g) {
    var lvl = g.level, guard = 0
    while (g.phase === "play" && g.level === lvl && guard++ < 200) {
      var m = bestMove(g)
      if (!m || !g.trySwap(m[0], m[1])) break
      settle(g, 30)
    }
  }

  FloatingWindow {
    implicitWidth: 800; implicitHeight: 600
    // Shown only for SOLDER_SNAPSHOT, and only ever under the offscreen platform
    // that tests/run.sh sets.
    visible: root.snapPath !== "" && Quickshell.env("QT_QPA_PLATFORM") === "offscreen"
    Game { id: g; anchors.fill: parent }
  }

  // SOLDER_SNAPSHOT=/tmp/x.png saves a picture of a mid-game board instead of
  // running the rules (for checking the drawing without a desktop window).
  readonly property string snapPath: Quickshell.env("SOLDER_SNAPSHOT") || ""
  Timer {
    id: snapTimer
    interval: 600
    onTriggered: g.grabToImage(function (r) { r.saveToFile(root.snapPath); Qt.quit() })
  }
  function snapshot() {
    g.theme = { background: "#1a1b26", dark_background: "#16161e", lighter_background: "#292e42", foreground: "#a9b1d6",
                bright_foreground: "#c0caf5", accent: "#7aa2f7", red: "#f7768e", yellow: "#e0af68", green: "#9ece6a",
                cyan: "#7dcfff", blue: "#7aa2f7", magenta: "#bb9af7" }
    g.seed = 41; g.newGame(); g.level = 6; g.loadLevel(); g.start()
    g.kinds[at(2, 2)] = Board.CORE
    g.specials[at(4, 5)] = "h"; g.specials[at(1, 6)] = "v"; g.specials[at(5, 1)] = "x"
    g.goalCounts = [9]; g.levelScore = 1100; g.addScore(1100); g.fluxMeter = 60
    g.cursor = at(3, 4); g.selected = at(3, 4); g.hint = Board.findMove(g.board())
    g.comboText = "CASCADE ×3"; g.comboT = 1
    g.banner = ""
    g.publish()
    // SOLDER_SNAPSHOT_PHASE=ready|paused|over pictures that screen instead.
    var ph = Quickshell.env("SOLDER_SNAPSHOT_PHASE") || ""
    if (ph === "ready") g.newGame()
    else if (ph === "paused") g.pause()
    else if (ph === "over") g.gameOver()
    snapTimer.start()
  }

  FileView { id: out; path: Quickshell.env("ARCADE_TEST_OUT") || "/dev/null"; printErrors: false }

  Timer {
    interval: 50; running: true
    onTriggered: {
      if (root.snapPath !== "") { root.snapshot(); return }
      try { root.tests() } catch (e) { root.failures.push("exception: " + e + " @" + e.lineNumber) }
      out.setText(JSON.stringify({ passed: root.passed, failed: root.failures }) + "\n")
      Qt.quit()
    }
  }

  function tests() {
    var k, runs, groups, sp, b, before, i, n

    // ---- match detection (pure rules) ----------------------------------------
    k = kindsOf(filler)
    check("the test filler has no line", Board.findRuns(k).length === 0)
    check("the test filler has no move", Board.findMove({ k: k, s: cellSpecials([]) }) === null)

    k = kindsOf(rows([[2, 3, "5"], [2, 4, "5"], [2, 5, "5"]]))
    runs = Board.findRuns(k)
    check("three in a row is a line", runs.length === 1 && runs[0].dir === "h" && same(runs[0].cells, [at(2, 3), at(2, 4), at(2, 5)]), JSON.stringify(runs))
    k = kindsOf(rows([[4, 6, "5"], [5, 6, "5"], [6, 6, "5"]]))
    runs = Board.findRuns(k)
    check("three in a column is a line", runs.length === 1 && runs[0].dir === "v" && runs[0].cells.length === 3, JSON.stringify(runs))

    k = kindsOf(rows([[7, 0, "5"], [7, 1, "5"], [7, 2, "5"], [6, 0, "5"], [5, 0, "5"]]))
    groups = Board.groupRuns(Board.findRuns(k))
    sp = groups.length === 1 ? Board.specialFor(groups[0], []) : null
    check("an L is one match of five", groups.length === 1 && groups[0].cells.length === 5, groups.length)
    check("an L builds a Surge where its lines cross", !!sp && sp.type === "x" && sp.at === at(7, 0), JSON.stringify(sp))

    k = kindsOf(rows([[7, 0, "5"], [7, 1, "5"], [7, 2, "5"], [6, 1, "5"], [5, 1, "5"]]))
    groups = Board.groupRuns(Board.findRuns(k))
    sp = groups.length === 1 ? Board.specialFor(groups[0], []) : null
    check("a T builds a Surge at its stem", groups.length === 1 && !!sp && sp.type === "x" && sp.at === at(7, 1), JSON.stringify(sp))

    k = kindsOf(rows([[1, 5, "5"], [2, 5, "5"], [3, 5, "5"], [4, 5, "5"]]))
    groups = Board.groupRuns(Board.findRuns(k))
    sp = Board.specialFor(groups[0], [at(3, 5)])
    check("four in a column builds a V-bus on the moved part", sp && sp.type === "v" && sp.at === at(3, 5), JSON.stringify(sp))
    k = kindsOf(rows([[0, 0, "5"], [0, 1, "5"], [0, 2, "5"]]))
    check("a plain three builds nothing", Board.specialFor(Board.groupRuns(Board.findRuns(k))[0], []) === null)

    k = kindsOf(rows([[0, 0, "F"], [0, 1, "F"], [0, 2, "F"]]))
    check("fried parts never match", Board.findRuns(k).length === 0)

    // ---- blasts (pure rules) ---------------------------------------------------
    b = { k: kindsOf(filler), s: cellSpecials([[3, 3, "h"]]) }
    var hit = Board.blast(b, [at(3, 3)], {})
    check("an H-bus clears its row", hit.length === 8 && hit.every(function (x) { return Board.rowOf(x) === 3 }), hit.length)
    b.s[at(3, 3)] = "v"
    hit = Board.blast(b, [at(3, 3)], {})
    check("a V-bus clears its column", hit.length === 8 && hit.every(function (x) { return Board.colOf(x) === 3 }), hit.length)
    b.s[at(3, 3)] = "x"
    check("a Surge clears a 13-cell diamond", Board.blast(b, [at(3, 3)], {}).length === 13)
    b.s[at(3, 3)] = ""; b.s[at(0, 0)] = "x"
    check("a Surge in the corner stays on the board", Board.blast(b, [at(0, 0)], {}).length === 6)
    b.s[at(0, 0)] = ""; b.s[at(0, 1)] = "h"; b.k[at(0, 5)] = Board.CORE
    hit = Board.blast(b, [at(0, 1)], {})
    var common = Board.mostCommon(b.k), all = true
    for (i = 0; i < 64; i++) if (b.k[i] === common && hit.indexOf(i) < 0) all = false
    check("a blast sets off a Core, which takes the most common part", all && hit.indexOf(at(0, 5)) >= 0, hit.length)

    // ---- a new game ---------------------------------------------------------------
    g.seed = 11; g.newGame()
    check("a new game waits to start", g.phase === "ready" && g.busy === "idle", g.phase)
    check("swaps do nothing before the start", !g.trySwap(0, 1))
    var ok = true
    for (i = 0; i < 64; i++) if (g.kinds[i] < 0 || g.kinds[i] >= g.levelInfo.kinds) ok = false
    check("a fresh board is full of this level's parts", ok)
    check("a fresh board has no ready-made line", !Board.hasMatch(g.kinds))
    check("a fresh board has a move", Board.findMove(g.board()) !== null)
    var k1 = g.kinds.slice()
    g.newGame()
    check("the same seed deals the same board", same(k1, g.kinds))
    g.seed = 12; g.newGame()
    check("another seed deals another board", !same(k1, g.kinds))
    g.seed = 5; g.level = 3; g.loadLevel()
    n = 0; ok = true
    for (i = 0; i < 64; i++) if (g.kinds[i] === Board.FRIED) { n++; if (Board.rowOf(i) < 3) ok = false }
    check("Burnt Relay deals its fried parts in the lower rows", n === Levels.level(3).fried && g.friedLeft === n && ok, n)

    // ---- gravity and refill ----------------------------------------------------------
    fresh(g)
    g.setBoard(filler)
    g.rngState = 99
    g.dropCells([at(7, 0), at(6, 0)])
    var after1 = g.kinds.slice()
    check("parts fall into the holes below", g.kinds[at(7, 0)] === 0 && g.kinds[at(2, 0)] === 0 && g.kinds[at(7, 1)] === 0, g.kinds[at(7, 0)])
    check("new parts feed in above and fall two rows", g.kinds[at(0, 0)] >= 0 && g.kinds[at(1, 0)] >= 0
          && g.offY[at(0, 0)] === -2 * g.cell && g.offY[at(7, 0)] === -2 * g.cell, g.offY[at(0, 0)])
    g.setBoard(filler)
    g.rngState = 99
    g.dropCells([at(7, 0), at(6, 0)])
    check("the refill is the same for the same seed", same(after1, g.kinds))

    // ---- swaps -------------------------------------------------------------------------
    fresh(g)
    g.setBoard(filler)
    before = g.kinds.slice()
    check("parts must be neighbours", !g.trySwap(0, 2) && !g.trySwap(0, 9))
    check("a swap starts", g.trySwap(0, 1) && g.busy === "swap")
    check("no second swap while one is moving", !g.trySwap(2, 3))
    settle(g)
    check("a swap that makes no line slides back", same(before, g.kinds) && g.busy === "idle", g.busy)
    check("a swap that slides back costs no move", g.moves === Levels.level(1).moves, g.moves)

    fresh(g)
    g.setBoard(rows(lineA))
    var scoreBefore = g.score
    g.trySwap(at(6, 2), at(7, 2))
    settle(g)
    check("a line costs one move", g.moves === Levels.level(1).moves - 1, g.moves)
    check("three parts score 30", g.cascadeLog.length >= 1 && g.cascadeLog[0].points === 30 && g.cascadeLog[0].cleared === 3, JSON.stringify(g.cascadeLog))
    check("the score adds up the cascades", g.score - scoreBefore === g.cascadeLog.reduce(function (s, c) { return s + c.points }, 0))
    check("a settled board has no line left", !Board.hasMatch(g.kinds) && g.busy === "idle")

    fresh(g)
    g.setBoard(rows([[7, 0, "5"], [7, 1, "F"], [6, 2, "5"]]))
    check("fried parts can't be swapped", !g.trySwap(at(7, 1), at(7, 2)) && !g.trySwap(at(7, 1), at(6, 1)))

    // Cascade: the column-0 line drops a 4 next to 4 4 on the bottom row.
    fresh(g)
    g.setBoard(rows([[5, 0, "5"], [6, 0, "5"], [7, 1, "5"], [4, 0, "4"], [7, 2, "4"]]))
    g.fluxMeter = 0; g.charges = 0
    g.trySwap(at(7, 1), at(7, 0))
    settle(g)
    var c2 = g.cascadeLog.length >= 2 ? g.cascadeLog[1] : null
    check("a falling part can make a cascade", !!c2 && c2.cascade === 2 && c2.cleared >= 3 && g.maxCascade >= 2, JSON.stringify(g.cascadeLog))
    check("a cascade scores double per part", !!c2 && c2.points === c2.cleared * 20, JSON.stringify(c2))
    check("a cascade charges the flux meter", g.fluxMeter >= 25 || g.charges > 0, g.fluxMeter)
    check("a whole cascade is still one move", g.moves === Levels.level(1).moves - 1, g.moves)

    // ---- specials in play ------------------------------------------------------------
    fresh(g)
    g.setBoard(rows(lineA), blankSpecials([[7, 0, "h"]]))
    g.trySwap(at(6, 2), at(7, 2))
    stepUntil(g, function () { return g.busy === "clear" })
    check("an H-bus in a line clears the whole row", g.cascadeLog.length === 1 && g.cascadeLog[0].cleared === 8, JSON.stringify(g.cascadeLog))

    fresh(g)
    g.setBoard(rows([[7, 0, "5"], [7, 1, "5"], [7, 3, "5"], [6, 2, "5"]]))
    g.trySwap(at(6, 2), at(7, 2))
    stepUntil(g, function () { return g.busy === "clear" })
    check("four in a row builds an H-bus where the part landed", g.specials[at(7, 2)] === "h" && g.kinds[at(7, 2)] === 5, g.specials[at(7, 2)])
    check("building a Bus scores its bonus", g.cascadeLog[0].points === 3 * 10 + Levels.SPECIAL_BONUS.h, g.cascadeLog[0].points)

    // Level 1's salvage goal is kind 2. The four-in-a-row is kind 2 here too, so
    // the cell the new Bus is built on (kept, not cleared) must still count.
    fresh(g)
    g.setBoard(rows([[7, 0, "2"], [7, 1, "2"], [7, 3, "2"], [6, 2, "2"]]))
    g.trySwap(at(6, 2), at(7, 2))
    stepUntil(g, function () { return g.busy === "clear" })
    check("the cell a new special is built on still counts toward its salvage goal",
          g.specials[at(7, 2)] === "h" && g.goalCounts[0] === 4, g.goalCounts[0])

    fresh(g)
    g.setBoard(rows([[7, 0, "5"], [7, 1, "5"], [7, 3, "5"], [7, 4, "5"], [6, 2, "5"]]))
    g.trySwap(at(6, 2), at(7, 2))
    stepUntil(g, function () { return g.busy === "clear" })
    check("five in a row builds a Core", g.kinds[at(7, 2)] === Board.CORE && g.specials[at(7, 2)] === "", g.kinds[at(7, 2)])

    fresh(g)
    g.setBoard(rows([[7, 7, "C"]]))
    var zeros = 0
    for (i = 0; i < 64; i++) if (g.kinds[i] === 0) zeros++
    check("a Core can be swapped with anything", Board.findMove(g.board()) !== null)
    g.trySwap(at(7, 7), at(7, 6))
    stepUntil(g, function () { return g.busy === "clear" })
    check("a swapped Core clears every part of that kind", g.cascadeLog.length === 1 && g.cascadeLog[0].cleared === zeros + 1, JSON.stringify(g.cascadeLog) + " zeros " + zeros)

    fresh(g)
    g.setBoard(rows([[7, 6, "C"], [7, 7, "C"]]))
    g.trySwap(at(7, 6), at(7, 7))
    stepUntil(g, function () { return g.busy === "clear" })
    check("two Cores swapped clear the whole board", g.cascadeLog.length === 1 && g.cascadeLog[0].cleared === 64, JSON.stringify(g.cascadeLog))

    fresh(g)
    g.setBoard(filler, blankSpecials([[3, 3, "h"], [3, 4, "v"]]))
    g.trySwap(at(3, 3), at(3, 4))
    stepUntil(g, function () { return g.busy === "clear" })
    check("two specials swapped go off together (a row and a column)", g.cascadeLog.length === 1 && g.cascadeLog[0].cleared === 15, JSON.stringify(g.cascadeLog))
    settle(g)
    check("a special swap costs a move", g.moves === Levels.level(1).moves - 1, g.moves)

    // Fried parts: a line next to one repairs it.
    fresh(g)
    g.setBoard(rows(lineA.concat([[7, 3, "F"]])))
    check("the fried part is counted", g.friedLeft === 1, g.friedLeft)
    g.trySwap(at(6, 2), at(7, 2))
    settle(g)
    check("a line next to a fried part repairs it", g.friedLeft === 0 && g.cascadeLog[0].cleared === 4, g.friedLeft)
    fresh(g)
    g.setBoard(rows(lineA.concat([[6, 3, "F"], [4, 5, "F"]])))
    g.trySwap(at(6, 2), at(7, 2))
    stepUntil(g, function () { return g.busy === "clear" })
    check("a line repairs a fried part at its corner, not one further away", g.friedLeft === 1 && g.cascadeLog[0].cleared === 4, g.friedLeft)

    // ---- goals, move limit ---------------------------------------------------------------
    fresh(g)
    g.setBoard(rows(lineA))
    g.levelScore = g.levelInfo.target - 10
    g.goalCounts = [Levels.level(1).goals[0].n]
    g.trySwap(at(6, 2), at(7, 2))
    stepUntil(g, function () { return g.busy === "levelup" }, 10)
    check("meeting every goal wins the level", g.busy === "levelup" && g.phase === "play", g.busy)
    check("moves left pay a bonus", g.lastBonus === g.moves * Levels.MOVE_BONUS && g.lastBonus > 0, g.lastBonus)
    settle(g)
    check("the next level starts with its own moves", g.level === 2 && g.moves === Levels.level(2).moves && g.levelScore === 0 && g.busy === "idle", g.level)

    fresh(g)
    g.setBoard(rows(lineA))
    g.trySwap(at(6, 2), at(7, 2))
    settle(g)
    check("goals not met yet: play goes on", g.phase === "play" && g.level === 1)
    g.setBoard(rows(lineA))
    g.moves = 1
    g.trySwap(at(6, 2), at(7, 2))
    settle(g)
    check("running out of moves ends the game", g.phase === "over" && g.moves === 0, g.phase)
    check("nothing moves after game over", !g.trySwap(0, 1))

    // ---- no moves: shuffle -------------------------------------------------------------------
    fresh(g)
    g.setBoard(rows([[3, 3, "F"]]))
    var counts = Board.countKinds(g.kinds)
    g.endTurn()
    check("a stuck board is noticed and shuffled", g.busy === "shuffle" && g.shuffles === 1, g.busy)
    settle(g)
    check("after the shuffle there is a move and no line", g.busy === "idle" && Board.findMove(g.board()) !== null && !Board.hasMatch(g.kinds))
    check("a shuffle keeps the same parts", JSON.stringify(Board.countKinds(g.kinds)) === JSON.stringify(counts))
    check("a shuffle leaves fried parts where they are", g.kinds[at(3, 3)] === Board.FRIED)

    // The last-resort reshuffle: every movable part is the same, so no shuffle can
    // avoid a line and the game deals fresh parts. On a level that deals fried parts
    // it must not add new ones (the repair count would then be wrong).
    fresh(g)
    g.level = 3; g.loadLevel()
    var allSame = ["F0000000", "00000000", "00000F00", "00000000", "00000000", "00000F00", "00000000", "00000000"]
    g.setBoard(allSame)
    g.shuffleBoard()
    var friedAt = []
    for (i = 0; i < 64; i++) if (g.kinds[i] === Board.FRIED) friedAt.push(i)
    check("the last-resort reshuffle keeps exactly the fried parts it had",
          same(friedAt, [at(0, 0), at(2, 5), at(5, 5)]) && g.friedLeft === 3, JSON.stringify(friedAt) + " left " + g.friedLeft)
    check("the last-resort reshuffle deals a board with a move and no line",
          !Board.hasMatch(g.kinds) && Board.findMove(g.board()) !== null && g.busy === "shuffle")
    settle(g)
    check("the last-resort reshuffle settles to the player's turn", g.busy === "idle" && g.offY[at(4, 4)] === 0, g.busy)

    // ---- keyboard -----------------------------------------------------------------------------
    fresh(g)
    g.setBoard(rows(lineA))
    g.cursor = 0
    g.moveCursor(0, -1); g.moveCursor(-1, 0)
    check("the cursor stops at the top-left edges", g.cursor === 0, g.cursor)
    g.moveCursor(1, 0); g.moveCursor(0, 1)
    check("arrows move the cursor", g.cursor === at(1, 1), g.cursor)
    g.cursor = 63; g.moveCursor(0, 1); g.moveCursor(1, 0)
    check("the cursor doesn't wrap", g.cursor === 63, g.cursor)
    g.cursor = at(6, 2)
    g.action()
    check("Space picks up the part under the cursor", g.selected === at(6, 2), g.selected)
    g.action()
    check("Space again puts it down", g.selected === -1, g.selected)
    g.action()
    g.moveCursor(1, 0)
    check("an arrow swaps the picked-up part", g.busy === "swap" && g.cursor === at(7, 2) && g.selected === -1, g.busy)
    settle(g)
    check("a keyboard swap plays like any other", g.moves === Levels.level(1).moves - 1, g.moves)

    fresh(g)
    g.setBoard(rows(lineA))
    g.clickCell(at(6, 2)); g.clickCell(at(7, 2))
    check("clicking two neighbours swaps them", g.busy === "swap")
    settle(g)

    // A click (or Space, which reaches clickCell through action()) is ignored
    // while the board is mid-cascade: the cell under it can change kind before
    // the board goes idle again.
    fresh(g)
    g.setBoard(rows([[5, 0, "5"], [6, 0, "5"], [7, 1, "5"], [4, 0, "4"], [7, 2, "4"]]))
    g.trySwap(at(7, 1), at(7, 0))
    check("mid-swap, a click selects nothing", (g.clickCell(at(3, 3)), g.selected === -1 && g.busy === "swap"))
    stepUntil(g, function () { return g.busy === "clear" || g.busy === "fall" }, 2)
    check("mid-cascade (falling/clearing), a click still selects nothing",
          g.busy !== "idle" && (g.clickCell(at(3, 3)), g.selected === -1), g.busy)
    settle(g, 5)
    check("once idle again, clicking works as usual", (g.clickCell(at(3, 3)), g.selected === at(3, 3)), g.selected)

    // ---- hint ----------------------------------------------------------------------------------
    fresh(g)
    for (i = 0; i < 4.9 * 60; i++) g.step(1 / 60)
    check("no hint before five idle seconds", g.hint.length === 0)
    for (i = 0; i < 0.3 * 60; i++) g.step(1 / 60)
    check("a hint after five idle seconds", g.hint.length === 2 && Board.swapWorks(g.board(), g.hint[0], g.hint[1]), JSON.stringify(g.hint))
    g.moveCursor(0, 1)
    check("any input hides the hint", g.hint.length === 0 && g.idleTime === 0)

    // ---- Reroute (our own mechanic) ------------------------------------------------------------
    fresh(g)
    g.setBoard(filler)
    before = g.kinds.slice()
    g.charges = 1
    check("Reroute turns a 2×2 block", g.reroute(0) && g.busy === "rotate" && g.kinds[1] === before[0] && g.kinds[9] === before[1])
    settle(g)
    check("a Reroute that makes no line turns back and keeps the charge", same(before, g.kinds) && g.charges === 1, g.charges)
    g.setBoard(rows([[7, 1, "5"], [6, 1, "5"], [7, 2, "5"]]))
    g.charges = 1
    g.reroute(at(6, 0))
    settle(g)
    check("a Reroute that makes a line spends the charge", g.charges === 0 && g.cascadeLog.length >= 1 && g.cascadeLog[0].cleared >= 3, g.charges)
    check("a Reroute costs no move", g.moves === Levels.level(1).moves, g.moves)
    check("no charge, no Reroute", !g.reroute(0))
    g.charges = 1
    check("a Reroute block must fit on the board", !g.reroute(at(0, 7)) && !g.reroute(at(7, 0)))
    g.setBoard(rows([[6, 0, "F"]]))
    g.charges = 1
    g.reroute(at(6, 0))
    check("a Reroute can move a fried part", g.kinds[at(6, 1)] === Board.FRIED)
    settle(g)

    g.charges = 0; g.fluxMeter = 0
    g.addFlux(90)
    check("flux below a full meter banks nothing", g.charges === 0 && g.fluxMeter === 90)
    g.addFlux(20)
    check("a full flux meter banks a Reroute charge", g.charges === 1 && g.fluxMeter === 10, g.charges + " " + g.fluxMeter)
    g.addFlux(1000)
    check("charges stop at the maximum", g.charges === g.maxCharges && g.fluxMeter === g.fluxPerCharge, g.charges)

    // ---- pause and focus ---------------------------------------------------------------------------
    fresh(g)
    g.setBoard(rows(lineA))
    g.trySwap(at(6, 2), at(7, 2))
    g.step(1 / 60)
    g.togglePause()
    var oy = g.offY[at(7, 2)]
    for (i = 0; i < 60; i++) g.step(1 / 60)
    check("a pause freezes the board mid-swap", g.phase === "paused" && g.busy === "swap" && g.offY[at(7, 2)] === oy && oy !== 0, oy)
    check("no swaps while paused", !g.trySwap(0, 1))
    g.togglePause()
    settle(g)
    check("resuming finishes the swap", g.phase === "play" && g.moves === Levels.level(1).moves - 1, g.moves)
    g.dragging = true; g.dragFrom = 5
    g.lostFocus()
    check("losing focus pauses", g.phase === "paused", g.phase)
    check("losing focus forgets a drag", !g.dragging && g.dragFrom === -1)

    // A level banner fades on its own timer; it must not keep counting down (and
    // so fade) while the game is paused.
    fresh(g)
    g.flash("Testing")
    check("flash starts the banner timer", g.bannerTimer.running)
    g.pause()
    check("pausing stops the banner timer", !g.bannerTimer.running)
    g.resume()
    check("resuming restarts the banner timer", g.bannerTimer.running)
    g.bannerTimer.stop()
    g.pause(); g.resume()
    check("resuming leaves an already-stopped banner timer alone", !g.bannerTimer.running)

    // The "picked up" tile fill must come from the theme, not a fixed white wash
    // that all but disappears against a light theme's own light background.
    g.theme = { accent: "#7aa2f7" }
    var darkFill = g.selectedFill()
    g.theme = { accent: "#3b5bdb" }
    var lightFill = g.selectedFill()
    check("the selected-part fill follows the theme's accent color, not a fixed white",
          darkFill.r !== lightFill.r && darkFill.a > 0 && darkFill.a < 0.5, JSON.stringify([darkFill, lightFill]))
    g.theme = {}

    // ---- drawing follows the board -------------------------------------------------------------
    fresh(g)
    g.setBoard(filler)
    var tv = g.tileView.itemAt(at(2, 3))
    check("a part is drawn in its cell", !!tv && tv.x === 3 * g.cell && tv.y === 2 * g.cell && tv.k === 2, tv ? tv.x + "," + tv.y : "no item")
    g.setBoard(rows(lineA))
    g.trySwap(at(6, 2), at(7, 2))
    for (i = 0; i < 12; i++) g.step(1 / 240)
    g.publish()
    tv = g.tileView.itemAt(at(7, 2))
    check("a swapped part is drawn sliding into place", tv.k === 5 && tv.y > 6 * g.cell && tv.y < 7 * g.cell, tv.y)
    settle(g)
    g.setBoard(filler)
    g.dropCells([at(7, 4)])
    g.publish()
    tv = g.tileView.itemAt(at(0, 4))
    var y0 = tv.y
    check("a new part is drawn above the board before it falls", y0 === -g.cell && tv.k === g.kinds[at(0, 4)], y0)
    for (i = 0; i < 24; i++) g.step(1 / 240)
    g.publish()
    check("the drawn part falls when the board steps", g.tileView.itemAt(at(0, 4)).y > y0, g.tileView.itemAt(at(0, 4)).y)

    // ---- difficulty curve: a greedy player (no Reroute, no aiming at fried parts) ----
    // SOLDER_CALIBRATE=1 logs its record on the first eight levels, for tuning levels.js.
    var calib = Quickshell.env("SOLDER_CALIBRATE") === "1"
    function winsAt(L, seeds) {
      var wins = 0, line = ""
      for (var sd = 1; sd <= seeds; sd++) {
        g.seed = sd * 77; g.newGame(); g.start(); g.level = L; g.loadLevel()
        playLevel(g)
        if (g.level > L) wins++
        if (calib) line += " " + (g.level > L ? "W+" + g.lastBonus / Levels.MOVE_BONUS : "L" + g.levelScore + JSON.stringify(g.goalCounts) + "f" + g.friedLeft)
      }
      if (calib) console.log("calib level " + L + " wins " + wins + "/" + seeds + ":" + line)
      return wins
    }
    if (calib) for (var L = 2; L <= 5; L++) winsAt(L, 8)
    var easy = winsAt(1, 4), hard = winsAt(6, 4)
    check("a greedy player clears Breadboard", easy >= 3, easy + "/4")
    check("Mainboard is harder than Breadboard", hard < easy, hard + " vs " + easy)
    if (calib) { winsAt(7, 8); winsAt(8, 8) }
    g.seed = 2024; g.newGame(); g.start()
    var guard = 0
    while (g.phase === "play" && guard++ < 12) playLevel(g)
    check("a whole game plays through to game over", g.phase === "over" && g.level >= 2, g.phase + " level " + g.level)


    // ---- game over and high score -----------------------------------------------------------------
    g.newGame()
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)

    g.seed = 3; g.newGame(); g.start()
    g.level = 4; g.loadLevel(); g.moves = 2; g.charges = 0; g.fluxMeter = 40; g.addScore(300)
    g.newGame()
    check("a new game clears the new-high-score flag", !g.beatHigh)
    check("new game resets everything", g.level === 1 && g.score === 0 && g.levelScore === 0 && g.moves === Levels.level(1).moves
          && g.phase === "ready" && g.charges === 1 && g.fluxMeter === 0 && g.shuffles === 0 && g.busy === "idle"
          && g.selected === -1 && g.goalCounts.length === 1 && g.goalCounts[0] === 0 && g.friedLeft === 0)

    // ---- on-screen text and color match the house conventions --------------------------------------
    fresh(g)
    g.score = 240; g.level = 3; g.beatHigh = false
    g.gameOver()
    check("game-over text reads Score N  ·  Level N with double-spaced dots, no lone 'level N' line",
          g.subtitleText.text === "Score 240  ·  Level 3\nEnter to play again  ·  Esc to quit", g.subtitleText.text)
    g.beatHigh = true
    check("a new high score is appended before the line break",
          g.subtitleText.text === "Score 240  ·  Level 3  ·  new high score!\nEnter to play again  ·  Esc to quit", g.subtitleText.text)

    g.newGame()
    check("the ready screen names start, move keys, pause and this game's own controls",
          g.subtitleText.text.indexOf("Space or click to start") === 0
          && g.subtitleText.text.indexOf("arrows/WASD move") >= 0
          && g.subtitleText.text.indexOf("P pause") >= 0
          && g.subtitleText.text.indexOf("R reroute") >= 0
          && g.subtitleText.text.indexOf("H hint") >= 0, g.subtitleText.text)

    check("the message backdrop matches the house opacity", Math.abs(g.messageBackdrop.opacity - 0.92) < 1e-6, g.messageBackdrop.opacity)

    g.theme = { bright_foreground: "#c0caf5", yellow: "#e0af68", dark_background: "#13141c" }
    check("the cascade combo text is a theme text color, not the low-contrast yellow hue",
          Qt.colorEqual(g.comboLabel.color, g.color("bright_foreground", "#c0caf5"))
          && !Qt.colorEqual(g.comboLabel.color, g.color("yellow", "#e0af68")), g.comboLabel.color)
    g.theme = {}

    fresh(g)
    g.theme = { green: "#9ece6a", bright_foreground: "#c0caf5" }
    var goalN = g.levelInfo.goals[0].n
    g.goalCounts = [0]
    var goalLabel = g.goalView.itemAt(0).label
    check("an unmet salvage goal shows plain counts with no check mark",
          goalLabel.text === "0 / " + goalN && !Qt.colorEqual(goalLabel.color, g.color("green", "#9ece6a")), goalLabel.text)
    g.goalCounts = [goalN]
    check("a met salvage goal gets a check-mark prefix, not a low-contrast green hue",
          goalLabel.text.indexOf("✓ ") === 0 && Qt.colorEqual(goalLabel.color, g.color("bright_foreground", "#c0caf5")), goalLabel.text)
    g.theme = {}
  }
}
