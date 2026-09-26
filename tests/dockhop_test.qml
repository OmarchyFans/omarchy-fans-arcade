import QtQuick
import Quickshell
import Quickshell.Io
import "lanes.js" as Lanes

// Headless rules test for Dockhop. tests/run.sh copies games/dockhop/ and this
// file into one temp folder and runs it offscreen; it writes
// {"passed": n, "failed": [..]} to $ARCADE_TEST_OUT.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }

  // Run the fixed step for `seconds` in 1/240 s steps, or until `until()` holds.
  function run(g, seconds, until) {
    var steps = Math.ceil(seconds * 240)
    for (var i = 0; i < steps; i++) {
      if (g.phase !== "play" && g.phase !== "ready") return
      g.step(1 / 240)
      if (until && until()) return
    }
  }
  function settle(g) { run(g, 0.6, function () { return !g.hopping }) }
  // A new game with every lane emptied, so each rule places exactly what it needs.
  function fresh(g) { g.newGame(7); g.objects = [] }
  function put(g, row, x, lenTiles, type) {
    var o = { row: row, x: x, len: lenTiles * g.tile, type: type }
    g.objects.push(o)
    return o
  }
  function place(g, x, row) { g.heroX = x; g.heroRow = row; g.heroY = g.rowCenter(row); g.bestRow = row }
  function near(a, b) { return Math.abs(a - b) < 0.01 }
  function rowsOf(objs, r) { var n = 0; for (var i = 0; i < objs.length; i++) if (objs[i].row === r) n++; return n }

  FloatingWindow {
    implicitWidth: 800; implicitHeight: 760
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
    var T = g.tile, i, o, s0, x0

    // ---- the warehouse --------------------------------------------------------
    var L1 = Lanes.lanesFor(1)
    var kindsOk = L1.length === 13 && L1[0].kind === "dock" && L1[5].kind === "strip" && L1[12].kind === "start"
                  && Lanes.STRIP_ROW === 5 && Lanes.START_ROW === 12
    for (i = 1; i <= 4; i++) if (L1[i].kind !== "shaft") kindsOk = false
    for (i = 6; i <= 11; i++) if (L1[i].kind !== "floor") kindsOk = false
    check("13 rows: bays, shaft 1-4, strip, floor 6-11, start", kindsOk)
    // Our own floor plan, not the classic five-and-five with five homes.
    check("four bays, set off the centre column", JSON.stringify(Lanes.DOCK_COLS) === "[2,5,9,12]" && Lanes.dockAt(7.5 * T, T, T / 2) === -1,
          JSON.stringify(Lanes.DOCK_COLS))
    var built = Lanes.build(L1, { s: 5 }, T, g.fieldW, g.margin)
    var everyLane = true
    for (i = 0; i < 13; i++) if (L1[i].dir && rowsOf(built, i) !== L1[i].count) everyLane = false
    check("every moving lane gets its objects", everyLane)
    check("the same seed builds the same lanes",
          JSON.stringify(built) === JSON.stringify(Lanes.build(L1, { s: 5 }, T, g.fieldW, g.margin))
          && JSON.stringify(built) !== JSON.stringify(Lanes.build(L1, { s: 6 }, T, g.fieldW, g.margin)))
    // Traffic never builds a lane with two objects overlapping.
    var overlapFree = true
    for (var r = 6; r <= 11; r++) {
      var xs = built.filter(function (b) { return b.row === r }).map(function (b) { return b.x + g.margin }).sort(function (a, b) { return a - b })
      for (i = 1; i < xs.length; i++) if (xs[i] - xs[i - 1] < L1[r].len * T) overlapFree = false
    }
    check("traffic objects in a lane never overlap", overlapFree)
    check("pads: on, blinking, then off, then on again",
          Lanes.padState(0) === "on" && Lanes.padState(Lanes.PAD_ON - 0.1) === "warn"
          && Lanes.padState(Lanes.PAD_ON + 0.1) === "off" && Lanes.padState(Lanes.padCycle() + 0.1) === "on")
    check("pads stay lit on shift 1 and power down from shift 2", !L1[2].pad && Lanes.lanesFor(2)[2].pad)
    check("each shift is faster, up to a cap",
          Lanes.lanesFor(3)[9].speed > L1[9].speed && Lanes.speedFactor(50) === 2.2, Lanes.lanesFor(3)[9].speed)
    check("later shifts shorten pallets and add carts",
          Lanes.lanesFor(4)[1].len === L1[1].len - 1 && Lanes.lanesFor(5)[6].count === L1[6].count + 2)

    // ---- a new game --------------------------------------------------------------
    g.newGame(7)
    check("new game waits for the first hop", g.phase === "ready" && g.lives === 3 && g.score === 0, g.phase)
    check("the bot starts mid start strip", g.heroRow === 12 && near(g.heroX, 7.5 * T), g.heroX)
    check("four empty bays and full boosts", g.dockModel.count === 4 && g.docked === 0 && g.boosts === 2 && !g.dockModel.get(0).filled)
    x0 = g.objects[0].x
    var t0 = g.timeLeft
    run(g, 0.2)
    check("traffic moves before the first hop", !near(g.objects[0].x, x0), g.objects[0].x)
    check("the clock waits for the first hop", g.timeLeft === t0, g.timeLeft)

    // ---- hopping -------------------------------------------------------------------
    fresh(g)
    check("the first hop starts play", g.hop(0, -1) && g.phase === "play" && g.hopping, g.phase)
    run(g, g.hopTime / 2)
    check("a hop glides between rows", g.hopping && g.heroY < g.rowCenter(12) - 5 && g.heroY > g.rowCenter(11) + 5, g.heroY)
    settle(g)
    check("a hop lands one row up", g.heroRow === 11 && near(g.heroY, g.rowCenter(11)) && !g.hopping, g.heroRow)
    check("a new row scores 10", g.score === 10, g.score)
    g.hop(0, 1); settle(g); g.hop(0, -1); settle(g)
    check("going back over old rows scores nothing", g.heroRow === 11 && g.score === 10, g.score)
    g.hop(0, 1); settle(g)
    check("down from the start strip is blocked", !g.hop(0, 1) && g.heroRow === 12 && !g.hopping && g.bumpT > 0, g.heroRow)
    place(g, g.colCenter(0), 12)
    check("off the left edge is blocked", !g.hop(-1, 0) && near(g.heroX, g.colCenter(0)))
    place(g, g.colCenter(14), 12)
    check("off the right edge is blocked", !g.hop(1, 0) && near(g.heroX, g.colCenter(14)))
    g.hop(-1, 0); settle(g)
    check("a sideways hop moves one tile", near(g.heroX, g.colCenter(13)) && g.heroRow === 12, g.heroX)
    g.hop(0, -1); g.hop(-1, 0)
    settle(g); settle(g)
    check("a key pressed mid-hop hops next", g.heroRow === 11 && near(g.heroX, g.colCenter(12)), g.heroRow + "," + g.heroX)

    // A buffered hop can't skip the row it lands on.
    fresh(g)
    put(g, 11, g.colCenter(7) - T / 2, 1, "tug")
    g.objects[0].len = 3 * T; g.objects[0].x = g.colCenter(7) - 1.5 * T
    g.hop(0, -1); g.hop(0, -1)
    run(g, 0.6, function () { return g.deathT > 0 })
    check("tapping ahead still crashes into traffic", g.deathCause === "hit" && g.heroRow === 11, g.deathCause)
    fresh(g); g.phase = "play"
    place(g, g.colCenter(7), Lanes.STRIP_ROW + 1)
    g.hop(0, -1); g.hop(0, -1)
    run(g, 0.6, function () { return g.deathT > 0 })
    check("tapping ahead still falls into an empty shaft", g.deathCause === "fell" && g.heroRow === Lanes.STRIP_ROW - 1, g.deathCause + " " + g.heroRow)

    // A blocked first press (down off the start strip) must not start the clock.
    fresh(g)
    var tb = g.timeLeft
    g.hop(0, 1); run(g, 0.5)
    check("a blocked first hop leaves the game waiting", g.phase === "ready" && g.timeLeft === tb, g.phase + " " + g.timeLeft)

    // ---- traffic -------------------------------------------------------------------
    fresh(g); g.phase = "play"
    place(g, g.colCenter(7), 11)
    put(g, 11, g.colCenter(7) - T / 2, 1, "cart")
    g.step(1 / 240)
    check("a cart on the bot crashes it", g.deathT > 0 && g.deathCause === "hit" && g.lives === 2, g.deathCause)
    check("hops are ignored while crashed", !g.hop(0, -1))
    g.timeLeft = 3
    run(g, g.deathTime + 0.05)
    check("after a crash a new bot starts with a full clock",
          g.deathT === 0 && g.heroRow === 12 && near(g.heroX, g.startX()) && g.timeLeft > g.timeLimit() - 0.1, g.timeLeft)

    fresh(g); g.phase = "play"
    place(g, g.colCenter(7), 8)                     // forklifts drive right
    put(g, 8, g.colCenter(7) - 3 * T, 1, "forklift")
    run(g, 0.2)
    check("a forklift two tiles off hasn't hit yet", g.deathT === 0)
    run(g, 2, function () { return g.deathT > 0 })
    check("a forklift driving into the bot crashes it", g.deathCause === "hit" && g.lives === 2, g.deathCause)

    // Boost: two tiles, sailing over the lane between.
    fresh(g)
    put(g, 11, g.colCenter(7) - T / 2, 1, "cart")
    g.objects[0].x = g.colCenter(7) - T / 2
    check("boost leaps two rows", g.boost() && g.hopping && g.hopToRow === 10, g.hopToRow)
    settle(g)
    check("a boost sails over traffic in between", g.heroRow === 10 && g.deathT === 0 && g.lives === 3, g.deathCause)
    check("a boost spends a charge and scores both rows", g.boosts === 1 && g.score === 20, g.boosts + " " + g.score)
    g.boost(); settle(g)
    check("no charges, no boost", g.boosts === 0 && !g.boost() && !g.hopping, g.boosts)
    run(g, g.boostRecharge * 0.9)
    check("a charge isn't back early", g.boosts === 0, g.boosts)
    run(g, g.boostRecharge * 0.2)
    check("a charge comes back after a while", g.boosts === 1, g.boosts)

    // ---- the drop shaft ------------------------------------------------------------
    fresh(g); g.phase = "play"
    place(g, g.colCenter(7), 4)
    g.step(1 / 240)
    check("the shaft with nothing underfoot swallows the bot", g.deathCause === "fell" && g.lives === 2, g.deathCause)

    fresh(g); g.phase = "play"
    place(g, g.colCenter(7), 3)                     // row 3 drifts left
    put(g, 3, g.colCenter(7) - T, 2, "pallet")
    x0 = g.heroX
    run(g, 0.5)
    check("a pallet carries the bot along", g.deathT === 0 && g.lane(3).dir === -1 && near(x0 - g.heroX, g.laneSpeedPx(3) * 0.5), g.heroX - x0)
    check("the bot rides exactly with its pallet", near(g.heroX - g.objects[0].x, T), g.heroX - g.objects[0].x)
    x0 = g.heroX
    g.hop(0, -1)
    check("a hop off a pallet keeps its drift (no grid snap)",
          near(g.hopToX, x0) && !near(g.hopToX, g.colCenter(g.colOf(x0))), g.hopToX)
    settle(g)
    check("with nothing on the next row the bot falls", g.deathCause === "fell", g.deathCause)

    fresh(g); g.phase = "play"
    place(g, g.fieldW - 10, 4)
    put(g, 4, g.fieldW - 10 - T, 3, "pad")          // row 4 drifts right
    run(g, 1, function () { return g.deathT > 0 })
    check("a pallet carries the bot off the edge", g.deathCause === "swept", g.deathCause)

    fresh(g); g.phase = "play"
    g.level = 2; g.lanes = Lanes.lanesFor(2)
    place(g, g.colCenter(7), 2)
    put(g, 2, g.colCenter(7) - T, 3, "pad")
    g.padClock = Lanes.PAD_ON - 0.5 - g.lane(2).padOffset
    g.step(1 / 240)
    check("a blinking pad still holds the bot", g.padStateOf(2) === "warn" && g.deathT === 0, g.padStateOf(2))
    run(g, 1, function () { return g.deathT > 0 })
    check("a pad that powers down drops the bot", g.deathCause === "fell" && g.padStateOf(2) === "off", g.padStateOf(2))

    // ---- dock bays -----------------------------------------------------------------
    var bc = function (i) { return g.dockModel.get(i).col }
    fresh(g); g.phase = "play"
    place(g, g.colCenter(bc(1)), 1)
    put(g, 1, g.colCenter(bc(1)) - T, 3, "pallet")
    s0 = g.score
    var tl = g.timeLeft
    g.hop(0, -1); settle(g)
    check("an aligned hop parks in the bay", g.dockModel.get(1).filled && g.docked === 1, g.docked)
    // Full clock (30 s) less one hop: 29 whole seconds are left.
    check("parking scores the row, the bay and the whole seconds left",
          g.score - s0 === g.rowPoints + g.dockPoints + g.secondPoints * Math.floor(tl - g.hopTime), g.score - s0)
    check("after parking a new bot starts", g.heroRow === 12 && g.timeLeft === g.timeLimit() && g.lives === 3, g.heroRow)

    place(g, g.colCenter(bc(1)), 1)
    g.objects[0].x = g.colCenter(bc(1)) - T
    check("a taken bay is shut", !g.hop(0, -1) && g.heroRow === 1, g.heroRow)
    place(g, g.colCenter(7), 1)
    g.objects[0].x = g.colCenter(7) - T
    check("the wall between bays is shut", !g.hop(0, -1) && g.heroRow === 1)
    place(g, g.colCenter(bc(2)) + 0.4 * T, 1)
    g.objects[0].x = g.heroX - T
    g.hop(0, -1)
    check("a drifted bot still parks in a bay it overlaps, centered", g.hopToRow === 0 && near(g.hopToX, g.colCenter(bc(2))), g.hopToX)
    settle(g)

    // Less than a whole second left: the bay pays no seconds bonus.
    place(g, g.colCenter(bc(3)), 1)
    g.objects[0].x = g.heroX - T
    g.timeLeft = 0.5
    s0 = g.score
    g.hop(0, -1); settle(g)
    check("a part second on the clock pays nothing extra", g.dockModel.get(3).filled && g.score - s0 === g.rowPoints + g.dockPoints, g.score - s0)
    g.dockModel.setProperty(3, "filled", false); g.docked = 2

    // Boost into a bay from two rows out.
    place(g, g.colCenter(bc(3)), 2)
    put(g, 2, g.colCenter(bc(3)) - T, 3, "pallet")
    g.facing = "up"
    g.boost(); settle(g)
    check("a boost can reach a bay from two rows out", g.dockModel.get(3).filled && g.docked === 3, g.docked)

    // A boost into the wall becomes a one-row hop.
    place(g, g.colCenter(7), 2)
    put(g, 1, g.colCenter(7) - T, 3, "pallet")
    put(g, 2, g.colCenter(7) - T, 3, "pallet")
    g.facing = "up"; g.boosts = 2
    g.boost()
    check("a boost at the wall stops a row short", g.hopToRow === 1, g.hopToRow)
    settle(g)

    // The last bay clears the shift.
    g.objects = []
    var livesBefore = g.lives
    place(g, g.colCenter(bc(0)), 1)
    put(g, 1, g.heroX - T, 3, "pallet")
    g.hop(0, -1); settle(g)
    check("four bays clear the shift", g.docked === 4 && g.clearT > 0, g.docked)
    check("a shift clear gives a life back", g.lives === livesBefore + 1, g.lives)
    var speed1 = g.lane(9).speed
    run(g, g.clearTime + 0.05)
    check("the next shift loads with empty bays", g.level === 2 && g.docked === 0 && !g.dockModel.get(0).filled && g.phase === "ready", g.level)
    check("the next shift is faster", g.lane(9).speed > speed1, g.lane(9).speed)
    check("the next shift is shorter on the clock", g.timeLimit() < Lanes.timeLimit(1), g.timeLimit())

    // ---- the clock -------------------------------------------------------------------
    fresh(g)
    g.hop(1, 0); settle(g)
    run(g, g.timeLimit() - 0.5)
    check("time left runs down while playing", g.deathT === 0 && g.timeLeft > 0 && g.timeLeft < 1, g.timeLeft)
    run(g, 1, function () { return g.deathT > 0 })
    check("running out of time costs a life", g.deathCause === "time" && g.lives === 2, g.deathCause)

    // ---- pause and focus -------------------------------------------------------------
    fresh(g)
    g.objects = Lanes.build(g.lanes, { s: 3 }, T, g.fieldW, g.margin)
    g.hop(1, 0); settle(g)
    g.togglePause()
    x0 = g.objects[0].x; t0 = g.timeLeft
    check("paused: hops are ignored", g.phase === "paused" && !g.hop(0, -1))
    g.step(1 / 60)
    check("paused: the clock and the traffic hold", g.timeLeft === t0 && g.objects[0].x === x0, g.timeLeft)
    g.togglePause()
    check("P again resumes", g.phase === "play")
    g.hop(0, -1); g.hop(1, 0)
    var hadQueue = g.hopping && g.queued !== null
    g.lostFocus()
    check("losing focus pauses", g.phase === "paused", g.phase)
    check("losing focus drops the buffered hop", hadQueue && g.queued === null, hadQueue)

    // ---- parcels ---------------------------------------------------------------------
    fresh(g); g.phase = "play"
    place(g, g.colCenter(0), 12)
    run(g, g.parcelT + 0.05)
    check("a parcel turns up on the strip", g.parcelCol >= 1 && g.parcelCol <= 13, g.parcelCol)
    place(g, g.colCenter(g.parcelCol), Lanes.STRIP_ROW + 1)
    g.hop(0, -1); settle(g)
    check("hopping onto the parcel picks it up", g.carrying && g.parcelCol === -1, g.parcelCol)
    place(g, g.colCenter(bc(0)), 1)
    put(g, 1, g.colCenter(bc(0)) - T, 3, "pallet")
    s0 = g.score
    g.hop(0, -1); settle(g)
    check("a delivered parcel scores its bonus", g.score - s0 >= g.parcelPoints + g.dockPoints && g.dockModel.get(0).parcel && !g.dockModel.get(1).parcel && !g.carrying, g.score - s0)
    g.carrying = true
    place(g, g.colCenter(3), 4)
    g.step(1 / 240)
    check("a crash loses the parcel", g.deathT > 0 && !g.carrying)

    // ---- drawing follows the model -----------------------------------------------------
    fresh(g)
    put(g, 8, 222, 1, "forklift")
    put(g, 3, 400, 4, "pallet")
    g.publish()
    var v0 = g.objView.itemAt(0), v1 = g.objView.itemAt(1)
    check("a drawn forklift is where its model is", !!v0 && near(v0.x, 222) && near(v0.y, g.rowTop(8)), v0 ? v0.x : "no item")
    check("a drawn pallet is as long as its model", !!v1 && near(v1.width, 4 * T) && near(v1.y, g.rowTop(3)), v1 ? v1.width : "no item")
    g.objects[0].x = 333
    g.publish()
    check("the drawn forklift moves when its model does", near(g.objView.itemAt(0).x, 333), g.objView.itemAt(0).x)
    g.heroX = g.colCenter(3)
    check("the drawn bot is where the bot is", near(g.heroItem.x, g.colCenter(3) - T / 2) && near(g.heroItem.y, g.rowCenter(12) - T / 2), g.heroItem.x)
    g.hop(0, -1); run(g, g.hopTime / 2)
    check("the drawn bot moves mid-hop", g.heroItem.y < g.rowCenter(12) - T / 2 - 5, g.heroItem.y)

    // ---- game over, reset and the high score -------------------------------------------
    fresh(g); g.phase = "play"
    g.lives = 1
    place(g, g.colCenter(7), 4)
    run(g, g.deathTime + 0.2)
    check("losing the last bot ends the game", g.phase === "over" && g.lives === 0, g.phase)
    check("no hops after game over", !g.hop(0, -1) && !g.boost())

    g.newGame(7)
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)
    g.level = 4; g.carrying = true; g.boosts = 0; g.dockModel.setProperty(0, "filled", true); g.docked = 1
    g.newGame(7)
    check("a new game resets everything",
          g.level === 1 && g.lives === 3 && g.score === 0 && g.phase === "ready" && !g.beatHigh && !g.carrying
          && g.boosts === 2 && g.docked === 0 && !g.dockModel.get(0).filled && g.highScore === 510)
  }
}
