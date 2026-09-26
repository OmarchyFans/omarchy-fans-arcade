import QtQuick
import "fighters.js" as Fighters
import "grapple.js" as Grapple
import "judges.js" as Judges
import "input.js" as Input
import "ai.js" as AI

// Super MMA Fighter: the whole game. A 2D side view of a twelve-sided cage (the
// Dodecage), in a fixed 800x540 field scaled to the window.
//
// Modes: 1 player vs a CPU ladder (the six other fighters, the CPU one level
// sharper each fight), or 2 players on one keyboard.
//
// A fight is up to 3 rounds of ROUND_TIME (60) seconds of game time. It ends early
// on a finish:
//   KO    head damage reaches 100 from a standing strike;
//   TKO   the referee stops it: head damage 100 from ground-and-pound, body or
//         leg damage 100, or three knockdowns in one round;
//   SUB   the tap meter of a submission fills (TAP OUT).
// If nobody finishes, three judges score every round 10-point-must style from
// damage, takedowns, control time, knockdowns and submission attempts
// (judges.js) and the DECISION is unanimous, split or majority, or a draw.
//
// The fight has four places to be (`pos`):
//   stand   strikes (jab, cross, hook, body shot, body/head/leg kick, knee and a
//           special), block by holding back, slip by tapping down (head strikes
//           miss, and your next strike is a counter), sprawl by holding down as
//           they shoot. Big head shots rock; a hit while rocked, or a huge one,
//           is a knockdown, and the one standing can pounce.
//   clinch  tie up at close range: dirty boxing, knees, trips and throws, pummel
//           for the inside, a guillotine, or break away.
//   ground  guard -> half guard -> side control -> mount -> back control. The top
//           fighter advances, strikes and attacks locks; the bottom one escapes a
//           step, sweeps from guard, stands up, covers, or attacks from guard.
//           The referee stands a stalled fight up.
//   sub     a submission struggle: the tap meter climbs from the attacker's
//           grappling against the defender's grappling and cardio; the defender
//           mashes keys to push it back and fill an escape meter.
// Stamina (from cardio) pays for everything; below 30 every strike, shot and
// escape gets weaker and slower. Every countdown is a number in step().
//
// Our own mechanics: every number comes from the fighter's eight ratings and
// finish split (fighters.js), so the same takedown lands on a kickboxer and gets
// sprawled on by a sambo grinder; each fighter has a signature special; and the
// slip -> counter window and the chain shot make timing matter.
//
// One open weight class: the roster is seven invented fighters whose ratings,
// not their size, decide the fight.
//
// Score (1 player only): 10 per point of damage, 150 per takedown, 500 per
// knockdown, 100 per submission attempt; a win adds 3000 for a finish (plus
// time and round bonuses) or 1500 for a decision (2000 if unanimous); all
// multiplied by the CPU level factor. The high score is the best ladder run;
// a score that only ties it is not a new high score.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- controls: every key in one place --------------------------------------
  // Qt reports left and right Ctrl (and Shift) as the same key, so either one
  // works for player 2; player 1 uses neither. Shift+/ arrives as '?'.
  readonly property var keymap: ({
    p1: { left: [Qt.Key_A], right: [Qt.Key_D], up: [Qt.Key_W], down: [Qt.Key_S],
          strike: [Qt.Key_F], kick: [Qt.Key_G], special: [Qt.Key_H], grapple: [Qt.Key_J] },
    p2: { left: [Qt.Key_Left], right: [Qt.Key_Right], up: [Qt.Key_Up], down: [Qt.Key_Down],
          strike: [Qt.Key_Control], kick: [Qt.Key_Shift], special: [Qt.Key_Return, Qt.Key_Enter],
          grapple: [Qt.Key_Slash, Qt.Key_Question] }
  })
  readonly property var keyNames: ({
    p1: "WASD move · F strike · G kick · H special · J grapple",
    p2: "arrows · Ctrl strike · Shift kick · Enter special · / grapple"
  })
  readonly property var actions: ["left", "right", "up", "down", "strike", "kick", "special", "grapple"]

  // ---- field and tuning -------------------------------------------------------
  readonly property real fieldW: 800
  readonly property real fieldH: 540
  readonly property real hudH: 96
  readonly property real groundY: 478
  readonly property real wallL: 40
  readonly property real wallR: 760
  readonly property real roundTime: 60
  readonly property int maxRounds: 3
  readonly property real readyTime: 1.4
  readonly property real roundPause: 2.4
  readonly property real resultTime: 5
  readonly property real startLeft: 290
  readonly property real startRight: 510
  readonly property real shootTime: 0.34
  readonly property real shootSpeed: 430
  readonly property real downTime: 1.8
  readonly property real rockTime: 1.6
  readonly property real clinchBreak: 12      // the referee breaks a clinch this old
  readonly property real groundStall: 7       // ... and stands up a ground fight this idle
  readonly property real limit: 100           // head, body or leg damage that ends it

  // ---- state ------------------------------------------------------------------
  property int seed: 0
  property real rngState: 1
  property string phase: "select"   // select | ready | play | roundover | paused | result | over
  property string pausedFrom: ""
  property string mode: "cpu"       // cpu | versus
  property int difficulty: 1
  property int stage: 1
  property int cpuLevel: 1
  property bool champion: false
  property int round: 1
  property real timeLeft: roundTime
  property real readyT: 0
  property real roundT: 0
  property real resultT: 0
  property real clock: 0
  property real drawT: 0            // `clock` as of the last publish(): what the drawing animates by
  property int score: 0
  property bool beatHigh: false
  property int tallyP1: 0           // versus: fights won this session
  property int tallyP2: 0
  property var fighters: []
  property var sparks: []
  property var decisionLog: []      // the CPU's recent decisions (tests and curiosity)
  property string banner: ""
  property real bannerT: 0

  // Where the fight is. clinchS / gnd / subS hold that place's details.
  property string pos: "stand"      // stand | clinch | ground | sub
  property var clinchS: ({ owner: 0, t: 0 })
  property var gnd: ({ top: 0, pos: "guard", t: 0, idle: 0, cx: 400 })
  property var subS: ({ att: 0, kind: "", where: "", tap: 0, esc: 0, t: 0 })
  property int posRev: 0            // bumps on every change of place, for the drawing

  // Round stats (for the judges) and the cards so far.
  property var rs: [blankStats(), blankStats()]
  property var cards: []
  property var result: ({ winner: -1, method: "", detail: "", round: 0, time: "", totals: [] })

  // Select screen
  property int selRow: 0
  property string selMode: "cpu"
  property int selDiff: 1
  property int selP1: 0
  property int selP2: 1

  readonly property alias fighterView: fighterView
  readonly property alias hudView: hudView
  readonly property alias stageView: stageView

  // The drawing components each have their own `game` property; inside them the
  // name means that property, so they are handed this instead.
  readonly property var engine: game

  function color(key, fallback) { return theme[key] || fallback }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function fighting() { return phase === "ready" || phase === "play" || phase === "roundover" }
  function blankStats() { return { dmg: 0, td: 0, ctrl: 0, kd: 0, subAtt: 0 } }

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
  function roll(chance) { return rand() < chance }

  // Delegates read through these (see docs/GAMES.md, rule 5).
  readonly property var offField: ({ x: -400, facing: 1, head: 0, body: 0, leg: 0, stamina: 0, d: 0, name: "", state: "", life: 0, h: 0, kind: "" })
  function fighterAt(i) { return fighters[i] || offField }
  function sparkAt(i) { return sparks[i] || offField }
  function defOf(p) { return Fighters.at(p.d) }
  function lookOf(i) { var f = fighters[i]; return f ? Fighters.at(f.d) : Fighters.at(0) }
  // Once per frame, never per substep. The drawing reads drawT, not clock, so
  // nothing on screen re-evaluates between publishes.
  function publish() {
    drawT = clock; fighters = fighters.slice(); sparks = sparks.slice(); rs = rs.slice()
    gnd = Object.assign({}, gnd); subS = Object.assign({}, subS); clinchS = Object.assign({}, clinchS)
  }

  // ---- setting up -------------------------------------------------------------
  function makeFighter(idx, d, cpu) {
    var def = Fighters.at(d)
    var st = Fighters.stats(def)
    var held = {}
    for (var i = 0; i < actions.length; i++) held[actions[i]] = false
    return {
      idx: idx, d: d, cpu: cpu, name: def.name, r: def.ratings, st: st, plan: Fighters.plan(def),
      w: st.w, hgt: st.h,
      x: idx === 0 ? startLeft : startRight, facing: idx === 0 ? 1 : -1, vx: 0, slide: 0,
      state: "idle", stateT: 0, move: "", moveT: 0, mv: null, hasHit: false,
      head: 0, body: 0, leg: 0, stamina: 100,
      rockedT: 0, slipT: 0, slipCd: 0, counterT: 0, invulT: 0, flashT: 0, actT: 0,
      kd: 0, sprawlAt: -9, shootBonus: 0, chainLeft: 0, sprawled: false, shootFrom: 0,
      held: held, pending: null, aiT: 0.4, mashT: 0, lastDecision: "", strikeAnim: -9
    }
  }

  // Everything back to the select screen, reseeded from `seed`.
  function newGame() {
    reseed()
    score = 0; beatHigh = false; champion = false; stage = 1
    tallyP1 = 0; tallyP2 = 0
    toSelect()
  }

  // The select screen, keeping the session's choices and versus tally.
  function toSelect() {
    phase = "select"; pausedFrom = ""
    round = 1; timeLeft = roundTime; clock = 0
    sparks = []; decisionLog = []; cards = []
    banner = ""; bannerT = 0; pos = "stand"
    result = { winner: -1, method: "", detail: "", round: 0, time: "", totals: [] }
    selRow = clamp(selRow, 0, selRows().length - 1)
    setPreview()
  }

  // The two chosen fighters (the select screen's stat cards read them).
  function setPreview() {
    fighters = [makeFighter(0, selP1, false),
                makeFighter(1, selMode === "cpu" ? Fighters.ladderOpponent(selP1, 1) : selP2, false)]
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
    beginFight(p1, opp)
  }

  function beginFight(p1, p2) {
    cpuLevel = mode === "cpu" ? Fighters.cpuLevel(difficulty, stage) : 0
    fighters = [makeFighter(0, p1, false), makeFighter(1, p2, mode === "cpu")]
    round = 1; cards = []
    result = { winner: -1, method: "", detail: "", round: 0, time: "", totals: [] }
    startRound()
  }

  function startRound() {
    for (var i = 0; i < fighters.length; i++) {
      var p = fighters[i]
      if (round > 1) {
        // The minute between rounds: most of the wind comes back, some of the
        // head clears; body and leg damage stay.
        p.stamina = Math.min(100, p.stamina + 0.7 * (100 - p.stamina))
        p.head = Math.max(0, p.head * 0.8)
      }
      p.kd = 0
      p.rockedT = 0; p.slipT = 0; p.slipCd = 0; p.counterT = 0; p.invulT = 0; p.flashT = 0; p.actT = 0
      p.pending = null; p.aiT = 0.4; p.mashT = 0
      if (p.cpu) for (var k in p.held) p.held[k] = false
    }
    toStand(startRight - startLeft, (startLeft + startRight) / 2, true)
    rs = [blankStats(), blankStats()]
    sparks = []
    timeLeft = roundTime; readyT = readyTime
    phase = "ready"
    publish()
  }

  // Both fighters back on their feet, `gap` apart around `cx` (default: where
  // they are), keeping their sides unless `p1Left`.
  function toStand(gap, cx, p1Left) {
    var a = fighters[0], b = fighters[1]
    var c = cx === undefined ? (a.x + b.x) / 2 : cx
    var s = p1Left || a.x <= b.x ? 1 : -1
    c = clamp(c, wallL + gap / 2 + 30, wallR - gap / 2 - 30)
    a.x = c - s * gap / 2; b.x = c + s * gap / 2
    a.facing = s; b.facing = -s
    for (var i = 0; i < 2; i++) {
      var p = fighters[i]
      p.state = "idle"; p.stateT = 0; p.move = ""; p.moveT = 0; p.hasHit = false; p.vx = 0; p.slide = 0
      p.actT = 0.2
    }
    pos = "stand"
    posRev++
  }

  // ---- pause and focus --------------------------------------------------------
  // The result card pauses too: its countdown starts the next ladder fight, and
  // nobody should come back to a fight already under way.
  function pause() {
    if (!fighting() && phase !== "result") return
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
      p.pending = null
    }
    pause()
  }

  // ---- scoring ----------------------------------------------------------------
  function levelMul() { return 1 + 0.25 * (cpuLevel - 1) }
  function addScore(points) {
    if (mode !== "cpu" || points <= 0) return
    score += Math.round(points * levelMul())
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }
  function flash(text, secs) { banner = text; bannerT = secs || 1.2 }

  // ---- stamina ------------------------------------------------------------------
  function spend(p, cost) { p.stamina = Math.max(0, p.stamina - cost * p.st.cost) }
  function tired(p) { return Grapple.tired(p.stamina) }

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

  function other(p) { return fighters[1 - p.idx] }
  function dist() { return Math.abs(fighters[1].x - fighters[0].x) }
  function towardHeld(p) { return p.facing > 0 ? (p.held.right && !p.held.left) : (p.held.left && !p.held.right) }
  function backHeld(p) { return p.facing > 0 ? (p.held.left && !p.held.right) : (p.held.right && !p.held.left) }
  function canAct(p) { return phase === "play" && pos === "stand" && p.state === "idle" }

  // A key went down. The CPU uses the same entry point (fromCpu); a person's
  // player-2 keys do nothing while the CPU plays player 2.
  function press(pi, act, fromCpu) {
    var p = fighters[pi]
    if (!p || (p.cpu && !fromCpu)) return
    if (p.held[act]) return
    p.held[act] = true
    if (phase !== "play") return
    if (pos === "sub") { subPress(p, act); return }
    var isDir = act === "left" || act === "right" || act === "up" || act === "down"
    if (isDir) { dirPress(p, act); return }
    if (!tryButton(p, act)) p.pending = { btn: act, t: clock }
  }

  function release(pi, act, fromCpu) {
    var p = fighters[pi]
    if (!p || (p.cpu && !fromCpu)) return
    p.held[act] = false
  }

  // A direction tapped: a slip (and sprawl) standing, a break from the clinch,
  // a pass / escape / stand-up on the ground.
  function dirPress(p, act) {
    var rel = Input.relative(act, p.facing)
    if (pos === "stand") {
      if (act === "down") {
        p.sprawlAt = clock
        if (p.state === "idle" && p.slipCd <= 0) { p.slipT = Input.SLIP_TIME; p.slipCd = Input.SLIP_COOLDOWN }
      }
      return
    }
    if (pos === "clinch") { if (rel === "B") clinchBreakAttempt(p); return }
    if (pos === "ground") groundMove(p, act)
  }

  // A button, now. Returns false if the fighter is busy (the caller buffers it).
  function tryButton(p, btn) {
    if (pos === "clinch") return clinchAction(p, btn)
    if (pos === "ground") return groundAction(p, btn)
    if (pos !== "stand") return true
    var o = other(p)
    if (o.state === "stuffed" && btn === "grapple" && p.state === "idle" && dist() < 110) {
      // The shot was stuffed: snap on a guillotine if you know one, else tie up.
      if (defOf(p).subs.indexOf("guillotine") >= 0) startSub(p.idx, "guillotine", "stand")
      else enterClinch(p.idx)
      return true
    }
    if (!canAct(p)) return false
    var d = dist()
    if (btn === "strike" || btn === "kick") {
      startMove(p, Input.strikeFor(btn, towardHeld(p), backHeld(p), p.held.down, d < 75))
      return true
    }
    if (btn === "special") { doSpecial(p); return true }
    if (btn === "grapple") {
      if (o.state === "down" && d < 170) { pounce(p); return true }
      if (d < 92) clinchAttempt(p)
      else startShoot(p, 0, 0)
      return true
    }
    return true
  }

  // ---- stand-up -------------------------------------------------------------------
  function startMove(p, key) {
    var m = Grapple.MOVES[key]
    var slow = p.st.tempo * (tired(p) < 1 ? 1.2 : 1) * (p.rockedT > 0 ? 1.15 : 1)
    p.state = "attack"; p.move = key; p.moveT = 0; p.hasHit = false; p.vx = 0
    p.mv = { startup: m.startup * slow, active: m.active, recovery: m.recovery * slow }
    p.pending = null
    spend(p, m.cost)
  }

  function doSpecial(p) {
    var o = other(p), d = dist()
    switch (defOf(p).special.id) {
    case "chain": if (d <= 220) { flash("CHAIN SHOT", 0.8); startShoot(p, 0.05, 1) } break
    case "pocket":
      p.state = "counter"; p.stateT = 0.5 * p.st.tempo; spend(p, 4)
      break
    case "pinwheel": startMove(p, "pinwheel"); break
    case "skyknee": startMove(p, "skyknee"); break
    case "overhand": startMove(p, "overhand"); break
    case "vine":
      if (d <= 110) {
        spend(p, Grapple.COST.pull)
        // Guard pull: she lands on her back with them in her guard, already
        // locking up her best guard submission.
        startGround(o.idx, "guard")
        var kind = Grapple.pickSub(defOf(p).subs, "bottom:guard")
        if (kind !== "") startSub(p.idx, kind, "bottom:guard", 30)
        flash("VINE PULL", 0.9)
      }
      break
    case "wheel": if (d <= 100) hipThrow(p); break
    }
  }

  function hipThrow(p) {
    var o = other(p)
    spend(p, Grapple.COST.throw)
    if (roll(Grapple.throwChance(p.r, o.r, p.stamina))) {
      rs[p.idx].td++
      addScoreFor(p, 150)
      startGround(p.idx, "side")
      hurt(p, o, "body", 4 * p.st.knee, "slam")
      flash("HARBOR WHEEL!", 1.0)
    } else {
      if (pos === "clinch") p.actT = 0.8
      else { p.state = "recover"; p.stateT = 0.5 }
      flash("THROW BLOCKED", 0.8)
    }
  }

  function startShoot(p, bonus, chain) {
    p.state = "shoot"; p.moveT = 0; p.vx = 0
    p.shootBonus = bonus; p.chainLeft = chain; p.shootFrom = clock
    other(p).sprawled = false
    spend(p, Grapple.COST.shoot)
  }

  // The shot reaches the legs (or runs out): roll the takedown.
  function resolveShoot(p, contact) {
    var o = other(p)
    if (!contact) { p.state = "recover"; p.stateT = 0.35; return }
    var sprawled = o.sprawled || o.held.down || o.sprawlAt >= p.shootFrom - 0.1
    var chance = Grapple.takedownChance(p.r, o.r, p.stamina, o.stamina, sprawled, p.shootBonus)
    if (roll(chance)) {
      rs[p.idx].td++
      addScoreFor(p, 150)
      startGround(p.idx, p.r.wrestling >= 9 ? "half" : "guard")
      flash("TAKEDOWN", 0.9)
    } else if (p.chainLeft > 0) {
      flash("CHAIN!", 0.7)
      startShoot(p, p.shootBonus + 0.1, p.chainLeft - 1)
      p.state = "shoot"; p.moveT = shootTime * 0.6          // already on the legs
    } else {
      p.state = "stuffed"; p.stateT = 0.7
      flash(sprawled ? "SPRAWL!" : "STUFFED", 0.8)
    }
  }

  function clinchAttempt(p) {
    var o = other(p)
    spend(p, Grapple.COST.clinch)
    if (roll(Grapple.clinchChance(p.r, o.r, p.stamina, canBlock(o)))) enterClinch(p.idx)
    else { p.state = "recover"; p.stateT = 0.3 }
  }

  function pounce(p) {
    var o = other(p)
    o.state = "ground"
    startGround(p.idx, "side")
    flash("POUNCE", 0.7)
  }

  function canBlock(p) {
    return backHeld(p) && p.rockedT <= 0 && (p.state === "idle" || p.state === "blockstun")
  }
  function strikeMul(p, kind) {
    if (kind === "punch") return p.st.punch
    if (kind === "kick") return p.st.kick * (1 - p.leg / 400)      // hurt legs kick softer
    return p.st.knee
  }
  function counterMul(p) { return p.plan.counter ? 1.6 : 1.35 }

  // A standing strike reaches the other fighter. Returns what happened:
  // "hit" | "block" | "slip" | "countered" | "miss".
  function resolveStrike(ai, key) {
    var att = fighters[ai], def = fighters[1 - ai], m = Grapple.MOVES[key]
    if (def.invulT > 0 || def.state === "down" || def.state === "ko") return "miss"
    if (def.state === "counter" && m.zone !== "leg") { triggerCounter(def, att); return "countered" }
    if (m.zone === "head" && def.slipT > 0) {
      def.counterT = Input.COUNTER_TIME
      addSpark(def.x, def.hgt * 0.9, "slip")
      flash("SLIP", 0.5)
      return "slip"
    }
    var dmg = m.dmg * strikeMul(att, m.kind) * tired(att)
    if (att.counterT > 0) { dmg *= counterMul(att); att.counterT = 0; flash("COUNTER!", 0.6) }
    var away = def.x >= att.x ? 1 : -1
    if (def.state === "shoot" && key === "knee") { dmg *= 1.6; flash("KNEE ON THE SHOT", 0.8) }
    if (m.zone !== "leg" && canBlock(def)) {
      hurt(att, def, m.zone, dmg * def.st.guard, "blocked")
      def.state = "blockstun"; def.stateT = 0.1 + 0.01 * m.dmg
      def.slide = away * 120
      spend(def, Grapple.COST.block)
      addSpark(def.x - away * def.w / 2, def.hgt * 0.7, "block")
      return "block"
    }
    hurt(att, def, m.zone, dmg, "strike")
    if (def.state !== "down" && def.state !== "ko" && phase === "play") {
      def.state = "hitstun"; def.stateT = 0.16 + 0.015 * dmg; def.move = ""
      def.slide = away * (100 + 8 * dmg)
    }
    addSpark(def.x - away * def.w / 3, def.hgt * (m.zone === "head" ? 0.9 : (m.zone === "body" ? 0.6 : 0.2)), "hit")
    return "hit"
  }

  // Pocket Trap sprung: the strike is slipped and a counter left comes back.
  function triggerCounter(def, att) {
    att.state = "hitstun"; att.stateT = 0.3; att.move = ""
    def.state = "idle"; def.stateT = 0
    var dmg = Grapple.MOVES.counter.dmg * def.st.punch * tired(def)
    flash("POCKET TRAP!", 0.9)
    def.move = "counter"                  // so a KO from it is named COUNTER LEFT
    hurt(def, att, "head", dmg, "strike")
    if (def.state === "idle") def.move = ""
    addSpark(att.x, att.hgt * 0.9, "hit")
  }

  // Damage lands on a zone. This is where rocked, knockdowns and finishes come
  // from. how: strike | blocked | clinch | gnp | slam.
  function hurt(att, def, zone, amount, how) {
    if (phase !== "play" || amount <= 0) return
    def[zone] = def[zone] + amount
    def.flashT = 0.1
    rs[att.idx].dmg += amount
    addScoreFor(att, 10 * amount)
    if (zone === "body") spend(def, amount * 0.6)
    if (pos === "ground") gnd.idle = 0
    if (def.head >= limit) {
      var ko = how === "strike" || how === "clinch"
      var what = how === "clinch" ? "CLINCH STRIKES" : (Grapple.MOVES[att.move] ? Grapple.MOVES[att.move].name : "PUNCHES")
      return finish(att.idx, ko ? "KO" : "TKO", ko ? what : "GROUND AND POUND")
    }
    if (def.body >= limit) return finish(att.idx, "TKO", "BODY SHOTS")
    if (def.leg >= limit) return finish(att.idx, "TKO", "LEG KICKS")
    if (zone !== "head" || how === "blocked") return
    if (pos === "stand" && how === "strike" && (amount >= 16 || (def.rockedT > 0 && amount >= 5))) return knockdown(att, def)
    if (amount >= (pos === "stand" ? 9 : 7) || def.head >= 70) {
      if (def.rockedT <= 0) flash("ROCKED!", 0.9)
      def.rockedT = rockTime
    }
  }

  function knockdown(att, def) {
    def.kd++
    rs[att.idx].kd++
    addScoreFor(att, 500)
    if (def.kd >= 3) return finish(att.idx, "TKO", "THREE KNOCKDOWNS")
    def.state = "down"; def.stateT = downTime; def.move = ""; def.rockedT = rockTime + downTime
    def.slide = (def.x >= att.x ? 1 : -1) * 260
    flash("KNOCKDOWN!", 1.2)
  }

  // ---- clinch -----------------------------------------------------------------------
  function enterClinch(owner) {
    var a = fighters[owner], b = other(a)
    var c = (a.x + b.x) / 2, s = a.x <= b.x ? 1 : -1
    c = clamp(c, wallL + 60, wallR - 60)
    a.x = c - s * 28; b.x = c + s * 28
    a.facing = s; b.facing = -s
    for (var i = 0; i < 2; i++) { var p = fighters[i]; p.state = "clinch"; p.actT = 0.25; p.move = ""; p.vx = 0; p.slide = 0 }
    clinchS = { owner: owner, t: 0 }
    pos = "clinch"; posRev++
    flash("CLINCH", 0.6)
  }

  function clinchAction(p, btn) {
    if (p.actT > 0) return false
    var o = other(p), owner = clinchS.owner === p.idx
    switch (btn) {
    case "strike":
      spend(p, Grapple.COST.dirty); p.actT = 0.3; p.strikeAnim = clock
      hurt(p, o, "head", 4 * p.st.punch * tired(p), "clinch")
      return true
    case "kick":
      spend(p, 5); p.actT = 0.45; p.strikeAnim = clock
      if (o.rockedT > 0) hurt(p, o, "head", 8 * p.st.knee * tired(p), "clinch")
      else hurt(p, o, "body", 7 * p.st.knee * tired(p), "clinch")
      return true
    case "grapple":
      if (p.held.down && defOf(p).subs.indexOf("guillotine") >= 0) { startSub(p.idx, "guillotine", "stand"); return true }
      if (owner) {
        spend(p, Grapple.COST.throw)
        if (roll(Grapple.clinchTakedownChance(p.r, o.r, p.stamina))) {
          rs[p.idx].td++
          addScoreFor(p, 150)
          startGround(p.idx, p.r.clinch >= 9 ? "side" : (p.r.wrestling >= 8 ? "half" : "guard"))
          flash(p.r.clinch >= 9 ? "THROW" : "TRIP", 0.8)
        } else p.actT = 0.8
      } else {
        spend(p, 3); p.actT = 0.5
        if (roll(Grapple.pummelChance(p.r, o.r, p.stamina))) { clinchS.owner = p.idx; flash("PUMMEL", 0.5) }
      }
      return true
    case "special":
      if (defOf(p).special.id === "wheel") { hipThrow(p); return true }
      return true
    }
    return true
  }

  function clinchBreakAttempt(p) {
    if (p.actT > 0) return
    var o = other(p)
    p.actT = 0.4
    spend(p, 2)
    if (roll(Grapple.breakChance(p.r, o.r, p.stamina, clinchS.owner === p.idx))) { toStand(120); flash("BREAK", 0.5) }
  }

  // ---- ground -----------------------------------------------------------------------
  function startGround(top, where) {
    var t = fighters[top], b = other(t)
    var cx = clamp((t.x + b.x) / 2, wallL + 130, wallR - 130)
    gnd = { top: top, pos: where, t: 0, idle: 0, cx: cx, fb: t.x >= b.x ? 1 : -1 }
    for (var i = 0; i < 2; i++) { var p = fighters[i]; p.state = "ground"; p.actT = 0.3; p.move = ""; p.vx = 0; p.slide = 0; p.pending = null }
    pos = "ground"; posRev++
    layoutGround()
  }

  // Where the two bodies lie: the bottom fighter's feet point at the top one;
  // the top one kneels over the body, further up for better positions.
  readonly property var groundReach: ({ guard: 0.34, half: 0.44, side: 0.52, mount: 0.56, back: 0.64 })
  function layoutGround() {
    var t = fighters[gnd.top], b = other(t), fb = gnd.fb
    b.facing = fb
    b.x = gnd.cx + fb * b.hgt * 0.45
    t.x = b.x - fb * b.hgt * groundReach[gnd.pos]
    t.facing = gnd.pos === "back" ? fb : -fb
  }

  function groundAction(p, btn) {
    if (p.actT > 0) return false
    var o = other(p), isTop = gnd.top === p.idx, where = (isTop ? "top:" : "bottom:") + gnd.pos
    switch (btn) {
    case "strike":
      if (isTop) {
        spend(p, Grapple.COST.gnp); p.actT = 0.32; p.strikeAnim = clock
        hurt(p, o, "head", 4.5 * p.st.punch * Grapple.GNP[gnd.pos] * tired(p) * cover(o), "gnp")
      } else if (gnd.pos === "guard") {
        spend(p, 2); p.actT = 0.4; p.strikeAnim = clock
        hurt(p, o, "head", 2.5 * p.st.punch * tired(p), "gnp")
      }
      return true
    case "kick":
      if (isTop) {
        spend(p, Grapple.COST.elbow); p.actT = 0.5; p.strikeAnim = clock
        hurt(p, o, "head", 6.5 * p.st.punch * p.st.elbow * Grapple.GNP[gnd.pos] * tired(p) * cover(o), "gnp")
      }
      return true
    case "grapple":
      var kind = Grapple.pickSub(defOf(p).subs, where)
      if (kind === "") { p.actT = 0.3; flash("NO LOCK FROM HERE", 0.6); return true }
      startSub(p.idx, kind, where)
      return true
    }
    return true
  }
  // Covering up on the bottom (holding down) takes the sting out of strikes.
  function cover(p) { return p.held.down ? 0.45 + p.st.guard : 1 }

  function groundMove(p, act) {
    if (p.actT > 0) return
    var o = other(p), isTop = gnd.top === p.idx
    if (isTop) {
      if (act === "up" && gnd.pos !== "back") {
        spend(p, Grapple.COST.pass); p.actT = 0.6
        if (roll(Grapple.passChance(p.r, o.r, p.stamina))) {
          gnd.pos = Grapple.nextPos(gnd.pos); gnd.idle = 0; posRev++
          layoutGround()
          flash(Grapple.POS_NAMES[gnd.pos], 0.7)
        }
      } else if (act === "down") { toStand(140); flash("BACK UP", 0.5) }
      return
    }
    if (act === "up") {
      spend(p, Grapple.COST.standup); p.actT = 0.7
      if (roll(Grapple.standupChance(p.r, o.r, p.stamina, gnd.pos))) { toStand(130); flash("BACK TO THE FEET", 0.8) }
    } else if (act === "left" || act === "right") {
      spend(p, Grapple.COST.escape); p.actT = 0.7
      if (roll(Grapple.escapeChance(p.r, o.r, p.stamina, gnd.pos))) {
        if (gnd.pos === "guard") { gnd.top = p.idx; gnd.fb = -gnd.fb; flash("SWEEP!", 0.8) }
        else { gnd.pos = Grapple.escapePos(gnd.pos); flash("ESCAPE", 0.6) }
        gnd.idle = 0; posRev++
        layoutGround()
      }
    }
  }

  // ---- submissions -------------------------------------------------------------------
  function startSub(att, kind, where, head) {
    var a = fighters[att]
    spend(a, Grapple.COST.sub)
    rs[att].subAtt++
    addScoreFor(a, 100)
    subS = { att: att, kind: kind, where: where, tap: head || 15, esc: 0, t: 0 }
    if (where === "stand") {
      var b = other(a), s = a.x <= b.x ? 1 : -1
      var c = clamp((a.x + b.x) / 2, wallL + 60, wallR - 60)
      a.x = c - s * 24; b.x = c + s * 24; a.facing = s; b.facing = -s
    }
    for (var i = 0; i < 2; i++) { var p = fighters[i]; p.state = "sub"; p.actT = 0; p.pending = null; p.mashT = 0.3 }
    pos = "sub"; posRev++
    flash(Fighters.SUB_NAMES[kind], 1.0)
  }

  // Every key the defender presses fights the hands; the attacker's grapple key
  // squeezes.
  function subPress(p, act) {
    var s = subS
    if (p.idx === s.att) {
      if (act === "grapple") { s.tap += Grapple.squeeze(p.r); spend(p, 1.2) }
      return
    }
    s.tap = Math.max(0, s.tap - Grapple.mash(p.r, p.stamina))
    s.esc += Grapple.escapeGain(p.r, p.stamina)
    spend(p, 0.4)
  }

  function updateSub(dt) {
    var s = subS, a = fighters[s.att], d = other(a)
    s.t += dt
    s.tap = Math.max(0, s.tap + Grapple.subRate(a.r, d.r, d.stamina, s.kind) * dt)
    spend(d, 8 * dt); spend(a, 5 * dt)
    if (s.tap >= 100) return finish(s.att, "SUB", Fighters.SUB_NAMES[s.kind])
    if (s.esc >= 100 || (s.t > 0.8 && s.tap <= 0) || s.t >= Grapple.SUB_MAX_TIME) escapeSub()
  }

  function escapeSub() {
    var s = subS
    flash("ESCAPED!", 0.8)
    if (s.where === "stand") { toStand(110); return }
    // Back to the ground position the lock came from; a failed lock from on top
    // costs the top fighter a step.
    for (var i = 0; i < 2; i++) { fighters[i].state = "ground"; fighters[i].actT = 0.5 }
    pos = "ground"; posRev++
    if (s.where.indexOf("top:") === 0) gnd.pos = Grapple.escapePos(gnd.pos)
    gnd.idle = 0
    layoutGround()
  }

  // ---- the end of a round and of the fight ------------------------------------------
  function clockText(secsLeft) {
    var e = Math.max(0, Math.floor(roundTime - secsLeft))
    return Math.floor(e / 60) + ":" + (e % 60 < 10 ? "0" : "") + (e % 60)
  }

  // w: winner index (-1 draw); method: KO | TKO | SUB | DEC; detail: how.
  function finish(w, method, detail) {
    if (phase !== "play") return
    // A decision is read out with both on their feet; a KO or stoppage leaves
    // the loser on the canvas; a tap-out keeps the lock on screen.
    if (method === "DEC") toStand(130)
    else if (method !== "SUB") pos = "stand"
    var totals = method === "DEC" ? Judges.decide(cards).totals : []
    result = { winner: w, method: method, detail: detail, round: round, time: clockText(timeLeft), totals: totals }
    phase = "result"; resultT = resultTime
    for (var i = 0; i < 2; i++) {
      var p = fighters[i]
      p.pending = null; p.flashT = 0          // timers stop on the card: no frozen hit flash
      if (method === "SUB") continue
      p.move = ""
      if (i === w) p.state = "victory"
      else if (w >= 0 && method !== "DEC") p.state = "ko"
      else p.state = "idle"
    }
    posRev++
    if (w === 0 && mode === "cpu") {
      if (method === "DEC") addScore(detail === "UNANIMOUS" ? 2000 : 1500)
      else addScore(3000 + 25 * Math.ceil(timeLeft) + 1000 * (maxRounds - round))
    }
    flash(method === "SUB" ? "TAP OUT!" : (method === "DEC" ? "TO THE JUDGES" : (method === "KO" ? "KNOCKOUT!" : "STOPPAGE!")), 2.0)
  }
  function addScoreFor(p, points) { if (p.idx === 0) addScore(points) }

  function endRoundOnTime() {
    timeLeft = 0
    cards = cards.concat([Judges.scoreAll(rs[0], rs[1])])
    if (round >= maxRounds) {
      var d = Judges.decide(cards)
      return finish(d.winner, "DEC", d.kind)
    }
    phase = "roundover"; roundT = roundPause
    for (var i = 0; i < 2; i++) { fighters[i].pending = null; fighters[i].flashT = 0 }
    flash("END OF ROUND " + round, roundPause)
  }

  // After the result card: the next ladder fight, a rematch, or game over.
  function afterFight() {
    var w = result.winner
    if (mode === "cpu") {
      if (w === 0) {
        if (stage >= Fighters.LADDER) { champion = true; phase = "over"; return }
        stage++
        beginFight(fighters[0].d, Fighters.ladderOpponent(fighters[0].d, stage))
        flash("FIGHT " + stage + " · " + fighters[1].name.toUpperCase(), 1.4)
      } else if (w === -1) {
        beginFight(fighters[0].d, fighters[1].d)
        flash("REMATCH", 1.4)
      } else phase = "over"
      return
    }
    if (w === 0) tallyP1++
    else if (w === 1) tallyP2++
    phase = "over"
  }

  // ---- one fighter per step --------------------------------------------------------
  function updateFighter(p, dt) {
    p.invulT = Math.max(0, p.invulT - dt)
    p.flashT = Math.max(0, p.flashT - dt)
    p.rockedT = Math.max(0, p.rockedT - dt)
    p.slipT = Math.max(0, p.slipT - dt)
    p.slipCd = Math.max(0, p.slipCd - dt)
    p.counterT = Math.max(0, p.counterT - dt)
    p.actT = Math.max(0, p.actT - dt)
    if (phase !== "play") return

    // Stamina comes back at the cardio rate, slower when tied up or with a
    // hurt body, and not at all while throwing or fighting a lock.
    var busy = p.state === "attack" || p.state === "shoot" || p.state === "sub" || p.state === "counter"
    if (!busy) {
      var place = pos === "stand" ? 1 : 0.5
      p.stamina = Math.min(100, p.stamina + p.st.regen * place * (1 - p.body / 250) * dt)
    }

    // A button pressed while busy fires as soon as the fighter is free.
    if (p.pending) {
      if (clock - p.pending.t > Input.BUFFER) p.pending = null
      else if (tryButton(p, p.pending.btn)) p.pending = null
    }

    if (pos !== "stand") return
    var o = other(p)
    switch (p.state) {
    case "hitstun": case "blockstun": case "recover": case "stuffed": case "counter":
      p.stateT -= dt
      if (p.stateT <= 0) { p.state = "idle"; p.stateT = 0 }
      break
    case "down":
      p.stateT -= dt
      if (p.stateT <= 0) { p.state = "idle"; p.invulT = 0.4; flash("UP AGAIN", 0.5) }
      break
    case "attack":
      p.moveT += dt
      var m = Grapple.MOVES[p.move]
      if (m.lunge && p.moveT < p.mv.startup + p.mv.active && Math.abs(o.x - p.x) > (p.w + o.w) / 2 + 4)
        p.x += p.facing * m.lunge * dt
      if (p.moveT >= p.mv.startup + p.mv.active + p.mv.recovery) { p.state = "idle"; p.move = ""; p.moveT = 0 }
      break
    case "shoot":
      p.moveT += dt
      if (o.held.down) o.sprawled = true
      var gap = Math.abs(o.x - p.x) - (p.w + o.w) / 2
      if (gap > 6) p.x += p.facing * Math.min(gap - 4, shootSpeed * dt)
      if (Math.abs(o.x - p.x) - (p.w + o.w) / 2 <= 8 && p.moveT >= shootTime * 0.5) resolveShoot(p, true)
      else if (p.moveT >= shootTime * p.st.tempo) resolveShoot(p, false)
      break
    case "idle":
      var wd = (p.held.right ? 1 : 0) - (p.held.left ? 1 : 0)
      var back = wd !== 0 && (wd > 0) !== (p.facing > 0)
      p.vx = wd * p.st.walk * (back ? 0.85 : 1) * (1 - p.leg / 250) * (p.rockedT > 0 ? 0.55 : 1) * (tired(p) < 1 ? 0.8 : 1)
      p.x += p.vx * dt
      break
    }
    if (p.slide !== 0) {
      p.x += p.slide * dt
      p.slide *= Math.exp(-12 * dt)
      if (Math.abs(p.slide) < 4) p.slide = 0
    }
    p.x = clamp(p.x, wallL + p.w / 2, wallR - p.w / 2)
  }

  // Fighters turn to face each other whenever they're free.
  function faceEachOther() {
    for (var i = 0; i < 2; i++) {
      var p = fighters[i], o = fighters[1 - i]
      if (p.state !== "idle" && p.state !== "blockstun" && p.state !== "hitstun") continue
      if (Math.abs(o.x - p.x) > 1) p.facing = o.x > p.x ? 1 : -1
    }
  }

  // Bodies don't overlap.
  function separate() {
    var a = fighters[0], b = fighters[1]
    var minD = (a.w + b.w) / 2
    var dx = b.x - a.x
    if (Math.abs(dx) >= minD) return
    var s = dx > 0 ? 1 : (dx < 0 ? -1 : a.facing)
    var push = (minD - Math.abs(dx)) / 2
    a.x -= s * push; b.x += s * push
    var loA = wallL + a.w / 2, hiA = wallR - a.w / 2, loB = wallL + b.w / 2, hiB = wallR - b.w / 2
    a.x = clamp(a.x, loA, hiA); b.x = clamp(b.x, loB, hiB)
    if (Math.abs(b.x - a.x) < minD - 0.01) {
      if (a.x <= loA + 0.01 || a.x >= hiA - 0.01) b.x = clamp(a.x + s * minD, loB, hiB)
      else a.x = clamp(b.x - s * minD, loA, hiA)
    }
  }

  // Strikes land. Both fighters' hits are found first and then applied, so a
  // trade hits both.
  function checkHits() {
    var found = []
    for (var i = 0; i < 2; i++) {
      var att = fighters[i], def = fighters[1 - i]
      if (att.state !== "attack" || att.hasHit) continue
      if (att.moveT < att.mv.startup || att.moveT >= att.mv.startup + att.mv.active) continue
      var facingIt = (def.x - att.x) * att.facing > 0
      if (facingIt && Math.abs(def.x - att.x) <= Grapple.MOVES[att.move].reach) found.push({ i: i, key: att.move })
    }
    for (var j = 0; j < found.length; j++) {
      fighters[found[j].i].hasHit = true
      if (phase === "play" && pos === "stand") resolveStrike(found[j].i, found[j].key)
    }
  }

  function addSpark(x, h, kind) { sparks.push({ x: x, h: h, kind: kind, life: 0 }) }

  // ---- the CPU ----------------------------------------------------------------
  function cpuContext(p) {
    var o = other(p), d = dist()
    var sit = pos === "stand" ? "stand" : pos === "clinch" ? "clinch"
            : pos === "ground" ? (gnd.top === p.idx ? "top" : "bottom")
            : (subS.att === p.idx ? "subAtt" : "subDef")
    if (sit === "stand" && p.state !== "idle" && p.state !== "blockstun") sit = "busy"
    var threat = ""
    if (o.state === "attack") {
      var m = Grapple.MOVES[o.move]
      if (o.moveT < o.mv.startup + o.mv.active && d <= m.reach + 20) threat = m.zone
    }
    var where = pos === "ground" ? (gnd.top === p.idx ? "top:" : "bottom:") + gnd.pos : "stand"
    var sp = defOf(p).special.id
    var spRange = { chain: 220, pocket: 140, pinwheel: 150, skyknee: 220, overhand: 110, vine: 110, wheel: 100 }[sp]
    return {
      level: cpuLevel, plan: p.plan, sit: sit, dist: d, threat: threat,
      oppShooting: o.state === "shoot", oppDown: o.state === "down",
      oppRecovering: o.state === "attack" && o.moveT >= o.mv.startup + o.mv.active,
      oppRocked: o.rockedT > 0, stamina: p.stamina,
      owner: pos === "clinch" && clinchS.owner === p.idx, pos: pos === "ground" ? gnd.pos : "",
      subHere: Grapple.pickSub(defOf(p).subs, where) !== "",
      special: sp, specialOk: d <= spRange && (sp !== "skyknee" || d > 90)
    }
  }

  function cpuHold(p, act, want) {
    if (p.held[act] === want) return
    if (want) press(p.idx, act, true); else release(p.idx, act, true)
  }
  function cpuTap(p, act) { cpuHold(p, act, false); press(p.idx, act, true); release(p.idx, act, true) }

  // Turn a decision into keys: the same held directions and presses a person makes.
  function cpuApply(p, d) {
    var o = other(p)
    var toward = o.x >= p.x ? "right" : "left", away = toward === "right" ? "left" : "right"
    if (pos === "stand") {
      cpuHold(p, "left", (d.dir === 1 && toward === "left") || (d.dir === -1 && away === "left"))
      cpuHold(p, "right", (d.dir === 1 && toward === "right") || (d.dir === -1 && away === "right"))
      if (d.tap === "down") cpuTap(p, "down")
      else cpuHold(p, "down", d.down)
    } else {
      cpuHold(p, "left", false); cpuHold(p, "right", false)
      cpuHold(p, "down", d.down)
      if (d.tap === "up") cpuTap(p, "up")
      else if (d.tap === "down") cpuTap(p, "down")
      else if (d.tap === "toward") cpuTap(p, p.facing > 0 ? "right" : "left")
      else if (d.tap === "away") cpuTap(p, p.facing > 0 ? "left" : "right")
    }
    if (d.button !== "") {
      // Directions that pick the strike are held for the press.
      press(p.idx, d.button, true); release(p.idx, d.button, true)
    }
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
    if (phase === "paused") return        // nothing counts down while paused
    clock += dt
    if (bannerT > 0) { bannerT -= dt; if (bannerT <= 0) banner = "" }
    for (var s = sparks.length - 1; s >= 0; s--) {
      sparks[s].life += dt
      if (sparks[s].life > 0.35) sparks.splice(s, 1)
    }
    if (phase === "result") {
      resultT -= dt
      if (resultT <= 0) afterFight()
      return
    }
    if (!fighting()) return

    if (phase === "ready") {
      readyT -= dt
      if (readyT <= 0) { readyT = 0; phase = "play" }
      return
    }
    if (phase === "roundover") {
      roundT -= dt
      if (roundT <= 0) { round++; startRound() }
      return
    }

    // play
    for (var c = 0; c < 2; c++) {
      var cp = fighters[c]
      if (!cp.cpu) continue
      cp.aiT -= dt
      if (cp.aiT <= 0) { cp.aiT = AI.thinkTime(cpuLevel); cpuThink(cp) }
      if (pos === "sub" && subS.att !== c) {
        cp.mashT -= dt
        if (cp.mashT <= 0) { cp.mashT = 1 / AI.mashRate(cpuLevel); subPress(cp, "grapple") }
      }
      if (phase !== "play") return
    }
    updateFighter(fighters[0], dt)
    if (phase !== "play") return
    updateFighter(fighters[1], dt)
    if (phase !== "play") return

    switch (pos) {
    case "stand":
      separate()
      faceEachOther()
      checkHits()
      break
    case "clinch":
      clinchS.t += dt
      rs[clinchS.owner].ctrl += 0.5 * dt
      if (clinchS.t >= clinchBreak) { toStand(120); flash("BREAK! (REFEREE)", 0.9) }
      break
    case "ground":
      gnd.t += dt; gnd.idle += dt
      rs[gnd.top].ctrl += Grapple.CTRL[gnd.pos] * dt
      if (gnd.idle >= groundStall) { toStand(130); flash("REFEREE STANDS THEM UP", 1.1) }
      break
    case "sub":
      updateSub(dt)
      break
    }
    if (phase !== "play") return
    timeLeft -= dt
    if (timeLeft <= 0) endRoundOnTime()
  }

  FrameAnimation {
    running: game.fighting() || game.phase === "result" || game.phase === "select"
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n; i++) game.step(dt / n)
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
    if (phase === "result") {
      if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || e.key === Qt.Key_F) afterFight()
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

  // ---- what each player can do right now (the HUD shows it) ---------------------
  function hintFor(i) {
    var p = fighters[i]
    if (!p || phase !== "play") return ""
    switch (pos) {
    case "clinch": return "strike dirty boxing · kick knee · grapple " + (clinchS.owner === i ? "takedown" : "pummel") + " · back: break"
    case "ground":
      if (gnd.top === i) return "up advance · strike/kick ground-and-pound · grapple lock · down stand"
      return "up stand · left/right escape · hold down cover · grapple lock"
    case "sub": return subS.att === i ? "grapple: squeeze!" : "MASH ANY KEY TO ESCAPE"
    }
    return ""
  }

  // ---- pose (what Fighter.qml draws) ---------------------------------------------
  // Angles in degrees for a fighter facing right: 0 = limb hanging down, -90 =
  // pointing forward, 90 = back, +-180 = up. Upper/lower pairs: aF/aB arms (front,
  // back), lF/lB legs. `hip` is the hip height as a share of leg length; `rot`
  // turns the whole body about the feet (-84 = lying on the back, head behind);
  // `lift` raises it.
  readonly property var basePose: ({ aFu: -60, aFl: -95, aBu: -40, aBl: -110, lFu: -16, lFl: 12, lBu: 16, lBl: 4, lean: 6, hip: 0.95, rot: 0, lift: 0 })
  function mixPose(a, b, k) {
    var o = {}
    for (var key in a) o[key] = a[key] + ((b[key] === undefined ? a[key] : b[key]) - a[key]) * k
    return o
  }
  function strikePose(key) {
    switch (key) {
    case "jab": return { aFu: -90, aFl: -2, lean: 10 }
    case "cross": case "counter": return { aBu: -92, aBl: 0, aFu: -40, aFl: -120, lean: 18 }
    case "hook": return { aFu: -95, aFl: -80, lean: 14 }
    case "overhand": return { aBu: -140, aBl: 40, lean: 30, hip: 0.9 }
    case "bodyshot": return { aFu: -70, aFl: -30, hip: 0.8, lean: 22, lFu: -40, lFl: 40 }
    case "bodykick": case "pinwheel": return { lFu: -92, lFl: -4, lean: -20, aFu: -30, aFl: -110 }
    case "headkick": return { lFu: -135, lFl: -4, lean: -30, aFu: -20, aFl: -110 }
    case "legkick": return { lFu: -58, lFl: -8, lean: -10 }
    case "knee": return { lFu: -100, lFl: 110, lean: 4, aFu: -110, aFl: -40, aBu: -110, aBl: -40 }
    case "skyknee": return { lFu: -110, lFl: 120, lBu: 30, lBl: 70, lean: 8, aFu: -150, aFl: -20, lift: 40 }
    }
    return {}
  }
  readonly property var lyingPose: ({ rot: -84, lift: 0, aFu: 150, aFl: 20, aBu: 120, aBl: 10, lFu: -30, lFl: 20, lBu: 10, lBl: 10, lean: 0, hip: 0.95 })

  function groundPose(p, q) {
    var isTop = gnd.top === p.idx, gp = gnd.pos
    var punching = drawT - p.strikeAnim < 0.18
    if (!isTop) {
      var lp = mixPose(q, lyingPose, 1)
      lp.lift = p.w * 0.42
      if (gp === "guard") return mixPose(lp, { lFu: -60, lFl: -70, lBu: -40, lBl: -80, aFu: 120, aFl: 60 }, 1)
      if (gp === "half") return mixPose(lp, { lFu: -40, lFl: -50, lBu: 0, lBl: 10 }, 1)
      if (gp === "back") return mixPose(lp, { rot: -60, lFu: -20, lFl: 30 }, 1)
      return mixPose(lp, { aFu: p.held.down ? 170 : 150, aFl: p.held.down ? 60 : 20 }, 1)
    }
    var k
    switch (gp) {
    case "guard": k = { hip: 0.52, lFu: -95, lFl: 95, lBu: -80, lBl: 90, lean: 30, aFu: -110, aFl: -20 }; break
    case "half": k = { hip: 0.5, lFu: -95, lFl: 95, lBu: -70, lBl: 90, lean: 42, aFu: -120, aFl: -20 }; break
    case "side": k = { hip: 0.42, lFu: -90, lFl: 100, lBu: -40, lBl: 90, lean: 68, aFu: -140, aFl: 10 }; break
    case "mount": k = { hip: 0.36, lFu: -100, lFl: 120, lBu: -100, lBl: 120, lean: 8, aFu: -60, aFl: -60 }; break
    default: k = { rot: -70, lift: 16, lFu: -60, lFl: 60, lBu: -30, lBl: 40, aFu: -80, aFl: -60, lean: 0 }
    }
    var r = mixPose(q, k, 1)
    if (punching) r = mixPose(r, { aFu: -150, aFl: -10 }, 1)
    return r
  }

  function subPose(p, q) {
    var s = subS, att = s.att === p.idx
    if (s.where === "stand") {
      if (att) return mixPose(q, { aFu: -60, aFl: -120, aBu: -80, aBl: -100, lean: -10, hip: 0.9 }, 1)
      return mixPose(q, { lean: 75, hip: 0.8, aFu: 20, aFl: -30, aBu: 40, aBl: -20 }, 1)
    }
    var g = groundPose(p, q)
    var fromTop = s.where.indexOf("top:") === 0
    if (att && !fromTop) return mixPose(g, { lFu: -160, lFl: -40, lBu: -140, lBl: -60, aFu: 170, aFl: -40 }, 1)
    if (att && fromTop) return mixPose(g, { lean: s.kind === "rnc" ? 0 : -25, aFu: -150, aFl: -120, aBu: -130, aBl: -110 }, 1)
    // defending: fight the hands
    var shake = 8 * Math.sin(drawT * 30)
    return mixPose(g, { aFu: g.aFu + shake, aBu: g.aBu - shake }, 1)
  }

  function poseOf(i) {
    var p = fighters[i]
    if (!p) return { x: -400, facing: 1, aFu: 0, aFl: 0, aBu: 0, aBl: 0, lFu: 0, lFl: 0, lBu: 0, lBl: 0, lean: 0, hip: 1, rot: 0, lift: 0, flash: false, rocked: false, t: 0, state: "", tired: false }
    var t = drawT + i * 0.7
    var q = mixPose(basePose, {}, 0)
    q.hip = 0.95 + 0.015 * Math.sin(t * 5)
    q.lean = 6 + 2 * Math.sin(t * 5)
    var bounce = 0
    switch (p.state) {
    case "idle":
      if (Math.abs(p.vx) > 1) {
        var ph = Math.sin(drawT * 11 * (p.vx * p.facing > 0 ? 1 : -1))
        q.lFu = -16 + 22 * ph; q.lBu = 16 - 22 * ph
        q.lFl = 12 + 16 * Math.max(0, -ph); q.lBl = 4 + 16 * Math.max(0, ph)
      }
      if (backHeld(p)) q = mixPose(q, { aFu: -120, aFl: -150, aBu: -110, aBl: -150, lean: -2 }, 1)
      if (p.slipT > 0) q = mixPose(q, { hip: 0.78, lean: 30, lFu: -40, lFl: 50 }, 1)
      else if (p.held.down) q = mixPose(q, { hip: 0.8, lean: 18, lFu: -36, lFl: 44, lBu: 30, lBl: 30 }, 1)
      break
    case "blockstun":
      q = mixPose(q, { aFu: -120, aFl: -150, aBu: -110, aBl: -150, lean: -8 }, 1)
      break
    case "hitstun":
      q = mixPose(q, { lean: -22, aFu: 20, aFl: -40, aBu: 40, aBl: -30, hip: 0.93 }, 1)
      break
    case "recover": case "stuffed":
      q = mixPose(q, { lean: 70, hip: 0.6, aFu: -60, aFl: 0, lFu: -60, lFl: 90, lBu: 50, lBl: 40 }, 1)
      break
    case "counter":
      q = mixPose(q, { hip: 0.86, lean: -12, aFu: -100, aFl: -150, aBu: -60, aBl: -130 }, 1)
      break
    case "shoot":
      q = mixPose(q, { hip: 0.5, lean: 78, aFu: -80, aFl: 0, aBu: -70, aBl: 0, lFu: -80, lFl: 100, lBu: 60, lBl: 20 }, 1)
      break
    case "down": case "ko":
      q = mixPose(q, lyingPose, 1)
      q.lift = p.w * 0.42
      break
    case "victory":
      q = mixPose(q, { aFu: -176, aFl: -8, aBu: -176, aBl: -8, lean: -4 }, 1)
      bounce = 4 * Math.abs(Math.sin(drawT * 6))
      break
    case "clinch":
      q = mixPose(q, { aFu: -125, aFl: -70, aBu: -110, aBl: -80, lean: 22, hip: 0.92 }, 1)
      if (drawT - p.strikeAnim < 0.2) q = mixPose(q, { lFu: -95, lFl: 100 }, 0.8)
      break
    case "ground":
      q = groundPose(p, q)
      break
    case "sub":
      q = subPose(p, q)
      break
    case "attack":
      var m = p.mv
      var hit = mixPose(q, strikePose(p.move), 1)
      if (p.moveT < m.startup) q = mixPose(q, hit, 0.35 * p.moveT / Math.max(0.001, m.startup))
      else if (p.moveT < m.startup + m.active) q = hit
      else q = mixPose(hit, q, (p.moveT - m.startup - m.active) / Math.max(0.001, m.recovery))
      break
    }
    // A tapped-out fighter on the result card keeps the struggle pose.
    q.x = p.x; q.facing = p.facing
    q.lift = (q.lift || 0) + bounce
    q.flash = p.flashT > 0; q.rocked = p.rockedT > 0 && p.state !== "down" && p.state !== "ko"
    q.t = drawT; q.state = p.state
    q.tired = p.stamina < 30
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

    Stage { id: stageView; anchors.fill: parent; game: engine }

    // Fighters (drawn during a fight; the select screen shows stat cards)
    Repeater {
      id: fighterView
      model: game.fighters.length
      delegate: Fighter {
        required property int index
        game: engine
        slot: index
        visible: engine.phase !== "select"
      }
    }

    // Hit, block and slip sparks: an expanding ring.
    Repeater {
      model: game.sparks.length
      delegate: Rectangle {
        required property int index
        readonly property real life: game.sparkAt(index).life
        readonly property real r: 6 + life * 110
        x: game.sparkAt(index).x - r
        y: game.groundY - game.sparkAt(index).h - r
        width: r * 2; height: r * 2; radius: r
        color: "transparent"
        border.width: 3
        border.color: game.sparkAt(index).kind === "block" ? game.color("blue", "#7aa2f7")
                    : game.sparkAt(index).kind === "slip" ? game.color("cyan", "#7dcfff")
                    : game.color("yellow", "#e0af68")
        opacity: Math.max(0, 1 - life / 0.35)
      }
    }

    Hud { id: hudView; anchors.fill: parent; game: engine }
  }
}
