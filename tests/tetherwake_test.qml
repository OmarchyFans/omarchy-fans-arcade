import QtQuick
import Quickshell
import Quickshell.Io
import "space.js" as Space

// Headless rules test for Tetherwake. tests/run.sh copies games/tetherwake/ and
// this file into one temp folder, runs it offscreen, and reads the JSON it
// writes to $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
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
      if (g.phase !== "play" && g.phase !== "ready") return
      g.step(1 / 240)
      if (until && until()) return
    }
  }
  function near(a, b, eps) { return Math.abs(a - b) < (eps === undefined ? 0.01 : eps) }
  function speed(o) { return Math.hypot(o.vx, o.vy) }
  function shipSpeed(g) { return Math.hypot(g.shipVx, g.shipVy) }
  // An empty field in play: no hazards, no storms, no carrier, and the wave
  // can't clear (interT holds the next wave off).
  function empty(g) {
    g.debris = []; g.mines = []; g.bullets = []; g.bolts = []; g.carriers = []
    g.sparks = []; g.blasts = []; g.popups = []
    g.interT = 999; g.stormT = -1; g.storm = ""; g.carrierT = -1
  }
  function fresh(g) { g.newGame(42); g.start(); g.invuln = 0; empty(g) }
  function positions(g) {
    var s = []
    for (var i = 0; i < g.debris.length; i++) s.push(g.debris[i].x.toFixed(2) + "," + g.debris[i].y.toFixed(2))
    return s.join(";")
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
    var d, d2, m, m2, c, i, before, s0

    // ---- a new game ------------------------------------------------------------
    g.newGame(7)
    check("new game waits in ready", g.phase === "ready", g.phase)
    check("the ready screen names every move key, not just the arrows",
          g.subtitleText.text.indexOf("A/D") >= 0 && g.subtitleText.text.indexOf("W") >= 0
          && g.subtitleText.text.indexOf(" or S casts the tether") >= 0, g.subtitleText.text)
    check("three skiffs, wave 1, no score", g.lives === 3 && g.wave === 1 && g.score === 0, g.lives + "/" + g.wave + "/" + g.score)
    check("wave 1 is three slabs and no mines", g.debris.length === 3 && g.mines.length === 0
          && g.debris.every(function (x) { return x.size === 3 }), g.debris.length + "/" + g.mines.length)
    var safe = true
    for (i = 0; i < g.debris.length; i++) if (g.dist(g.debris[i].x, g.debris[i].y, g.shipX, g.shipY) < g.safeSpawn) safe = false
    check("wave debris spawns clear of the skiff", safe)
    var p7 = positions(g)
    g.newGame(7)
    var p7b = positions(g)
    g.newGame(8)
    check("the same seed lays out the same wave", p7 === p7b, p7 + " vs " + p7b)
    check("another seed lays it out differently", positions(g) !== p7)
    g.start()
    check("start plays, briefly shielded", g.phase === "play" && g.invuln > 0, g.phase)
    check("the opening banner is Title case", g.banner === "Wave 1", g.banner)

    // ---- flying ------------------------------------------------------------------
    fresh(g)
    g.rightHeld = true; run(g, 0.5); g.rightHeld = false
    check("right turns clockwise at the turn rate", near(g.shipA, g.turnRate * 0.5, 0.02), g.shipA)
    g.leftHeld = true; run(g, 0.5); g.leftHeld = false
    check("left turns back", near(g.shipA, 0, 0.02), g.shipA)

    g.shipA = 0; g.shipVx = 0; g.shipVy = 0
    g.thrustHeld = true; run(g, 0.5); g.thrustHeld = false
    check("thrust accelerates along the heading", g.shipVy < -100 && Math.abs(g.shipVx) < 1e-6, g.shipVx + "," + g.shipVy)
    s0 = shipSpeed(g)
    var y0 = g.shipY
    run(g, 0.5)
    check("with thrust off the skiff coasts", shipSpeed(g) > 0.8 * s0 && shipSpeed(g) < s0 && g.shipY !== y0, shipSpeed(g) + " of " + s0)
    g.thrustHeld = true; run(g, 5); g.thrustHeld = false
    check("speed is capped", near(shipSpeed(g), g.maxSpeed, 1), shipSpeed(g))

    g.shipX = 799; g.shipY = 300; g.shipVx = 200; g.shipVy = 0
    run(g, 0.02)
    check("the skiff wraps off the right edge", g.shipX < 10, g.shipX)
    g.shipX = 400; g.shipY = 1; g.shipVx = 0; g.shipVy = -200
    run(g, 0.02)
    check("the skiff wraps off the top edge", g.shipY > 590, g.shipY)

    // ---- bullets -------------------------------------------------------------------
    fresh(g)
    g.shipVx = 100; g.shipVy = 0; g.shipA = 0
    g.fire()
    var b = g.bullets[0]
    check("a shot inherits the skiff's velocity", !!b && near(b.vx, 100) && near(b.vy, -g.bulletSpeed), b ? b.vx + "," + b.vy : "none")
    g.shipVx = 0
    run(g, 0.8)
    check("a shot lives out its lifetime", g.bullets.length === 1, g.bullets.length)
    run(g, 0.2)
    check("then it's gone", g.bullets.length === 0, g.bullets.length)
    for (i = 0; i < 8; i++) g.fire()
    check("at most five shots at once", g.bullets.length === g.maxBullets, g.bullets.length)
    g.bullets = [{ x: 798, y: 100, vx: 400, vy: 0, life: 1, dead: false }]
    run(g, 0.02)
    check("shots wrap too", g.bullets.length === 1 && g.bullets[0].x < 10, g.bullets.length ? g.bullets[0].x : "none")

    fresh(g)
    d = g.makeDebris(3, 400, 150, 0, 0)
    before = g.score
    g.fire()
    run(g, 1, function () { return g.debris.length !== 1 })
    check("a shot shatters a slab into two plates", g.debris.length === 2
          && g.debris.every(function (x) { return x.size === 2 }), g.debris.length)
    check("a slab scores 20", g.score === before + 20, g.score - before)
    check("the shot is spent", g.bullets.length === 0, g.bullets.length)
    var a1 = Math.atan2(g.debris[0].vy, g.debris[0].vx), a2 = Math.atan2(g.debris[1].vy, g.debris[1].vx)
    check("the plates fly apart", Math.abs(g.normAngle(a1 - a2)) > 0.5, a1 + " / " + a2)

    empty(g)
    g.makeDebris(1, 400, 200, 0, 0)
    before = g.score
    g.fire()
    run(g, 1, function () { return g.debris.length === 0 })
    check("a shard is destroyed for 100", g.debris.length === 0 && g.score === before + 100, g.score - before)

    // ---- mines ---------------------------------------------------------------------
    fresh(g)
    m = g.makeMine(400, 60, 0, 0)                  // 240 from the skiff
    run(g, 1)
    check("a distant mine stays asleep", !m.armed && speed(m) <= 30.01, speed(m))
    empty(g)
    m = g.makeMine(400, 150, 0, 0)                 // 150 from the skiff
    var dm = g.dist(m.x, m.y, g.shipX, g.shipY)
    run(g, 0.3)
    check("a close mine arms and homes in", m.armed && g.dist(m.x, m.y, g.shipX, g.shipY) < dm - 3, g.dist(m.x, m.y, g.shipX, g.shipY))
    run(g, 2, function () { return !g.shipAlive })
    check("a mine that reaches the skiff costs a life", !g.shipAlive && g.lives === 2, g.lives)

    fresh(g)
    m = g.makeMine(100, 100, 0, 0)
    m2 = g.makeMine(140, 100, 0, 0)
    g.makeDebris(1, 100, 130, 0, 0)
    before = g.score
    g.explodeMine(m, 1)
    g.step(1 / 240)
    check("a blast sets off nearby mines and shatters debris", g.mines.length === 0 && g.debris.length === 0, g.mines.length + "/" + g.debris.length)
    check("each piece of the chain scores", g.score === before + 150 + 150 + 100, g.score - before)

    // ---- lives, respawn, game over ----------------------------------------------------
    fresh(g)
    g.makeDebris(3, 400, 300, 0, 0)
    g.step(1 / 240)
    check("hitting debris costs a life", !g.shipAlive && g.lives === 2, g.lives)
    g.debris = []
    run(g, g.respawnDelay - 0.2)
    check("the skiff waits before it respawns", !g.shipAlive)
    run(g, 0.3)
    check("then respawns in the middle, shielded", g.shipAlive && near(g.shipX, 400) && near(g.shipY, 300) && g.invuln > 2, g.invuln)
    g.makeDebris(3, 400, 300, 0, 0)
    run(g, 0.2)
    check("while shielded, debris doesn't hurt", g.shipAlive && g.lives === 2, g.lives)
    g.debris = []
    before = g.score
    g.makeMine(405, 300, 0, 0)
    g.step(1 / 240)
    check("a shielded skiff sets a mine off harmlessly, for no points", g.mines.length === 0 && g.shipAlive && g.score === before, g.mines.length)

    fresh(g)
    g.lives = 1
    g.makeDebris(3, 400, 300, 0, 0)
    g.step(1 / 240)
    g.debris = []
    run(g, g.respawnDelay + 0.1)
    check("losing the last skiff ends the game", g.phase === "over" && g.lives === 0, g.phase)
    g.score = 500
    check("the game-over score line uses double-spaced separators, not a bare dot",
          g.subtitleText.text.indexOf("Score 500  ·  Wave " + g.wave) === 0, g.subtitleText.text)

    // House rule: Enter (or a click) on GAME OVER starts a new game and lands on
    // the ready screen, not straight into play; a click on ready then starts play.
    g.keyDown(Qt.Key_Return)
    check("Enter on game over goes to ready, not play", g.phase === "ready" && g.score === 0, g.phase)

    fresh(g)
    g.lives = 1; g.makeDebris(3, 400, 300, 0, 0); g.step(1 / 240); g.debris = []
    run(g, g.respawnDelay + 0.1)
    g.score = 500
    g.fieldClicked()
    check("a click on game over also starts a new game", g.phase === "ready" && g.score === 0, g.phase)
    g.fieldClicked()
    check("a click on the ready screen starts play", g.phase === "play", g.phase)

    fresh(g)
    g.addScore(9990)
    var lv = g.lives
    g.addScore(20)
    check("an extra skiff every 10000", g.lives === lv + 1 && g.nextLifeAt === 20000, g.lives)

    // ---- waves ------------------------------------------------------------------------
    fresh(g)
    g.interT = 0
    g.makeDebris(1, 400, 200, 0, 0)
    before = g.score
    g.fire()
    run(g, 1, function () { return g.interT > 0 })
    check("clearing the field ends the wave with a bonus", g.interT > 0 && g.score === before + 100 + 250, g.score - before)
    check("the wave-clear banner is Title case", g.banner === "Wave 1 clear  +250", g.banner)
    run(g, g.waveDelay + 0.1)
    check("the next wave brings more debris and a mine", g.wave === 2 && g.debris.length === 4 && g.mines.length === 1,
          g.wave + ": " + g.debris.length + "/" + g.mines.length)
    check("the new-wave banner is Title case", g.banner === "Wave 2", g.banner)
    var w1 = Space.wave(1), w3 = Space.wave(3), w4 = Space.wave(4), w8 = Space.wave(8)
    check("waves get harder", w8.debris > w1.debris && w8.mines > w1.mines && w8.speed > w1.speed && w8.carrierFire < w4.carrierFire)
    check("storms from wave 3, the carrier from wave 4", !w1.storms && w3.storms && !w3.carrier && w4.carrier)

    // A wave that clears while the skiff is dead must still lay out the next
    // one clear of the centre it will respawn at, not clear of wherever the
    // skiff happened to die.
    fresh(g)
    g.shipAlive = false
    g.shipX = 40; g.shipY = 40
    var sawNearCentre = false
    for (i = 0; i < 200; i++) {
      var fp = g.freeSpot()
      if (g.dist(fp.x, fp.y, g.fieldW / 2, g.fieldH / 2) < g.safeSpawn) sawNearCentre = true
    }
    check("hazards for the next wave spawn clear of the respawn point even while the skiff is dead", !sawNearCentre)

    // ---- ion gusts ----------------------------------------------------------------------
    fresh(g)
    g.stormT = 0.001
    run(g, 0.01)
    check("a gust is announced first", g.storm === "warn" && near(Math.hypot(g.windX, g.windY), 1, 1e-6), g.storm)
    g.shipVx = 0; g.shipVy = 0
    run(g, g.stormWarn - 0.05)
    check("the warning doesn't push", shipSpeed(g) < 0.5, shipSpeed(g))
    run(g, 1.05)
    var along = (g.shipVx * g.windX + g.shipVy * g.windY) / Math.max(1e-6, shipSpeed(g))
    check("the gust shoves the skiff downwind", g.storm === "gust" && shipSpeed(g) > 30 && along > 0.99, shipSpeed(g) + " / " + along)
    run(g, g.stormGust)
    check("and blows over", g.storm === "" && g.stormT > 5, g.storm)

    // ---- the carrier ----------------------------------------------------------------
    fresh(g)
    g.wave = 4
    g.carrierT = 0.01
    run(g, 0.05)
    check("the carrier arrives on schedule", g.carriers.length === 1 && g.carriers[0].hp === Space.wave(4).carrierHp, g.carriers.length)
    c = g.carriers[0]
    c.x = 300; c.baseY = 150; c.fireT = 0.005; c.mineT = 99
    run(g, 0.02)
    var bolt = g.bolts[0]
    var aim = bolt ? ((bolt.vx * g.dx(bolt.x, g.shipX) + bolt.vy * g.dy(bolt.y, g.shipY))
                      / (speed(bolt) * g.dist(bolt.x, bolt.y, g.shipX, g.shipY))) : 0
    check("the carrier fires at the skiff", !!bolt && aim > 0.98, aim)
    g.bolts = []
    c.mineT = 0.005
    before = g.mines.length
    run(g, 0.02)
    check("the carrier lays mines", g.mines.length === before + 1, before + " -> " + g.mines.length + " armed " + (g.mines[0] && g.mines[0].armed))
    g.mines = []
    var hp = c.hp
    g.bullets = [{ x: c.x, y: c.y, vx: 0, vy: 0, life: 1, dead: false }]
    g.step(1 / 240)
    check("a shot dents the carrier", c.hp === hp - 1 && g.bullets.length === 0, c.hp)
    before = g.score
    c.hp = 1
    g.bullets = [{ x: c.x, y: c.y, vx: 0, vy: 0, life: 1, dead: false }]
    g.step(1 / 240)
    check("sinking the carrier scores 1500", g.carriers.length === 0 && g.score === before + 1500, g.score - before)

    // ---- the tether ------------------------------------------------------------------
    fresh(g)
    g.tetherAction()
    check("Shift casts the grapple", g.tether === "cast")
    run(g, 0.6)
    check("a grapple that catches nothing reels in", g.tether === "idle" && g.tetherCd > 0, g.tether)
    g.tetherAction()
    check("and can't be recast until it's reeled", g.tether === "idle")
    run(g, g.tetherCooldown)
    g.tetherAction()
    check("then it can", g.tether === "cast")

    fresh(g)
    d = g.makeDebris(2, 400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    check("the grapple latches onto debris", g.tether === "tow" && g.towed === d && d.towed, g.tether)
    before = g.score
    g.bullets = [{ x: d.x, y: d.y, vx: 0, vy: 0, life: 0.2, dead: false }]
    g.step(1 / 240)
    check("shots pass through the towed load", g.debris.length === 1 && g.bullets.length === 1 && g.score === before)
    g.bullets = []
    g.shipVx = 0; g.shipVy = 220
    run(g, 1.2)
    var gap = g.dist(g.shipX, g.shipY, d.x, d.y)
    check("the load follows on the line", g.tether === "tow" && gap < g.ropeLen + 40 && d.vy > 40, gap + " / " + d.vy)

    // A towed load drags the skiff: the same push, with and without it.
    fresh(g)
    g.shipVy = 220
    run(g, 1)
    var free = g.shipVy
    fresh(g)
    d = g.makeDebris(3, 400, 210, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    g.shipVy = 220
    run(g, 1)
    check("a heavy slab drags the skiff", g.tether === "tow" && g.shipVy < free - 20, g.shipVy + " vs " + free)

    // Ramming with the towed load: the target breaks for double points.
    fresh(g)
    d = g.makeDebris(2, 400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    before = g.score
    d2 = g.makeDebris(1, d.x + d.r + 5, d.y, 0, 0)
    g.step(1 / 240)
    check("the towed load smashes what it hits, double points", d2.dead && g.score === before + 200, g.score - before)
    check("ramming wears the load down", d.hp === 1 && g.tether === "tow", d.hp)

    // Letting go flings it: faster, and a triple-point ram for a moment.
    d.vx = 0; d.vy = -60
    g.tetherAction()
    check("casting again flings the load", g.tether === "idle" && !d.towed && d.flung > 0 && speed(d) >= 120 - 1e-6, speed(d))
    before = g.score
    d2 = g.makeDebris(1, d.x, d.y - d.r - 5, 0, 0)
    g.step(1 / 240)
    check("a flung load scores triple", d2.dead && g.score >= before + 300, g.score - before)
    check("a worn-out load breaks up on its last ram, triple too", d.dead && g.score === before + 300 + 150, g.score - before)
    fresh(g)
    d = g.makeDebris(2, 400, 300, 0, -150)
    d.flung = 1
    g.step(1 / 240)
    check("a flung load doesn't hurt the skiff", g.shipAlive && g.lives === 3, g.lives)
    run(g, 1.1)
    check("the fling wears off", d.flung === 0, d.flung)

    // The line runs out, or snaps when stretched too far.
    fresh(g)
    d = g.makeDebris(2, 400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    g.towLeft = 0.002
    g.step(1 / 240)
    check("the line runs out and drops the load, no fling", g.tether === "idle" && !d.towed && d.flung === 0, g.tether)
    empty(g)
    d = g.makeDebris(2, 400, 200, 0, 0)
    g.tetherCd = 0
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    d.y = g.shipY - g.ropeSnap - 20
    g.step(1 / 240)
    check("an overstretched line snaps", g.tether === "idle" && !d.towed, g.tether)

    // A towed mine is disarmed, and goes off on the first thing it hits.
    fresh(g)
    m = g.makeMine(400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    check("a mine can be towed, disarmed", g.towed === m && !m.armed)
    run(g, 0.3)
    check("a towed mine doesn't home", !m.armed && g.shipAlive)
    before = g.score
    g.shipVx = 0; g.shipVy = 0
    d2 = g.makeDebris(1, m.x, m.y - 14, 0, 0)
    g.step(1 / 240)
    check("a towed mine rams and goes off, double points", d2.dead && m.dead && g.tether === "idle" && g.score === before + 200 + 300,
          g.score - before)

    // A flung mine stays disarmed while it flies and can't hurt the skiff.
    fresh(g)
    m = g.makeMine(400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    m.vx = 0; m.vy = -60
    g.tetherAction()
    run(g, 0.3)
    check("a flung mine doesn't re-arm and home back", !m.armed && m.vy < -100, m.armed + " / " + m.vy)
    empty(g)
    m = g.makeMine(400, 300, 0, 0)
    m.flung = 1
    g.step(1 / 240)
    check("a flung mine passing the skiff doesn't hurt it", g.shipAlive && !m.dead && g.lives === 3, g.lives)

    // A mine dropped off the line (line ran out or snapped) sits well within
    // arming range of the skiff that just let go of it; it needs a beat
    // before it can re-arm, or it homes in from point-blank range at once.
    fresh(g)
    m = g.makeMine(400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    check("towing pulls the mine well inside its own arming range", g.tether === "tow"
          && g.dist(m.x, m.y, g.shipX, g.shipY) < g.mineArmRange, g.dist(m.x, m.y, g.shipX, g.shipY))
    g.towLeft = 0.002
    g.step(1 / 240)
    check("the line running out drops the mine without re-arming it at once",
          g.tether === "idle" && !m.towed && !m.armed, m.armed)
    run(g, g.mineDropGrace - 0.05)
    check("it stays disarmed through the grace period", !m.armed, m.armed)
    run(g, 0.1)
    check("and re-arms once the grace period passes, still in range", m.armed, m.armed)

    // A snapped line drops the mine through the very same tetherIdle() cleanup
    // (a snap can leave the mine outside arming range for a while, so drive
    // the shared cleanup directly to prove the grace applies there too).
    fresh(g)
    m = g.makeMine(g.shipX + 60, g.shipY, 0, 0)   // inside arming range
    g.towed = m; m.towed = true; g.tether = "tow"
    g.tetherIdle()
    check("the snap path (tetherIdle) also arms the mine's grace instead of leaving it live",
          !m.towed && !m.armed && m.armGrace > 0, m.armGrace)
    run(g, 0.05)
    check("...so it stays disarmed right after, even well within range", !m.armed, m.armed)

    // A towed or flung mine is on the skiff's own side: its blast must not
    // kill the skiff that was towing or just flung it, even point-blank.
    fresh(g)
    m = g.makeMine(g.shipX + 40, g.shipY, 0, 0)     // well inside blastR + shipR of the skiff
    m.flung = 1
    g.explodeMine(m, 3)
    check("a flung mine's own blast doesn't kill the skiff that released it",
          g.shipAlive && g.lives === 3, g.lives)
    fresh(g)
    m = g.makeMine(g.shipX + 40, g.shipY, 0, 0)
    m.towed = true
    g.explodeMine(m, 2)
    check("a towed mine's own blast doesn't kill the skiff towing it either",
          g.shipAlive && g.lives === 3, g.lives)
    fresh(g)
    m = g.makeMine(g.shipX + 40, g.shipY, 0, 0)
    g.explodeMine(m, 1)
    check("an ordinary mine's blast still kills the skiff up close",
          !g.shipAlive && g.lives === 2, g.lives)

    // The carrier doesn't wrap, so neither do its hits.
    fresh(g)
    g.carriers = [{ x: -40, y: 300, baseY: 300, vx: 70, t: 0, hp: 6, maxHp: 6, fireT: 99, mineT: 99, flash: 0, dead: false }]
    g.shipX = 785; g.shipY = 300
    g.step(1 / 240)
    check("a carrier off the left edge can't ram a skiff on the right edge", g.shipAlive && g.lives === 3, g.lives)
    g.shipX = 400
    g.bullets = [{ x: 782, y: 300, vx: 0, vy: 0, life: 1, dead: false }]
    g.step(1 / 240)
    check("nor can a shot on the right edge hit it", g.carriers.length === 1 && g.carriers[0].hp === 6 && g.bullets.length === 1,
          g.carriers.length ? g.carriers[0].hp : "gone")

    // A wave with a carrier still due doesn't clear early.
    fresh(g)
    g.interT = 0; g.wave = 4; g.carrierT = 5
    g.step(1 / 240)
    check("the wave waits for its carrier", g.interT === 0 && g.carrierT > 0 && g.wave === 4, g.interT + " / " + g.carrierT)

    // A carrier sunk for no points shows no score pop-up.
    fresh(g)
    c = { x: 400, y: 100, baseY: 100, vx: 70, t: 0, hp: 1, maxHp: 6, fireT: 99, mineT: 99, flash: 0, dead: false }
    g.carriers = [c]
    before = g.score
    g.damageCarrier(c, 2, 0)
    check("a carrier sunk for nothing shows no +1500", c.dead && g.score === before
          && g.popups.every(function (p) { return p.text.indexOf("1500") < 0 }), g.popups.length)

    // ---- pause and focus -------------------------------------------------------------
    fresh(g)
    g.shipVx = 100
    g.togglePause()
    var px = g.shipX
    g.step(1 / 60)
    check("pause freezes the skiff", g.phase === "paused" && g.shipX === px, g.phase)
    g.togglePause()
    check("resume plays", g.phase === "play")
    g.leftHeld = true; g.rightHeld = true; g.thrustHeld = true; g.fireHeld = true
    g.lostFocus()
    check("losing focus pauses and lets go of every key", g.phase === "paused" && !g.leftHeld && !g.rightHeld && !g.thrustHeld && !g.fireHeld)
    g.newGame(3)
    g.lostFocus()
    check("losing focus before launch stays in ready", g.phase === "ready")

    // ---- drawing follows the physics ------------------------------------------------
    fresh(g)
    g.shipX = 222; g.shipY = 333
    d = g.makeDebris(2, 500, 150, 0, 0)
    m = g.makeMine(100, 450, 0, 0)
    g.publish()
    var sv = g.shipView, dv = g.debrisView.itemAt(0), mv = g.mineView.itemAt(0)
    check("the drawn skiff is where the skiff is", near(sv.x, 222 - 16) && near(sv.y, 333 - 16), sv.x + "," + sv.y)
    check("the drawn debris is where the debris is", !!dv && near(dv.x, 500 - d.r) && near(dv.y, 150 - d.r), dv ? dv.x : "no item")
    check("the drawn mine is where the mine is", !!mv && near(mv.x, 100 - g.mineR), mv ? mv.x : "no item")
    d.x = 600; d.y = 250; m.x = 150
    g.shipA = Math.PI / 2
    g.publish()
    check("the drawn debris moves when the debris does", near(g.debrisView.itemAt(0).x, 600 - d.r) && near(g.debrisView.itemAt(0).y, 250 - d.r),
          g.debrisView.itemAt(0).x)
    check("the drawn mine moves when the mine does", near(g.mineView.itemAt(0).x, 150 - g.mineR), g.mineView.itemAt(0).x)
    check("the drawn skiff turns with the skiff", near(g.shipView.rotation, 90), g.shipView.rotation)

    // Debris delegates read their shape and position through an accessor
    // (game.debrisAt(index)), never by holding the array element itself, so
    // when one piece dies and compaction shifts a different piece into its
    // slot, the delegate at that index must repaint as the new piece, not
    // freeze on the old one's shape (docs/GAMES.md, "Draw without freezing").
    fresh(g)
    d = g.makeDebris(2, 300, 300, 0, 0)          // will die and be compacted out
    d2 = g.makeDebris(1, 500, 400, 0, 0)         // survives, shifts down into slot 0
    g.publish()
    check("two distinct debris shapes to start", g.debrisView.itemAt(0).pts !== g.debrisView.itemAt(1).pts)
    d.dead = true
    g.compactAll()
    g.publish()
    check("compaction maps a later index onto the next surviving debris", g.debris.length === 1 && g.debris[0] === d2)
    var slot0 = g.debrisView.itemAt(0)
    check("the drawn shape at that slot follows the debris now there, not the dead one",
          !!slot0 && slot0.pts === d2.pts, slot0 ? "stale shape" : "no item")
    check("the drawn position at that slot follows too",
          !!slot0 && near(slot0.x, 500 - d2.r) && near(slot0.y, 400 - d2.r), slot0 ? slot0.x + "," + slot0.y : "no item")
    d2.x = 650; d2.y = 120
    g.publish()
    check("...and keeps following when that surviving debris moves",
          near(g.debrisView.itemAt(0).x, 650 - d2.r) && near(g.debrisView.itemAt(0).y, 120 - d2.r), g.debrisView.itemAt(0).x)

    // House rule: only foreground/bright_foreground/accent/red draw text; yellow,
    // orange, green and cyan are for shapes and bars, too low-contrast for text
    // on light themes.
    g.theme = { green: "#9ece6a", cyan: "#7dcfff", bright_foreground: "#c0caf5", accent: "#7aa2f7" }
    g.popup(400, 300, "+10")
    g.publish()
    check("a score popup is a theme text color, not the low-contrast green hue",
          Qt.colorEqual(g.popupView.itemAt(0).color, g.color("bright_foreground", "#c0caf5"))
          && !Qt.colorEqual(g.popupView.itemAt(0).color, g.color("green", "#9ece6a")), g.popupView.itemAt(0).color)
    g.tether = "tow"
    check("the TOW label is a theme text color, not the low-contrast green hue",
          Qt.colorEqual(g.tetherLabel.color, g.color("bright_foreground", "#c0caf5"))
          && !Qt.colorEqual(g.tetherLabel.color, g.color("green", "#9ece6a")), g.tetherLabel.color)
    g.tether = "idle"; g.tetherCd = 0
    check("the idle TETHER label is a theme text color, not the low-contrast cyan hue",
          Qt.colorEqual(g.tetherLabel.color, g.color("accent", "#7aa2f7"))
          && !Qt.colorEqual(g.tetherLabel.color, g.color("cyan", "#7dcfff")), g.tetherLabel.color)
    g.theme = {}

    // ---- high score and reset ------------------------------------------------------
    fresh(g)
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)
    var got = -1
    var onHigh = function (sc) { got = sc }
    g.newHighScore.connect(onHigh)
    g.addScore(5)
    g.newHighScore.disconnect(onHigh)
    check("a new best signals the host with the score", got === 515 && g.highScore === 515, got)
    d = g.makeDebris(2, 400, 200, 0, 0)
    g.tetherAction()
    run(g, 0.5, function () { return g.tether === "tow" })
    g.wave = 5; g.lives = 1
    g.newGame(11)
    check("a new game resets everything", g.score === 0 && g.lives === 3 && g.wave === 1 && !g.beatHigh
          && g.tether === "idle" && g.towed === null && g.bullets.length === 0 && g.carriers.length === 0
          && g.phase === "ready" && g.shipAlive, g.score + "/" + g.lives + "/" + g.wave + "/" + g.tether)
    check("the high score survives a new game", g.highScore === 515, g.highScore)
  }
}
