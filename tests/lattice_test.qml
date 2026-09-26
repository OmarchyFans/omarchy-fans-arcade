import QtQuick
import Quickshell
import Quickshell.Io
import "layouts.js" as Layouts
import "paths.js" as Paths

// Headless rules test for Lattice Siege. tests/run.sh copies games/lattice/ and
// this file into one temp folder, runs it offscreen, and reads the JSON written
// to $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
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
      if (g.phase !== "play") return
      g.step(1 / 240)
      if (until && until()) return
    }
  }
  function fresh(g, seed) { g.seed = seed || 1; g.noDives = true; g.newGame(); g.start() }
  function allFormed(g) {
    for (var i = 0; i < g.enemies.length; i++) {
      var s = g.enemies[i].state
      if (s !== "form" && s !== "dead") return false
    }
    return true
  }
  function settle(g) { run(g, 25, function () { return allFormed(g) }) }
  function find(g, pred) {
    for (var i = 0; i < g.enemies.length; i++) if (pred(g.enemies[i], i)) return i
    return -1
  }
  function shootAt(g, e) { g.shots.push({ x: e.x, y: e.y + 12, src: "ship" }) }
  function firstDive(seed) {
    g.seed = seed; g.noDives = false; g.newGame(); g.start()
    var idx = -1
    run(g, 30, function () { idx = find(g, function (e) { return e.state === "dive" }); return idx >= 0 })
    var at = g.clock
    run(g, 0.5)
    var e = g.enemies[idx] || { x: -1, y: -1 }
    return { idx: idx, at: at, x: e.x, y: e.y }
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
    var i, e, idx, before, b

    // ---- formations and schedule -------------------------------------------------
    var okRows = true
    for (var l = 0; l < Layouts.LAYOUTS.length; l++)
      for (var r = 0; r < Layouts.LAYOUTS[l].rows.length; r++)
        if (Layouts.LAYOUTS[l].rows[r].length !== Layouts.COLS || /[^.nrp]/.test(Layouts.LAYOUTS[l].rows[r])) okRows = false
    check("formations are 10 columns of known enemies", okRows)
    check("runs split into constellations of at most three",
          Layouts.chunk(8).join() === "3,3,2" && Layouts.chunk(4).join() === "2,2" && Layouts.chunk(3).join() === "3", Layouts.chunk(8).join())
    check("every fourth stage is a Monolith", Layouts.isBoss(4) && Layouts.isBoss(8) && !Layouts.isBoss(3) && !Layouts.isBoss(5))
    check("stage 5 is the fourth formation", Layouts.layoutFor(5).name === Layouts.LAYOUTS[3].name, Layouts.layoutFor(5).name)
    var offOk = true, landOk = true
    for (i = 0; i < Paths.KINDS.length; i++) {
      var p0 = Paths.point(Paths.KINDS[i], 0, 400, 120, 800, 600)
      if (p0.x >= 0 && p0.x <= 800 && p0.y >= 0) offOk = false
      var p1 = Paths.point(Paths.KINDS[i], 1, 333, 144, 800, 600)
      if (Math.abs(p1.x - 333) > 0.01 || Math.abs(p1.y - 144) > 0.01) landOk = false
    }
    check("every entry path starts off the field", offOk)
    check("every entry path ends on its slot", landOk)

    // ---- a new game --------------------------------------------------------------
    g.seed = 1; g.noDives = true; g.newGame()
    check("new game waits on the ready screen", g.phase === "ready" && g.lives === 3 && g.stage === 1, g.phase)
    check("stage 1 loads the Wedge's 20 enemies", g.enemies.length === 20, g.enemies.length)
    var sum = 0
    for (i = 0; i < g.groups.length; i++) sum += g.groups[i].size
    check("constellations cover every enemy", sum === 20 && g.groups.length === 8, sum + " in " + g.groups.length)
    g.step(0.1)
    check("nothing moves before the start", g.clock === 0 && g.enemies[0].state === "wait")
    g.start()
    check("Space starts play", g.phase === "play", g.phase)

    // ---- formation entry ---------------------------------------------------------
    run(g, 0.3)
    check("constellations fly in one after another",
          g.enemies[0].state === "enter" && g.enemies[19].state === "wait", g.enemies[0].state + "/" + g.enemies[19].state)
    settle(g)
    check("everyone locks into the lattice", allFormed(g) && g.clock < 20, g.clock)
    var slotOk = true
    for (i = 0; i < g.enemies.length; i++) {
      var sp = g.slotPos(g.enemies[i])
      if (Math.abs(sp.x - g.enemies[i].x) > 0.01 || Math.abs(sp.y - g.enemies[i].y) > 0.01) slotOk = false
    }
    check("formed enemies sit on their slots", slotOk)
    var sx0 = g.enemies[0].x, sxMin = sx0, sxMax = sx0
    run(g, 4.0, function () { sxMin = Math.min(sxMin, g.enemies[0].x); sxMax = Math.max(sxMax, g.enemies[0].x); return false })
    check("the lattice sways", sxMax - sxMin > 30, sxMax - sxMin)

    // ---- the cannon ------------------------------------------------------------------
    g.rightHeld = true; run(g, 3); g.rightHeld = false
    check("cannon stops at the right wall", g.shipX === g.fieldW - g.shipHalfW, g.shipX)
    g.leftHeld = true; run(g, 0.5); g.leftHeld = false
    check("cannon moves left", g.shipX < g.fieldW - g.shipHalfW - 150, g.shipX)
    g.shots = []; g.fireCd = 0
    check("fire makes a shot", g.fire() && g.shots.length === 1, g.shots.length)
    check("fire has a cooldown", !g.fire() && g.shots.length === 1)
    g.fireCd = 0; g.fire(); g.fireCd = 0
    check("at most two cannon shots in the air", g.shots.length === 2 && !g.fire(), g.shots.length)
    g.shots = []; g.fireCd = 0; g.fireHeld = true
    run(g, 0.02)
    g.fireHeld = false
    check("holding Space keeps firing", g.shots.length === 1, g.shots.length)
    g.shots = []

    // ---- hits and score -------------------------------------------------------------
    fresh(g); settle(g)
    idx = find(g, function (e) { return e.row === 3 && e.kind === "n" })
    e = g.enemies[idx]; before = g.score
    shootAt(g, e)
    run(g, 0.2, function () { return e.state === "dead" })
    check("a shot destroys a node", e.state === "dead" && g.shots.length === 0, e.state)
    check("a node in the lattice scores 50", g.score === before + 50, g.score - before)

    idx = find(g, function (e) { return e.kind === "p" })
    e = g.enemies[idx]; before = g.score
    shootAt(g, e)
    run(g, 0.2, function () { return e.hp < 2 })
    check("the first hit cracks a prism for 10", e.state === "form" && e.hp === 1 && g.score === before + 10, e.hp)
    shootAt(g, e)
    run(g, 0.2, function () { return e.state === "dead" })
    check("the second hit destroys it", e.state === "dead")

    idx = find(g, function (e) { return e.kind === "n" && e.state === "form" })
    e = g.enemies[idx]
    g.startDive(e, 0)
    run(g, 0.3)
    before = g.score
    g.shots.push({ x: e.x, y: e.y + 8, src: "ship" })
    run(g, 0.1, function () { return e.state === "dead" })
    check("a diver is worth double", e.state === "dead" && g.score === before + 100, g.score - before)

    // ---- dives -----------------------------------------------------------------------
    var d1 = firstDive(7), d2 = firstDive(7)
    check("the dive AI orders a dive", d1.idx >= 0 && d1.at > 0, d1.idx)
    check("same seed, same diver at the same moment", d1.idx === d2.idx && d1.at === d2.at, d1.idx + "@" + d1.at + " vs " + d2.idx + "@" + d2.at)
    check("same seed, same flight", Math.abs(d1.x - d2.x) < 1e-6 && Math.abs(d1.y - d2.y) < 1e-6)
    var diffSeed = false
    for (var sd = 11; sd < 16 && !diffSeed; sd++) {
      var d3 = firstDive(sd)
      if (d3.idx !== d1.idx || d3.at !== d1.at) diffSeed = true
    }
    check("another seed dives differently", diffSeed)

    fresh(g); settle(g)
    idx = find(g, function (e) { return e.state === "form" && e.x < 330 })
    e = g.enemies[idx]
    var startX = e.x, startY = e.y, minX = e.x, minY = e.y
    g.shieldT = 100
    g.startDive(e, 0)
    run(g, 0.7, function () { minX = Math.min(minX, e.x); minY = Math.min(minY, e.y); return false })
    check("a diver loops up and outward first", minX < startX - 15 && minY < startY - 10, (minX - startX) + "," + (minY - startY))
    run(g, 2.5)
    check("then curves down at the cannon", e.state === "return" || e.y > startY + 250, e.state + " " + e.y)
    var sawReturn = e.state === "return"
    run(g, 10, function () { if (e.state === "return") sawReturn = true; return e.state === "form" })
    check("a missed diver wraps round and returns to its slot", sawReturn && e.state === "form", e.state)

    fresh(g); settle(g)
    g.stage = 3
    var squads = 0
    g.rngState = 5
    for (i = 0; i < 40; i++) {
      for (var q = 0; q < g.enemies.length; q++) if (g.enemies[q].state === "dive") { g.enemies[q].state = "form" }
      g.orderDive()
      var n = 0
      for (q = 0; q < g.enemies.length; q++) if (g.enemies[q].state === "dive") n++
      if (n > 1) squads++
    }
    check("from stage 3 a constellation can dive as a squad", squads > 0, squads)
    for (q = 0; q < g.enemies.length; q++) g.enemies[q].state = "form"
    g.stage = 1
    for (i = 0; i < 5; i++) g.orderDive()
    n = 0
    for (q = 0; q < g.enemies.length; q++) if (g.enemies[q].state === "dive") n++
    check("stage 1 allows one diver at a time", n === Paths.maxDivers(1) && n === 1, n)

    // ---- getting hit ---------------------------------------------------------------
    fresh(g); settle(g)
    g.enemyShots.push({ x: g.shipX, y: g.shipY - 30, vx: 0, vy: 300, r: 4 })
    run(g, 0.3, function () { return !g.shipAlive })
    check("an enemy shot costs a cannon", g.lives === 2 && !g.shipAlive, g.lives)
    run(g, g.respawnTime + 0.1, function () { return g.shipAlive })
    check("the cannon comes back shielded", g.shipAlive && g.shieldT > 0 && g.shipX === g.fieldW / 2)
    g.enemyShots.push({ x: g.shipX, y: g.shipY - 30, vx: 0, vy: 300, r: 4 })
    run(g, 0.3)
    check("the shield lets shots pass", g.lives === 2 && g.shipAlive, g.lives)
    run(g, 2)
    idx = find(g, function (e) { return e.state === "form" })
    e = g.enemies[idx]
    g.startDive(e, 0)
    e.t = 1; e.x = g.shipX; e.y = g.shipY - 30; e.h = Math.PI / 2
    before = g.score
    run(g, 0.3, function () { return !g.shipAlive })
    check("a diver ramming the cannon takes both down", !g.shipAlive && e.state === "dead" && g.lives === 1 && g.score > before, g.lives)

    // ---- link snap and wing drones -----------------------------------------------------
    fresh(g); settle(g)
    var trios = []
    for (i = 0; i < g.groups.length; i++) {
      var allN = true
      for (q = 0; q < g.groups[i].members.length; q++) if (g.enemies[g.groups[i].members[q]].kind !== "n") allN = false
      if (g.groups[i].size === 3 && allN) trios.push(g.groups[i])
    }
    check("the Wedge has node trios", trios.length >= 2, trios.length)
    var slow = trios[0], fast = trios[1]
    before = g.score
    g.killEnemy(g.enemies[slow.members[0]], true)
    run(g, g.snapWindow + 0.5)
    g.killEnemy(g.enemies[slow.members[1]], true)
    g.killEnemy(g.enemies[slow.members[2]], true)
    check("a slow clear scores the plain bonus", g.score === before + 150 + 300, g.score - before)
    check("a slow clear earns no drone", !g.droneL && !g.droneR)
    before = g.score
    g.killEnemy(g.enemies[fast.members[0]], true)
    run(g, 0.5)
    g.killEnemy(g.enemies[fast.members[1]], true)
    g.killEnemy(g.enemies[fast.members[2]], true)
    check("a link snap doubles the bonus", g.score === before + 150 + 600, g.score - before)
    check("a link snap earns a wing drone", g.droneL && !g.droneR)
    var hotSeen = false
    fresh(g); settle(g)
    g.killEnemy(g.enemies[g.groups[3].members[0]], true)     // a trio: two left, still linked
    g.publish()
    for (i = 0; i < g.links.length; i++) if (g.links[i].hot) hotSeen = true
    check("a wounded constellation's link glows while a snap is on", hotSeen)
    run(g, g.snapWindow + 0.2)
    g.publish()
    hotSeen = false
    for (i = 0; i < g.links.length; i++) if (g.links[i].hot) hotSeen = true
    check("the glow ends with the snap window", !hotSeen)

    g.droneL = true; g.droneR = false; g.shots = []; g.fireCd = 0
    g.fire()
    check("a drone fires beside the cannon", g.shots.length === 2 && g.shots[1].src === "drone"
          && Math.abs(g.shots[1].x - (g.shipX - g.droneOffset)) < 0.01, g.shots.length)
    g.shots = []
    var livesB = g.lives
    g.enemyShots.push({ x: g.shipX - g.droneOffset, y: g.shipY - 30, vx: 0, vy: 300, r: 4 })
    run(g, 0.3, function () { return !g.droneL })
    check("a drone soaks a hit for the cannon", !g.droneL && g.lives === livesB && g.shipAlive)
    check("two drones at most", g.gainDrone() && g.gainDrone() && !g.gainDrone() && g.droneL && g.droneR)
    g.killShip()
    check("losing the cannon loses its drones", !g.droneL && !g.droneR)

    // Review fix: drone shots used to be unlimited, so with two drones and close
    // hits more shots flew than the 8-delegate pool could draw (invisible shots).
    fresh(g); g.droneL = true; g.droneR = true; g.shots = []
    for (i = 0; i < 20; i++) {
      for (q = g.shots.length - 1; q >= 0; q--) if (g.shots[q].src === "ship") g.shots.splice(q, 1)
      g.fireCd = 0; g.fire()
    }
    g.publish()
    shown = 0
    for (i = 0; i < g.shotView.count; i++) if (g.shotView.itemAt(i).visible) shown++
    check("every shot in the air is drawn, drones included", g.shots.length > 4 && g.shots.length <= g.maxShotsDrawn && shown === g.shots.length,
          g.shots.length + " shots, " + shown + " drawn")
    g.shots = []; g.droneL = false; g.droneR = false

    // ---- stages ---------------------------------------------------------------------
    fresh(g); settle(g)
    for (i = 0; i < g.enemies.length; i++) g.killEnemy(g.enemies[i], false)
    run(g, 0.05)
    check("clearing the lattice clears the stage", g.clearT > 0 && g.stage === 1, g.clearT)
    run(g, g.clearTime + 0.2, function () { return g.stage === 2 })
    check("the next stage loads", g.stage === 2 && g.enemies.length === 28 && g.phase === "play", g.stage + " " + g.enemies.length)
    check("aggression rises with the stage",
          Paths.diveInterval(6) < Paths.diveInterval(1) && Paths.diveSpeed(6) > Paths.diveSpeed(1)
          && Paths.maxDivers(6) > Paths.maxDivers(1) && Paths.shotSpeed(6) > Paths.shotSpeed(1)
          && Paths.formFireInterval(1) === 0 && Paths.formFireInterval(2) > 0)

    // ---- the Monolith ------------------------------------------------------------------
    g.stage = 4; g.loadStage()
    b = g.bossList[0]
    check("stage 4 is a Monolith alone", g.bossList.length === 1 && g.enemies.length === 0 && b.hp === Paths.bossHp(1) && b.plates === 4)
    b.angle = 0
    check("plates block, gaps don't",
          g.plateBlocks(b, b.x + 54, b.y) && !g.plateBlocks(b, b.x + 54 * Math.cos(Math.PI / 4), b.y + 54 * Math.sin(Math.PI / 4))
          && !g.plateBlocks(b, b.x, b.y))
    // Review fix: plates used to block by angle, so near the outer rim a shot that
    // was visibly clear of a plate's drawn edge still stopped. Now they match the drawing.
    b.angle = 0
    check("a shot just past a plate's drawn edge at the rim gets through",
          !g.plateBlocks(b, b.x + 63 * Math.cos(0.33), b.y + 63 * Math.sin(0.33)))
    check("a shot on a plate's drawn inner corner is stopped",
          g.plateBlocks(b, b.x + 48 * Math.cos(0.365), b.y + 48 * Math.sin(0.365)))
    b.spin = 0; b.angle = Math.PI / 2                       // a plate straight below the core
    var hp0 = b.hp
    g.shots = [{ x: b.x, y: b.y + g.plateOuter + 2, src: "ship" }]
    run(g, 0.06)
    check("a plate stops a shot", g.shots.length === 0 && b.hp === hp0, b.hp)
    b.angle = Math.PI / 2 + Math.PI / 4                      // a gap straight below
    before = g.score
    g.shots = [{ x: b.x, y: b.y + g.plateOuter + 2, src: "ship" }]
    run(g, 0.12, function () { return b.hp < hp0 })
    check("a shot through a gap hits the core", b.hp === hp0 - 1 && g.score === before + 20, b.hp)
    g.shieldT = 100
    var sawShots = false
    run(g, 4, function () { if (g.enemyShots.length > 0) sawShots = true; return false })
    check("the Monolith fires", sawShots)
    check("the Monolith launches diving escorts", find(g, function (e) { return e.group === -1 }) >= 0)
    b.hp = 1; b.angle = Math.PI / 2 + Math.PI / 4
    before = g.score
    g.shots = [{ x: b.x, y: b.y + g.plateOuter + 2, src: "ship" }]
    run(g, 0.12, function () { return g.bossList.length === 0 })
    check("destroying the core ends the Monolith", g.bossList.length === 0 && g.score >= before + Paths.bossBonus(1), g.score - before)
    check("its escorts go with it", g.aliveEnemies() === 0)
    run(g, g.clearTime + 0.3, function () { return g.stage === 5 })
    check("after the Monolith comes stage 5", g.stage === 5 && Layouts.stageName(5) === "Arrowheads", g.stage)

    // ---- lives and game over ---------------------------------------------------------
    fresh(g)
    g.addScore(20000)
    check("an extra cannon every 20000", g.lives === 4 && g.nextExtra === 40000, g.lives)
    fresh(g)
    g.lives = 1
    g.killShip()
    run(g, 3)
    check("losing the last cannon ends the game", g.phase === "over" && g.lives === 0, g.phase)
    check("no firing after game over", !g.fire())

    // ---- pause and focus ---------------------------------------------------------------
    fresh(g); run(g, 1)
    g.togglePause()
    var c0 = g.clock, ex = g.enemies[0].x
    g.step(1 / 60)
    check("pause freezes the game", g.phase === "paused" && g.clock === c0 && g.enemies[0].x === ex)
    g.togglePause()
    check("resume plays", g.phase === "play")
    g.leftHeld = true; g.fireHeld = true
    g.lostFocus()
    check("losing focus pauses", g.phase === "paused", g.phase)
    check("losing focus forgets held keys", !g.leftHeld && !g.rightHeld && !g.fireHeld)

    // ---- drawing follows the rules -------------------------------------------------------
    fresh(g); settle(g)
    g.publish()
    idx = find(g, function (e) { return e.state === "form" })
    var item = g.enemyView.itemAt(idx)
    check("the drawn enemy is where the enemy is", !!item && Math.abs(item.x - (g.enemies[idx].x - 16)) < 0.01 && item.visible, item ? item.x : "no item")
    g.enemies[idx].x += 40
    g.publish()
    check("the drawn enemy moves when the enemy does", Math.abs(g.enemyView.itemAt(idx).x - (g.enemies[idx].x - 16)) < 0.01, g.enemyView.itemAt(idx).x)
    g.killEnemy(g.enemies[idx], false)
    g.publish()
    check("a destroyed enemy is not drawn", !g.enemyView.itemAt(idx).visible)
    g.shots = [{ x: 300, y: 400, src: "ship" }]
    g.publish()
    check("the drawn shot is where the shot is", !!g.shotView.itemAt(0) && Math.abs(g.shotView.itemAt(0).y - 400) < 0.01)
    g.shots[0].y = 250
    g.publish()
    check("the drawn shot moves when the shot does", Math.abs(g.shotView.itemAt(0).y - 250) < 0.01, g.shotView.itemAt(0).y)
    var shown = 0
    for (i = 0; i < g.linkView.count; i++) if (g.linkView.itemAt(i).visible) shown++
    check("constellation links are drawn from their ends", g.links.length > 0 && shown === g.links.length
          && Math.abs(g.linkView.itemAt(0).x - g.links[0].x1) < 0.01, g.links.length + "/" + shown)
    check("spare shot delegates stay hidden", g.shotView.itemAt(0).visible && !g.shotView.itemAt(1).visible)
    g.stage = 4; g.loadStage(); g.publish()
    check("the drawn Monolith is where it is", !!g.bossView.itemAt(0) && Math.abs(g.bossView.itemAt(0).x - g.bossList[0].x) < 0.01)

    // ---- high score -------------------------------------------------------------------
    g.newGame()
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)
    g.droneL = true; g.stage = 3; g.lives = 1
    g.newGame()
    check("a new game clears the new-high-score flag", !g.beatHigh)
    check("new game resets", g.stage === 1 && g.lives === 3 && g.score === 0 && g.phase === "ready"
          && !g.droneL && g.enemies.length === 20 && g.bossList.length === 0 && g.shots.length === 0)
  }
}
