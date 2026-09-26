import QtQuick
import "fighters.js" as Fighters
import "input.js" as Input
import "ai.js" as AI

// Emberbout: the whole game. A 1-on-1 fighter under the lanterns of a night
// market, in a fixed 800×540 field scaled to the window.
//
// Modes: 1 player vs a CPU ladder (six matches, the CPU sharper each time), or
// 2 players on one keyboard. A match is best of three rounds of ROUND_TIME s.
//
// Rules of a fight (the numbers live in fighters.js and below):
//   - walk, jump, crouch; hold back (away from the opponent) to block. A standing
//     block stops mid and air ("high") attacks, a crouching block stops mid and
//     low ones.
//   - Light and Heavy attack; standing, crouching and in the air. Every countdown
//     (hitstun, blockstun, knockdown, the round clock, the CPU's thinking) is a
//     number counted down in step().
//   - one special per fighter with its own input (fighters.js, input.js). A
//     normal attack that hits can be cancelled into the special.
//   - hits in a row (a combo) do less and less: 100%, 85%, 70% ... down to 40%.
//   - Ember, our own mechanic: a meter (0..100) that fills as you land, block
//     and take hits and carries across rounds. Full, the Ember button either
//     Kindles you (KINDLE_TIME s of +30% damage, chip damage on blocked hits,
//     faster specials) or, pressed while stunned, Flares: you break out of the
//     combo and blow the attacker back.
//   - a round ends on a KO (both at once is a draw) or when the clock runs out
//     (the higher share of health wins, equal is a draw). A drawn round scores
//     for nobody; after MAX_ROUNDS the match goes to whoever won more.
//
// Score (1 player only): damage dealt, a round bonus (1000 + 20 per second left,
// +2000 for a perfect round) and a match bonus (3000 × stage), all multiplied by
// the CPU level factor. The high score is the best ladder run. A score that only
// ties the high score is not a new high score. Versus matches are not scored:
// they keep a win tally instead.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- controls: every key in one place --------------------------------------
  // Qt reports left and right Ctrl (and Shift) as the same key, so either one
  // works for player 2; player 1 uses neither.
  readonly property var keymap: ({
    p1: { left: [Qt.Key_A], right: [Qt.Key_D], up: [Qt.Key_W], down: [Qt.Key_S],
          light: [Qt.Key_F], heavy: [Qt.Key_G], ember: [Qt.Key_H] },
    p2: { left: [Qt.Key_Left], right: [Qt.Key_Right], up: [Qt.Key_Up], down: [Qt.Key_Down],
          light: [Qt.Key_Control], heavy: [Qt.Key_Shift], ember: [Qt.Key_Return, Qt.Key_Enter] }
  })
  readonly property var actions: ["left", "right", "up", "down", "light", "heavy", "ember"]

  // ---- field and tuning -------------------------------------------------------
  readonly property real fieldW: 800
  readonly property real fieldH: 540
  readonly property real hudH: 92
  readonly property real groundY: 492
  readonly property real wallL: 34
  readonly property real wallR: 766
  readonly property real gravity: 2100
  readonly property real roundTime: 60
  readonly property real readyTime: 1.6
  readonly property real roundPause: 2.4
  readonly property int maxRounds: 5
  readonly property int winsNeeded: 2
  readonly property real knockTime: 0.8       // on the floor after landing
  readonly property real wakeInvuln: 0.3
  readonly property real kindleTime: 6
  readonly property real kindleMul: 1.3
  readonly property real flareInvuln: 0.4
  readonly property real flarePush: 900      // px/s slide given to the attacker
  readonly property real flareStun: 0.35
  readonly property real specialChip: 0.12   // blocked specials still scratch
  readonly property real kindleChip: 0.2     // blocked Kindled hits scratch more
  readonly property real comboStep: 0.15
  readonly property real comboFloor: 0.4
  readonly property real startLeft: 260
  readonly property real startRight: 540

  // ---- state ------------------------------------------------------------------
  property int seed: 0
  property real rngState: 1
  property string phase: "select"   // select | ready | play | roundover | paused | over
  property string pausedFrom: ""
  property string mode: "cpu"       // cpu | versus
  property int difficulty: 1
  property int stage: 1
  property int cpuLevel: 1
  property bool champion: false
  property int round: 1
  property int winsP1: 0
  property int winsP2: 0
  property int roundWinner: -1
  property string roundReason: ""
  property int matchWinner: -1
  property bool perfect: false
  property real timeLeft: roundTime
  property real readyT: 0
  property real roundT: 0
  property real clock: 0
  property real drawT: 0            // `clock` as of the last publish(): what the drawing animates by
  property int score: 0
  property bool beatHigh: false
  property int tallyP1: 0           // versus: matches won this session
  property int tallyP2: 0
  property var fighters: []
  property var projectiles: []
  property var sparks: []
  property var decisionLog: []      // the CPU's recent decisions (for tests and curiosity)
  property string banner: ""
  property real bannerT: 0
  property string comboText: ""
  property int comboSide: 0
  property real comboT: 0

  // Select screen
  property int selRow: 0
  property string selMode: "cpu"
  property int selDiff: 1
  property int selP1: 0
  property int selP2: 1

  readonly property alias fighterView: fighterView
  readonly property alias shotView: shotView
  readonly property alias hudView: hudView

  // The drawing components each have their own `game` property; inside them the
  // name means that property, so they are handed this instead.
  readonly property var engine: game

  function color(key, fallback) { return theme[key] || fallback }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function fighting() { return phase === "ready" || phase === "play" || phase === "roundover" }

  // mulberry32, seeded by `seed`. Math.random() is never used.
  function reseed() { rngState = (seed >>> 0) || 1 }
  function rand() {
    var a = (rngState + 0x6D2B79F5) >>> 0
    rngState = a
    var t = a
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }

  // Delegates read through these (see docs/GAMES.md, rule 5).
  readonly property var offField: ({ x: -400, h: 0, kind: "", life: 0, facing: 1, hp: 0, maxHp: 1, trail: 0, meter: 0, kindleT: 0, d: 0, wins: 0 })
  function fighterAt(i) { return fighters[i] || offField }
  function shotAt(i) { return projectiles[i] || offField }
  function sparkAt(i) { return sparks[i] || offField }
  function defOf(p) { return Fighters.at(p.d) }
  function lookOf(i) { var f = fighters[i]; return f ? Fighters.at(f.d) : Fighters.at(0) }
  // Once per frame, never per substep. The drawing reads drawT, not clock, so
  // nothing on screen re-evaluates between publishes.
  function publish() { drawT = clock; fighters = fighters.slice(); projectiles = projectiles.slice(); sparks = sparks.slice() }

  // ---- setting up -------------------------------------------------------------
  function makeFighter(idx, d, cpu) {
    var def = Fighters.at(d)
    var held = {}
    for (var i = 0; i < actions.length; i++) held[actions[i]] = false
    return {
      idx: idx, d: d, cpu: cpu, name: def.name,
      w: def.w, hgt: def.h, maxHp: def.hp, hp: def.hp, trail: def.hp,
      x: idx === 0 ? startLeft : startRight, h: 0, vx: 0, vy: 0, air: false, slide: 0,
      facing: idx === 0 ? 1 : -1,
      state: "idle", stateT: 0, move: "", moveT: 0, hasHit: false, spawned: false, airAttacked: false, armorUsed: false,
      combo: 0, invulT: 0, flashT: 0, kindleT: 0, meter: 0,
      held: held, buf: [], pending: null, chargeT: 0, chargeGrace: 0,
      aiT: 0, lastDecision: "", flares: 0, kindles: 0
    }
  }

  // Everything back to the title/select screen, reseeded from `seed`.
  function newGame() {
    reseed()
    score = 0; beatHigh = false; champion = false; stage = 1
    tallyP1 = 0; tallyP2 = 0
    toSelect()
  }

  // The select screen, keeping the session's choices and versus tally.
  function toSelect() {
    phase = "select"; pausedFrom = ""
    round = 1; winsP1 = 0; winsP2 = 0; roundWinner = -1; matchWinner = -1
    timeLeft = roundTime; clock = 0
    projectiles = []; sparks = []; decisionLog = []
    banner = ""; bannerT = 0; comboText = ""; comboT = 0
    selRow = clamp(selRow, 0, selRows().length - 1)
    setPreview()
  }

  // The two chosen fighters stand on the stage while you choose.
  function setPreview() {
    fighters = [makeFighter(0, selP1, false),
                makeFighter(1, selMode === "cpu" ? Fighters.ladderOpponent(selP1, 1) : selP2, false)]
    fighters[0].x = 96; fighters[1].x = fieldW - 96     // clear of the fighter cards
  }

  function selRows() { return selMode === "cpu" ? ["mode", "diff", "p1"] : ["mode", "p1", "p2"] }
  function selMove(dy) { var n = selRows().length; selRow = (selRow + dy + n) % n }
  function selChange(dx) {
    var n = Fighters.count()
    switch (selRows()[selRow]) {
    case "mode": selMode = selMode === "cpu" ? "versus" : "cpu"; break
    case "diff": selDiff = (selDiff + dx + Fighters.DIFFICULTY.length) % Fighters.DIFFICULTY.length; break
    case "p1": selP1 = (selP1 + dx + n) % n; break
    case "p2": selP2 = (selP2 + dx + n) % n; break
    }
    setPreview()
  }
  function selConfirm() { startMatch(selMode, selP1, selMode === "cpu" ? -1 : selP2, selDiff) }

  // Start a match directly (the select screen and the tests both use this).
  // In "cpu" mode p2 < 0 means the ladder's first opponent.
  function startMatch(m, p1, p2, diff) {
    mode = m
    difficulty = clamp(diff === undefined ? 1 : diff, 0, Fighters.DIFFICULTY.length - 1)
    stage = 1; champion = false; score = 0; beatHigh = false
    selP1 = p1
    decisionLog = []
    var opp = m === "cpu" ? (p2 >= 0 ? p2 : Fighters.ladderOpponent(p1, 1)) : p2
    beginMatch(p1, opp)
  }

  function beginMatch(p1, p2) {
    cpuLevel = mode === "cpu" ? Fighters.cpuLevel(difficulty, stage) : 0
    fighters = [makeFighter(0, p1, false), makeFighter(1, p2, mode === "cpu")]
    winsP1 = 0; winsP2 = 0; round = 1; matchWinner = -1
    startRound()
  }

  function startRound() {
    for (var i = 0; i < fighters.length; i++) {
      var p = fighters[i]
      p.x = i === 0 ? startLeft : startRight
      p.h = 0; p.vx = 0; p.vy = 0; p.air = false; p.slide = 0
      p.facing = i === 0 ? 1 : -1
      p.hp = p.maxHp; p.trail = p.maxHp
      p.state = "idle"; p.stateT = 0; p.move = ""; p.moveT = 0; p.hasHit = false; p.spawned = false
      p.combo = 0; p.invulT = 0; p.flashT = 0; p.kindleT = 0
      p.buf = []; p.pending = null; p.chargeT = 0; p.chargeGrace = 0; p.aiT = 0.3
      if (p.cpu) for (var k in p.held) p.held[k] = false
    }
    projectiles = []; sparks = []
    timeLeft = roundTime; readyT = readyTime; roundWinner = -1; roundReason = ""; perfect = false
    comboText = ""; comboT = 0
    phase = "ready"
    publish()
  }

  // ---- pause and focus --------------------------------------------------------
  function pause() {
    if (!fighting()) return
    pausedFrom = phase
    phase = "paused"
  }
  function resume() {
    if (phase !== "paused") return
    phase = pausedFrom || "play"
    pausedFrom = ""
  }
  function togglePause() { if (phase === "paused") resume(); else pause() }

  // Key releases don't arrive while away: forget every held key and pause.
  function lostFocus() {
    for (var i = 0; i < fighters.length; i++) {
      var p = fighters[i]
      for (var k in p.held) p.held[k] = false
      p.pending = null; p.chargeT = 0; p.chargeGrace = 0
    }
    pause()
  }

  // ---- scoring ----------------------------------------------------------------
  function levelMul() { return 1 + 0.25 * (cpuLevel - 1) }
  function addScore(points) {
    if (mode !== "cpu" || points <= 0) return
    score += Math.round(points)
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  function flash(text, secs) { banner = text; bannerT = secs || 1.4 }

  // ---- input ------------------------------------------------------------------
  // What a key does: { player, act } or null.
  function keyAction(key) {
    var sides = ["p1", "p2"]
    for (var s = 0; s < 2; s++) {
      var m = keymap[sides[s]]
      for (var a in m) if (m[a].indexOf(key) >= 0) return { player: s, act: a }
    }
    return null
  }

  function holdingBack(p) { return p.facing > 0 ? (p.held.left && !p.held.right) : (p.held.right && !p.held.left) }
  function chargeReady(p) { return p.chargeT >= Input.CHARGE || p.chargeGrace > 0 }
  function ownShotAlive(idx) {
    for (var i = 0; i < projectiles.length; i++) if (projectiles[i].owner === idx) return true
    return false
  }
  function canNeutral(p) { return phase === "play" && (p.state === "idle" || p.state === "crouch") }

  // A key went down. The CPU uses the same entry point (fromCpu); a person's
  // player-2 keys do nothing while the CPU plays player 2.
  function press(pi, act, fromCpu) {
    var p = fighters[pi]
    if (!p || (p.cpu && !fromCpu)) return
    if (p.held[act]) return
    p.held[act] = true
    if (act === "left" || act === "right" || act === "up" || act === "down") {
      Input.push(p.buf, Input.relative(act, p.facing), clock)
      return
    }
    if (phase !== "play") return
    if (!tryButton(p, act)) p.pending = { btn: act, t: clock }
  }

  function release(pi, act, fromCpu) {
    var p = fighters[pi]
    if (!p || (p.cpu && !fromCpu)) return
    p.held[act] = false
    if (act === "down") {
      if (p.chargeT >= Input.CHARGE) p.chargeGrace = Input.CHARGE_GRACE
      p.chargeT = 0
    }
  }

  // A button, now: the special if its input is complete, else the normal move
  // for the stance. Returns false if the fighter is busy (the caller buffers it).
  function tryButton(p, btn) {
    if (btn === "ember") return tryEmber(p)
    var def = defOf(p)
    var sp = !p.air && Input.special(def.special, btn, p.buf, clock, chargeReady(p))
    if (sp && def.special.projectile && ownShotAlive(p.idx)) sp = false   // one kite or wave at a time
    if (canNeutral(p)) {
      if (p.air) {
        if (p.airAttacked) return true      // one air attack per jump; the press is spent
        p.airAttacked = true
        startMove(p, "j" + (btn === "light" ? "L" : "H"))
        return true
      }
      if (sp) { startMove(p, "sp"); return true }
      startMove(p, (p.held.down ? "c" : "s") + (btn === "light" ? "L" : "H"))
      return true
    }
    // Cancel: a grounded normal that hit can go straight into the special.
    if (sp && p.state === "attack" && p.move !== "sp" && !p.air && p.hasHit) { startMove(p, "sp"); return true }
    return false
  }

  function startMove(p, key) {
    p.state = "attack"; p.move = key; p.moveT = 0; p.hasHit = false; p.spawned = false; p.armorUsed = false
    if (!p.air) p.vx = 0
    if (key === "sp") { p.buf = []; p.chargeT = 0; p.chargeGrace = 0 }
    p.pending = null
  }

  // Ember: full meter only. Stunned → Flare; free → Kindle.
  function tryEmber(p) {
    if (p.meter < 100) return true          // nothing happens; not worth buffering
    var o = fighters[1 - p.idx]
    if (phase === "play" && (p.state === "hitstun" || p.state === "blockstun")) {
      p.state = "idle"; p.stateT = 0; p.combo = 0; p.invulT = flareInvuln; p.meter = 0; p.slide = 0
      p.flares++
      var away = o.x >= p.x ? 1 : -1
      o.slide = away * flarePush
      if (o.state !== "knockdown" && o.state !== "ko") { o.state = "hitstun"; o.stateT = flareStun; o.move = "" }
      addSpark(p.x, p.h + p.hgt * 0.5, "flare")
      flash("FLARE", 0.9)
      return true
    }
    if (canNeutral(p) && !p.air) {
      p.kindleT = kindleTime; p.meter = 0; p.kindles++
      addSpark(p.x, p.h + p.hgt * 0.6, "flare")
      flash(p.name.toUpperCase() + " KINDLES", 1.0)
      return true
    }
    return false
  }

  function gainMeter(p, amount) { p.meter = Math.min(100, p.meter + amount) }

  // ---- the fight --------------------------------------------------------------
  function moveOf(p) { return Fighters.move(defOf(p), p.move) }
  function isCrouching(p) {
    if (p.air) return false
    if (p.state === "crouch") return true
    if (p.state === "attack") return p.move.charAt(0) === "c"
    if (p.state === "blockstun" || p.state === "hitstun") return p.held.down
    return false
  }
  function hurtBox(p) {
    var top = p.state === "knockdown" || p.state === "ko" ? p.hgt * 0.3 : (isCrouching(p) ? p.hgt * 0.62 : p.hgt)
    return { x1: p.x - p.w / 2, x2: p.x + p.w / 2, y1: p.h, y2: p.h + top }
  }
  function hitBox(p, m) {
    var a = p.x + p.facing * m.from, b = p.x + p.facing * m.reach
    return { x1: Math.min(a, b), x2: Math.max(a, b), y1: p.h + m.yLo, y2: p.h + m.yHi }
  }
  function overlap(a, b) { return a.x1 < b.x2 && a.x2 > b.x1 && a.y1 < b.y2 && a.y2 > b.y1 }

  function canBlock(p, level) {
    if (p.air || !holdingBack(p)) return false
    if (p.state !== "idle" && p.state !== "crouch" && p.state !== "blockstun") return false
    if (level === "low") return p.held.down
    if (level === "high") return !p.held.down
    return true
  }

  // One attack (a move, or a projectile carrying its move's numbers) reaches the
  // other fighter. Returns "hit", "block", "armor" (absorbed) or "miss"
  // (invulnerable / on the floor).
  function resolveHit(ai, m, isShot, kindled) {
    var att = fighters[ai], def = fighters[1 - ai]
    if (def.invulT > 0 || def.state === "knockdown" || def.state === "ko") return "miss"
    var mul = kindled ? kindleMul : 1
    var away = def.x >= att.x ? 1 : -1
    var special = isShot || att.move === "sp"
    if (canBlock(def, m.level)) {
      var chip = (special ? specialChip : 0) + (kindled ? kindleChip : 0)
      var cd = Math.round(m.dmg * chip * mul)
      def.hp = Math.max(0, def.hp - cd)
      def.state = "blockstun"; def.stateT = m.blockstun; def.move = ""
      def.slide = away * m.push * 7
      gainMeter(att, m.dmg * 0.06); gainMeter(def, m.dmg * 0.08)
      addSpark(isShot ? def.x - away * def.w / 2 : def.x - away * def.w / 2, def.h + def.hgt * 0.6, "block")
      return "block"
    }
    var scale = Math.max(comboFloor, 1 - comboStep * def.combo)
    var dmg = Math.round(m.dmg * scale * mul)
    // Armor (Marrow): the first hit during an armored move's startup or active
    // part does half damage and the move carries on.
    var hpBefore = def.hp
    if (def.state === "attack" && !def.armorUsed) {
      var dm = moveOf(def)
      if (dm.armor && def.moveT < dm.startup + dm.active) {
        dmg = Math.round(dmg * 0.5)
        def.hp = Math.max(0, def.hp - dmg)
        def.armorUsed = true
        def.flashT = 0.12
        gainMeter(att, dmg * 0.12); gainMeter(def, dmg * 0.08)
        if (ai === 0) addScore((hpBefore - def.hp) * levelMul())   // health taken, not overkill
        addSpark(def.x - away * def.w / 3, def.h + def.hgt * 0.62, "block")
        return "armor"
      }
    }
    def.hp = Math.max(0, def.hp - dmg)
    def.combo++
    def.flashT = 0.12
    def.move = ""; def.pending = null
    if (def.air || m.knock || def.hp <= 0) {
      def.state = "knockdown"; def.stateT = knockTime
      def.air = true; def.vy = 380; def.vx = away * 150
      if (def.h <= 0) def.h = 0.5
    } else {
      def.state = "hitstun"; def.stateT = m.hitstun
      def.slide = away * m.push * 6
    }
    gainMeter(att, dmg * 0.12); gainMeter(def, dmg * 0.08)
    if (ai === 0) addScore((hpBefore - def.hp) * levelMul())      // health taken, not overkill
    if (def.combo >= 2) { comboText = def.combo + " HITS"; comboSide = ai; comboT = 1.2 }
    addSpark(def.x - away * def.w / 3, def.h + def.hgt * (m.level === "low" ? 0.15 : 0.62), "hit")
    return "hit"
  }

  function addSpark(x, h, kind) { sparks.push({ x: x, h: h, kind: kind, life: 0 }) }

  function spawnShot(p) {
    var sp = defOf(p).special, pr = sp.projectile
    var kindled = p.kindleT > 0
    projectiles.push({
      owner: p.idx, kind: pr.kind, x: p.x + p.facing * (p.w / 2 + pr.w / 2), h: pr.y, baseH: pr.y,
      vx: p.facing * pr.speed * (kindled ? 1.35 : 1), w: pr.w, hgt: pr.hgt, t: 0, life: pr.life,
      kindled: kindled, facing: p.facing,
      dmg: sp.dmg, hitstun: sp.hitstun, blockstun: sp.blockstun, level: sp.level, push: sp.push, knock: !!sp.knock
    })
  }

  // One fighter's timers, state and movement.
  function updateFighter(p, dt) {
    p.invulT = Math.max(0, p.invulT - dt)
    p.flashT = Math.max(0, p.flashT - dt)
    p.kindleT = Math.max(0, p.kindleT - dt)
    p.chargeGrace = Math.max(0, p.chargeGrace - dt)
    if (p.held.down && phase === "play") p.chargeT += dt
    if (p.trail > p.hp) p.trail = Math.max(p.hp, p.trail - 260 * dt)
    else p.trail = p.hp

    // A button pressed while busy fires as soon as the fighter is free, if that
    // happens within Input.BUFFER seconds.
    if (p.pending) {
      if (clock - p.pending.t > Input.BUFFER) p.pending = null
      else if (phase === "play" && tryButton(p, p.pending.btn)) p.pending = null
    }

    switch (p.state) {
    case "hitstun":
    case "blockstun":
      p.stateT -= dt
      if (p.stateT <= 0) { if (p.state === "hitstun") p.combo = 0; p.state = "idle"; p.stateT = 0 }
      break
    case "knockdown":
      if (!p.air) {
        p.stateT -= dt
        if (p.stateT <= 0) {
          if (p.hp <= 0) { p.state = "ko"; break }
          p.state = "idle"; p.stateT = 0; p.combo = 0; p.invulT = wakeInvuln
        }
      }
      break
    case "attack":
      p.moveT += dt
      var m = moveOf(p)
      if (m.rush && p.moveT < m.startup + m.active)
        p.x += p.facing * m.rush * (p.kindleT > 0 ? 1.2 : 1) * dt
      if (m.projectile && !p.spawned && p.moveT >= m.startup) { p.spawned = true; spawnShot(p) }
      if (p.moveT >= Fighters.total(m)) { p.state = "idle"; p.move = ""; p.moveT = 0 }
      break
    case "idle":
    case "crouch":
      if (phase !== "play") { if (!p.air) p.vx = 0; break }
      if (p.air) break
      if (p.held.up) {
        var dir = (p.held.right ? 1 : 0) - (p.held.left ? 1 : 0)
        var def = defOf(p)
        p.vx = dir * def.jumpX; p.vy = def.jumpV; p.air = true; p.airAttacked = false
        p.state = "idle"
        if (p.cpu) p.held.up = false        // the CPU taps up, it doesn't hold it
      } else if (p.held.down) {
        p.state = "crouch"; p.vx = 0
      } else {
        p.state = "idle"
        var wd = (p.held.right ? 1 : 0) - (p.held.left ? 1 : 0)
        var back = wd !== 0 && (wd > 0) !== (p.facing > 0)
        p.vx = wd * defOf(p).walk * (back ? 0.8 : 1)
      }
      break
    }

    // Movement.
    if (p.air) {
      p.vy -= gravity * dt
      p.h += p.vy * dt
      p.x += p.vx * dt
      if (p.h <= 0) {
        p.h = 0; p.vy = 0; p.vx = 0; p.air = false
        if (p.state === "attack") { p.state = "idle"; p.move = ""; p.moveT = 0 }
      }
    } else if (p.state === "idle") {
      p.x += p.vx * dt
    }
    if (p.slide !== 0) {
      p.x += p.slide * dt
      p.slide *= Math.exp(-12 * dt)
      if (Math.abs(p.slide) < 4) p.slide = 0
    }
    p.x = clamp(p.x, wallL + p.w / 2, wallR - p.w / 2)
  }

  // Fighters turn to face each other whenever they're free and on the ground.
  function faceEachOther() {
    for (var i = 0; i < 2; i++) {
      var p = fighters[i], o = fighters[1 - i]
      if (p.air || (p.state !== "idle" && p.state !== "crouch")) continue
      if (Math.abs(o.x - p.x) > 1) p.facing = o.x > p.x ? 1 : -1
    }
  }

  // Bodies don't overlap (unless one is jumping over the other: a jump clears
  // the other's pushbox once it is 30 px up).
  function separate() {
    var a = fighters[0], b = fighters[1]
    var minD = (a.w + b.w) / 2
    if (a.h > 30 || b.h > 30) return
    var dx = b.x - a.x
    if (Math.abs(dx) >= minD) return
    var s = dx > 0 ? 1 : (dx < 0 ? -1 : a.facing)
    var push = (minD - Math.abs(dx)) / 2
    a.x -= s * push; b.x += s * push
    var loA = wallL + a.w / 2, hiA = wallR - a.w / 2, loB = wallL + b.w / 2, hiB = wallR - b.w / 2
    a.x = clamp(a.x, loA, hiA); b.x = clamp(b.x, loB, hiB)
    if (Math.abs(b.x - a.x) < minD - 0.01) {
      // One is against a wall: the other one gives way.
      if (a.x <= loA + 0.01 || a.x >= hiA - 0.01) b.x = clamp(a.x + s * minD, loB, hiB)
      else a.x = clamp(b.x - s * minD, loA, hiA)
    }
  }

  // Attacks and projectiles land. Both fighters' hits are found first and then
  // applied, so a trade hits both (and a double KO is a draw).
  function checkHits() {
    var found = []
    for (var i = 0; i < 2; i++) {
      var att = fighters[i], def = fighters[1 - i]
      if (att.state !== "attack" || att.hasHit) continue
      var m = moveOf(att)
      if (m.projectile) continue
      if (att.moveT < m.startup || att.moveT >= m.startup + m.active) continue
      if (overlap(hitBox(att, m), hurtBox(def))) found.push({ i: i, m: m, k: att.kindleT > 0 })
    }
    for (var j = 0; j < found.length; j++) {
      fighters[found[j].i].hasHit = true
      resolveHit(found[j].i, found[j].m, false, found[j].k)
    }
  }

  function updateShots(dt) {
    var i, q
    for (i = projectiles.length - 1; i >= 0; i--) {
      q = projectiles[i]
      q.t += dt
      q.x += q.vx * dt
      if (q.kind === "kite") q.h = q.baseH + 10 * Math.sin(q.t * 7)
      if (q.t > q.life || q.x < -40 || q.x > fieldW + 40) projectiles.splice(i, 1)
    }
    // Opposing shots cancel each other out.
    for (i = projectiles.length - 1; i >= 0; i--) {
      for (var k = i - 1; k >= 0; k--) {
        var a = projectiles[i], b = projectiles[k]
        if (a.owner === b.owner) continue
        if (Math.abs(a.x - b.x) < (a.w + b.w) / 2 && a.h < b.h + b.hgt && b.h < a.h + a.hgt) {
          addSpark((a.x + b.x) / 2, (a.h + b.h) / 2 + 10, "block")
          projectiles.splice(i, 1); projectiles.splice(k, 1)
          i--
          break
        }
      }
    }
    for (i = projectiles.length - 1; i >= 0; i--) {
      q = projectiles[i]
      var def = fighters[1 - q.owner]
      var box = { x1: q.x - q.w / 2, x2: q.x + q.w / 2, y1: q.h, y2: q.h + q.hgt }
      if (!overlap(box, hurtBox(def))) continue
      if (resolveHit(q.owner, q, true, q.kindled) !== "miss") projectiles.splice(i, 1)
    }
  }

  function checkRoundEnd() {
    var a = fighters[0], b = fighters[1]
    if (a.hp <= 0 && b.hp <= 0) return endRound(-1, "double")
    if (a.hp <= 0) return endRound(1, "ko")
    if (b.hp <= 0) return endRound(0, "ko")
    if (timeLeft <= 0) {
      timeLeft = 0
      var ra = a.hp / a.maxHp, rb = b.hp / b.maxHp
      if (Math.abs(ra - rb) < 1e-9) return endRound(-1, "time")
      return endRound(ra > rb ? 0 : 1, "time")
    }
  }

  function endRound(w, reason) {
    phase = "roundover"
    roundT = roundPause
    roundWinner = w
    roundReason = reason
    projectiles = []            // shots in flight would hang frozen through the pause
    if (w === 0) winsP1++
    else if (w === 1) winsP2++
    for (var i = 0; i < 2; i++) {
      var p = fighters[i]
      p.pending = null; p.kindleT = 0
      if (p.hp <= 0) { if (p.state !== "knockdown") { p.state = "ko"; p.move = "" } }
      else if (i === w) { p.state = "victory"; p.move = ""; p.slide = 0 }
      else if (p.state === "attack") { p.state = "idle"; p.move = "" }
    }
    var winner = w >= 0 ? fighters[w] : null
    perfect = !!winner && winner.hp === winner.maxHp
    if (w === 0) addScore((1000 + 20 * Math.ceil(timeLeft) + (perfect ? 2000 : 0)) * levelMul())
  }

  function afterRound() {
    if (winsP1 >= winsNeeded || winsP2 >= winsNeeded || round >= maxRounds) return matchOver()
    round++
    startRound()
  }

  function matchOver() {
    var mw = winsP1 > winsP2 ? 0 : (winsP2 > winsP1 ? 1 : -1)
    matchWinner = mw
    if (mode === "cpu") {
      if (mw === 0) {
        addScore(3000 * stage * levelMul())
        if (stage >= Fighters.LADDER) { champion = true; phase = "over"; return }
        stage++
        beginMatch(fighters[0].d, Fighters.ladderOpponent(fighters[0].d, stage))
        flash("STAGE " + stage + " · " + fighters[1].name.toUpperCase(), 1.6)
      } else if (mw === -1) {
        beginMatch(fighters[0].d, fighters[1].d)   // a drawn match is fought again
        flash("REMATCH", 1.4)
      } else {
        phase = "over"
      }
      return
    }
    if (mw === 0) tallyP1++
    else if (mw === 1) tallyP2++
    phase = "over"
  }

  // ---- the CPU ----------------------------------------------------------------
  function cpuContext(p) {
    var o = fighters[1 - p.idx]
    var def = defOf(p)
    var dist = Math.abs(o.x - p.x)
    var threat = "", shot = false
    if (o.state === "attack") {
      var m = moveOf(o)
      if (!m.projectile && o.moveT < m.startup + m.active && dist <= (m.reach || 0) + p.w / 2 + 24)
        threat = m.level
    }
    for (var i = 0; i < projectiles.length; i++) {
      var q = projectiles[i]
      if (q.owner === p.idx) continue
      var gap = (p.x - q.x) * (q.vx > 0 ? 1 : -1)
      if (gap > 0 && gap < 230) { threat = q.level; shot = true }
    }
    var om = o.state === "attack" ? moveOf(o) : null
    return {
      level: cpuLevel, dist: dist, range: def.moves.sH.reach, input: def.special.input,
      specialReady: def.special.input === "charge" ? chargeReady(p)
                  : def.special.input === "dd" ? !ownShotAlive(p.idx) : true,
      charging: p.held.down, threat: threat, threatIsShot: shot,
      oppRecovering: !!om && o.moveT >= om.startup + om.active,
      oppDown: o.state === "knockdown", meter: p.meter,
      stunned: p.state === "hitstun" || p.state === "blockstun"
    }
  }

  function cpuHold(p, act, want) {
    if (p.held[act] === want) return
    if (want) press(p.idx, act, true); else release(p.idx, act, true)
  }

  // Turn a decision into keys: the same held directions and presses a person
  // makes. A special is entered as its motion (taps a moment apart) + button.
  function cpuApply(p, d) {
    var o = fighters[1 - p.idx]
    var toward = o.x >= p.x ? "right" : "left", away = toward === "right" ? "left" : "right"
    cpuHold(p, "left", (d.dir === 1 && toward === "left") || (d.dir === -1 && away === "left"))
    cpuHold(p, "right", (d.dir === 1 && toward === "right") || (d.dir === -1 && away === "right"))
    cpuHold(p, "down", d.down)
    // Jump only when free to: a held `up` pressed mid-move would fire a late,
    // unintended jump the moment the CPU is idle again.
    if (d.jump && canNeutral(p) && !p.air) { cpuHold(p, "up", false); press(p.idx, "up", true) }
    var btn = d.button
    if (btn === "special") {
      var sp = defOf(p).special
      if (sp.input === "dash") { Input.push(p.buf, "F", clock - 0.12); Input.push(p.buf, "F", clock - 0.03) }
      else if (sp.input === "dd") { Input.push(p.buf, "D", clock - 0.12); Input.push(p.buf, "D", clock - 0.03) }
      btn = sp.button
    }
    if (btn !== "") { press(p.idx, btn, true); release(p.idx, btn, true) }
  }

  function cpuThink(p) {
    var d = AI.decide(cpuContext(p), rand)
    p.lastDecision = d.why
    decisionLog.push(d.why)
    if (decisionLog.length > 64) decisionLog.shift()
    cpuApply(p, d)
    return d
  }

  // ---- the step ---------------------------------------------------------------
  function step(dt) {
    clock += dt
    if (bannerT > 0) { bannerT -= dt; if (bannerT <= 0) banner = "" }
    if (comboT > 0) { comboT -= dt; if (comboT <= 0) comboText = "" }
    for (var s = sparks.length - 1; s >= 0; s--) {
      sparks[s].life += dt
      if (sparks[s].life > 0.35) sparks.splice(s, 1)
    }
    if (!fighting()) return

    if (phase === "ready") {
      readyT -= dt
      if (readyT <= 0) { readyT = 0; phase = "play" }
    }
    if (phase === "play") {
      for (var c = 0; c < 2; c++) {
        var cp = fighters[c]
        if (!cp.cpu) continue
        cp.aiT -= dt
        if (cp.aiT <= 0) { cp.aiT = AI.thinkTime(cpuLevel); cpuThink(cp) }
      }
    }
    updateFighter(fighters[0], dt)
    updateFighter(fighters[1], dt)
    separate()
    faceEachOther()

    if (phase === "play") {
      checkHits()
      updateShots(dt)
      timeLeft -= dt
      checkRoundEnd()
    } else if (phase === "roundover") {
      roundT -= dt
      if (roundT <= 0) afterRound()
    }
  }

  FrameAnimation {
    running: game.fighting() || game.phase === "select"
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n && (game.fighting() || game.phase === "select"); i++) game.step(dt / n)
      game.publish()
    }
  }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }

  // ---- keys -------------------------------------------------------------------
  Keys.onPressed: function (e) {
    e.accepted = true
    if (e.isAutoRepeat) return            // held keys are flags; repeats mean nothing
    if (e.key === Qt.Key_Escape) { quitRequested(); return }
    if (e.key === Qt.Key_P) { togglePause(); return }
    if (phase === "select") {
      switch (e.key) {
      case Qt.Key_W: case Qt.Key_Up: selMove(-1); break
      case Qt.Key_S: case Qt.Key_Down: selMove(1); break
      case Qt.Key_A: case Qt.Key_Left: selChange(-1); break
      case Qt.Key_D: case Qt.Key_Right: selChange(1); break
      case Qt.Key_F: case Qt.Key_Space: case Qt.Key_Return: case Qt.Key_Enter: selConfirm(); break
      default: e.accepted = false
      }
      return
    }
    if (phase === "over") {
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) toSelect()
      else e.accepted = false
      return
    }
    var a = keyAction(e.key)
    if (!a) { e.accepted = false; return }
    press(a.player, a.act, false)
  }
  Keys.onReleased: function (e) {
    if (e.isAutoRepeat) return
    var a = keyAction(e.key)
    if (a) release(a.player, a.act, false)
  }

  Component.onCompleted: {
    if (seed === 0) seed = (Date.now() % 2147483647) || 1
    newGame()
  }

  // ---- pose (what Fighter.qml draws) ---------------------------------------------
  // Angles in degrees for a fighter facing right: 0 = limb hanging down, -90 =
  // pointing forward, 90 = back, ±180 = up. Upper/lower pairs: aF/aB arms (front,
  // back), lF/lB legs. `hip` is the hip height as a share of leg length.
  readonly property var basePose: ({ aFu: -50, aFl: -80, aBu: -25, aBl: -100, lFu: -18, lFl: 14, lBu: 18, lBl: 4, lean: 4, hip: 0.97, rot: 0, lift: 0 })
  function mixPose(a, b, k) {
    var o = {}
    for (var key in a) o[key] = a[key] + ((b[key] === undefined ? a[key] : b[key]) - a[key]) * k
    return o
  }
  function strikePose(p, key) {
    var id = defOf(p).special.id
    switch (key) {
    case "sL": return { aFu: -90, aFl: -2, lean: 10 }
    case "sH": return id === "quarry" ?{ aFu: -150, aFl: 60, aBu: -60, lean: 16 }
                                      : { lFu: -98, lFl: -2, lean: -12, aFu: -40, aFl: -110 }
    case "cL": return { hip: 0.58, lFu: -88, lFl: 0, lBu: -20, lBl: 80, lean: 12 }
    case "cH": return { hip: 0.46, lFu: -86, lFl: -4, lBu: -30, lBl: 110, lean: 32, aFu: 30, aBu: 50 }
    case "jL": return { aFu: -55, aFl: -2, lFu: -60, lFl: 90, lBu: -20, lBl: 80 }
    case "jH": return { lFu: -55, lFl: -6, lBu: 20, lBl: 60, lean: 8 }
    case "sp":
      if (id === "talon") return { lean: 34, aFu: -92, aFl: 0, aBu: 70, aBl: 0, lFu: 30, lFl: 30, lBu: 55, lBl: 20 }
      if (id === "kite") return { aFu: -105, aFl: -6, aBu: -95, aBl: -10, lean: 6 }
      return { aFu: -40, aFl: 0, aBu: -30, aBl: 0, lean: 26, hip: 0.8 }
    }
    return {}
  }
  function windupPose(p, key) {
    var id = defOf(p).special.id
    if (key === "sp" && id === "quarry") return { aFu: -178, aFl: 0, aBu: -172, aBl: 0, lean: -8 }
    if (key === "sp" && id === "kite") return { aFu: -170, aFl: -10, aBu: -150, lean: -6 }
    return null
  }

  function poseOf(i) {
    var p = fighters[i]
    if (!p) return { x: -400, h: 0, facing: 1, aFu: 0, aFl: 0, aBu: 0, aBl: 0, lFu: 0, lFl: 0, lBu: 0, lBl: 0, lean: 0, hip: 1, rot: 0, lift: 0, flash: false, kindle: false, t: 0, state: "" }
    var t = drawT + i * 0.7
    var q = mixPose(basePose, {}, 0)
    q.hip = 0.97 + 0.015 * Math.sin(t * 4)
    var o = fighters[1 - i]
    var guarding = holdingBack(p) && o && Math.abs(o.x - p.x) < 260
    switch (p.state) {
    case "idle":
      if (p.air) q = mixPose(q, { lFu: -60, lFl: 95, lBu: -20, lBl: 80, aFu: -130, aFl: -30, hip: 0.95 }, 1)
      else if (Math.abs(p.vx) > 1) {
        var ph = Math.sin(drawT * 10 * (p.vx * p.facing > 0 ? 1 : -1))
        q.lFu = -18 + 24 * ph; q.lBu = 18 - 24 * ph
        q.lFl = 14 + 18 * Math.max(0, -ph); q.lBl = 4 + 18 * Math.max(0, ph)
      }
      if (guarding && !p.air) q = mixPose(q, { aFu: -95, aFl: -150, aBu: -70, aBl: -140, lean: -4 }, 1)
      break
    case "crouch":
      q = mixPose(q, { hip: 0.58, lFu: -75, lFl: 100, lBu: -25, lBl: 80, lean: 14 }, 1)
      if (guarding) q = mixPose(q, { aFu: -95, aFl: -150, aBu: -70, aBl: -140 }, 1)
      break
    case "blockstun":
      q = mixPose(q, { aFu: -95, aFl: -150, aBu: -70, aBl: -140, lean: -8 }, 1)
      if (p.held.down) q = mixPose(q, { hip: 0.58, lFu: -75, lFl: 100, lBu: -25, lBl: 80 }, 1)
      break
    case "hitstun":
      q = mixPose(q, { lean: -22, aFu: 30, aFl: -40, aBu: 50, aBl: -30, hip: 0.94 }, 1)
      break
    case "knockdown":
    case "ko":
      var down = p.air ? clamp(0.4 + (p.vy < 0 ? 0.6 : 0.2), 0, 1) : 1
      if (p.state === "knockdown" && !p.air && p.stateT < 0.25) down = p.stateT / 0.25
      // Lying down: rotated about the feet and lifted so the body rests on the floor.
      q = mixPose(q, { rot: -84, lift: defOf(p).w * 0.42, aFu: 150, aFl: 20, aBu: 120, aBl: 10, lFu: -30, lFl: 20, lBu: 10, lBl: 10, lean: 0 }, down)
      break
    case "victory":
      q = mixPose(q, { aFu: -176, aFl: -8, aBu: -20, aBl: -90, lean: -4 }, 1)
      break
    case "attack":
      var m = moveOf(p)
      var base = p.air ? mixPose(q, { lFu: -60, lFl: 95, lBu: -20, lBl: 80, aFu: -130, aFl: -30 }, 1)
               : p.move.charAt(0) === "c" ? mixPose(q, { hip: 0.58, lFu: -75, lFl: 100, lBu: -25, lBl: 80, lean: 14 }, 1) : q
      var hit = mixPose(base, strikePose(p, p.move), 1)
      var wind = windupPose(p, p.move)
      if (p.moveT < m.startup) {
        var k = p.moveT / Math.max(0.001, m.startup)
        q = wind ? mixPose(base, mixPose(base, wind, 1), k) : mixPose(base, hit, k * 0.6)
      } else if (p.moveT < m.startup + m.active) q = hit
      else q = mixPose(hit, base, (p.moveT - m.startup - m.active) / Math.max(0.001, m.recovery))
      break
    }
    q.x = p.x; q.h = p.h; q.facing = p.facing
    q.flash = p.flashT > 0; q.kindle = p.kindleT > 0; q.t = drawT; q.state = p.state
    q.invuln = p.invulT > 0
    return q
  }

  // ---- drawing ----------------------------------------------------------------
  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)
    clip: true

    Stage { anchors.fill: parent; game: engine }

    // Projectiles: a Kite Lantern is a diamond kite with a glowing core and a
    // tail; a Quarry Slam wave is a rolling ridge of stones.
    Repeater {
      id: shotView
      model: game.projectiles.length
      delegate: Item {
        id: shot
        required property int index
        x: game.shotAt(index).x
        y: game.groundY - game.shotAt(index).h
        width: 0; height: 0
        readonly property color tint: game.shotAt(index).owner === 0 ? game.color("yellow", "#e0af68") : game.color("cyan", "#7dcfff")
        // kite
        Item {
          visible: game.shotAt(shot.index).kind === "kite"
          Rectangle {
            x: -11; y: -26; width: 22; height: 22; rotation: 45
            color: game.color("magenta", "#bb9af7"); border.width: 2; border.color: shot.tint
          }
          Rectangle {
            x: -5; y: -20; width: 10; height: 10; radius: 5
            color: shot.tint; opacity: 0.6 + 0.4 * Math.sin(game.drawT * 18)
          }
          Repeater {
            model: 3
            delegate: Rectangle {
              required property int index
              width: 4; height: 4; radius: 2
              x: -game.shotAt(shot.index).facing * (16 + index * 9) - 2
              y: -14 + 5 * Math.sin(game.drawT * 9 + index)
              color: shot.tint; opacity: 0.8 - index * 0.22
            }
          }
        }
        // wave
        Item {
          visible: game.shotAt(shot.index).kind === "wave"
          Repeater {
            model: 4
            delegate: Rectangle {
              required property int index
              readonly property real hh: 14 + 20 * Math.abs(Math.sin(game.drawT * 14 + index * 1.3))
              width: 12; height: hh; radius: 3
              x: -23 + index * 12 - game.shotAt(shot.index).facing * 2
              y: -hh
              color: index % 2 ? game.color("orange", "#e0af68") : game.color("red", "#f7768e")
              border.width: 1; border.color: game.color("dark_background", "#13141c")
            }
          }
        }
      }
    }

    // Fighters
    Repeater {
      id: fighterView
      model: game.fighters.length
      delegate: Fighter {
        required property int index
        game: engine
        slot: index
      }
    }

    // Hit and block sparks: an expanding ring.
    Repeater {
      model: game.sparks.length
      delegate: Rectangle {
        required property int index
        readonly property real life: game.sparkAt(index).life
        readonly property real r: 6 + life * (game.sparkAt(index).kind === "flare" ? 260 : 110)
        x: game.sparkAt(index).x - r
        y: game.groundY - game.sparkAt(index).h - r
        width: r * 2; height: r * 2; radius: r
        color: "transparent"
        border.width: 3
        border.color: game.sparkAt(index).kind === "block" ? game.color("blue", "#7aa2f7")
                    : game.sparkAt(index).kind === "flare" ? game.color("orange", "#ff9e64")
                    : game.color("bright_foreground", "#c0caf5")
        opacity: Math.max(0, 1 - life / 0.35)
      }
    }

    Hud { id: hudView; anchors.fill: parent; game: engine }
  }
}
