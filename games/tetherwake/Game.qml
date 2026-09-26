import QtQuick
import "space.js" as Space

// Tetherwake: the whole game. A salvage skiff works a wrap-around 800×600 field
// of drifting wreckage. It plays in that fixed field, scaled to fit the window,
// so physics never depend on the window size.
//
// Controls: ←/→ or A/D rotate, ↑ or W thrusts, Space fires (hold for auto-fire),
// Shift, ↓ or S works the tether; P pauses; Esc quits; Enter starts, and starts
// over after a game over.
//
// The hazards:
//  - debris: hull slabs that shatter into plates, then shards, when shot;
//  - mines: drift asleep until the skiff comes close, then arm and home in; a
//    mine's blast sets off other mines and shatters debris near it (and hurts
//    the skiff, too);
//  - ion gusts (wave 3 on): a warning, then a few seconds of wind that shoves
//    the skiff and everything else;
//  - the carrier (wave 4 on): crosses the field once per wave, firing aimed
//    bolts and laying mines, and takes several hits.
//
// The tether (the game's own mechanic): cast a grapple line; if it catches a
// piece of debris or a mine, the skiff tows it on a springy line. Anything the
// towed load hits breaks for double points (a towed mine goes off on contact).
// Cast again to let go: the load is flung with a boost and scores triple for a
// moment. Heavy slabs drag the skiff; the line snaps if stretched too far and
// runs out after a few seconds.
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
  readonly property real shipR: 11
  readonly property real turnRate: 4.2          // rad/s
  readonly property real thrustAccel: 280       // px/s²
  readonly property real maxSpeed: 360          // px/s
  readonly property real drag: 0.25             // fraction of speed lost per second
  readonly property real bulletSpeed: 520
  readonly property real bulletLife: 0.9        // s
  readonly property int maxBullets: 5
  readonly property real autoFire: 0.22         // s between shots while Space is held
  readonly property real respawnDelay: 2.0
  readonly property real invulnTime: 3.0
  readonly property int startLives: 3
  readonly property int maxLives: 5
  readonly property int lifeEvery: 10000
  readonly property real safeSpawn: 180         // new hazards keep this far from the skiff
  // tether
  readonly property real hookSpeed: 640
  readonly property real hookRange: 240
  readonly property real ropeLen: 80
  readonly property real ropeK: 20
  readonly property real ropeDamp: 5
  readonly property real ropeSnap: 260
  readonly property real towTime: 8
  readonly property real tetherCooldown: 0.6
  readonly property real flingBoost: 1.6
  readonly property real flingTime: 1.5
  readonly property real flingMax: 520
  readonly property real shipMass: 2
  // mines
  readonly property real mineR: 10
  readonly property real mineArmRange: 170
  readonly property real mineAccel: 150
  readonly property real blastR: 64
  readonly property real mineDropGrace: 0.5    // a dropped mine waits this long before it can re-arm
  // carrier
  readonly property real carrierR: 26
  readonly property real carrierSpeed: 70
  readonly property real boltSpeed: 230
  readonly property real boltLife: 2.6
  readonly property real carrierDelay: 10
  readonly property real carrierMineEvery: 5
  // storms and waves
  readonly property real stormAccel: 70
  readonly property real stormWarn: 2
  readonly property real stormGust: 4
  readonly property real stormFirst: 8
  readonly property real waveDelay: 2.5
  readonly property real debrisMaxSpeed: 170

  // ---- state --------------------------------------------------------------------
  property string phase: "ready"                // ready | play | paused | over
  property int wave: 1
  property int lives: startLives
  property int score: 0
  property bool beatHigh: false
  property int nextLifeAt: lifeEvery
  property int seed: 1
  property var rng: ({ s: 1 })
  property string banner: ""

  property real shipX: fieldW / 2
  property real shipY: fieldH / 2
  property real shipVx: 0
  property real shipVy: 0
  property real shipA: 0                        // radians; 0 points up, clockwise
  property bool shipAlive: true
  property real invuln: 0
  property real respawnT: 0

  property bool leftHeld: false
  property bool rightHeld: false
  property bool thrustHeld: false
  property bool fireHeld: false
  property real fireT: 0
  readonly property bool thrusting: thrustHeld && shipAlive && phase === "play"

  property var bullets: []                      // { x, y, vx, vy, life, dead }
  property var debris: []                       // { x, y, vx, vy, size, r, hp, rot, spin, pts, towed, flung, noRam, dead }
  property var mines: []                        // { x, y, vx, vy, armed, towed, flung, noRam, dead }
  property var carriers: []                     // zero or one { x, y, baseY, vx, t, hp, fireT, mineT, flash, dead }
  property var bolts: []                        // { x, y, vx, vy, life, dead }
  property var sparks: []                       // { x, y, vx, vy, life, max, dead }
  property var blasts: []                       // { x, y, life, dead }
  property var popups: []                       // { x, y, text, life, dead }

  property string tether: "idle"                // idle | cast | tow
  property var hook: ({ x: 0, y: 0, vx: 0, vy: 0, travel: 0 })
  property var towed: null                      // the debris or mine on the line
  property real towLeft: 0
  property real tetherCd: 0

  property real interT: 0                       // > 0: between waves
  property real waveTime: 0
  property real carrierT: -1                    // countdown to this wave's carrier; -1 none
  property string storm: ""                     // "" | warn | gust
  property real stormT: -1                      // -1: no storms this wave
  property real windX: 0
  property real windY: 0

  // Published once per frame for the drawing.
  property real clock: 0
  property real shownClock: 0
  property real lineDx: 0                       // line end, relative to the skiff (wrapped)
  property real lineDy: 0

  function color(key, fallback) { return theme[key] || fallback }
  function rand() { return Space.rand(rng) }
  function setSeed(n) { seed = n | 0; rng.s = n | 0 }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function wrapX(v) { return Space.wrap(v, fieldW) }
  function wrapY(v) { return Space.wrap(v, fieldH) }
  function dx(ax, bx) { return Space.delta(ax, bx, fieldW) }
  function dy(ay, by) { return Space.delta(ay, by, fieldH) }
  function dist(ax, ay, bx, by) { return Space.dist(ax, ay, bx, by, fieldW, fieldH) }
  function normAngle(a) {
    while (a > Math.PI) a -= 2 * Math.PI
    while (a <= -Math.PI) a += 2 * Math.PI
    return a
  }
  function speedOf(o) { return Math.hypot(o.vx, o.vy) }
  function massOf(o) { return o.size ? Space.debrisMass(o.size) : 1 }
  function radiusOf(o) { return o.size ? o.r : mineR }
  function isMine(o) { return !o.size }
  // The carrier crosses without wrapping, so its hits don't wrap across x
  // either: a carrier just off the left edge can't touch the right edge.
  function carrierDist(c, x, y) { return Math.hypot(x - c.x, dy(c.y, y)) }

  // What the Repeaters draw: each delegate reads its element through these, so
  // every publish() repaints it (see docs/GAMES.md, "Draw without freezing").
  readonly property var offField: ({ x: -500, y: -500, vx: 0, vy: 0, r: 10, size: 1, rot: 0, pts: [], towed: false,
                                     flung: 0, armed: false, hp: 1, life: 1, max: 1, text: "", flash: 0, dead: true })
  function bulletAt(i) { return bullets[i] || offField }
  function debrisAt(i) { return debris[i] || offField }
  function mineAt(i) { return mines[i] || offField }
  function carrierAt(i) { return carriers[i] || offField }
  function boltAt(i) { return bolts[i] || offField }
  function sparkAt(i) { return sparks[i] || offField }
  function blastAt(i) { return blasts[i] || offField }
  function popupAt(i) { return popups[i] || offField }

  readonly property alias shipView: shipView
  readonly property alias debrisView: debrisView
  readonly property alias mineView: mineView
  readonly property alias bulletView: bulletView
  readonly property alias carrierView: carrierView
  readonly property alias popupView: popupView
  readonly property alias tetherLabel: tetherLabel
  readonly property alias subtitleText: subtitleText

  // Physics mutates the arrays in place; the drawing sees them once per frame.
  function publish() {
    bullets = bullets.slice(); debris = debris.slice(); mines = mines.slice()
    carriers = carriers.slice(); bolts = bolts.slice(); sparks = sparks.slice()
    blasts = blasts.slice(); popups = popups.slice()
    shownClock = clock
    if (tether === "cast") { lineDx = dx(shipX, hook.x); lineDy = dy(shipY, hook.y) }
    else if (tether === "tow" && towed) { lineDx = dx(shipX, towed.x); lineDy = dy(shipY, towed.y) }
    else { lineDx = 0; lineDy = 0 }
  }
  function flash(text) { banner = text; bannerTimer.restart() }

  // ---- game flow ------------------------------------------------------------------
  function newGame(seedValue) {
    setSeed(seedValue === undefined ? Date.now() % 2147483647 : seedValue)
    wave = 1; lives = startLives; score = 0; beatHigh = false; nextLifeAt = lifeEvery
    bullets = []; debris = []; mines = []; carriers = []; bolts = []; sparks = []; blasts = []; popups = []
    towed = null; tether = "idle"; tetherCd = 0; towLeft = 0
    leftHeld = false; rightHeld = false; thrustHeld = false; fireHeld = false; fireT = 0
    interT = 0; clock = 0; banner = ""
    spawnShip()
    invuln = 0
    startWave(1)
    banner = ""
    phase = "ready"
    publish()
  }

  function start() {
    if (phase !== "ready") return
    phase = "play"
    invuln = 2
    flash("Wave 1")
  }

  function pause() { if (phase === "play") phase = "paused" }
  function resume() { if (phase === "paused") phase = "play" }
  function togglePause() { if (phase === "play") pause(); else if (phase === "paused") resume() }
  // A click on the field: same as Enter on ready/over, and it also resumes a pause.
  function fieldClicked() {
    if (phase === "over") newGame()
    else if (phase === "ready") start()
    else if (phase === "paused") resume()
  }

  // Key releases don't arrive while away: forget held keys, or the skiff would
  // keep turning and thrusting after the game resumes.
  function lostFocus() {
    leftHeld = false; rightHeld = false; thrustHeld = false; fireHeld = false
    pause()
  }

  function addScore(points) {
    if (points <= 0) return
    score += points
    while (score >= nextLifeAt) {
      nextLifeAt += lifeEvery
      if (lives < maxLives) { lives++; flash("EXTRA SKIFF") }
    }
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  function spawnShip() {
    shipX = fieldW / 2; shipY = fieldH / 2; shipVx = 0; shipVy = 0; shipA = 0
    shipAlive = true
    invuln = invulnTime
  }

  // A free spot at least safeSpawn from the skiff — or, while it's dead and
  // waiting to respawn, from the centre it will respawn at, not from wherever
  // it happened to die.
  function freeSpot() {
    var x = 0, y = 0
    var refX = shipAlive ? shipX : fieldW / 2
    var refY = shipAlive ? shipY : fieldH / 2
    for (var tries = 0; tries < 40; tries++) {
      x = rand() * fieldW; y = rand() * fieldH
      if (dist(x, y, refX, refY) >= safeSpawn) break
    }
    return { x: x, y: y }
  }

  function makeDebris(size, x, y, vx, vy) {
    var d = { x: wrapX(x), y: wrapY(y), vx: vx, vy: vy, size: size, r: Space.debrisRadius(size), hp: size,
              rot: rand() * 360, spin: (rand() - 0.5) * 90, pts: Space.debrisShape(rng),
              towed: false, flung: 0, noRam: 0, dead: false }
    debris.push(d)
    return d
  }

  function makeMine(x, y, vx, vy) {
    var m = { x: wrapX(x), y: wrapY(y), vx: vx, vy: vy, armed: false, towed: false, flung: 0, noRam: 0,
              armGrace: 0, dead: false }
    mines.push(m)
    return m
  }

  function startWave(n) {
    wave = n
    var cfg = Space.wave(n)
    var i, p, a, s
    for (i = 0; i < cfg.debris; i++) {
      p = freeSpot(); a = rand() * Math.PI * 2; s = (28 + rand() * 32) * cfg.speed
      makeDebris(3, p.x, p.y, Math.cos(a) * s, Math.sin(a) * s)
    }
    for (i = 0; i < cfg.mines; i++) {
      p = freeSpot(); a = rand() * Math.PI * 2
      makeMine(p.x, p.y, Math.cos(a) * 14, Math.sin(a) * 14)
    }
    carrierT = cfg.carrier ? carrierDelay : -1
    stormT = cfg.storms ? stormFirst : -1
    storm = ""; windX = 0; windY = 0
    waveTime = 0
    interT = 0
    flash("Wave " + n)
  }

  function waveClear() {
    addScore(250 * wave)
    interT = waveDelay
    carrierT = -1; stormT = -1; storm = ""
    flash("Wave " + wave + " clear  +" + (250 * wave))
  }

  function killShip() {
    if (!shipAlive || invuln > 0) return
    shipAlive = false
    lives--
    burst(shipX, shipY, 26, 170)
    tetherIdle()
    fireHeld = false
    respawnT = respawnDelay
    if (lives > 0) flash(lives === 1 ? "LAST SKIFF" : lives + " SKIFFS LEFT")
  }

  // ---- shots ----------------------------------------------------------------------
  function fire() {
    if (phase !== "play" || !shipAlive || bullets.length >= maxBullets) return false
    var ux = Math.sin(shipA), uy = -Math.cos(shipA)
    bullets.push({ x: wrapX(shipX + ux * 14), y: wrapY(shipY + uy * 14),
                   vx: shipVx + ux * bulletSpeed, vy: shipVy + uy * bulletSpeed, life: bulletLife, dead: false })
    return true
  }

  // ---- breaking things ------------------------------------------------------------
  function burst(x, y, n, speed) {
    for (var i = 0; i < n && sparks.length < 120; i++) {
      var a = rand() * Math.PI * 2, s = speed * (0.3 + rand() * 0.7), l = 0.35 + rand() * 0.45
      sparks.push({ x: x, y: y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: l, max: l, dead: false })
    }
  }
  function popup(x, y, text) { popups.push({ x: x, y: y, text: text, life: 0.9, dead: false }) }

  // A hit shatters debris: a slab into two plates, a plate into two shards. The
  // pieces fly apart either side of the parent's heading, a little faster.
  // mult 0 breaks it for no points (a blast set off by a respawning skiff).
  function hitDebris(d, mult) {
    if (d.dead) return
    d.dead = true
    if (d === towed) tetherIdle()
    var pts = Space.debrisPoints(d.size) * mult
    addScore(pts)
    if (mult > 1) popup(d.x, d.y, "+" + pts + " ×" + mult)
    burst(d.x, d.y, 6 + 3 * d.size, 110)
    if (d.size <= 1) return
    var sp = speedOf(d)
    var base = sp > 1 ? Math.atan2(d.vy, d.vx) : rand() * Math.PI * 2
    var ns = Math.min(Math.max(sp * 1.25, 45), debrisMaxSpeed)
    for (var k = -1; k <= 1; k += 2) {
      var a = base + k * (0.35 + rand() * 0.5)
      var off = d.r * 0.45
      var c = makeDebris(d.size - 1, d.x - Math.sin(base) * off * k, d.y + Math.cos(base) * off * k,
                         Math.cos(a) * ns, Math.sin(a) * ns)
      c.noRam = 0.3
    }
  }

  // A mine goes off: its blast sets off other mines, shatters debris, dents the
  // carrier and hurts the skiff inside its radius.
  function explodeMine(m, mult) {
    if (m.dead) return
    // Towed or (still) flung, this mine is on the skiff's own side: its blast
    // must not kill the skiff that was just carrying or throwing it, even
    // when the ram happens at point-blank range. Read this before dead/tetherIdle
    // touch the flags below.
    var friendly = m.towed || m.flung > 0
    m.dead = true
    if (m === towed) tetherIdle()
    var pts = Space.MINE_POINTS * mult
    addScore(pts)
    if (mult > 1) popup(m.x, m.y, "+" + pts + " ×" + mult)
    blasts.push({ x: m.x, y: m.y, life: 0.5, dead: false })
    burst(m.x, m.y, 16, 150)
    var chain = mult > 0 ? 1 : 0
    if (shipAlive && !friendly && dist(m.x, m.y, shipX, shipY) < blastR + shipR) killShip()
    var i, n = mines.length
    for (i = 0; i < n; i++) if (!mines[i].dead && dist(m.x, m.y, mines[i].x, mines[i].y) < blastR) explodeMine(mines[i], chain)
    n = debris.length
    for (i = 0; i < n; i++) {
      var d = debris[i]
      if (!d.dead && d.noRam <= 0 && dist(m.x, m.y, d.x, d.y) < blastR + d.r * 0.5) hitDebris(d, chain)
    }
    for (i = 0; i < carriers.length; i++)
      if (!carriers[i].dead && carrierDist(carriers[i], m.x, m.y) < blastR + carrierR) damageCarrier(carriers[i], 2, chain)
  }

  function damageCarrier(c, hits, mult) {
    if (c.dead) return
    c.hp -= hits
    c.flash = 0.15
    burst(c.x, c.y, 4, 90)
    if (c.hp > 0) return
    c.dead = true
    var pts = Space.CARRIER_POINTS * Math.max(mult, 1)
    if (mult > 0) addScore(pts)
    if (mult > 0) popup(c.x, c.y, "+" + pts)
    blasts.push({ x: c.x, y: c.y, life: 0.7, dead: false })
    burst(c.x, c.y, 40, 200)
  }

  // ---- the tether -----------------------------------------------------------------
  // Shift/↓/S: cast the grapple, or let go of the load (a fling).
  function tetherAction() {
    if (phase !== "play" || !shipAlive) return
    if (tether === "tow") release(true)
    else if (tether === "idle" && tetherCd <= 0) cast()
  }

  function cast() {
    var ux = Math.sin(shipA), uy = -Math.cos(shipA)
    hook = { x: wrapX(shipX + ux * 14), y: wrapY(shipY + uy * 14),
             vx: shipVx + ux * hookSpeed, vy: shipVy + uy * hookSpeed, travel: 0 }
    tether = "cast"
  }

  function latch(o) {
    towed = o
    o.towed = true
    o.flung = 0
    if (isMine(o)) o.armed = false
    tether = "tow"
    towLeft = towTime
  }

  // Let go. A fling boosts the load along its motion and makes it a battering
  // ram for a moment; a line that runs out just drops it.
  function release(fling) {
    var o = towed
    tetherIdle()
    if (!o || !fling) return
    var s = speedOf(o)
    var ns = Math.min(Math.max(s * flingBoost, 120), flingMax)
    if (s > 1) { o.vx *= ns / s; o.vy *= ns / s }
    else { o.vx = Math.sin(shipA) * ns; o.vy = -Math.cos(shipA) * ns }
    o.flung = flingTime
  }

  // Letting go of a mine (dropped, ran out or snapped) leaves it close to the
  // skiff; give it a moment before it can re-arm, or it homes in from point
  // blank the instant it's off the line.
  function tetherIdle() {
    if (towed) {
      towed.towed = false
      if (isMine(towed)) towed.armGrace = mineDropGrace
    }
    towed = null
    if (tether !== "idle") tetherCd = tetherCooldown
    tether = "idle"
  }

  function updateTether(dt) {
    tetherCd = Math.max(0, tetherCd - dt)
    if (tether === "cast") {
      var h = hook
      h.x = wrapX(h.x + h.vx * dt); h.y = wrapY(h.y + h.vy * dt)
      h.travel += hookSpeed * dt
      var i
      for (i = 0; i < debris.length; i++) {
        var d = debris[i]
        if (!d.dead && dist(h.x, h.y, d.x, d.y) < d.r + 6) { latch(d); return }
      }
      for (i = 0; i < mines.length; i++) {
        var m = mines[i]
        if (!m.dead && dist(h.x, h.y, m.x, m.y) < mineR + 6) { latch(m); return }
      }
      if (h.travel >= hookRange) tetherIdle()
      return
    }
    if (tether !== "tow") return
    var o = towed
    if (!o || o.dead) { tetherIdle(); return }
    towLeft -= dt
    if (towLeft <= 0) { release(false); flash("LINE RAN OUT"); return }
    // A spring line that only pulls: past its length it drags the load toward
    // the skiff and the skiff toward the load, each by the other's share of mass.
    var ex = dx(shipX, o.x), ey = dy(shipY, o.y)
    var dd = Math.hypot(ex, ey)
    if (dd > ropeSnap) { tetherIdle(); flash("LINE SNAPPED"); return }
    if (dd <= ropeLen || dd < 0.001) return
    var nx = ex / dd, ny = ey / dd
    var rv = (o.vx - shipVx) * nx + (o.vy - shipVy) * ny
    var f = Math.max(0, ropeK * (dd - ropeLen) + ropeDamp * rv)
    var mo = massOf(o), total = mo + shipMass
    var j = f * dt * 2
    o.vx -= nx * j * shipMass / total; o.vy -= ny * j * shipMass / total
    shipVx += nx * j * mo / total; shipVy += ny * j * mo / total
  }

  // The towed load and flung loads break what they hit.
  function rams() {
    var rammers = []
    var i, k
    for (i = 0; i < debris.length; i++) if (!debris[i].dead && (debris[i].towed || debris[i].flung > 0)) rammers.push(debris[i])
    for (i = 0; i < mines.length; i++) if (!mines[i].dead && (mines[i].towed || mines[i].flung > 0)) rammers.push(mines[i])
    for (k = 0; k < rammers.length; k++) {
      var r = rammers[k]
      if (r.dead) continue
      var mult = r.towed ? 2 : 3
      var rr = radiusOf(r)
      var hit = false
      var n = debris.length
      for (i = 0; i < n && !r.dead; i++) {
        var d = debris[i]
        if (d === r || d.dead || d.towed || d.noRam > 0) continue
        if (dist(r.x, r.y, d.x, d.y) < rr + d.r) { hitDebris(d, mult); hit = true; rammed(r, mult) }
      }
      n = mines.length
      for (i = 0; i < n && !r.dead; i++) {
        var m = mines[i]
        if (m === r || m.dead || m.towed || m.noRam > 0) continue
        if (dist(r.x, r.y, m.x, m.y) < rr + mineR) { explodeMine(m, mult); hit = true; rammed(r, mult) }
      }
      for (i = 0; i < carriers.length && !r.dead; i++) {
        var c = carriers[i]
        if (c.dead || r.noRam > 0) continue
        if (carrierDist(c, r.x, r.y) < rr + carrierR) { damageCarrier(c, 2, mult); r.noRam = 0.4; rammed(r, mult) }
      }
    }
  }
  // A ram wears the load down: debris loses a point of hull, a mine goes off.
  function rammed(r, mult) {
    if (r.dead) return
    if (isMine(r)) { explodeMine(r, mult); return }
    r.hp--
    if (r.hp <= 0) hitDebris(r, mult)
  }

  // ---- physics ----------------------------------------------------------------------
  function step(dt) {
    clock += dt
    if (phase === "ready") { drift(dt); return }
    if (phase !== "play") return
    waveTime += dt
    updateStorm(dt)
    updateShip(dt)
    updateTether(dt)
    moveBullets(dt)
    drift(dt)
    moveMines(dt)
    updateCarrier(dt)
    moveBolts(dt)
    collide()
    rams()
    updateFx(dt)
    compactAll()

    if (!shipAlive) {
      respawnT -= dt
      if (respawnT <= 0) {
        if (lives > 0) spawnShip()
        else { phase = "over"; banner = ""; return }
      }
    }
    if (interT > 0) {
      interT -= dt
      if (interT <= 0) startWave(wave + 1)
    } else if (debris.length === 0 && mines.length === 0 && carriers.length === 0 && carrierT <= 0) {
      waveClear()
    }
  }

  function updateStorm(dt) {
    if (stormT < 0) return
    stormT -= dt
    if (stormT > 0) return
    if (storm === "") {
      var a = rand() * Math.PI * 2
      windX = Math.cos(a); windY = Math.sin(a)
      storm = "warn"; stormT = stormWarn
      flash("ION GUST INCOMING")
    } else if (storm === "warn") {
      storm = "gust"; stormT = stormGust
    } else {
      storm = ""; stormT = 10 + rand() * 6
    }
  }

  function updateShip(dt) {
    if (!shipAlive) return
    if (invuln > 0) invuln = Math.max(0, invuln - dt)
    var turn = (rightHeld ? 1 : 0) - (leftHeld ? 1 : 0)
    if (turn !== 0) shipA = normAngle(shipA + turn * turnRate * dt)
    var vx = shipVx, vy = shipVy
    if (thrustHeld) { vx += Math.sin(shipA) * thrustAccel * dt; vy -= Math.cos(shipA) * thrustAccel * dt }
    if (storm === "gust") { vx += windX * stormAccel * dt; vy += windY * stormAccel * dt }
    var k = 1 - drag * dt
    vx *= k; vy *= k
    var s = Math.hypot(vx, vy)
    if (s > maxSpeed) { vx *= maxSpeed / s; vy *= maxSpeed / s }
    shipVx = vx; shipVy = vy
    shipX = wrapX(shipX + vx * dt)
    shipY = wrapY(shipY + vy * dt)
    if (fireHeld) {
      fireT -= dt
      if (fireT <= 0) { fire(); fireT = autoFire }
    }
  }

  function moveBullets(dt) {
    for (var i = 0; i < bullets.length; i++) {
      var b = bullets[i]
      b.life -= dt
      if (b.life <= 0) { b.dead = true; continue }
      b.x = wrapX(b.x + b.vx * dt); b.y = wrapY(b.y + b.vy * dt)
    }
  }

  // Debris (and, before the game starts, the whole field) drifts and spins.
  function drift(dt) {
    var gust = storm === "gust" && phase === "play"
    for (var i = 0; i < debris.length; i++) {
      var d = debris[i]
      if (gust) { d.vx += windX * stormAccel * 0.5 * dt; d.vy += windY * stormAccel * 0.5 * dt }
      var s = speedOf(d), cap = d.flung > 0 ? flingMax : debrisMaxSpeed
      if (s > cap && !d.towed) { d.vx *= cap / s; d.vy *= cap / s }
      d.x = wrapX(d.x + d.vx * dt); d.y = wrapY(d.y + d.vy * dt)
      d.rot = (d.rot + d.spin * dt) % 360
      if (d.flung > 0) d.flung = Math.max(0, d.flung - dt)
      if (d.noRam > 0) d.noRam = Math.max(0, d.noRam - dt)
    }
    if (phase === "ready") {
      for (var j = 0; j < mines.length; j++) {
        mines[j].x = wrapX(mines[j].x + mines[j].vx * dt); mines[j].y = wrapY(mines[j].y + mines[j].vy * dt)
      }
    }
  }

  // Mines sleep until the skiff comes within mineArmRange, then home in on it
  // for good. A towed mine is disarmed.
  function moveMines(dt) {
    var cap = Space.wave(wave).mineSpeed
    var gust = storm === "gust"
    for (var i = 0; i < mines.length; i++) {
      var m = mines[i]
      // A towed or flung mine is on the skiff's side: it neither arms nor homes.
      if (!m.towed && m.flung <= 0) {
        var ex = dx(m.x, shipX), ey = dy(m.y, shipY), d = Math.hypot(ex, ey)
        if (!m.armed && shipAlive && d < mineArmRange && m.armGrace <= 0) m.armed = true
        if (m.armed && shipAlive && d > 0.001) {
          m.vx += ex / d * mineAccel * dt; m.vy += ey / d * mineAccel * dt
        } else if (m.armed) {
          m.vx *= 1 - 1.5 * dt; m.vy *= 1 - 1.5 * dt       // lost its target: slows
        }
        var s = speedOf(m), c = m.flung > 0 ? flingMax : (m.armed ? cap : 30)
        if (s > c) { m.vx *= c / s; m.vy *= c / s }
      }
      if (gust) { m.vx += windX * stormAccel * 0.5 * dt; m.vy += windY * stormAccel * 0.5 * dt }
      m.x = wrapX(m.x + m.vx * dt); m.y = wrapY(m.y + m.vy * dt)
      if (m.flung > 0) m.flung = Math.max(0, m.flung - dt)
      if (m.noRam > 0) m.noRam = Math.max(0, m.noRam - dt)
      if (m.armGrace > 0) m.armGrace = Math.max(0, m.armGrace - dt)
    }
  }

  // The carrier crosses once from one side to the other (it doesn't wrap),
  // bobbing, firing bolts at the skiff and laying mines behind it.
  function spawnCarrier() {
    var cfg = Space.wave(wave)
    var fromLeft = rand() < 0.5
    var y = 90 + rand() * (fieldH - 180)
    carriers.push({ x: fromLeft ? -40 : fieldW + 40, y: y, baseY: y, vx: fromLeft ? carrierSpeed : -carrierSpeed,
                    t: 0, hp: cfg.carrierHp, maxHp: cfg.carrierHp, fireT: 1.2, mineT: carrierMineEvery, flash: 0, dead: false })
    flash("CARRIER INBOUND")
  }

  function updateCarrier(dt) {
    if (carrierT > 0) {
      carrierT -= dt
      if (carrierT <= 0) { carrierT = -1; spawnCarrier() }
    }
    var cfg = Space.wave(wave)
    for (var i = 0; i < carriers.length; i++) {
      var c = carriers[i]
      if (c.dead) continue
      c.t += dt
      c.x += c.vx * dt
      c.y = c.baseY + Math.sin(c.t * 1.4) * 30
      if (c.flash > 0) c.flash = Math.max(0, c.flash - dt)
      if ((c.vx > 0 && c.x > fieldW + 60) || (c.vx < 0 && c.x < -60)) { c.dead = true; continue }
      c.fireT -= dt
      if (c.fireT <= 0) {
        c.fireT = cfg.carrierFire
        if (shipAlive) {
          var ex = dx(c.x, shipX), ey = dy(c.y, shipY), d = Math.max(1, Math.hypot(ex, ey))
          bolts.push({ x: c.x, y: c.y, vx: ex / d * boltSpeed, vy: ey / d * boltSpeed, life: boltLife, dead: false })
        }
      }
      c.mineT -= dt
      if (c.mineT <= 0 && c.x > 0 && c.x < fieldW) {
        c.mineT = carrierMineEvery
        makeMine(c.x - Math.sign(c.vx) * 30, c.y, 0, 0)
      }
    }
  }

  function moveBolts(dt) {
    for (var i = 0; i < bolts.length; i++) {
      var b = bolts[i]
      b.life -= dt
      if (b.life <= 0) { b.dead = true; continue }
      b.x = wrapX(b.x + b.vx * dt); b.y = wrapY(b.y + b.vy * dt)
    }
  }

  function collide() {
    var i, j
    // Bullets: the towed load is on your side, so they pass through it.
    for (i = 0; i < bullets.length; i++) {
      var b = bullets[i]
      if (b.dead) continue
      var n = debris.length
      for (j = 0; j < n && !b.dead; j++) {
        var d = debris[j]
        if (!d.dead && !d.towed && dist(b.x, b.y, d.x, d.y) < d.r + 2) { b.dead = true; hitDebris(d, 1) }
      }
      for (j = 0; j < mines.length && !b.dead; j++) {
        var m = mines[j]
        if (!m.dead && !m.towed && dist(b.x, b.y, m.x, m.y) < mineR + 3) { b.dead = true; explodeMine(m, 1) }
      }
      for (j = 0; j < carriers.length && !b.dead; j++) {
        var c = carriers[j]
        if (!c.dead && carrierDist(c, b.x, b.y) < carrierR) { b.dead = true; damageCarrier(c, 1, 1) }
      }
    }
    if (!shipAlive) return
    // The skiff. While it shimmers after a respawn nothing hurts it; a mine it
    // touches then goes off for no points.
    for (i = 0; i < mines.length && shipAlive; i++) {
      var mm = mines[i]
      if (!mm.dead && !mm.towed && mm.flung <= 0 && dist(shipX, shipY, mm.x, mm.y) < shipR + mineR) explodeMine(mm, invuln > 0 ? 0 : 1)
    }
    if (invuln > 0 || !shipAlive) return
    for (i = 0; i < debris.length; i++) {
      var dd = debris[i]
      if (!dd.dead && !dd.towed && dd.flung <= 0 && dist(shipX, shipY, dd.x, dd.y) < shipR + dd.r * 0.85) { killShip(); return }
    }
    for (i = 0; i < bolts.length; i++)
      if (!bolts[i].dead && dist(shipX, shipY, bolts[i].x, bolts[i].y) < shipR + 3) { bolts[i].dead = true; killShip(); return }
    for (i = 0; i < carriers.length; i++)
      if (!carriers[i].dead && carrierDist(carriers[i], shipX, shipY) < shipR + carrierR) { killShip(); return }
  }

  function updateFx(dt) {
    var i
    for (i = 0; i < sparks.length; i++) {
      var s = sparks[i]
      s.life -= dt
      if (s.life <= 0) { s.dead = true; continue }
      s.x += s.vx * dt; s.y += s.vy * dt
      s.vx *= 1 - 2 * dt; s.vy *= 1 - 2 * dt
    }
    for (i = 0; i < blasts.length; i++) { blasts[i].life -= dt; if (blasts[i].life <= 0) blasts[i].dead = true }
    for (i = 0; i < popups.length; i++) { popups[i].life -= dt; popups[i].y -= 30 * dt; if (popups[i].life <= 0) popups[i].dead = true }
  }

  function compact(arr) {
    var j = 0
    for (var i = 0; i < arr.length; i++) if (!arr[i].dead) arr[j++] = arr[i]
    arr.length = j
  }
  function compactAll() {
    compact(bullets); compact(debris); compact(mines); compact(carriers)
    compact(bolts); compact(sparks); compact(blasts); compact(popups)
  }

  FrameAnimation {
    running: game.phase === "play" || game.phase === "ready"
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n && (game.phase === "play" || game.phase === "ready"); i++) game.step(dt / n)
      game.publish()
    }
  }

  // The one Timer: it only fades the banner text.
  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }

  // What a key does, pulled out of the event handler so the rules test can drive
  // it directly (Keys.onPressed's KeyEvent can't be built from plain JS). Returns
  // true when the key meant something, so the caller knows to accept the event.
  function keyDown(key) {
    switch (key) {
    case Qt.Key_Left: case Qt.Key_A: leftHeld = true; break
    case Qt.Key_Right: case Qt.Key_D: rightHeld = true; break
    case Qt.Key_Up: case Qt.Key_W: thrustHeld = true; break
    case Qt.Key_Space:
      if (phase === "ready") start()
      else if (phase === "paused") resume()
      else if (phase === "play") { fireHeld = true; fire(); fireT = autoFire }
      break
    case Qt.Key_Shift: case Qt.Key_Down: case Qt.Key_S: tetherAction(); break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter:
      if (phase === "over") newGame()
      else if (phase === "ready") start()
      else if (phase === "paused") resume()
      else if (phase === "play") fire()
      break
    case Qt.Key_Escape: quitRequested(); break
    default: return false
    }
    return true
  }

  // Held keys are flags read by step(); auto-repeat is ignored because holding
  // is already handled (Space auto-fires on its own cooldown).
  Keys.onPressed: function (e) {
    if (e.isAutoRepeat) { e.accepted = true; return }
    if (keyDown(e.key)) e.accepted = true
  }
  Keys.onReleased: function (e) {
    if (e.isAutoRepeat) return
    switch (e.key) {
    case Qt.Key_Left: case Qt.Key_A: leftHeld = false; break
    case Qt.Key_Right: case Qt.Key_D: rightHeld = false; break
    case Qt.Key_Up: case Qt.Key_W: thrustHeld = false; break
    case Qt.Key_Space: fireHeld = false; break
    }
  }

  Component.onCompleted: newGame()

  // ---- drawing ------------------------------------------------------------------------
  // Everything is vector line art on Canvases, painted once per shape (and on a
  // theme change) and moved by Item x/y/rotation, so a frame costs no repaints.
  readonly property var starList: Space.stars(70, fieldW, fieldH)
  readonly property var streakList: Space.stars(28, fieldW, fieldH)

  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)
    clip: true

    Rectangle { anchors.fill: parent; color: game.color("dark_background", "#13141c"); radius: 6 }

    Repeater {
      model: game.starList.length
      delegate: Rectangle {
        required property int index
        readonly property var st: game.starList[index]
        x: st.x; y: st.y; width: st.s; height: st.s
        color: game.color("foreground", "#a9b1d6")
        opacity: st.b * 0.6
      }
    }

    // Ion gust streaks along the wind.
    Repeater {
      model: game.storm === "" ? 0 : game.streakList.length
      delegate: Rectangle {
        required property int index
        readonly property var st: game.streakList[index]
        readonly property real run: game.shownClock * (game.storm === "gust" ? 420 : 120) * (0.6 + st.b)
        x: Space.wrap(st.x + game.windX * run, game.fieldW + 60) - 30
        y: Space.wrap(st.y + game.windY * run, game.fieldH + 60) - 30
        width: 26 + st.b * 40; height: 1.5
        rotation: Math.atan2(game.windY, game.windX) * 180 / Math.PI
        color: game.color("blue", "#7aa2f7")
        opacity: game.storm === "gust" ? 0.38 : 0.16
      }
    }

    // Debris: torn hull polygons.
    Repeater {
      id: debrisView
      model: game.debris.length
      delegate: Item {
        id: dv
        required property int index
        readonly property real r: game.debrisAt(index).r
        x: game.debrisAt(index).x - r
        y: game.debrisAt(index).y - r
        width: r * 2; height: r * 2
        rotation: game.debrisAt(index).rot
        readonly property var pts: game.debrisAt(index).pts
        readonly property string ink: game.debrisAt(index).towed ? game.color("green", "#9ece6a")
                                    : game.debrisAt(index).flung > 0 ? game.color("yellow", "#e0af68")
                                    : game.color("cyan", "#7dcfff")
        Canvas {
          anchors.fill: parent; anchors.margins: -8
          property var p: dv.pts
          property string c: dv.ink
          property real rr: dv.r
          onPChanged: requestPaint()
          onCChanged: requestPaint()
          onRrChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (!p || p.length < 3) return
            ctx.translate(width / 2, height / 2)
            ctx.beginPath()
            for (var i = 0; i < p.length; i++) {
              if (i === 0) ctx.moveTo(p[i].x * rr, p[i].y * rr); else ctx.lineTo(p[i].x * rr, p[i].y * rr)
            }
            ctx.closePath()
            ctx.globalAlpha = 0.1; ctx.fillStyle = c; ctx.fill(); ctx.globalAlpha = 1
            ctx.lineJoin = "round"
            ctx.shadowColor = c; ctx.shadowBlur = 7
            ctx.strokeStyle = c; ctx.lineWidth = 1.8
            ctx.stroke()
            // a rivet line across the plate
            ctx.shadowBlur = 0; ctx.globalAlpha = 0.45; ctx.lineWidth = 1
            ctx.beginPath(); ctx.moveTo(-rr * 0.35, -rr * 0.1); ctx.lineTo(rr * 0.3, rr * 0.2); ctx.stroke()
          }
        }
      }
    }

    // Mines: a ring with four prongs; orange asleep, red and blinking when armed.
    Repeater {
      id: mineView
      model: game.mines.length
      delegate: Item {
        id: mv
        required property int index
        x: game.mineAt(index).x - game.mineR
        y: game.mineAt(index).y - game.mineR
        width: game.mineR * 2; height: width
        readonly property bool armed: game.mineAt(index).armed
        readonly property string ink: game.mineAt(index).towed ? game.color("green", "#9ece6a")
                                    : armed ? game.color("red", "#f7768e") : game.color("orange", "#ff9e64")
        rotation: game.shownClock * (armed ? 240 : 40)
        opacity: armed && Math.floor(game.shownClock * 8) % 2 === 1 ? 0.55 : 1
        Canvas {
          anchors.fill: parent; anchors.margins: -8
          property string c: mv.ink
          onCChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.translate(width / 2, height / 2)
            var r = game.mineR
            ctx.strokeStyle = c; ctx.shadowColor = c; ctx.shadowBlur = 8; ctx.lineWidth = 1.8
            ctx.beginPath(); ctx.arc(0, 0, r * 0.6, 0, Math.PI * 2); ctx.stroke()
            ctx.beginPath()
            for (var k = 0; k < 4; k++) {
              var a = k * Math.PI / 2
              ctx.moveTo(Math.cos(a) * r * 0.6, Math.sin(a) * r * 0.6)
              ctx.lineTo(Math.cos(a) * r * 1.15, Math.sin(a) * r * 1.15)
            }
            ctx.stroke()
            ctx.fillStyle = c; ctx.beginPath(); ctx.arc(0, 0, 2, 0, Math.PI * 2); ctx.fill()
          }
        }
      }
    }

    // The carrier: a long hexagonal hull with a sensor ring, flashing when hit.
    Repeater {
      id: carrierView
      model: game.carriers.length
      delegate: Item {
        id: cv
        required property int index
        x: game.carrierAt(index).x - 40
        y: game.carrierAt(index).y - 20
        width: 80; height: 40
        readonly property string ink: game.carrierAt(index).flash > 0 ? game.color("bright_foreground", "#c0caf5")
                                                                     : game.color("magenta", "#bb9af7")
        readonly property real health: game.carrierAt(index).hp / Math.max(1, game.carrierAt(index).maxHp || 1)
        Canvas {
          anchors.fill: parent; anchors.margins: -8
          property string c: cv.ink
          onCChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.translate(width / 2, height / 2)
            ctx.strokeStyle = c; ctx.shadowColor = c; ctx.shadowBlur = 9; ctx.lineWidth = 2; ctx.lineJoin = "round"
            ctx.beginPath()
            ctx.moveTo(-38, 0); ctx.lineTo(-24, -10); ctx.lineTo(24, -10); ctx.lineTo(38, 0)
            ctx.lineTo(24, 10); ctx.lineTo(-24, 10); ctx.closePath()
            ctx.globalAlpha = 0.12; ctx.fillStyle = c; ctx.fill(); ctx.globalAlpha = 1
            ctx.stroke()
            ctx.beginPath(); ctx.arc(0, -10, 7, Math.PI, 0); ctx.stroke()
            ctx.beginPath(); ctx.moveTo(-30, 0); ctx.lineTo(30, 0); ctx.globalAlpha = 0.5; ctx.stroke()
            ctx.globalAlpha = 1
            for (var k = -2; k <= 2; k++) { ctx.beginPath(); ctx.arc(k * 9, 5, 1.6, 0, Math.PI * 2); ctx.fill() }
          }
        }
        Rectangle {
          x: 10; y: -8; height: 3; radius: 1.5
          width: 60 * cv.health
          color: game.color("magenta", "#bb9af7")
          opacity: 0.8
        }
      }
    }

    // Tether line and grapple.
    Rectangle {
      visible: game.tether !== "idle" && game.shipAlive
      x: game.shipX; y: game.shipY - height / 2
      width: Math.hypot(game.lineDx, game.lineDy); height: 1.6
      transformOrigin: Item.Left
      rotation: Math.atan2(game.lineDy, game.lineDx) * 180 / Math.PI
      color: game.color("green", "#9ece6a")
      opacity: game.tether === "tow" && game.towLeft < 2 && Math.floor(game.shownClock * 6) % 2 === 1 ? 0.4 : 0.9
    }
    Rectangle {
      visible: game.tether === "cast" && game.shipAlive
      x: game.shipX + game.lineDx - 4; y: game.shipY + game.lineDy - 4
      width: 8; height: 8; rotation: 45
      color: "transparent"
      border.width: 1.5; border.color: game.color("green", "#9ece6a")
    }

    // Bullets and carrier bolts.
    Repeater {
      id: bulletView
      model: game.bullets.length
      delegate: Rectangle {
        required property int index
        x: game.bulletAt(index).x - 2; y: game.bulletAt(index).y - 2
        width: 4; height: 4; radius: 2
        color: game.color("bright_foreground", "#c0caf5")
        Rectangle { anchors.centerIn: parent; width: 9; height: 9; radius: 4.5; color: parent.color; opacity: 0.18 }
      }
    }
    Repeater {
      model: game.bolts.length
      delegate: Rectangle {
        required property int index
        x: game.boltAt(index).x - 4; y: game.boltAt(index).y - 4
        width: 8; height: 8; rotation: 45
        color: "transparent"
        border.width: 2; border.color: game.color("yellow", "#e0af68")
      }
    }

    // The skiff: an arrowhead with a forked tail and the tether winch ring.
    Item {
      id: shipView
      x: game.shipX - 16; y: game.shipY - 16
      width: 32; height: 32
      visible: game.shipAlive
      rotation: game.shipA * 180 / Math.PI
      opacity: game.invuln > 0 && Math.floor(game.shownClock * 10) % 2 === 1 ? 0.35 : 1
      Canvas {
        id: flame
        anchors.fill: parent
        visible: game.thrusting
        scale: 0.85 + 0.3 * (Math.floor(game.shownClock * 30) % 2)
        property string c: game.color("orange", "#ff9e64")
        onCChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.translate(width / 2, height / 2)
          ctx.strokeStyle = c; ctx.shadowColor = c; ctx.shadowBlur = 6; ctx.lineWidth = 1.6
          ctx.beginPath(); ctx.moveTo(-3.5, 9); ctx.lineTo(0, 16); ctx.lineTo(3.5, 9); ctx.stroke()
        }
      }
      Canvas {
        anchors.fill: parent
        property string c: game.color("accent", "#7aa2f7")
        property string w: game.color("green", "#9ece6a")
        onCChanged: requestPaint()
        onWChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.translate(width / 2, height / 2)
          ctx.lineJoin = "round"
          ctx.strokeStyle = c; ctx.shadowColor = c; ctx.shadowBlur = 8; ctx.lineWidth = 1.8
          ctx.beginPath()
          ctx.moveTo(0, -14); ctx.lineTo(7, 5); ctx.lineTo(10, 12); ctx.lineTo(4, 8)
          ctx.lineTo(-4, 8); ctx.lineTo(-10, 12); ctx.lineTo(-7, 5); ctx.closePath()
          ctx.globalAlpha = 0.15; ctx.fillStyle = c; ctx.fill(); ctx.globalAlpha = 1
          ctx.stroke()
          ctx.strokeStyle = w; ctx.shadowColor = w; ctx.lineWidth = 1.4
          ctx.beginPath(); ctx.arc(0, 0, 3, 0, Math.PI * 2); ctx.stroke()
        }
      }
    }

    // Blast rings, sparks and score pop-ups.
    Repeater {
      model: game.blasts.length
      delegate: Rectangle {
        required property int index
        readonly property real k: 1 - Math.max(0, game.blastAt(index).life) / 0.5
        width: game.blastR * 2 * Math.min(1, 0.3 + k); height: width; radius: width / 2
        x: game.blastAt(index).x - width / 2; y: game.blastAt(index).y - width / 2
        color: "transparent"
        border.width: 2; border.color: game.color("red", "#f7768e")
        opacity: Math.max(0, 1 - k)
      }
    }
    Repeater {
      model: game.sparks.length
      delegate: Rectangle {
        required property int index
        x: game.sparkAt(index).x - 1; y: game.sparkAt(index).y - 1
        width: 2; height: 2
        color: game.color("yellow", "#e0af68")
        opacity: game.sparkAt(index).life / game.sparkAt(index).max
      }
    }
    Repeater {
      id: popupView
      model: game.popups.length
      delegate: Text {
        required property int index
        x: game.popupAt(index).x - width / 2; y: game.popupAt(index).y - 10
        text: game.popupAt(index).text
        color: game.color("bright_foreground", "#c0caf5")
        opacity: Math.min(1, game.popupAt(index).life * 2)
        font.pixelSize: 14; font.bold: true; font.family: "monospace"
      }
    }

    // HUD
    Rectangle {
      width: parent.width; height: 48
      color: game.color("lighter_background", "#24283b")
      radius: 6
      opacity: 0.85
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.leftMargin: 16
        spacing: 24
        Text { text: "SCORE " + game.score; color: game.color("bright_foreground", "#c0caf5"); font.pixelSize: 18; font.bold: true; font.family: "monospace" }
        Text { text: "HIGH " + game.highScore; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 18; font.family: "monospace" }
      }
      Text {
        anchors.centerIn: parent
        text: "WAVE " + game.wave + (game.storm === "gust" ? " · ION GUST" : "")
        color: game.color("accent", "#7aa2f7"); font.pixelSize: 16; font.bold: true; font.family: "monospace"
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 16
        spacing: 6
        Text {
          id: tetherLabel
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: 10
          text: game.tether === "tow" ? "TOW " + Math.max(0, game.towLeft).toFixed(1)
              : game.tether === "cast" ? "CAST"
              : game.tetherCd > 0 ? "REEL" : "TETHER"
          color: game.tether === "tow" ? game.color("bright_foreground", "#c0caf5")
               : game.tetherCd > 0 ? game.color("foreground", "#a9b1d6") : game.color("accent", "#7aa2f7")
          opacity: game.tetherCd > 0 && game.tether === "idle" ? 0.5 : 1
          font.pixelSize: 14; font.bold: true; font.family: "monospace"
        }
        Repeater {
          model: Math.max(0, game.lives)
          delegate: Canvas {
            width: 14; height: 18
            property string c: game.color("accent", "#7aa2f7")
            onCChanged: requestPaint()
            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              ctx.strokeStyle = c; ctx.lineWidth = 1.5; ctx.lineJoin = "round"
              ctx.beginPath()
              ctx.moveTo(7, 1); ctx.lineTo(11, 12); ctx.lineTo(13, 17); ctx.lineTo(9, 14)
              ctx.lineTo(5, 14); ctx.lineTo(1, 17); ctx.lineTo(3, 12); ctx.closePath()
              ctx.stroke()
            }
          }
        }
      }
    }

    // Messages, with a backdrop for PAUSED and GAME OVER.
    Rectangle {
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 32
      radius: 8
      visible: game.phase === "paused" || game.phase === "over" || game.phase === "ready"
      color: game.color("dark_background", "#13141c")
      opacity: 0.9
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.centerIn: parent
      anchors.verticalCenterOffset: game.phase === "play" ? -120 : game.phase === "ready" ? 120 : 0
      spacing: 10
      visible: title.text !== ""
      Text {
        id: title
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : game.phase === "ready" ? "TETHERWAKE"
            : game.banner
        color: game.color("bright_foreground", "#c0caf5")
        font.pixelSize: game.phase === "play" ? 26 : 40; font.bold: true; font.family: "monospace"
      }
      Text {
        id: subtitleText
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "Score " + game.score + "  ·  Wave " + game.wave + (game.beatHigh ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "ready" ? "Space to launch\n← → or A/D turn  ·  ↑ or W thrust  ·  Space fire  ·  P pause\nShift, ↓ or S casts the tether: tow wreckage into hazards,\ncast again to fling it for triple points"
            : ""
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 15; font.family: "monospace"
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        game.forceActiveFocus()
        game.fieldClicked()
      }
    }
  }
}
