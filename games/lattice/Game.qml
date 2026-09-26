import QtQuick
import "layouts.js" as Layouts
import "paths.js" as Paths

// Lattice Siege: the whole game. A formation shooter played in a fixed 800×600
// field that is scaled to fit the window, so physics never depend on the window.
//
// Controls: ←/→ or A/D move the cannon, Space fires (hold it to keep firing),
// P pauses, Esc quits, Enter starts over after a game over.
//
// Rules in short:
// - Constellations of geometric drones fly in along curved paths and lock into
//   a swaying, breathing lattice (layouts.js, paths.js).
// - Drones peel off and dive: they loop outward first, then curve down toward
//   the cannon, shooting on the way. Missed divers wrap to the top and return.
// - Every constellation is drawn linked. Destroy all of one for a bonus; do it
//   within snapWindow seconds of its first loss (a "link snap") to double the
//   bonus and earn a wing drone. Up to two drones fly beside the cannon, fire
//   with it and soak one hit each; they are lost with the ship.
// - Every fourth stage is a Monolith: a core behind rotating shield plates
//   that fires rings and volleys and launches escorts. Shoot through the gaps.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  property int seed: 1                  // tests set it; the host sets autoSeed
  property bool autoSeed: false         // true: every new game seeds from the clock
  property bool noDives: false          // tests: hold the dive orders
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real fieldW: 800
  readonly property real fieldH: 600
  readonly property real hudH: 44
  readonly property real shipY: 550           // cannon center
  readonly property real shipHalfW: 18
  readonly property real shipSpeed: 380       // px/s
  readonly property real droneOffset: 40      // drones sit this far either side
  readonly property real droneRadius: 9
  readonly property real enemyR: 14
  readonly property real slotSpacing: 54
  readonly property real rowSpacing: 42
  readonly property real formTop: 100
  readonly property real shotSpeed: 640       // player shots, px/s
  readonly property int maxShots: 2           // cannon shots on screen at once
  readonly property real fireCooldown: 0.16
  readonly property real snapWindow: 2.5      // s to finish a constellation for a link snap
  readonly property real respawnTime: 1.6
  readonly property real shieldTime: 2.0
  readonly property real clearTime: 2.2
  readonly property int maxLives: 5
  readonly property int extraLifeEvery: 25000  // our own threshold, not a classic's
  readonly property int maxEnemyShots: 16
  // Delegate pools: each Repeater keeps a fixed count and hides the spare
  // delegates, so a shot or spark appearing never rebuilds the whole Repeater.
  readonly property int maxEnemies: 64
  readonly property int maxShotsDrawn: 12   // every shot in the air (cannon and drones) has a delegate
  readonly property int maxSparks: 96
  readonly property int maxLinks: 48
  readonly property real bossY: 150
  readonly property real bossCoreR: 34
  readonly property real plateInner: 44
  readonly property real plateOuter: 64
  readonly property real plateHalfLen: 18     // a plate is a straight bar, 2 × this long, as drawn

  // ---- state --------------------------------------------------------------------
  property string phase: "ready"              // ready | play | paused | over
  property int stage: 1
  property int lives: 3
  property int score: 0
  property bool beatHigh: false               // this game went past the old best
  property int nextExtra: extraLifeEvery
  property real shipX: fieldW / 2
  property bool shipAlive: true
  property real respawnT: 0
  property real shieldT: 0
  property real fireCd: 0
  property bool droneL: false
  property bool droneR: false
  property var enemies: []    // see makeEnemy()
  property var shots: []      // { x, y, src: "ship" | "drone" }
  property var enemyShots: [] // { x, y, vx, vy, r }
  property var sparks: []     // { x, y, vx, vy, life, max, c, f }
  property var links: []      // { x1, y1, x2, y2, hot } drawn constellation lines
  property var bossList: []   // zero or one Monolith, an array so it draws like the rest
  property var groups: []     // { size, alive, firstKill, members: [enemy index] }
  property real clock: 0      // play time, s
  property real formT: 0      // drives the formation's sway
  property real diveCd: 0
  property real formFireCd: 0
  property real clearT: 0     // > 0: stage cleared, the next one loads when it runs out
  property real drawClock: 0  // clock, published once per frame for the drawing
  property bool leftHeld: false
  property bool rightHeld: false
  property bool fireHeld: false
  property string banner: ""
  property int rngState: 1

  readonly property var offField: ({ x: -200, y: -200, kind: "", state: "dead", rot: 0, hp: 0, maxHp: 1, flash: 0,
                                     vx: 0, vy: 0, r: 4, life: 0, max: 1, c: "foreground", f: "#a9b1d6",
                                     x1: -200, y1: -200, x2: -200, y2: -200, hot: false,
                                     angle: 0, plates: 0, t: 0 })
  function enemyAt(i) { return enemies[i] || offField }
  function shotAt(i) { return shots[i] || offField }
  function enemyShotAt(i) { return enemyShots[i] || offField }
  function sparkAt(i) { return sparks[i] || offField }
  function linkAt(i) { return links[i] || offField }
  function bossAt(i) { return bossList[i] || offField }

  readonly property alias enemyView: enemyView
  readonly property alias shotView: shotView
  readonly property alias linkView: linkView
  readonly property alias bossView: bossView

  function color(key, fallback) { return theme[key] || fallback }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function wrapAngle(a) {
    while (a > Math.PI) a -= 2 * Math.PI
    while (a < -Math.PI) a += 2 * Math.PI
    return a
  }
  // mulberry32: the only randomness in the rules. Math.random() is not used.
  function rand() {
    var t = (rngState + 0x6D2B79F5) | 0
    rngState = t
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  function flash(text) { banner = text; bannerTimer.restart() }
  function kindColor(kind) {
    return kind === "p" ? ["magenta", "#ad8ee6"] : kind === "r" ? ["green", "#9ece6a"] : ["cyan", "#7dcfff"]
  }

  // ---- the formation ---------------------------------------------------------------
  // A slot's position now: the lattice sways side to side and breathes in and out.
  // slotPos() is called for every formed/entering/returning enemy on every physics
  // substep (hundreds of times a second), so it writes into one reused scratch object
  // instead of allocating a fresh one each call. Every caller reads .x/.y right away
  // and never holds onto the object, so reusing it is safe.
  readonly property var _slotScratch: ({ x: 0, y: 0 })
  function slotPos(e) {
    var spread = 1 + 0.07 * Math.sin(formT * 1.4)
    var sway = 50 * Math.sin(formT * 0.55)
    _slotScratch.x = fieldW / 2 + (e.col - (Layouts.COLS - 1) / 2) * slotSpacing * spread + sway
    _slotScratch.y = formTop + e.row * rowSpacing + 4 * Math.sin(formT * 2 + e.col * 0.6)
    return _slotScratch
  }

  function makeEnemy(kind, col, row, group, delay, path) {
    return {
      kind: kind, hp: Layouts.hpFor(kind), maxHp: Layouts.hpFor(kind),
      state: "wait",          // wait | enter | form | dive | return | dead
      x: -200, y: -200, col: col, row: row, group: group,
      delay: delay, u: 0, path: path,
      h: 0, t: 0, side: 1, v: 0, targetX: 0, shotsLeft: 0, fireCd: 0, retarget: false,
      rot: 0, flash: 0
    }
  }

  function loadStage() {
    enemies = []; shots = []; enemyShots = []; bossList = []; groups = []; links = []
    clearT = 0
    diveCd = 3.0
    formFireCd = Paths.formFireInterval(stage)
    if (Layouts.isBoss(stage)) { spawnBoss(); return }
    var b = Layouts.build(Layouts.layoutFor(stage).rows)
    var gap = Paths.groupGap(stage)
    var gs = []
    for (var g = 0; g < b.sizes.length; g++) gs.push({ size: b.sizes[g], alive: b.sizes[g], firstKill: -1, members: [] })
    for (var i = 0; i < b.members.length; i++) {
      var m = b.members[i]
      enemies.push(makeEnemy(m.kind, m.col, m.row, m.group, m.group * gap + m.order * 0.14,
                             Paths.KINDS[m.group % Paths.KINDS.length]))
      gs[m.group].members.push(i)
    }
    groups = gs
    enemies = enemies.slice()
  }

  function newGame() {
    if (autoSeed) seed = (Date.now() % 2147483646) + 1
    rngState = seed | 0
    stage = 1; lives = 3; score = 0; beatHigh = false; nextExtra = extraLifeEvery
    shipX = fieldW / 2; shipAlive = true; respawnT = 0; shieldT = 0; fireCd = 0
    droneL = false; droneR = false
    clock = 0; formT = 0; drawClock = 0
    leftHeld = false; rightHeld = false; fireHeld = false
    sparks = []
    banner = ""
    phase = "ready"
    loadStage()
  }

  function start() {
    if (phase !== "ready") return
    phase = "play"
    flash("Stage " + stage + " · " + Layouts.stageName(stage))
  }

  function pause() { if (phase === "play") phase = "paused" }
  function resume() { if (phase === "paused") phase = "play" }
  function togglePause() { if (phase === "play") pause(); else if (phase === "paused") resume() }
  // Key releases don't arrive while away: forget held keys, or the cannon would
  // keep drifting (and firing) after the game resumes.
  function lostFocus() {
    leftHeld = false; rightHeld = false; fireHeld = false
    pause()
  }

  function addScore(points) {
    score += points
    while (score >= nextExtra) {
      nextExtra += extraLifeEvery
      if (lives < maxLives) { lives++; flash("Extra cannon") }
    }
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  function explode(x, y, key, fallback, n) {
    for (var i = 0; i < n && sparks.length < maxSparks; i++) {
      var a = rand() * 2 * Math.PI, s = 60 + rand() * 180, life = 0.35 + rand() * 0.45
      sparks.push({ x: x, y: y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: life, max: life, c: key, f: fallback })
    }
  }

  // ---- the cannon and its drones -------------------------------------------------
  function ownShots() {
    var n = 0
    for (var i = 0; i < shots.length; i++) if (shots[i].src === "ship") n++
    return n
  }

  // One cannon shot (at most maxShots in the air), plus one from each drone.
  function fire() {
    if (phase !== "play" || !shipAlive || fireCd > 0 || ownShots() >= maxShots) return false
    shots.push({ x: shipX, y: shipY - 18, src: "ship" })
    // Drone shots only while the pool has room, so every shot in the air is drawn.
    if (droneL && shots.length < maxShotsDrawn) shots.push({ x: shipX - droneOffset, y: shipY - 8, src: "drone" })
    if (droneR && shots.length < maxShotsDrawn) shots.push({ x: shipX + droneOffset, y: shipY - 8, src: "drone" })
    fireCd = fireCooldown
    return true
  }

  function gainDrone() {
    if (!droneL) droneL = true
    else if (!droneR) droneR = true
    else return false
    return true
  }

  function killShip() {
    if (!shipAlive) return
    explode(shipX, shipY, "accent", "#7aa2f7", 26)
    if (droneL) explode(shipX - droneOffset, shipY, "yellow", "#e0af68", 8)
    if (droneR) explode(shipX + droneOffset, shipY, "yellow", "#e0af68", 8)
    shipAlive = false
    droneL = false; droneR = false
    lives--
    respawnT = respawnTime
    if (lives > 0) flash(lives === 1 ? "Last cannon!" : lives + " cannons left")
  }

  function shipHitBy(x, y, r) {
    return shipAlive && shieldT <= 0 && Math.abs(x - shipX) < shipHalfW - 6 + r && Math.abs(y - shipY) < 10 + r
  }
  function droneHitBy(side, x, y, r) {
    if (!shipAlive || !(side < 0 ? droneL : droneR)) return false
    var dx = x - (shipX + side * droneOffset), dy = y - shipY
    return dx * dx + dy * dy < (droneRadius + r) * (droneRadius + r)
  }
  function loseDrone(side) {
    explode(shipX + side * droneOffset, shipY, "yellow", "#e0af68", 10)
    if (side < 0) droneL = false; else droneR = false
  }

  // ---- enemies ------------------------------------------------------------------
  function damageEnemy(e) {
    e.hp--
    if (e.hp > 0) { addScore(10); e.flash = 0.15; return }
    killEnemy(e, true)
  }

  function killEnemy(e, scored) {
    if (e.state === "dead") return
    var diving = e.state === "dive"
    e.state = "dead"
    var kc = kindColor(e.kind)
    explode(e.x, e.y, kc[0], kc[1], 12)
    if (scored) addScore(Layouts.pointsFor(e.kind, diving))
    if (e.group < 0 || !groups[e.group]) return
    var g = groups[e.group]
    g.alive--
    if (g.firstKill < 0) g.firstKill = clock
    if (g.alive === 0) groupCleared(g)
  }

  // A whole constellation is gone. Fast enough is a link snap: double bonus and a drone.
  function groupCleared(g) {
    var snap = g.size >= 2 && clock - g.firstKill <= snapWindow
    addScore(Layouts.groupBonus(g.size, snap))
    if (snap) flash(gainDrone() ? "Link snap · wing drone" : "Link snap")
  }

  // Start a dive: loop up and outward, then curve down toward where the cannon is.
  function startDive(e, delay) {
    e.state = "dive"
    e.t = -(delay || 0)
    e.side = e.x >= fieldW / 2 ? 1 : -1
    e.h = -Math.PI / 2
    e.v = Paths.diveSpeed(stage) * (e.kind === "p" ? 1.1 : 1)
    e.targetX = clamp(shipX + (rand() - 0.5) * 120, 30, fieldW - 30)
    e.shotsLeft = Paths.shotsPerDive(stage)
    e.fireCd = 0.2 + rand() * 0.4
    e.retarget = false
  }

  // The dive AI: one dive order every diveInterval (jittered), never more than
  // maxDivers at once. From stage 3 a diver may take its constellation along.
  function orderDive() {
    var divers = 0, cands = [], i
    for (i = 0; i < enemies.length; i++) {
      if (enemies[i].state === "dive") divers++
      else if (enemies[i].state === "form") cands.push(i)
    }
    if (divers >= Paths.maxDivers(stage) || cands.length === 0) return -1
    var pick = cands[Math.floor(rand() * cands.length)]
    var lead = enemies[pick]
    startDive(lead, 0)
    if (lead.group >= 0 && rand() < Paths.squadChance(stage)) {
      var mem = groups[lead.group].members, k = 1
      for (i = 0; i < mem.length; i++) {
        var o = enemies[mem[i]]
        if (o !== lead && o.state === "form") { startDive(o, 0.18 * k); o.side = lead.side; k++ }
      }
    }
    return pick
  }

  function aimAt(x, y, speed, spread) {
    var dx = shipX - x + (spread || 0), dy = Math.max(shipY - y, 40)
    var d = Math.hypot(dx, dy)
    var vx = dx / d * speed, vy = dy / d * speed
    if (vy < speed * 0.55) { vy = speed * 0.55; vx = (vx < 0 ? -1 : 1) * Math.sqrt(speed * speed - vy * vy) }
    return { vx: vx, vy: vy }
  }
  function enemyFire(x, y, vx, vy, r) {
    if (enemyShots.length >= maxEnemyShots) return
    enemyShots.push({ x: x, y: y, vx: vx, vy: vy, r: r || 4 })
  }

  function diveStep(e, dt) {
    e.t += dt
    if (e.t < 0) { var s0 = slotPos(e); e.x = s0.x; e.y = s0.y; return }
    var tA = 0.7
    if (e.t < tA) {
      // The loop: half a turn outward from straight up to straight down.
      e.h = -Math.PI / 2 + e.side * Math.PI * (e.t / tA)
    } else {
      // Prisms re-aim once, halfway down.
      if (e.kind === "p" && !e.retarget && e.y > fieldH * 0.45) { e.targetX = shipX; e.retarget = true }
      var want = Math.atan2(fieldH + 80 - e.y, e.targetX - e.x)
      var diff = wrapAngle(want - e.h), turn = 2.4 * dt
      e.h += clamp(diff, -turn, turn) + Math.sin(e.t * 4 + e.col) * 0.9 * dt
      e.fireCd -= dt
      if (e.shotsLeft > 0 && e.fireCd <= 0 && e.y < shipY - 110 && shipAlive) {
        var a = aimAt(e.x, e.y, Paths.shotSpeed(stage), 0)
        enemyFire(e.x, e.y + 10, a.vx, a.vy, 4)
        e.shotsLeft--
        e.fireCd = 0.35 + rand() * 0.5
      }
    }
    e.x += Math.cos(e.h) * e.v * dt
    e.y += Math.sin(e.h) * e.v * dt
    if (e.x < enemyR) { e.x = enemyR; e.h = Math.PI - e.h }
    if (e.x > fieldW - enemyR) { e.x = fieldW - enemyR; e.h = Math.PI - e.h }
    e.rot = e.h * 180 / Math.PI + 90
    if (e.y > fieldH + 30) {
      if (e.group < 0) { e.state = "dead"; return }       // Monolith escorts don't come back
      var s = slotPos(e)
      e.state = "return"; e.x = s.x; e.y = -30
    }
  }

  function updateEnemies(dt) {
    var entry = Paths.entryTime(stage)
    for (var i = 0; i < enemies.length; i++) {
      var e = enemies[i], s
      if (e.flash > 0) e.flash -= dt
      switch (e.state) {
      case "wait":
        e.delay -= dt
        if (e.delay <= 0) { e.state = "enter"; e.u = 0 }
        break
      case "enter":
        e.u += dt / entry
        s = slotPos(e)
        if (e.u >= 1) { e.state = "form"; e.x = s.x; e.y = s.y; break }
        var p = Paths.point(e.path, e.u, s.x, s.y, fieldW, fieldH)
        if (e.x > -150) e.rot = Math.atan2(p.y - e.y, p.x - e.x) * 180 / Math.PI + 90
        e.x = p.x; e.y = p.y
        break
      case "form":
        s = slotPos(e)
        e.x = s.x; e.y = s.y
        e.rot = e.kind === "n" ? (formT * 70 + e.col * 25) % 360 : e.kind === "p" ? (formT * 30) % 360 : 0
        break
      case "dive":
        diveStep(e, dt)
        break
      case "return":
        s = slotPos(e)
        var dx = s.x - e.x, dy = s.y - e.y, d = Math.hypot(dx, dy), v = 240 * dt
        if (d <= v) { e.state = "form"; e.x = s.x; e.y = s.y }
        else { e.x += dx / d * v; e.y += dy / d * v; e.rot = 180 }
        break
      }
    }
  }

  // ---- the Monolith ---------------------------------------------------------------
  function spawnBoss() {
    var k = Layouts.bossNumber(stage)
    bossList = [{ x: fieldW / 2, y: bossY, hp: Paths.bossHp(k), maxHp: Paths.bossHp(k), t: 0, angle: 0,
                  plates: Paths.bossPlates(k), spin: Paths.bossSpin(k), fireCd: 1.6, pattern: 0,
                  spawnCd: 3.5, flash: 0, k: k }]
  }

  // Does a point lie on one of the rotating shield plates? Each plate is tested
  // as the same rectangle the drawing shows (radial plateInner..plateOuter,
  // plateHalfLen either side), so a shot that looks clear of a plate is clear.
  function plateBlocks(b, x, y) {
    var dx = x - b.x, dy = y - b.y
    if (Math.hypot(dx, dy) > Math.hypot(plateOuter, plateHalfLen)) return false
    for (var i = 0; i < b.plates; i++) {
      var a = b.angle + i * 2 * Math.PI / b.plates, c = Math.cos(a), sn = Math.sin(a)
      var u = dx * c + dy * sn, v = -dx * sn + dy * c
      if (u >= plateInner && u <= plateOuter && Math.abs(v) <= plateHalfLen) return true
    }
    return false
  }

  function updateBoss(b, dt) {
    b.t += dt
    b.x = fieldW / 2 + 200 * Math.sin(b.t * 0.38)
    b.angle = wrapAngle(b.angle + b.spin * dt)
    if (b.flash > 0) b.flash -= dt
    if (!shipAlive) return
    b.fireCd -= dt
    if (b.fireCd <= 0) {
      b.fireCd = Paths.bossFireGap(b.k)
      if (b.pattern % 2 === 0) {
        // A ring of slow shots.
        var n = 8 + 2 * b.k, sp = 145 + 10 * b.k, off = rand() * Math.PI
        for (var i = 0; i < n; i++) {
          var a = off + i * 2 * Math.PI / n
          if (Math.sin(a) > -0.2) enemyFire(b.x + Math.cos(a) * 30, b.y + Math.sin(a) * 30, Math.cos(a) * sp, Math.sin(a) * sp, 5)
        }
      } else {
        // An aimed volley of three.
        for (var j = -1; j <= 1; j++) {
          var v = aimAt(b.x, b.y + 30, Paths.shotSpeed(stage) * 0.85, j * 90)
          enemyFire(b.x, b.y + 30, v.vx, v.vy, 4)
        }
      }
      b.pattern++
    }
    b.spawnCd -= dt
    if (b.spawnCd <= 0) {
      b.spawnCd = Paths.bossSpawnGap(b.k)
      // Spent escorts are dropped first, so a long fight never outgrows the pool.
      // Review fix: this used to reassign `enemies` (enemies.filter(...)), replacing
      // the array reference inside a physics substep. Splice it in place instead, as
      // every other in-step mutation does; the array is still replaced (once) by
      // publish() at the end of the frame.
      for (var d = enemies.length - 1; d >= 0; d--) if (enemies[d].state === "dead") enemies.splice(d, 1)
      var alive = enemies.length
      for (var s = -1; s <= 1 && alive < 4; s += 2) {
        var e = makeEnemy("n", 0, 0, -1, 0, "drop")
        e.x = b.x + s * 40; e.y = b.y + 40
        startDive(e, 0)
        e.side = s
        enemies.push(e)
        alive++
      }
    }
  }

  function bossDown(b) {
    addScore(Paths.bossBonus(b.k))
    explode(b.x, b.y, "red", "#f7768e", 40)
    explode(b.x, b.y, "yellow", "#e0af68", 30)
    bossList = []
    for (var i = 0; i < enemies.length; i++) if (enemies[i].state !== "dead") killEnemy(enemies[i], false)
    flash("Monolith down")
  }

  // ---- one physics step ------------------------------------------------------------
  function step(dt) {
    if (phase !== "play") return
    clock += dt
    formT += dt
    var i, j, e, s

    // Cannon.
    if (shipAlive) shipX = clamp(shipX + (rightHeld - leftHeld) * shipSpeed * dt, shipHalfW, fieldW - shipHalfW)
    if (fireCd > 0) fireCd -= dt
    if (shieldT > 0) shieldT -= dt
    if (!shipAlive) {
      respawnT -= dt
      if (respawnT <= 0) {
        if (lives <= 0) { phase = "over"; banner = ""; fireHeld = false; return }
        shipAlive = true; shipX = fieldW / 2; shieldT = shieldTime
      }
    }
    if (fireHeld) fire()

    updateEnemies(dt)
    var boss = bossList.length ? bossList[0] : null
    if (boss) updateBoss(boss, dt)

    // Dive orders and the formation's pot shots wait while the cannon is down.
    if (shipAlive && clearT <= 0) {
      if (!noDives) {
        diveCd -= dt
        if (diveCd <= 0) { diveCd = Paths.diveInterval(stage) * (0.7 + rand() * 0.6); orderDive() }
      }
      if (formFireCd > 0) {
        formFireCd -= dt
        if (formFireCd <= 0) {
          formFireCd = Paths.formFireInterval(stage) * (0.7 + rand() * 0.6)
          var shooters = []
          for (i = 0; i < enemies.length; i++) if (enemies[i].state === "form") shooters.push(enemies[i])
          if (shooters.length) {
            e = shooters[Math.floor(rand() * shooters.length)]
            var a = aimAt(e.x, e.y, Paths.shotSpeed(stage) * 0.8, 0)
            enemyFire(e.x, e.y + 10, a.vx * 0.4, Math.hypot(a.vx * 0.6, a.vy), 4)
          }
        }
      }
    }

    // Player and drone shots.
    for (i = shots.length - 1; i >= 0; i--) {
      s = shots[i]
      s.y -= shotSpeed * dt
      if (s.y < hudH) { shots.splice(i, 1); continue }
      var hit = false
      if (boss) {
        if (plateBlocks(boss, s.x, s.y)) {
          explode(s.x, s.y, "yellow", "#e0af68", 3)
          hit = true
        } else if (Math.hypot(s.x - boss.x, s.y - boss.y) < bossCoreR) {
          boss.hp--; boss.flash = 0.1; addScore(20); hit = true
          if (boss.hp <= 0) { shots.splice(i, 1); bossDown(boss); boss = null; continue }
        }
      }
      for (j = 0; j < enemies.length && !hit; j++) {
        e = enemies[j]
        if (e.state === "dead" || e.state === "wait") continue
        if (Math.abs(s.x - e.x) < enemyR && Math.abs(s.y - e.y) < enemyR + 4) { damageEnemy(e); hit = true }
      }
      if (hit) shots.splice(i, 1)
    }

    // Enemy shots: a drone takes the hit before the cannon does.
    for (i = enemyShots.length - 1; i >= 0; i--) {
      s = enemyShots[i]
      s.x += s.vx * dt
      s.y += s.vy * dt
      if (s.y > fieldH + 10 || s.y < hudH - 20 || s.x < -10 || s.x > fieldW + 10) { enemyShots.splice(i, 1); continue }
      if (droneHitBy(-1, s.x, s.y, s.r)) { loseDrone(-1); enemyShots.splice(i, 1); continue }
      if (droneHitBy(1, s.x, s.y, s.r)) { loseDrone(1); enemyShots.splice(i, 1); continue }
      if (shipHitBy(s.x, s.y, s.r)) { enemyShots.splice(i, 1); killShip() }
    }

    // Divers ramming the cannon or a drone. Both go down; the shield lets them pass.
    for (i = 0; i < enemies.length; i++) {
      e = enemies[i]
      if (e.state !== "dive" || e.t < 0) continue
      if (droneHitBy(-1, e.x, e.y, enemyR)) { loseDrone(-1); killEnemy(e, true); continue }
      if (droneHitBy(1, e.x, e.y, enemyR)) { loseDrone(1); killEnemy(e, true); continue }
      if (shipHitBy(e.x, e.y, enemyR - 4)) { killEnemy(e, true); killShip() }
    }

    // Sparks (drawing only; they never touch the rules).
    for (i = sparks.length - 1; i >= 0; i--) {
      s = sparks[i]
      s.life -= dt
      if (s.life <= 0) { sparks.splice(i, 1); continue }
      s.x += s.vx * dt; s.y += s.vy * dt
      s.vx *= 0.985; s.vy *= 0.985
    }

    // Stage clear: every enemy and the Monolith gone.
    if (clearT > 0) {
      clearT -= dt
      if (clearT <= 0) {
        stage++
        flash("Stage " + stage + " · " + Layouts.stageName(stage))
        loadStage()
      }
    } else if (bossList.length === 0 && aliveEnemies() === 0) {
      clearT = clearTime
      enemyShots = []
      if (banner === "") flash("Stage " + stage + " clear")
    }
  }

  function aliveEnemies() {
    var n = 0
    for (var i = 0; i < enemies.length; i++) if (enemies[i].state !== "dead") n++
    return n
  }

  // Lines between neighbours of a constellation still sitting in the lattice.
  // A constellation that has lost a member glows while a link snap is still on.
  function computeLinks() {
    var out = []
    for (var g = 0; g < groups.length; g++) {
      var gr = groups[g], prev = null
      var hot = gr.firstKill >= 0 && clock - gr.firstKill <= snapWindow
      for (var k = 0; k < gr.members.length; k++) {
        var e = enemies[gr.members[k]]
        if (!e || (e.state !== "form" && e.state !== "enter")) { prev = null; continue }
        if (prev && out.length < maxLinks) out.push({ x1: prev.x, y1: prev.y, x2: e.x, y2: e.y, hot: hot })
        prev = e
      }
    }
    return out
  }

  // The Repeaters redraw when these arrays are replaced; physics mutates them in
  // place, so this runs once per frame (not per physics step).
  function publish() {
    enemies = enemies.slice(); shots = shots.slice(); enemyShots = enemyShots.slice()
    sparks = sparks.slice(); bossList = bossList.slice()
    links = computeLinks()
    drawClock = clock
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

  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }

  // Space held down keeps firing through fireHeld, so key auto-repeat is ignored.
  Keys.onPressed: function (e) {
    if (e.isAutoRepeat) { e.accepted = true; return }
    switch (e.key) {
    case Qt.Key_Left: case Qt.Key_A: leftHeld = true; break
    case Qt.Key_Right: case Qt.Key_D: rightHeld = true; break
    case Qt.Key_Space:
      if (phase === "ready") start()
      else if (phase === "play") { fireHeld = true; fire() }
      else if (phase === "paused") resume()
      break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter:
      if (phase === "over") newGame()
      else if (phase === "ready") start()
      else if (phase === "play") fire()
      break
    case Qt.Key_Escape: quitRequested(); break
    default: return
    }
    e.accepted = true
  }
  Keys.onReleased: function (e) {
    if (e.isAutoRepeat) return
    if (e.key === Qt.Key_Left || e.key === Qt.Key_A) leftHeld = false
    else if (e.key === Qt.Key_Right || e.key === Qt.Key_D) rightHeld = false
    else if (e.key === Qt.Key_Space) fireHeld = false
  }

  Component.onCompleted: newGame()

  // ---- drawing --------------------------------------------------------------------
  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)
    clip: true

    Rectangle { anchors.fill: parent; color: game.color("dark_background", "#13141c"); radius: 6 }

    // Starfield drifting down.
    Repeater {
      model: 60
      delegate: Rectangle {
        required property int index
        x: Paths.starX(index)
        y: (Paths.starY(index) + game.drawClock * Paths.starSpeed(index)) % game.fieldH
        width: Paths.starSize(index); height: width
        color: game.color("foreground", "#a9b1d6")
        opacity: 0.25 + (index % 4) * 0.15
      }
    }

    // Constellation lines.
    Repeater {
      id: linkView
      model: game.maxLinks
      delegate: Rectangle {
        required property int index
        readonly property real dx: game.linkAt(index).x2 - game.linkAt(index).x1
        readonly property real dy: game.linkAt(index).y2 - game.linkAt(index).y1
        visible: index < game.links.length
        x: game.linkAt(index).x1
        y: game.linkAt(index).y1 - 1
        width: Math.hypot(dx, dy)
        height: 2
        transformOrigin: Item.Left
        rotation: Math.atan2(dy, dx) * 180 / Math.PI
        color: game.linkAt(index).hot ? game.color("yellow", "#e0af68") : game.color("blue", "#7aa2f7")
        opacity: game.linkAt(index).hot ? 0.9 : 0.35
      }
    }

    // The Monolith: a core in concentric rings behind rotating shield plates.
    Repeater {
      id: bossView
      model: game.bossList.length
      delegate: Item {
        id: bossItem
        required property int index
        x: game.bossAt(index).x
        y: game.bossAt(index).y
        width: 0; height: 0
        Repeater {
          model: game.bossAt(bossItem.index).plates
          delegate: Rectangle {
            required property int index
            readonly property real a: game.bossAt(bossItem.index).angle + index * 2 * Math.PI / game.bossAt(bossItem.index).plates
            readonly property real rr: (game.plateInner + game.plateOuter) / 2
            width: game.plateOuter - game.plateInner; height: game.plateHalfLen * 2
            x: Math.cos(a) * rr - width / 2
            y: Math.sin(a) * rr - height / 2
            rotation: a * 180 / Math.PI
            radius: 3
            color: game.color("yellow", "#e0af68")
            opacity: 0.85
          }
        }
        Rectangle {
          x: -game.bossCoreR; y: -game.bossCoreR
          width: game.bossCoreR * 2; height: width; radius: width / 2
          color: game.bossAt(bossItem.index).flash > 0 ? game.color("bright_foreground", "#c0caf5") : game.color("red", "#f7768e")
          border.width: 4
          border.color: game.color("orange", "#ff9e64")
          Rectangle {
            anchors.centerIn: parent
            width: 36; height: 36; rotation: game.bossAt(bossItem.index).angle * -57.3
            color: "transparent"
            border.width: 3; border.color: game.color("dark_background", "#13141c")
          }
          Rectangle {
            anchors.centerIn: parent
            width: 12; height: 12; radius: 6
            color: game.color("bright_foreground", "#c0caf5")
          }
        }
      }
    }

    // Enemies: node (diamond), relay (ringed satellite), prism (eight-point star).
    Repeater {
      id: enemyView
      model: game.maxEnemies
      delegate: Item {
        id: en
        required property int index
        readonly property string kind: game.enemyAt(index).kind
        readonly property string st: game.enemyAt(index).state
        readonly property bool cracked: game.enemyAt(index).hp < game.enemyAt(index).maxHp
        x: game.enemyAt(index).x - 16
        y: game.enemyAt(index).y - 16
        width: 32; height: 32
        visible: st !== "dead" && st !== "wait"
        rotation: game.enemyAt(index).rot

        Rectangle {           // node
          visible: en.kind === "n"
          anchors.centerIn: parent
          width: 19; height: 19; rotation: 45
          color: "transparent"
          border.width: 3
          border.color: game.color("cyan", "#7dcfff")
          Rectangle { anchors.centerIn: parent; width: 6; height: 6; color: game.color("bright_foreground", "#c0caf5") }
        }
        Item {                // relay
          visible: en.kind === "r"
          anchors.fill: parent
          // Wide, low solar panels on a boom, like a satellite's.
          Rectangle { x: -6; y: 13; width: 13; height: 6; color: game.color("blue", "#7aa2f7") }
          Rectangle { x: 25; y: 13; width: 13; height: 6; color: game.color("blue", "#7aa2f7") }
          Rectangle { x: 0; y: 13; width: 1; height: 6; color: game.color("dark_background", "#13141c") }
          Rectangle { x: 31; y: 13; width: 1; height: 6; color: game.color("dark_background", "#13141c") }
          Rectangle { x: 6; y: 15; width: 20; height: 2; color: game.color("blue", "#7aa2f7") }
          Rectangle {
            anchors.centerIn: parent
            width: 18; height: 18; radius: 9
            color: game.color("dark_background", "#13141c")
            border.width: 3
            border.color: game.color("green", "#9ece6a")
          }
          Rectangle { anchors.centerIn: parent; width: 5; height: 5; radius: 2.5; color: game.color("green", "#9ece6a") }
        }
        Item {                // prism
          visible: en.kind === "p"
          anchors.fill: parent
          Repeater {
            model: 2
            delegate: Rectangle {
              required property int index
              anchors.centerIn: parent
              width: 20; height: 20
              rotation: index * 45
              color: en.cracked ? game.color("orange", "#ff9e64") : game.color("magenta", "#bb9af7")
              opacity: 0.9
            }
          }
          Rectangle {
            anchors.centerIn: parent
            width: 8; height: 8; rotation: 45
            color: game.color("dark_background", "#13141c")
          }
        }
        Rectangle {           // hit flash
          anchors.centerIn: parent
          width: 26; height: 26; radius: 13
          color: game.color("bright_foreground", "#c0caf5")
          visible: game.enemyAt(en.index).flash > 0
          opacity: 0.7
        }
      }
    }

    // Player and drone shots.
    Repeater {
      id: shotView
      model: game.maxShotsDrawn
      delegate: Rectangle {
        required property int index
        visible: index < game.shots.length
        x: game.shotAt(index).x - 1.5
        y: game.shotAt(index).y
        width: 3; height: 14; radius: 1.5
        color: game.shotAt(index).src === "drone" ? game.color("yellow", "#e0af68") : game.color("bright_foreground", "#c0caf5")
      }
    }

    // Enemy shots.
    Repeater {
      model: game.maxEnemyShots
      delegate: Rectangle {
        required property int index
        visible: index < game.enemyShots.length
        x: game.enemyShotAt(index).x - game.enemyShotAt(index).r
        y: game.enemyShotAt(index).y - game.enemyShotAt(index).r
        width: game.enemyShotAt(index).r * 2; height: width; radius: width / 2
        color: game.enemyShotAt(index).r > 4 ? game.color("orange", "#ff9e64") : game.color("red", "#f7768e")
        border.width: 1
        border.color: game.color("bright_foreground", "#c0caf5")
      }
    }

    // Wing drones.
    Repeater {
      model: 2
      delegate: Rectangle {
        required property int index
        readonly property int side: index === 0 ? -1 : 1
        visible: game.shipAlive && (index === 0 ? game.droneL : game.droneR)
        x: game.shipX + side * game.droneOffset - width / 2
        y: game.shipY - height / 2
        width: 16; height: 16
        rotation: 45 + game.drawClock * 120 * side
        color: "transparent"
        border.width: 3
        border.color: game.color("yellow", "#e0af68")
        Rectangle { anchors.centerIn: parent; width: 5; height: 5; color: game.color("yellow", "#e0af68") }
      }
    }

    // The cannon: a split arrowhead with a glowing keel.
    Item {
      id: ship
      x: game.shipX - 20
      y: game.shipY - 17
      width: 40; height: 34
      visible: game.shipAlive && (game.shieldT <= 0 || Math.floor(game.drawClock * 12) % 2 === 0)
      Canvas {
        id: shipArt
        anchors.fill: parent
        readonly property color body: game.color("accent", "#7aa2f7")
        readonly property color keel: game.color("bright_foreground", "#c0caf5")
        onBodyChanged: requestPaint()
        onKeelChanged: requestPaint()
        Component.onCompleted: requestPaint()
        onPaint: {
          var c = getContext("2d")
          c.reset()
          c.fillStyle = body
          c.beginPath()
          c.moveTo(20, 0); c.lineTo(36, 30); c.lineTo(26, 24); c.lineTo(20, 32)
          c.lineTo(14, 24); c.lineTo(4, 30); c.closePath()
          c.fill()
          c.fillStyle = keel
          c.fillRect(19, 8, 2, 16)
        }
      }
    }
    Rectangle {           // spawn shield
      visible: game.shipAlive && game.shieldT > 0
      x: game.shipX - 26; y: game.shipY - 26
      width: 52; height: 52; radius: 26
      color: "transparent"
      border.width: 2
      border.color: game.color("cyan", "#7dcfff")
      opacity: 0.6
    }

    // Sparks.
    Repeater {
      model: game.maxSparks
      delegate: Rectangle {
        required property int index
        visible: index < game.sparks.length
        x: game.sparkAt(index).x - 1.5
        y: game.sparkAt(index).y - 1.5
        width: 3; height: 3
        color: game.color(game.sparkAt(index).c, game.sparkAt(index).f)
        opacity: game.sparkAt(index).life / game.sparkAt(index).max
      }
    }

    // HUD.
    Rectangle {
      width: parent.width; height: game.hudH
      color: game.color("lighter_background", "#24283b")
      radius: 6
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.leftMargin: 18
        spacing: 26
        Text { text: "SCORE " + game.score; color: game.color("bright_foreground", "#c0caf5"); font.pixelSize: 19; font.bold: true; font.family: "monospace" }
        Text { text: "HIGH " + game.highScore; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 19; font.family: "monospace" }
      }
      Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 60
        text: "STAGE " + game.stage + " · " + Layouts.stageName(game.stage).toUpperCase()
        color: game.color("accent", "#7aa2f7"); font.pixelSize: 15; font.bold: true; font.family: "monospace"
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 18
        spacing: 8
        Repeater {
          model: (game.droneL ? 1 : 0) + (game.droneR ? 1 : 0)
          delegate: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 10; height: 10; rotation: 45
            color: "transparent"; border.width: 2; border.color: game.color("yellow", "#e0af68")
          }
        }
        Item { width: 6; height: 1 }
        Repeater {
          model: Math.max(0, game.lives - (game.shipAlive ? 1 : 0))
          delegate: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12; radius: 2; rotation: 45
            color: game.color("accent", "#7aa2f7")
          }
        }
      }
    }

    // Monolith integrity bar.
    Rectangle {
      visible: game.bossList.length > 0
      x: 200; y: game.hudH + 8; width: 400; height: 6; radius: 3
      color: game.color("lighter_background", "#24283b")
      Rectangle {
        width: parent.width * Math.max(0, game.bossAt(0).hp / game.bossAt(0).maxHp)
        height: parent.height; radius: 3
        color: game.color("red", "#f7768e")
      }
    }

    // Messages. Paused and game-over messages get a backdrop.
    Rectangle {
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 32
      radius: 8
      visible: game.phase === "paused" || game.phase === "over" || game.phase === "ready"
      color: game.color("dark_background", "#13141c")
      opacity: 0.92
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 60
      spacing: 10
      visible: text1.text !== ""
      Text {
        id: text1
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : game.phase === "ready" ? "LATTICE SIEGE"
            : game.banner
        color: game.color("bright_foreground", "#c0caf5")
        font.pixelSize: game.phase === "play" ? 30 : 40; font.bold: true; font.family: "monospace"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: text !== ""
        text: game.phase === "over" ? "Stage " + game.stage + "  ·  Score " + game.score + (game.beatHigh ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "ready" ? "Space to launch  ·  ← → or A/D move  ·  Space fire  ·  P pause\nWipe out a linked constellation fast for a wing drone"
            : ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 15; font.family: "monospace"
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        game.forceActiveFocus()
        if (game.phase === "over") game.newGame()
        else if (game.phase === "ready") game.start()
      }
    }
  }
}
