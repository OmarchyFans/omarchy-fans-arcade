import QtQuick
import "physics.js" as Physics
import "cpu.js" as Cpu

// Surge Rink: an air-hockey duel on a table seen from above. It plays in a fixed
// 960x600 field that is scaled to fit the window, so physics never depend on the
// window size.
//
// Rules
// - First to 7 goals wins the match. After a goal the side that conceded serves:
//   the puck is set down at rest in the middle of its half and play starts when
//   either striker touches it.
// - Shot clock: the puck may stay in one half (serve included) for 7 s. Then it
//   is handed over: the other side serves. Nobody can stall a match.
// - Strikers stay in their own half. The puck has momentum, slows with friction
//   and bounces off the rails and the goal posts; a puck whose centre crosses a
//   goal line inside the mouth is a goal.
// - SURGE (this game's own mechanic): hold the surge key to charge your striker
//   (a ring fills over 0.7 s; you move slower while charging). A strike while
//   charged, or within 0.3 s after letting go, is a smash: the puck leaves up to
//   1.9x faster and runs "hot" for 1.6 s, barely slowing and keeping its speed off
//   the rails. A smash costs a 0.6 s cooldown.
// - SWERVE: a glancing strike (the striker moving across the puck) puts spin on
//   it, and a spinning puck curves.
//
// Modes: "cpu" (1 player vs CPU, a run of matches) and "versus" (2 players).
// In a 1P run each match you win moves the CPU up a tier (faster, sharper, more
// surges); losing a match ends the run.
//
// Score and the high score (1P only; 2P matches never touch them):
//   +10 x tier per goal you score, +10 x tier more when it was a hot (surged) goal,
//   +100 x tier + 20 x margin for every match won.
//   Tie rule: the high score only moves when the run's score goes strictly past it,
//   so equalling the best is not a new high score (beatHigh stays false).
//
// Controls: P1 WASD + F/G/H or Space (surge); in 1P also the arrows + Enter, and the mouse
// moves P1's striker (hold a button to surge). P2 arrows + Ctrl/Shift/Enter.
// P pauses (P, Space or Enter resumes), Esc quits, Enter plays again after a game over.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real fieldW: 960
  readonly property real fieldH: 600
  readonly property real hudH: 58
  readonly property int target: 7                 // goals to win a match
  readonly property real keySpeed: 560            // px/s, keyboard striker
  readonly property real mouseSpeed: 1500         // px/s, the most a mouse striker moves
  readonly property real chargeTime: 0.7          // s to a full surge
  readonly property real surgeMin: 0.25           // charge below this is no smash
  readonly property real armWindow: 0.3           // s a released charge still counts
  readonly property real surgeCool: 0.6
  readonly property real surgeHot: 1.6
  readonly property real chargeSlow: 0.7          // move speed while charging
  readonly property real goalPause: 1.1
  readonly property real shotClock: 7             // s the puck may stay in one half
  readonly property var table: ({ L: 56, R: 904, T: 80, B: 578, cy: 329, mouth: 78, r: 15, sr: 28 })
  readonly property real midX: (table.L + table.R) / 2
  readonly property var levels: Cpu.LEVELS

  // ---- state --------------------------------------------------------------------
  property string phase: "select"   // select | serve | play | goal | won | paused | over
  property string pausedFrom: ""
  property string mode: "cpu"       // cpu | versus
  property int selRow: 0            // menu: 0 = mode, 1 = level
  property string selMode: "cpu"
  property int selLevel: 1
  property int tier: 1              // CPU tier (1P run)
  property int matchNo: 1           // match within a 1P run
  property int goals1: 0
  property int goals2: 0
  property int winner: -1           // 0 = P1, 1 = P2/CPU
  property int server: 0            // who serves (the side that conceded)
  property int score: 0
  property bool beatHigh: false
  property real goalT: 0
  property string banner: ""
  property real bannerT: 0
  property real clock: 0
  property int halfSide: 0          // the half the puck is in (0 = P1's)
  property real halfT: 0            // how long it has been there (shot clock)

  property var pucks: []            // [ { x, y, vx, vy, spin, hot, owner, rot } ]
  property var strikers: []         // see makeStriker()
  property var sparks: []           // { x, y, vx, vy, life, side }
  property var trail: []            // { x, y, a } recent hot-puck positions

  property bool mouseActive: false  // 1P: the mouse drives P1 until a key is used
  property real mouseX: 0
  property real mouseY: 0

  // CPU brain: a decision every `react` s, counted down in step().
  property real cpuT: 0
  property var cpuGoal: ({ x: 0, y: 0, surge: false, mode: "defend" })

  // mulberry32, seeded by `seed`. Math.random() is never used. The effects
  // (sparks) draw from their own stream so they never change what the CPU does.
  property int seed: 0
  property int rngState: 1
  property int fxState: 7
  // A fresh seed for the next match: the clock mixed with the old seed, and never
  // the same seed twice in a row. newGame() itself keeps the seed it is given, so
  // the tests can replay a match exactly.
  function rollSeed() {
    var n = (Math.imul((seed ^ Date.now()) | 0, 0x9E3779B1) ^ 0x2545F491) >>> 1
    if (n === 0 || n === seed) n = (seed % 2147483646) + 1
    seed = n
  }
  function reseed() { rngState = (seed >>> 0) || 1; fxState = ((seed ^ 0x5bd1e995) >>> 0) || 7 }
  function mulberry(st) {
    var a = (st + 0x6D2B79F5) >>> 0
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return { st: a, v: ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
  }
  function rand() { var r = mulberry(rngState); rngState = r.st | 0; return r.v }
  function fxRand() { var r = mulberry(fxState); fxState = r.st | 0; return r.v }

  function color(key, fallback) { return theme[key] || fallback }
  function sideColor(i) { return i === 0 ? color("blue", "#7aa2f7") : color("orange", "#ff9e64") }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function cpuParams() { return Cpu.params(tier) }
  function puck() { return pucks[0] }
  function isCpu(i) { return mode === "cpu" && i === 1 }
  function playing() { return phase === "serve" || phase === "play" || phase === "goal" }

  // Delegates read through these (docs/GAMES.md, rule 5).
  readonly property var offField: ({ x: -500, y: -500, vx: 0, vy: 0, spin: 0, hot: 0, owner: -1, rot: 0,
                                     charge: 0, armed: 0, cool: 0, life: 0, side: 0, a: 0 })
  function puckAt(i) { return pucks[i] || offField }
  function strikerAt(i) { return strikers[i] || offField }
  function sparkAt(i) { return sparks[i] || offField }
  function trailAt(i) { return trail[i] || offField }
  readonly property alias puckView: puckView
  readonly property alias strikerView: strikerView
  readonly property alias sparkView: sparkView
  readonly property alias trailView: trailView
  readonly property alias fieldBg: fieldBg
  readonly property alias backdrop: backdrop
  // The lines under the title, PAUSED, MATCH WON and GAME OVER. Separators are
  // double spaced ("  ·  "); single spacing is only for the HUD's match label.
  readonly property string messageBody: phase === "select"
      ? "Enter or Space to face off  ·  first to " + target + "\n"
        + "P1: WASD move, F/Space surge" + (selMode === "cpu" ? " (or arrows, or the mouse + button)" : "") + "\n"
        + (selMode === "cpu" ? "" : "P2: arrows move, Ctrl/Shift/Enter surge\n")
        + "Hold surge to charge, strike to smash  ·  P pause  ·  Esc quit"
    : phase === "paused" ? "P or Space to resume  ·  Esc to quit"
    : phase === "won" ? goals1 + " – " + goals2 + "  ·  Score " + score
                        + (beatHigh ? "  ·  new high score!" : "")
                        + "\nEnter for match " + (matchNo + 1) + " (CPU tier " + (tier + 1) + ")  ·  M menu"
    : phase === "over" ? goals1 + " – " + goals2
                         + (mode === "cpu" ? "  ·  Score " + score + (beatHigh ? "  ·  new high score!" : "") : "")
                         + "\nEnter to play again  ·  M menu  ·  Esc to quit"
    : ""
  readonly property bool effectsShown: phase === "serve" || phase === "play" || phase === "goal" || phase === "paused"

  function homeX(i) { return i === 0 ? table.L + 90 : table.R - 90 }
  function makeStriker(i) {
    return { x: homeX(i), y: table.cy, vx: 0, vy: 0, kvx: 0, kvy: 0,
             charge: 0, armed: 0, armCharge: 0, cool: 0, touching: false,
             held: { up: false, down: false, left: false, right: false, surge: false },
             keys: {} }   // which keys hold each action: key -> act (see press())
  }
  function strikerBounds(i) { return Physics.bounds(i, table) }

  // Once per frame: new arrays so the Repeaters redraw (never per substep).
  function publish() {
    var p = puck()
    if (p && p.hot > 0 && playing()) {
      trail.push({ x: p.x, y: p.y, a: 1, side: p.owner })
      if (trail.length > 12) trail.shift()
    } else if (trail.length) trail.shift()
    for (var i = 0; i < trail.length; i++) trail[i].a = (i + 1) / trail.length
    pucks = pucks.slice(); strikers = strikers.slice(); sparks = sparks.slice(); trail = trail.slice()
  }

  function flash(text, seconds) { banner = text; bannerT = seconds || 1.2 }

  // ---- game flow ----------------------------------------------------------------
  // Back to the menu with everything reset.
  function newGame() {
    reseed()
    phase = "select"; pausedFrom = ""
    score = 0; beatHigh = false; tier = 1; matchNo = 1
    goals1 = 0; goals2 = 0; winner = -1; server = 0
    banner = ""; bannerT = 0; goalT = 0; clock = 0
    mouseActive = false; cpuT = 0
    cpuGoal = { x: homeX(1), y: table.cy, surge: false, mode: "defend" }
    strikers = [makeStriker(0), makeStriker(1)]
    pucks = [{ x: midX, y: table.cy, vx: 0, vy: 0, spin: 0, hot: 0, owner: -1, rot: 0 }]
    sparks = []; trail = []
  }

  // Start a run (1P) or a match (2P). levelIdx picks the CPU's starting tier.
  function startRun(m, levelIdx) {
    mode = m
    selMode = m
    if (levelIdx !== undefined) selLevel = clamp(levelIdx, 0, levels.length - 1)
    score = 0; beatHigh = false; matchNo = 1
    tier = mode === "cpu" ? levels[selLevel].tier : 1
    beginMatch()
  }

  function beginMatch() {
    goals1 = 0; goals2 = 0; winner = -1
    sparks = []; trail = []
    flash(mode === "cpu" ? "Match " + matchNo + " · tier " + tier : "First to " + target, 1.6)
    serveTo(rand() < 0.5 ? 0 : 1)
  }

  // 1P: after a won match, the next one against a stronger CPU.
  function nextMatch() {
    if (phase !== "won") return
    tier++; matchNo++
    beginMatch()
  }

  // The puck is set down at rest in the middle of the server's half.
  function serveTo(side) {
    server = side
    var p = puck()
    p.x = side === 0 ? (table.L + midX) / 2 : (midX + table.R) / 2
    p.y = table.cy; p.vx = 0; p.vy = 0; p.spin = 0; p.hot = 0; p.owner = -1
    for (var i = 0; i < 2; i++) {
      var h = strikers[i].held, k = strikers[i].keys
      strikers[i] = makeStriker(i)
      strikers[i].held = h                    // keys still held stay held
      strikers[i].keys = k
    }
    cpuT = 0.35                               // the CPU takes a breath first
    cpuGoal = { x: homeX(1), y: table.cy, surge: false, mode: "defend" }
    halfSide = side; halfT = 0
    phase = "serve"
  }

  function addScore(points) {
    if (mode !== "cpu" || points <= 0) return
    score += points
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  // `who` scored (0 = P1, 1 = P2/CPU).
  function scoreGoal(who) {
    var p = puck()
    var hotGoal = p.hot > 0 && p.owner === who
    if (who === 0) goals1++; else goals2++
    if (who === 0) addScore(10 * tier + (hotGoal ? 10 * tier : 0))
    burst(who === 0 ? table.R : table.L, clamp(p.y, table.cy - table.mouth, table.cy + table.mouth), who, 22)
    p.vx = 0; p.vy = 0; p.spin = 0; p.hot = 0
    if ((who === 0 ? goals1 : goals2) >= target) { endMatch(who); return }
    flash(hotGoal ? "SURGE GOAL!" : "GOAL!", goalPause)
    server = 1 - who
    goalT = goalPause
    phase = "goal"
  }

  function endMatch(who) {
    winner = who
    banner = ""; bannerT = 0
    sparks = []; trail = []                   // nothing left hanging over the result
    if (mode === "cpu" && who === 0) {
      addScore(100 * tier + 20 * (goals1 - goals2))
      phase = "won"
    } else {
      phase = "over"
    }
  }

  function pause() {
    if (!playing()) return
    pausedFrom = phase
    phase = "paused"
  }
  function resume() {
    if (phase !== "paused") return
    phase = pausedFrom || "play"
  }
  function togglePause() { if (phase === "paused") resume(); else pause() }

  // Key releases don't arrive while away: forget every held key and charge.
  function lostFocus() {
    for (var i = 0; i < strikers.length; i++) {
      var h = strikers[i].held
      h.up = h.down = h.left = h.right = h.surge = false
      strikers[i].keys = {}
      strikers[i].charge = 0; strikers[i].armed = 0; strikers[i].kvx = 0; strikers[i].kvy = 0
    }
    pause()
  }

  // ---- input (keys and mouse call these; the tests call them too) ------------------
  // Every key (or the mouse button) is tracked on its own, so in 1P letting go
  // of D doesn't stop a striker still driven by Right. `key` is any name for the
  // source; it defaults to the action. An action is held while any key holds it.
  function press(player, act, key) {
    var s = strikers[player]
    if (!s || isCpu(player)) return
    s.keys[key === undefined ? act : key] = act
    s.held[act] = true
    if (player === 0 && act !== "surge") mouseActive = false
  }
  function release(player, act, key) {
    var s = strikers[player]
    if (!s) return
    delete s.keys[key === undefined ? act : key]
    var still = false
    for (var k in s.keys) if (s.keys[k] === act) still = true
    s.held[act] = still
  }
  function mouseMove(x, y) {
    if (mode !== "cpu") return
    mouseX = x; mouseY = y; mouseActive = true
  }
  // The mouse button surges P1 in 1P only. Its release lets go of the mouse's own
  // hold, never a surge key held on the keyboard (or P1's keys in 2P).
  function mouseDown(x, y) {
    if (mode !== "cpu") return
    mouseMove(x, y)
    press(0, "surge", "mouse")
  }
  function mouseUp() { release(0, "surge", "mouse") }

  // ---- surge ----------------------------------------------------------------------
  function surgeMul(s) {
    var c = s.charge >= surgeMin ? s.charge : (s.armed > 0 ? s.armCharge : 0)
    return c > 0 ? 1 + 0.9 * c : 1
  }
  function charging(s) { return s.held.surge && s.cool <= 0 }
  function updateCharge(s, dt) {
    if (s.cool > 0) { s.cool = Math.max(0, s.cool - dt); s.charge = 0; return }
    if (s.held.surge) s.charge = Math.min(1, s.charge + dt / chargeTime)
    else {
      if (s.charge >= surgeMin) { s.armed = armWindow; s.armCharge = s.charge }
      s.charge = 0
    }
    if (s.armed > 0) s.armed = Math.max(0, s.armed - dt)
  }

  // ---- strikers --------------------------------------------------------------------
  function moveHuman(i, dt) {
    var s = strikers[i], h = s.held
    var slow = charging(s) ? chargeSlow : 1
    var dx = (h.right ? 1 : 0) - (h.left ? 1 : 0)
    var dy = (h.down ? 1 : 0) - (h.up ? 1 : 0)
    if (i === 0 && mode === "cpu" && mouseActive && dx === 0 && dy === 0) {
      Physics.moveTo(s, mouseX, mouseY, mouseSpeed * slow, dt, strikerBounds(i))
      s.kvx = 0; s.kvy = 0
      return
    }
    var len = Math.hypot(dx, dy) || 1
    var tvx = dx / len * keySpeed * slow, tvy = dy / len * keySpeed * slow
    // A quick ramp rather than instant velocity: it feels like pushing a mallet.
    var k = Math.min(1, 22 * dt)
    s.kvx += (tvx - s.kvx) * k
    s.kvy += (tvy - s.kvy) * k
    if (Math.abs(s.kvx) < 0.5 && dx === 0) s.kvx = 0
    if (Math.abs(s.kvy) < 0.5 && dy === 0) s.kvy = 0
    Physics.moveBy(s, s.kvx, s.kvy, dt, strikerBounds(i))
  }

  function cpuContext() {
    return { side: 1, puck: puck(), self: strikers[1], foe: strikers[0], table: table, p: cpuParams(), serving: phase === "serve" && server === 1 }
  }

  function moveCpu(dt) {
    var s = strikers[1], k = cpuParams()
    cpuT -= dt
    if (cpuT <= 0) {
      cpuGoal = Cpu.decide(cpuContext(), rand)
      cpuT = k.react
    }
    // The CPU charges on the way in and lets go just before contact, so the
    // smash lands inside the arm window.
    var p = puck()
    s.held.surge = cpuGoal.surge && cpuGoal.mode === "attack" && Math.hypot(p.x - s.x, p.y - s.y) > 64
    var slow = charging(s) ? chargeSlow : 1
    Physics.moveTo(s, cpuGoal.x, cpuGoal.y, k.speed * slow, dt, strikerBounds(1))
  }

  // ---- effects ---------------------------------------------------------------------
  function burst(x, y, side, n) {
    for (var i = 0; i < n && sparks.length < 60; i++) {
      var a = fxRand() * Math.PI * 2, v = 80 + fxRand() * 260
      sparks.push({ x: x, y: y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 0.35 + fxRand() * 0.4, side: side })
    }
  }
  function stepSparks(dt) {
    for (var i = sparks.length - 1; i >= 0; i--) {
      var f = sparks[i]
      f.life -= dt
      if (f.life <= 0) { sparks.splice(i, 1); continue }
      f.x += f.vx * dt; f.y += f.vy * dt
      f.vx *= Math.exp(-4 * dt); f.vy *= Math.exp(-4 * dt)
      // Sparks stay on the table (the goal pockets reach a little past each end);
      // one that flies off it is dropped instead of drawing in the window margin.
      if (f.y < table.T || f.y > table.B || f.x < table.L - 24 || f.x > table.R + 24) sparks.splice(i, 1)
    }
  }

  // ---- physics -------------------------------------------------------------------
  function step(dt) {
    if (phase === "goal") {
      stepSparks(dt)
      goalT -= dt
      if (bannerT > 0) { bannerT = Math.max(0, bannerT - dt); if (bannerT === 0) banner = "" }
      if (goalT <= 0) { banner = ""; bannerT = 0; serveTo(server) }
      return
    }
    if (phase !== "serve" && phase !== "play") return
    clock += dt
    if (bannerT > 0) { bannerT = Math.max(0, bannerT - dt); if (bannerT === 0) banner = "" }

    for (var i = 0; i < 2; i++) {
      if (isCpu(i)) moveCpu(dt); else moveHuman(i, dt)
      updateCharge(strikers[i], dt)
    }

    var p = puck()
    var res = Physics.stepPuck(p, dt, table)
    p.rot += p.spin * 3 * dt + Physics.speed(p) * dt * 0.004

    // Each striker twice, so a puck squeezed between both is still separated.
    for (var pass = 0; pass < 4; pass++) {
      i = pass % 2
      var s = strikers[i]
      var mul = surgeMul(s)
      if (!Physics.strike(p, s, table, mul, strikerBounds(i))) continue
      if (phase === "serve") phase = "play"
      if (mul > 1) {
        s.charge = 0; s.armed = 0; s.cool = surgeCool
        p.hot = surgeHot; p.owner = i
        burst(p.x, p.y, i, 14)
        flash("SURGE", 0.7)
      } else if (Physics.speed(p) > 700) {
        burst(p.x, p.y, i, 4)
      }
    }
    Physics.keepIn(p, table)
    stepSparks(dt)

    if (res.goal) { scoreGoal(res.goal === 1 ? 0 : 1); return }

    // Shot clock: too long in one half hands the serve to the other side.
    var half = p.x < midX ? 0 : 1
    if (half !== halfSide) { halfSide = half; halfT = 0 }
    else {
      halfT += dt
      if (halfT >= shotClock) { flash("Shot clock", 1.2); serveTo(1 - half) }
    }
  }

  FrameAnimation {
    running: game.playing()
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n && game.playing(); i++) game.step(dt / n)
      game.publish()
    }
  }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }

  // ---- keys ------------------------------------------------------------------------
  // Which player and action a key means. In 1P the arrows also drive P1.
  function keyAction(key) {
    var p2 = mode === "cpu" ? 0 : 1
    switch (key) {
    case Qt.Key_W: return { player: 0, act: "up" }
    case Qt.Key_S: return { player: 0, act: "down" }
    case Qt.Key_A: return { player: 0, act: "left" }
    case Qt.Key_D: return { player: 0, act: "right" }
    case Qt.Key_F: case Qt.Key_G: case Qt.Key_H: case Qt.Key_Space: return { player: 0, act: "surge" }
    case Qt.Key_Up: return { player: p2, act: "up" }
    case Qt.Key_Down: return { player: p2, act: "down" }
    case Qt.Key_Left: return { player: p2, act: "left" }
    case Qt.Key_Right: return { player: p2, act: "right" }
    case Qt.Key_Control: case Qt.Key_Shift: return { player: p2, act: "surge" }
    case Qt.Key_Return: case Qt.Key_Enter: return { player: p2, act: "surge" }
    }
    return null
  }

  function selMove(d) { selRow = selMode === "cpu" ? clamp(selRow + d, 0, 1) : 0 }
  function selChange(d) {
    if (selRow === 0) { selMode = selMode === "cpu" ? "versus" : "cpu"; if (selMode !== "cpu") selRow = 0 }
    else selLevel = (selLevel + d + levels.length) % levels.length
  }
  function playAgain() { var m = mode; rollSeed(); newGame(); startRun(m, selLevel) }
  function toMenu() { rollSeed(); newGame() }

  // The key handlers call these (so do the tests). keyDown returns whether the key
  // was used.
  function keyDown(key, autoRepeat) {
    if (autoRepeat) return true                // held keys are tracked by press/release
    if (key === Qt.Key_Escape) { quitRequested(); return true }
    if (key === Qt.Key_P) { togglePause(); return true }
    var enter = key === Qt.Key_Return || key === Qt.Key_Enter
    var confirm = enter || key === Qt.Key_Space || key === Qt.Key_F
    switch (phase) {
    case "select":
      switch (key) {
      case Qt.Key_W: case Qt.Key_Up: selMove(-1); break
      case Qt.Key_S: case Qt.Key_Down: selMove(1); break
      case Qt.Key_A: case Qt.Key_Left: selChange(-1); break
      case Qt.Key_D: case Qt.Key_Right: selChange(1); break
      default: if (confirm) startRun(selMode, selLevel); else return false
      }
      return true
    case "over":
      if (enter || key === Qt.Key_Space) playAgain()
      else if (key === Qt.Key_M) toMenu()
      return true
    case "won":
      if (confirm) nextMatch()
      else if (key === Qt.Key_M) toMenu()
      return true
    case "paused":
      if (key === Qt.Key_Space || enter) resume()
      return true
    }
    var a = keyAction(key)
    if (!a) return false
    press(a.player, a.act, key)
    return true
  }
  function keyUp(key, autoRepeat) {
    if (autoRepeat) return
    var a = keyAction(key)
    if (a) release(a.player, a.act, key)
  }
  Keys.onPressed: function (e) { e.accepted = keyDown(e.key, e.isAutoRepeat) }
  Keys.onReleased: function (e) { keyUp(e.key, e.isAutoRepeat) }

  Component.onCompleted: {
    if (seed === 0) seed = (Date.now() % 2147483647) || 1
    newGame()
  }

  // ---- drawing ---------------------------------------------------------------------
  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)

    Rectangle { id: fieldBg; anchors.fill: parent; color: game.color("dark_background", "#13141c"); radius: 6 }

    // HUD: goals for each side, the match, and (1P) score and high score.
    Rectangle {
      width: parent.width; height: game.hudH
      color: game.color("lighter_background", "#24283b")
      radius: 8
      Row {
        anchors.left: parent.left; anchors.leftMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Rectangle { width: 16; height: 16; radius: 8; color: game.sideColor(0); anchors.verticalCenter: parent.verticalCenter }
        Text { text: "P1"; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 18; font.bold: true; font.family: "monospace"; anchors.verticalCenter: parent.verticalCenter }
        Text { text: game.goals1; color: game.sideColor(0); font.pixelSize: 34; font.bold: true; font.family: "monospace"; anchors.verticalCenter: parent.verticalCenter }
      }
      Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: game.phase === "select" ? "SURGE RINK"
              : game.mode === "cpu" ? "MATCH " + game.matchNo + " · CPU TIER " + game.tier : "2 PLAYERS"
          color: game.color("accent", "#7aa2f7"); font.pixelSize: 15; font.bold: true; font.family: "monospace"
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: game.mode === "cpu" ? "SCORE " + game.score + "   HIGH " + game.highScore : "FIRST TO " + game.target
          color: game.color("foreground", "#a9b1d6"); font.pixelSize: 14; font.family: "monospace"
        }
      }
      Row {
        anchors.right: parent.right; anchors.rightMargin: 20
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14
        Text { text: game.goals2; color: game.sideColor(1); font.pixelSize: 34; font.bold: true; font.family: "monospace"; anchors.verticalCenter: parent.verticalCenter }
        Text { text: game.mode === "cpu" ? "CPU" : "P2"; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 18; font.bold: true; font.family: "monospace"; anchors.verticalCenter: parent.verticalCenter }
        Rectangle { width: 16; height: 16; radius: 8; color: game.sideColor(1); anchors.verticalCenter: parent.verticalCenter }
      }
    }

    // Goal pockets behind each mouth.
    Repeater {
      model: 2
      delegate: Rectangle {
        required property int index
        width: 22; height: game.table.mouth * 2
        x: index === 0 ? game.table.L - 22 : game.table.R
        y: game.table.cy - game.table.mouth
        radius: 4
        color: game.sideColor(index)
        opacity: 0.35
      }
    }

    // The rink: rails, a faint air-hole grid, centre line and ring, and a
    // half-ring crease in front of each mouth, all drawn once per theme.
    Rectangle {
      id: rink
      x: game.table.L - 8; y: game.table.T - 8
      width: game.table.R - game.table.L + 16; height: game.table.B - game.table.T + 16
      radius: 34
      color: "transparent"
      border.width: 8
      border.color: game.color("lighter_background", "#24283b")
    }
    Rectangle {
      x: game.table.L; y: game.table.T
      width: game.table.R - game.table.L; height: game.table.B - game.table.T
      radius: 26
      color: game.color("dark_background", "#13141c")
    }
    Canvas {
      id: markings
      x: game.table.L; y: game.table.T
      width: game.table.R - game.table.L; height: game.table.B - game.table.T
      onPaint: {
        var c = getContext("2d"), w = width, h = height, cy = game.table.cy - game.table.T
        c.reset()
        c.fillStyle = game.color("foreground", "#a9b1d6")
        c.globalAlpha = 0.07
        for (var gx = 24; gx < w - 12; gx += 32)
          for (var gy = 22; gy < h - 12; gy += 32) { c.beginPath(); c.arc(gx, gy, 1.6, 0, Math.PI * 2); c.fill() }
        c.globalAlpha = 0.35
        c.strokeStyle = game.color("foreground", "#a9b1d6")
        c.lineWidth = 3
        c.setLineDash([10, 10])
        c.beginPath(); c.moveTo(w / 2, 6); c.lineTo(w / 2, h - 6); c.stroke()
        c.setLineDash([])
        c.beginPath(); c.arc(w / 2, cy, 58, 0, Math.PI * 2); c.stroke()
        c.globalAlpha = 0.5
        c.strokeStyle = game.sideColor(0)
        c.beginPath(); c.arc(0, cy, 108, -Math.PI / 2, Math.PI / 2); c.stroke()
        c.strokeStyle = game.sideColor(1)
        c.beginPath(); c.arc(w, cy, 108, Math.PI / 2, Math.PI * 1.5); c.stroke()
      }
      Connections { target: game; function onThemeChanged() { markings.requestPaint() } }
    }
    // Goal posts.
    Repeater {
      model: 4
      delegate: Rectangle {
        required property int index
        width: 10; height: 10; radius: 5
        x: (index < 2 ? game.table.L : game.table.R) - 5
        y: game.table.cy + (index % 2 ? game.table.mouth : -game.table.mouth) - 5
        color: game.color("bright_foreground", "#c0caf5")
      }
    }

    // Hot-puck trail (and the sparks below) only show while a match is on.
    Repeater {
      id: trailView
      model: game.trail.length
      delegate: Rectangle {
        required property int index
        visible: game.effectsShown
        readonly property real r: game.table.r * (0.4 + 0.6 * game.trailAt(index).a)
        x: game.trailAt(index).x - r; y: game.trailAt(index).y - r
        width: r * 2; height: width; radius: r
        color: game.sideColor(game.trailAt(index).side)
        opacity: 0.45 * game.trailAt(index).a
      }
    }

    // Strikers: a rim in the player's color, a darker dish, a knob, and a ring
    // that fills while a surge charges.
    Repeater {
      id: strikerView
      model: game.strikers.length
      delegate: Item {
        id: st
        required property int index
        readonly property real charge: game.strikerAt(index).charge
        readonly property bool armed: game.strikerAt(index).armed > 0
        readonly property bool cooling: game.strikerAt(index).cool > 0
        x: game.strikerAt(index).x - game.table.sr
        y: game.strikerAt(index).y - game.table.sr
        width: game.table.sr * 2; height: width
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 14; height: width; radius: width / 2
          color: "transparent"
          border.width: 3
          border.color: game.sideColor(st.index)
          opacity: st.armed ? 0.9 : (st.charge >= game.surgeMin ? 0.25 + 0.5 * st.charge : 0)
        }
        Rectangle {
          anchors.fill: parent; radius: width / 2
          color: game.sideColor(st.index)
          opacity: st.cooling ? 0.6 : 1
        }
        Rectangle {
          anchors.centerIn: parent
          width: parent.width - 12; height: width; radius: width / 2
          color: game.color("dark_background", "#13141c"); opacity: 0.55
        }
        Rectangle {
          anchors.centerIn: parent
          width: 22; height: 22; radius: 11
          color: game.sideColor(st.index)
          border.width: 2; border.color: game.color("bright_foreground", "#c0caf5")
        }
        Canvas {
          id: ring
          anchors.centerIn: parent
          width: parent.width + 8; height: width
          property int bucket: Math.round(st.charge * 24)
          onBucketChanged: requestPaint()
          onPaint: {
            var c = getContext("2d")
            c.reset()
            if (bucket <= 0) return
            c.strokeStyle = game.color("bright_foreground", "#c0caf5")
            c.lineWidth = 4
            c.beginPath()
            c.arc(width / 2, height / 2, width / 2 - 2, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * bucket / 24)
            c.stroke()
          }
        }
      }
    }

    // The puck. A hot puck takes the smasher's color; the notch shows its spin.
    Repeater {
      id: puckView
      model: game.pucks.length
      delegate: Item {
        id: pk
        required property int index
        readonly property bool hot: game.puckAt(index).hot > 0
        x: game.puckAt(index).x - game.table.r
        y: game.puckAt(index).y - game.table.r
        width: game.table.r * 2; height: width
        visible: game.phase !== "select"
        Rectangle {
          anchors.centerIn: parent
          visible: pk.hot
          width: parent.width + 12; height: width; radius: width / 2
          color: game.sideColor(game.puckAt(pk.index).owner); opacity: 0.35
        }
        Rectangle {
          anchors.fill: parent; radius: width / 2
          color: pk.hot ? game.sideColor(game.puckAt(pk.index).owner) : game.color("bright_foreground", "#c0caf5")
          border.width: 2; border.color: game.color("background", "#1a1b26")
          Rectangle {
            width: 3; height: parent.height / 2 - 3
            x: parent.width / 2 - 1.5; y: 3
            color: game.color("background", "#1a1b26"); opacity: 0.6
            transformOrigin: Item.Bottom
            rotation: game.puckAt(pk.index).rot * 57.2958
          }
        }
      }
    }

    Repeater {
      id: sparkView
      model: game.sparks.length
      delegate: Rectangle {
        required property int index
        visible: game.effectsShown
        x: game.sparkAt(index).x - 2.5; y: game.sparkAt(index).y - 2.5
        width: 5; height: 5; radius: 2.5
        color: game.sideColor(game.sparkAt(index).side)
        opacity: Math.min(1, game.sparkAt(index).life * 2.5)
      }
    }

    // Short banners (GOAL, SURGE, match start) over the rink.
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: game.table.T + 40
      visible: game.banner !== "" && (game.phase === "play" || game.phase === "serve" || game.phase === "goal")
      text: game.banner
      color: game.color("bright_foreground", "#c0caf5")
      font.pixelSize: game.phase === "goal" ? 44 : 26; font.bold: true; font.family: "monospace"
      opacity: 0.9
    }
    // The last seconds of the shot clock, over the half that must move the puck.
    Text {
      x: (game.halfSide === 0 ? (game.table.L + game.midX) / 2 : (game.midX + game.table.R) / 2) - width / 2
      y: game.table.T + 12
      visible: (game.phase === "play" || game.phase === "serve") && game.halfT > game.shotClock - 3
      text: Math.ceil(game.shotClock - game.halfT)
      color: game.sideColor(game.halfSide)
      font.pixelSize: 28; font.bold: true; font.family: "monospace"
      opacity: 0.85
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: game.table.B - 34
      visible: game.phase === "serve"
      text: (game.server === 0 ? "P1" : (game.mode === "cpu" ? "CPU" : "P2")) + " to serve"
      color: game.color("foreground", "#a9b1d6"); font.pixelSize: 15; font.family: "monospace"
    }

    // Menus and messages, on a backdrop.
    Rectangle {
      id: backdrop
      anchors.centerIn: messages
      width: messages.width + 56; height: messages.height + 40
      radius: 10
      visible: messages.visible
      color: game.color("dark_background", "#13141c")
      opacity: 0.92
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 26
      spacing: 12
      visible: game.phase === "select" || game.phase === "paused" || game.phase === "over" || game.phase === "won"
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "select" ? "SURGE RINK"
            : game.phase === "paused" ? "PAUSED"
            : game.phase === "won" ? "MATCH WON"
            : game.mode === "versus" ? (game.winner === 0 ? "P1 WINS" : "P2 WINS")
            : "GAME OVER"
        color: game.phase === "won" ? game.sideColor(0) : game.color("bright_foreground", "#c0caf5")
        font.pixelSize: 42; font.bold: true; font.family: "monospace"
      }
      // The menu: mode and CPU level.
      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: game.phase === "select"
        spacing: 8
        Repeater {
          model: game.selMode === "cpu" ? 2 : 1
          delegate: Text {
            required property int index
            anchors.horizontalCenter: parent.horizontalCenter
            text: (game.selRow === index ? "▸ " : "  ")
                + (index === 0 ? "Mode   ◂ " + (game.selMode === "cpu" ? "1 player vs CPU" : "2 players") + " ▸"
                               : "Level  ◂ " + game.levels[game.selLevel].name + " ▸")
            color: game.selRow === index ? game.color("accent", "#7aa2f7") : game.color("foreground", "#a9b1d6")
            font.pixelSize: 20; font.bold: game.selRow === index; font.family: "monospace"
          }
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        text: game.messageBody
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 15; font.family: "monospace"
        lineHeight: 1.2
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: game.mode === "cpu" && (game.phase === "play" || game.phase === "serve") ? Qt.BlankCursor : Qt.ArrowCursor
      onPositionChanged: function (m) { game.mouseMove(m.x, m.y) }
      onPressed: function (m) {
        game.forceActiveFocus()
        switch (game.phase) {
        case "select": game.startRun(game.selMode, game.selLevel); break
        case "over": game.playAgain(); break
        case "won": game.nextMatch(); break
        case "paused": game.resume(); break
        default: game.mouseDown(m.x, m.y)
        }
      }
      onReleased: game.mouseUp()
    }
  }
}
