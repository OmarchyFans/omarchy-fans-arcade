import QtQuick
import Quickshell
import Quickshell.Io
import "fighters.js" as Fighters
import "grapple.js" as Grapple
import "judges.js" as Judges
import "ai.js" as AI
import "input.js" as Input

// Headless rules test for Super MMA Fighter. tests/run.sh stages games/mma/ and
// this file in one folder and runs it offscreen; the JSON result goes to
// $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  // Roster indices (fighters.js)
  readonly property int brannoch: 0
  readonly property int castellane: 1
  readonly property int dole: 2
  readonly property int marrask: 3
  readonly property int korrow: 4
  readonly property int quenby: 5
  readonly property int tidewell: 6

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }
  function near(a, b, eps) { return Math.abs(a - b) <= (eps === undefined ? 0.01 : eps) }

  // Run the game for `seconds` in 1/240 s steps while a fight is on, or until
  // `until()` holds.
  function run(g, seconds, until) {
    var steps = Math.ceil(seconds * 240)
    for (var i = 0; i < steps; i++) {
      if (!g.fighting()) return
      g.step(1 / 240)
      if (until && until()) return
    }
  }
  function f(g, i) { return g.fighters[i] }
  function def(i) { return Fighters.at(i) }
  function st(i) { return Fighters.stats(Fighters.at(i)) }
  function tap(g, pi, act) { g.press(pi, act, false); g.release(pi, act, false) }

  // A versus fight between two people (no CPU), past the round call, with the
  // fighters placed at x0 and x1.
  function fight(g, p1, p2, x0, x1) {
    g.seed = 7
    g.newGame()
    g.startMatch("versus", p1, p2, 1)
    run(g, 2, function () { return g.phase === "play" })
    place(g, x0 === undefined ? 300 : x0, x1 === undefined ? 380 : x1)
  }
  function place(g, x0, x1) {
    f(g, 0).x = x0; f(g, 1).x = x1
    f(g, 0).facing = x1 > x0 ? 1 : -1; f(g, 1).facing = -f(g, 0).facing
  }
  // A 1-player ladder fight, stopped the moment it goes live (before the CPU acts).
  function ladder(g, p1) {
    g.seed = 7
    g.newGame()
    g.startMatch("cpu", p1, -1, 1)
    run(g, 2, function () { return g.phase === "play" })
  }
  function ctx(plan, extra) {
    return Object.assign({ level: 3, plan: plan, sit: "stand", dist: 150, threat: "", oppShooting: false,
      oppDown: false, oppRecovering: false, oppRocked: false, stamina: 100, owner: false, pos: "",
      subHere: false, special: "chain", specialOk: false }, extra || {})
  }
  // The test's own seeded PRNG (mulberry32), for AI tallies.
  function prng(seed) {
    var s = seed >>> 0
    return function () {
      s = (s + 0x6D2B79F5) >>> 0
      var t = s
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }
  // A drawn item under `item` by objectName (HUD bars).
  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (var i = 0; i < item.children.length; i++) { var r = find(item.children[i], name); if (r) return r }
    return null
  }
  function tally(plan, extra, why, n) {
    var r = prng(99), c = 0
    for (var i = 0; i < n; i++) if (AI.decide(ctx(plan, extra), r).why === why) c++
    return c
  }

  FloatingWindow {
    implicitWidth: 800; implicitHeight: 540
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
    var a, b, h, x, t, r, before

    // ---- select screen and the start of a fight --------------------------------------
    g.seed = 7
    g.newGame()
    check("a new game opens the select screen", g.phase === "select", g.phase)
    g.pause()
    check("pause does nothing on the select screen", g.phase === "select", g.phase)
    g.selRow = 0; g.selMode = "cpu"; g.selChange(1)
    check("the mode row switches to 2 players, which adds a P2 row",
          g.selMode === "versus" && g.selRows().indexOf("p2") >= 0, g.selMode + " " + g.selRows())
    g.selMode = "cpu"
    g.startMatch("cpu", brannoch, -1, 1)
    check("a ladder starts at fight 1 against the first ladder opponent, a CPU at level 3",
          g.phase === "ready" && f(g, 1).cpu && !f(g, 0).cpu && f(g, 1).d === Fighters.ladderOpponent(brannoch, 1) && g.cpuLevel === 3,
          g.phase + " d=" + f(g, 1).d + " lv=" + g.cpuLevel)
    run(g, 2, function () { return g.phase === "play" })
    check("the round call gives way to play with a full 60 s clock", g.phase === "play" && g.timeLeft > 59.9, g.phase + " " + g.timeLeft)
    g.press(1, "right", false)
    check("player-2 keys do nothing while the CPU plays player 2", !f(g, 1).held.right)

    // ---- ratings drive the numbers -----------------------------------------------------
    check("speed rating sets walk speed (Korrow 7.3 walks faster than Brannoch 5.5)",
          st(korrow).walk > st(brannoch).walk && near(st(korrow).walk, 110 + 14 * 7.3), st(korrow).walk)
    fight(g, korrow, brannoch, 200, 600)
    x = f(g, 0).x
    g.press(0, "right", false)
    run(g, 0.5)
    g.release(0, "right", false)
    check("walking forward covers the fighter's own walk speed", near(f(g, 0).x - x, st(korrow).walk * 0.5, 2), (f(g, 0).x - x) + " vs " + st(korrow).walk * 0.5)

    fight(g, korrow, brannoch)
    check("a clean jab lands", g.resolveStrike(0, "jab") === "hit")
    a = f(g, 1).head
    fight(g, brannoch, korrow)
    g.resolveStrike(0, "jab")
    b = f(g, 1).head
    check("power rating sets punch damage (Korrow's jab 3.2 x punch, harder than Brannoch's)",
          near(a, 3.2 * st(korrow).punch) && near(b, 3.2 * st(brannoch).punch) && a > b, a + " / " + b)
    check("cardio sets stamina: Brannoch (9.5) pays less and recovers faster than Korrow (5.3)",
          st(brannoch).cost < st(korrow).cost && st(brannoch).regen > st(korrow).regen)
    fight(g, brannoch, korrow)
    g.startMove(f(g, 0), "headkick"); g.startMove(f(g, 1), "headkick")
    check("... and the engine charges it: the same kick costs Korrow more gas",
          100 - f(g, 1).stamina > 100 - f(g, 0).stamina + 2, f(g, 0).stamina + " / " + f(g, 1).stamina)
    check("wrestling decides takedowns: the grinder takes the kickboxer down far more often than the reverse",
          Grapple.takedownChance(def(brannoch).ratings, def(marrask).ratings, 100, 100, false, 0)
            > Grapple.takedownChance(def(marrask).ratings, def(brannoch).ratings, 100, 100, false, 0) + 0.5)
    check("a sprawl takes a lot off a shot",
          Grapple.takedownChance(def(brannoch).ratings, def(dole).ratings, 100, 100, true, 0)
            < Grapple.takedownChance(def(brannoch).ratings, def(dole).ratings, 100, 100, false, 0) - 0.3)
    check("grappling decides locks: Quenby's tap rate on Marrask far outruns the reverse",
          Grapple.subRate(def(quenby).ratings, def(marrask).ratings, 100, "triangle")
            > Grapple.subRate(def(marrask).ratings, def(quenby).ratings, 100, "triangle") + 40)
    check("the finish split shapes the CPU plan: the grinder shoots, the kickboxer never does and keeps long range",
          Fighters.plan(def(brannoch)).shoot > 0.5 && Fighters.plan(def(marrask)).shoot === 0 && Fighters.plan(def(marrask)).range === 125)

    // ---- stand-up: block, slip, counter, trades, walls --------------------------------
    fight(g, brannoch, castellane)
    f(g, 1).held.right = true                 // fighter 2 faces left: right is back
    r = g.resolveStrike(0, "cross")
    check("holding back blocks, letting only the defense share through",
          r === "block" && near(f(g, 1).head, 7 * st(brannoch).punch * st(castellane).guard), r + " " + f(g, 1).head)
    fight(g, brannoch, castellane)
    f(g, 1).held.right = true
    r = g.resolveStrike(0, "legkick")
    check("a leg kick can't be blocked", r === "hit" && f(g, 1).leg > 0, r)

    fight(g, brannoch, dole)
    tap(g, 1, "down")
    r = g.resolveStrike(0, "cross")
    check("a tapped slip makes a head strike miss and opens a counter", r === "slip" && f(g, 1).head === 0 && f(g, 1).counterT > 0, r)
    g.resolveStrike(1, "jab")
    check("the counter lands x1.35", near(f(g, 0).head, 3.2 * st(dole).punch * 1.35), f(g, 0).head)
    fight(g, brannoch, castellane)
    tap(g, 1, "down")
    g.resolveStrike(0, "cross")
    g.resolveStrike(1, "jab")
    check("the power counter (Castellane) lands x1.6", near(f(g, 0).head, 3.2 * st(castellane).punch * 1.6), f(g, 0).head)
    run(g, Input.SLIP_TIME + 0.02)
    tap(g, 1, "down")
    check("a slip can't be repeated inside its cooldown", f(g, 1).slipT === 0 && f(g, 1).slipCd > 0, f(g, 1).slipT)

    fight(g, brannoch, castellane, 300, 380)
    g.startMove(f(g, 0), "jab"); g.startMove(f(g, 1), "jab")
    f(g, 0).moveT = f(g, 0).mv.startup; f(g, 1).moveT = f(g, 1).mv.startup
    g.checkHits()
    check("a trade hits both fighters", f(g, 0).head > 0 && f(g, 1).head > 0, f(g, 0).head + " / " + f(g, 1).head)

    fight(g, brannoch, castellane, 0, 380)
    g.step(1 / 240)
    check("the cage wall stops a fighter", f(g, 0).x >= g.wallL + f(g, 0).w / 2 - 0.001, f(g, 0).x)

    // ---- knockdowns and finishes ------------------------------------------------------
    fight(g, brannoch, castellane)
    g.hurt(f(g, 0), f(g, 1), "head", 16, "strike")
    check("a huge standing head shot is a knockdown", f(g, 1).state === "down" && f(g, 1).kd === 1 && g.rs[0].kd === 1, f(g, 1).state)
    g.hurt(f(g, 0), f(g, 1), "head", 16, "strike")
    g.hurt(f(g, 0), f(g, 1), "head", 16, "strike")
    check("three knockdowns in a round is a TKO", g.phase === "result" && g.result.method === "TKO" && g.result.detail === "THREE KNOCKDOWNS" && g.result.winner === 0,
          g.result.method + " " + g.result.detail)

    fight(g, brannoch, castellane)
    f(g, 1).head = 95
    g.hurt(f(g, 0), f(g, 1), "head", 8, "strike")
    check("head damage 100 from a standing strike is a KO", g.result.method === "KO" && g.result.winner === 0 && f(g, 1).state === "ko", g.result.method)
    g.publish()
    check("the finishing blow's hit flash doesn't freeze on the result card",
          f(g, 1).flashT === 0 && g.fighterView.itemAt(1).pose.flash === false, f(g, 1).flashT)
    fight(g, brannoch, castellane)
    f(g, 1).body = 95
    g.hurt(f(g, 0), f(g, 1), "body", 8, "strike")
    check("body damage 100 is a TKO", g.result.method === "TKO" && g.result.detail === "BODY SHOTS", g.result.detail)
    fight(g, brannoch, castellane)
    g.startGround(0, "mount")
    f(g, 0).actT = 0; f(g, 1).head = 98
    g.groundAction(f(g, 0), "strike")
    check("head damage 100 from ground-and-pound is a TKO", g.result.method === "TKO" && g.result.detail === "GROUND AND POUND", g.result.method + " " + g.result.detail)

    // ---- the seven specials --------------------------------------------------------------
    fight(g, brannoch, brannoch, 300, 500)
    f(g, 0).stamina = 0; f(g, 1).held.down = true
    g.doSpecial(f(g, 0))
    check("Chain Shot shoots with one re-shot in hand", f(g, 0).state === "shoot" && f(g, 0).chainLeft === 1, f(g, 0).state)
    check("a gassed shooter into a sprawl is at the 5% floor",
          near(Grapple.takedownChance(f(g, 0).r, f(g, 1).r, 0, 100, true, 0.05), 0.05, 1e-9))
    g.rngState = 12345                          // next rolls: 0.98, 0.31 (both miss a 5% chance)
    g.resolveShoot(f(g, 0), true)
    check("Chain Shot: sprawled, it re-shoots once", f(g, 0).state === "shoot" && f(g, 0).chainLeft === 0 && g.pos === "stand", f(g, 0).state + " " + g.pos)
    g.resolveShoot(f(g, 0), true)
    check("... and the second sprawl stuffs it", f(g, 0).state === "stuffed" && g.pos === "stand", f(g, 0).state)

    fight(g, castellane, brannoch)
    g.doSpecial(f(g, 0))
    check("Pocket Trap sets a counter stance", f(g, 0).state === "counter")
    r = g.resolveStrike(1, "jab")
    check("Pocket Trap: their strike is slipped and a counter left comes back",
          r === "countered" && f(g, 0).head === 0 && near(f(g, 1).head, Grapple.MOVES.counter.dmg * st(castellane).punch), r + " " + f(g, 1).head)

    fight(g, castellane, brannoch)
    f(g, 1).head = 95
    g.doSpecial(f(g, 0))
    g.resolveStrike(1, "cross")
    check("a KO from Pocket Trap is called a COUNTER LEFT", g.result.method === "KO" && g.result.detail === "COUNTER LEFT" && g.result.winner === 0,
          g.result.method + " " + g.result.detail)

    fight(g, dole, brannoch)
    g.doSpecial(f(g, 0))
    check("Pinwheel Kick is the longest reach", f(g, 0).move === "pinwheel" && Grapple.MOVES.pinwheel.reach > Grapple.MOVES.headkick.reach, f(g, 0).move)

    fight(g, marrask, brannoch, 200, 420)
    g.doSpecial(f(g, 0))
    run(g, 0.25)
    check("Skyward Knee lunges in", f(g, 0).move === "skyknee" && f(g, 0).x - 200 > 60, f(g, 0).x)

    fight(g, korrow, brannoch)
    g.doSpecial(f(g, 0))
    check("Freight Overhand is a slow big right", f(g, 0).move === "overhand" && f(g, 0).mv.startup > Grapple.MOVES.cross.startup)
    fight(g, korrow, brannoch)
    g.resolveStrike(0, "overhand")
    check("a clean Freight Overhand drops them", f(g, 1).state === "down", f(g, 1).state)

    fight(g, quenby, marrask)
    g.doSpecial(f(g, 0))
    check("Vine Pull: guard pull straight into her triangle",
          g.pos === "sub" && g.gnd.top === 1 && g.subS.att === 0 && g.subS.kind === "triangle" && g.subS.tap === 30,
          g.pos + " top=" + g.gnd.top + " " + g.subS.kind)

    fight(g, tidewell, marrask)
    g.doSpecial(f(g, 0))
    check("Harbor Wheel: a hip throw into side control", g.pos === "ground" && g.gnd.pos === "side" && g.gnd.top === 0 && g.rs[0].td === 1,
          g.pos + " " + g.gnd.pos)

    // ---- takedowns, clinch and ground ----------------------------------------------------
    fight(g, brannoch, marrask, 300, 450)
    g.startShoot(f(g, 0), 0, 0)
    g.resolveShoot(f(g, 0), true)
    check("a landed shot takes it to the ground (a 9+ wrestler lands in half guard)",
          g.pos === "ground" && g.gnd.top === 0 && g.gnd.pos === "half" && g.rs[0].td === 1, g.pos + " " + g.gnd.pos)

    fight(g, brannoch, castellane)
    g.enterClinch(0)
    t = g.clock
    run(g, 13, function () { return g.pos === "stand" })
    check("the referee breaks a clinch at 12 s", g.pos === "stand" && g.clock - t >= g.clinchBreak - 0.01, (g.clock - t))
    check("clinch control counts for the one inside", near(g.rs[0].ctrl, 6, 0.1) && g.rs[1].ctrl === 0, g.rs[0].ctrl)

    fight(g, brannoch, castellane)
    g.startGround(0, "mount")
    run(g, 2)
    check("control time on the ground is weighted by position (mount 1.3/s)", near(g.rs[0].ctrl, 2.6, 0.05), g.rs[0].ctrl)
    t = g.clock
    run(g, 8, function () { return g.pos === "stand" })
    check("the referee stands up a stalled ground fight", g.pos === "stand" && g.clock - t >= g.groundStall - 2 - 0.01, g.clock - t)
    check("positions advance guard -> half and stop at back; escapes go back to guard",
          Grapple.nextPos("guard") === "half" && Grapple.nextPos("back") === "back" && Grapple.escapePos("mount") === "guard")
    check("a lock only works from where it can",
          Grapple.pickSub(["armbar"], "top:guard") === "" && Grapple.pickSub(def(quenby).subs, "bottom:guard") === "triangle")

    // ---- submissions ------------------------------------------------------------------------
    fight(g, brannoch, marrask)
    g.startGround(0, "back")
    g.startSub(0, "rnc", "top:back", 95)
    run(g, 1)
    check("a full tap meter is a SUB", g.phase === "result" && g.result.method === "SUB" && g.result.detail === "REAR-NAKED CHOKE" && g.result.winner === 0,
          g.result.method + " " + g.result.detail)

    fight(g, quenby, marrask)
    g.startGround(1, "guard")
    g.startSub(0, "triangle", "bottom:guard", 20)
    g.press(0, "grapple", false)
    check("the attacker's grapple squeezes", near(g.subS.tap, 20 + Grapple.squeeze(def(quenby).ratings)), g.subS.tap)

    fight(g, brannoch, quenby)
    g.startGround(0, "back")
    g.startSub(0, "rnc", "top:back", 15)
    for (h = 0; h < 21; h++) tap(g, 1, h % 2 ? "strike" : "left")
    check("mashing fills the escape meter", g.subS.esc >= 100, g.subS.esc)
    g.step(1 / 240)
    check("a full escape meter escapes, and a failed lock from on top costs a step",
          g.pos === "ground" && g.phase === "play" && g.gnd.pos === "guard" && g.gnd.top === 0, g.pos + " " + g.gnd.pos)

    // ---- rounds, judges and the decision ----------------------------------------------------
    check("judges: a close round is 10-10, a clear one 10-9, a rout 10-8",
          String(Judges.scoreRound(Judges.JUDGES[0], { dmg: 1, td: 0, ctrl: 0, kd: 0, subAtt: 0 }, g.blankStats())) === "10,10"
          && String(Judges.scoreRound(Judges.JUDGES[0], { dmg: 10, td: 0, ctrl: 0, kd: 0, subAtt: 0 }, g.blankStats())) === "10,9"
          && String(Judges.scoreRound(Judges.JUDGES[0], g.blankStats(), { dmg: 50, td: 0, ctrl: 0, kd: 0, subAtt: 0 })) === "8,10")
    // One round of a striker's edge (damage) against a grappler's edge (takedowns):
    // judge A (strikes) and judge B (grappling) disagree.
    a = { dmg: 20, td: 0, ctrl: 0, kd: 0, subAtt: 0 }; b = { dmg: 6, td: 2, ctrl: 10, kd: 0, subAtt: 0 }
    r = Judges.scoreAll(a, b)
    check("the judges weigh the same round differently", r[0][0] > r[0][1] && r[1][1] > r[1][0], JSON.stringify(r))
    check("decisions: split, majority and split draw",
          Judges.decide([[[10, 9], [9, 10], [10, 9]]]).kind === "SPLIT" && Judges.decide([[[10, 9], [9, 10], [10, 9]]]).winner === 0
          && Judges.decide([[[10, 9], [10, 10], [10, 9]]]).kind === "MAJORITY"
          && Judges.decide([[[10, 9], [9, 10], [10, 10]]]).kind === "SPLIT DRAW" && Judges.decide([[[10, 9], [9, 10], [10, 10]]]).winner === -1)

    fight(g, brannoch, castellane)
    f(g, 0).stamina = 20; f(g, 0).head = 50
    g.rs[0].dmg = 20
    g.endRoundOnTime()
    check("the clock running out ends the round", g.phase === "roundover" && g.cards.length === 1, g.phase)
    run(g, 5, function () { return g.phase === "play" })
    check("between rounds: 70% of the lost stamina and 20% of head damage come back",
          g.round === 2 && near(f(g, 0).stamina, 76, 0.5) && near(f(g, 0).head, 40, 0.01), g.round + " " + f(g, 0).stamina + " " + f(g, 0).head)
    g.rs[0].dmg = 20; g.endRoundOnTime()
    run(g, 5, function () { return g.phase === "play" })
    g.rs[0].dmg = 20; g.endRoundOnTime()
    check("three rounds go to a unanimous decision", g.phase === "result" && g.result.method === "DEC" && g.result.detail === "UNANIMOUS" && g.result.winner === 0,
          g.result.method + " " + g.result.detail)
    check("the card shows each judge's total", g.result.totals.length === 3 && String(g.result.totals[0]) === "30,27", JSON.stringify(g.result.totals))

    // ---- scoring, the ladder and the high score ----------------------------------------------
    fight(g, brannoch, castellane)
    g.hurt(f(g, 0), f(g, 1), "head", 10, "strike")
    check("2 players: nothing scores", g.score === 0, g.score)

    ladder(g, brannoch)
    g.highScore = 1000
    g.hurt(f(g, 0), f(g, 1), "head", 10, "strike")
    check("1 player: 10 per point of damage times the CPU level factor (1.5 at level 3)", g.score === 150, g.score)
    g.highScore = g.score + 150
    g.addScore(100)
    check("tying the high score is not a new high", !g.beatHigh && g.highScore === g.score, g.beatHigh + " " + g.highScore)
    g.addScore(1)
    check("going past it is", g.beatHigh && g.highScore === g.score, g.beatHigh)
    before = g.score
    g.finish(0, "KO", "PUNCHES")
    check("a finish adds the win bonus (with time and round bonus)",
          g.score - before === Math.round((3000 + 25 * Math.ceil(g.timeLeft) + 1000 * 2) * 1.5), g.score - before)
    g.afterFight()
    check("a win moves up the ladder: next opponent, CPU a level sharper",
          g.stage === 2 && g.phase === "ready" && f(g, 1).d === Fighters.ladderOpponent(brannoch, 2) && g.cpuLevel === 4 && f(g, 1).head === 0,
          g.stage + " " + g.phase + " " + g.cpuLevel)
    run(g, 2, function () { return g.phase === "play" })
    g.finish(1, "SUB", "ARMBAR")
    g.afterFight()
    check("a loss is game over", g.phase === "over", g.phase)
    g.newGame()
    check("a new game resets score, ladder and high-score flag", g.phase === "select" && g.score === 0 && g.stage === 1 && !g.beatHigh && g.pos === "stand",
          g.score + " " + g.stage)

    // ---- pause and focus -------------------------------------------------------------------
    fight(g, brannoch, castellane)
    g.press(0, "right", false)
    g.togglePause()
    x = f(g, 0).x; t = g.timeLeft
    for (h = 0; h < 60; h++) g.step(1 / 60)
    check("pause freezes the fight and the clock", g.phase === "paused" && f(g, 0).x === x && g.timeLeft === t, g.phase)
    g.togglePause()
    check("P again resumes", g.phase === "play", g.phase)
    g.lostFocus()
    check("losing focus pauses and forgets held keys", g.phase === "paused" && !f(g, 0).held.right, g.phase)
    fight(g, brannoch, castellane)
    g.finish(0, "KO", "PUNCHES")
    t = g.resultT
    g.lostFocus()
    for (h = 0; h < 600; h++) g.step(1 / 60)
    check("losing focus on the result card pauses its countdown (no fight starts unattended)",
          g.phase === "paused" && g.pausedFrom === "result" && g.resultT === t, g.phase + " " + g.resultT)
    g.resume()
    check("... and resuming returns to the card", g.phase === "result", g.phase)

    // ---- the CPU -------------------------------------------------------------------------------
    check("CPU: it sprawls on a shot", AI.decide(ctx(Fighters.plan(def(brannoch)), { oppShooting: true }), function () { return 0 }).why === "sprawl")
    check("CPU: a counter-puncher slips a head strike",
          AI.decide(ctx(Fighters.plan(def(castellane)), { threat: "head" }), function () { return 0 }).why === "slip")
    a = tally(Fighters.plan(def(brannoch)), {}, "shoot", 400)
    b = tally(Fighters.plan(def(marrask)), {}, "shoot", 400)
    check("CPU: the grinder's plan shoots, the kickboxer's never does", a > 60 && b === 0, a + " / " + b)
    a = tally(Fighters.plan(def(quenby)), { sit: "bottom", pos: "guard", subHere: true }, "attack from bottom", 400)
    b = tally(Fighters.plan(def(marrask)), { sit: "bottom", pos: "guard", subHere: true }, "attack from bottom", 400)
    check("CPU: the submission artist attacks off her back far more than the kickboxer", a > 3 * b && a > 100, a + " / " + b)
    ladder(g, brannoch)
    run(g, 4)
    a = g.decisionLog.join(",")
    ladder(g, brannoch)
    run(g, 4)
    check("CPU: it decides, and the same seed plays the same fight", a.length > 0 && g.decisionLog.join(",") === a, a.slice(0, 60))

    // ---- drawing ---------------------------------------------------------------------------------
    fight(g, brannoch, castellane, 250, 520)
    g.publish()
    check("render: each drawn fighter stands where the model says",
          near(g.fighterView.itemAt(0).x, 250) && near(g.fighterView.itemAt(1).x, 520), g.fighterView.itemAt(0).x + " " + g.fighterView.itemAt(1).x)
    f(g, 0).x = 330; f(g, 1).x = 470
    g.publish()
    check("render: ... and moves when the model moves",
          near(g.fighterView.itemAt(0).x, 330) && near(g.fighterView.itemAt(1).x, 470), g.fighterView.itemAt(0).x + " " + g.fighterView.itemAt(1).x)
    x = find(g.hudView, "dmg-1-head")
    check("render: the HUD head bar starts empty", x !== null && x.width === 0, x ? x.width : "no bar")
    f(g, 1).head = 50
    g.publish()
    check("render: ... and fills with the model's head damage after publish", x !== null && near(x.width, 0.5 * x.parent.width, 0.5),
          x ? x.width + " / " + x.parent.width : "no bar")
    g.enterClinch(0)
    g.publish()
    a = g.fighterView.itemAt(0).pose.lFu
    f(g, 0).strikeAnim = g.clock
    g.clock += 1 / 240                          // a substep, no publish
    check("render: the drawing does not change between publishes", g.fighterView.itemAt(0).pose.lFu === a, a + " -> " + g.fighterView.itemAt(0).pose.lFu)
    g.publish()
    check("render: ... and shows the clinch knee after one", g.fighterView.itemAt(0).pose.lFu < a - 20, a + " -> " + g.fighterView.itemAt(0).pose.lFu)
    g.startGround(0, "mount")
    g.publish()
    check("render: the drawn pose follows the fight to the ground",
          g.fighterView.itemAt(1).pose.state === "ground" && g.fighterView.itemAt(1).pose.rot < -40 && near(g.fighterView.itemAt(1).x, f(g, 1).x),
          g.fighterView.itemAt(1).pose.state)
  }
}
