import QtQuick
import Quickshell
import Quickshell.Io
import "fighters.js" as Fighters
import "input.js" as Input
import "ai.js" as AI

// Headless rules test for Emberbout. tests/run.sh stages games/emberbout/ and
// this file in one folder and runs it offscreen; the JSON result goes to
// $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  readonly property int marrow: 0
  readonly property int kestrel: 1
  readonly property int sable: 2

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }

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
  function tap(g, pi, act) { g.press(pi, act, false); g.step(1 / 240); g.release(pi, act, false); g.step(1 / 240) }

  // A versus fight between two people (no CPU), skipped past the round call,
  // with the fighters placed at x0 and x1.
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
  function hp(g, i) { return f(g, i).hp }
  function lost(g, i) { return f(g, i).maxHp - f(g, i).hp }

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
    var i, m, before, p, q

    // ---- character select ---------------------------------------------------------
    g.seed = 7
    g.newGame()
    check("a new game opens the select screen", g.phase === "select", g.phase)
    g.pause()
    check("pause does nothing on the select screen", g.phase === "select", g.phase)
    g.selMode = "cpu"; g.selP1 = 0; g.selRow = 2
    g.selChange(1)
    check("right on the P1 row picks the next fighter", g.selP1 === 1 && f(g, 0).d === 1, g.selP1)
    g.selChange(-1); g.selChange(-1)
    check("the fighter choice wraps around", g.selP1 === Fighters.count() - 1, g.selP1)
    check("the fighters differ: health and walk speed",
          Fighters.at(marrow).hp > Fighters.at(sable).hp && Fighters.at(sable).hp > Fighters.at(kestrel).hp
          && Fighters.at(kestrel).walk > Fighters.at(marrow).walk)
    check("vs CPU the preview shows the first ladder opponent", f(g, 1).d === Fighters.ladderOpponent(g.selP1, 1), f(g, 1).d)
    g.selRow = 0; g.selChange(1)
    check("the mode row switches to 2 players, with a P2 row", g.selMode === "versus" && g.selRows().indexOf("p2") >= 0, g.selRows())
    g.selP2 = sable; g.setPreview()
    g.selConfirm()
    check("confirming starts the match on the round call",
          g.phase === "ready" && f(g, 0).d === g.selP1 && f(g, 1).d === sable && !f(g, 1).cpu, g.phase)
    g.press(0, "light", false)
    check("nobody can attack during the round call", f(g, 0).state === "idle", f(g, 0).state)
    g.release(0, "light", false)
    run(g, 2, function () { return g.phase === "play" })
    check("the round call gives way to the fight", g.phase === "play" && Math.abs(g.timeLeft - g.roundTime) < 0.05, g.phase)

    // ---- movement -------------------------------------------------------------------
    fight(g, sable, sable, 200, 600)
    g.press(0, "right", false)
    run(g, 0.5)
    g.release(0, "right", false)
    check("walking forward moves at the fighter's walk speed", Math.abs(f(g, 0).x - (200 + Fighters.at(sable).walk * 0.5)) < 2, f(g, 0).x)
    g.press(0, "left", false)
    run(g, 4)
    g.release(0, "left", false)
    check("the wall stops a fighter", Math.abs(f(g, 0).x - (g.wallL + f(g, 0).w / 2)) < 0.01, f(g, 0).x)

    fight(g, marrow, kestrel, 300, 420)
    g.press(0, "right", false)
    run(g, 1.5)
    g.release(0, "right", false)
    check("fighters can't walk through each other",
          f(g, 1).x - f(g, 0).x >= (f(g, 0).w + f(g, 1).w) / 2 - 0.01 && f(g, 1).x > f(g, 0).x, (f(g, 1).x - f(g, 0).x))

    fight(g, sable, sable, 300, 362)
    g.press(0, "up", false); g.press(0, "right", false)
    run(g, 0.15)
    g.release(0, "up", false)
    var peak = 0
    run(g, 2, function () { peak = Math.max(peak, f(g, 0).h); return !f(g, 0).air })
    g.release(0, "right", false)
    run(g, 0.05)
    check("a jump goes up and comes back down", peak > 100 && f(g, 0).h === 0 && !f(g, 0).air, peak)
    check("jumping over the opponent swaps sides and turns both around",
          f(g, 0).x > f(g, 1).x && f(g, 0).facing === -1 && f(g, 1).facing === 1, f(g, 0).x + " / " + f(g, 1).x)

    // ---- hits, blocks, stun -----------------------------------------------------------
    m = Fighters.at(sable).moves.sL
    fight(g, sable, sable, 300, 380)
    g.press(0, "light", false)
    run(g, m.startup + 0.02)
    check("a Light in range hits for its damage", lost(g, 1) === m.dmg && f(g, 1).state === "hitstun", lost(g, 1))
    run(g, m.hitstun - 0.06)
    check("hitstun holds the defender for the move's hitstun...", f(g, 1).state === "hitstun", f(g, 1).state)
    run(g, 0.08)
    check("... and then lets go", f(g, 1).state === "idle", f(g, 1).state)
    g.release(0, "light", false)

    fight(g, sable, sable, 200, 420)
    g.press(0, "light", false)
    run(g, 0.4)
    check("a Light out of range misses", lost(g, 1) === 0, lost(g, 1))
    g.release(0, "light", false)

    fight(g, sable, sable, 300, 380)
    g.press(1, "right", false)                       // P2 faces left: right is back
    g.press(0, "light", false)
    run(g, m.startup + 0.02)
    check("holding back blocks: no damage, blockstun", lost(g, 1) === 0 && f(g, 1).state === "blockstun", f(g, 1).state)
    check("a block fills both Ember meters", f(g, 0).meter > 0 && f(g, 1).meter > 0, f(g, 0).meter + "/" + f(g, 1).meter)
    run(g, 0.5)
    g.release(0, "light", false)
    place(g, 300, 380)
    g.press(0, "down", false)
    g.press(0, "light", false)
    run(g, Fighters.at(sable).moves.cL.startup + 0.02)
    check("a standing block doesn't stop a low attack", lost(g, 1) === Fighters.at(sable).moves.cL.dmg, lost(g, 1))
    g.release(0, "light", false)
    run(g, 0.6)
    place(g, 300, 380)
    before = hp(g, 1)
    g.press(1, "down", false)
    run(g, 0.05)
    g.press(0, "light", false)
    run(g, Fighters.at(sable).moves.cL.startup + 0.02)
    check("a crouching block stops a low attack", hp(g, 1) === before && f(g, 1).state === "blockstun", f(g, 1).state)
    g.release(0, "light", false); g.release(0, "down", false)
    run(g, 0.6)
    // An air attack on a crouching blocker.
    place(g, 300, 390)
    p = f(g, 0); p.air = true; p.h = 60; p.vy = 0; p.vx = 0; p.state = "idle"; p.airAttacked = false
    before = hp(g, 1)
    g.press(0, "heavy", false)
    run(g, 0.3, function () { return hp(g, 1) !== before })
    check("a crouching block doesn't stop an air attack", hp(g, 1) < before && f(g, 1).state === "hitstun", before - hp(g, 1))
    g.release(0, "heavy", false); g.release(1, "down", false); g.release(1, "right", false)

    // ---- knockdown ----------------------------------------------------------------------
    fight(g, sable, sable, 300, 400)
    g.press(0, "down", false); g.press(0, "heavy", false)
    run(g, Fighters.at(sable).moves.cH.startup + 0.02)
    check("a Heavy sweep knocks down", f(g, 1).state === "knockdown", f(g, 1).state)
    before = hp(g, 1)
    check("a knocked-down fighter can't be hit", g.resolveHit(0, m, false, false) === "miss" && hp(g, 1) === before)
    g.release(0, "heavy", false); g.release(0, "down", false)
    run(g, 3, function () { return f(g, 1).state === "idle" })
    check("a knocked-down fighter gets up, briefly untouchable", f(g, 1).state === "idle" && f(g, 1).invulT > 0, f(g, 1).state)

    // ---- Marrow's armor -----------------------------------------------------------------
    fight(g, marrow, sable, 300, 390)
    g.press(0, "heavy", false); g.release(0, "heavy", false)
    run(g, 0.05)
    check("armor: a hit during Marrow's Heavy windup is absorbed at half damage",
          g.resolveHit(1, m, false, false) === "armor" && lost(g, 0) === Math.round(m.dmg * 0.5) && f(g, 0).state === "attack", lost(g, 0))
    check("armor holds for one hit only: the second one lands",
          g.resolveHit(1, m, false, false) === "hit" && f(g, 0).state === "hitstun", f(g, 0).state)
    fight(g, marrow, sable, 300, 390)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, 0.03)
    check("a Light has no armor", g.resolveHit(1, m, false, false) === "hit" && f(g, 0).state === "hitstun", f(g, 0).state)

    // ---- combo scaling -------------------------------------------------------------------
    fight(g, sable, sable, 300, 380)
    g.resolveHit(0, m, false, false)
    before = hp(g, 1)
    g.resolveHit(0, m, false, false)
    check("the second hit of a combo does 85%", before - hp(g, 1) === Math.round(m.dmg * 0.85), before - hp(g, 1))

    // ---- specials: input detection --------------------------------------------------------
    fight(g, kestrel, sable, 200, 600)
    tap(g, 0, "right"); run(g, 0.05); tap(g, 0, "right")
    g.press(0, "light", false)
    check("Kestrel: forward, forward, Light is Talon Rush", f(g, 0).move === "sp", f(g, 0).move)
    var x0 = f(g, 0).x
    run(g, 0.3)
    check("Talon Rush carries Kestrel forward", f(g, 0).x > x0 + 100, f(g, 0).x - x0)
    g.release(0, "light", false)

    fight(g, kestrel, sable, 200, 600)
    tap(g, 0, "right"); run(g, 0.05); tap(g, 0, "right")
    run(g, 0.5)
    g.press(0, "light", false)
    check("a motion older than the window is a plain Light", f(g, 0).move === "sL", f(g, 0).move)
    g.release(0, "light", false)
    fight(g, kestrel, sable, 200, 600)
    tap(g, 0, "right"); run(g, 0.4); tap(g, 0, "right")
    g.press(0, "light", false)
    check("two taps too far apart are no motion", f(g, 0).move === "sL", f(g, 0).move)
    g.release(0, "light", false)
    fight(g, kestrel, sable, 600, 200)             // on the right side, forward is left
    tap(g, 0, "left"); run(g, 0.05); tap(g, 0, "left")
    g.press(0, "light", false)
    check("motions read toward the opponent on either side", f(g, 0).move === "sp", f(g, 0).move)
    g.release(0, "light", false)

    fight(g, sable, marrow, 200, 600)
    tap(g, 0, "down"); run(g, 0.05); tap(g, 0, "down")
    g.press(0, "light", false)
    run(g, Fighters.at(sable).special.startup + 0.02)
    check("Sable: down, down, Light throws a Kite Lantern", g.projectiles.length === 1 && g.projectiles[0].kind === "kite", g.projectiles.length)
    g.release(0, "light", false)
    run(g, 0.6)
    tap(g, 0, "down"); run(g, 0.05); tap(g, 0, "down")
    g.press(0, "light", false)
    check("one kite at a time: the input gives a plain Light", f(g, 0).move === "cL" || f(g, 0).move === "sL", f(g, 0).move)
    g.release(0, "light", false)
    run(g, 3, function () { return g.projectiles.length === 0 })
    q = Fighters.at(sable).special
    check("the kite hits across the stage", lost(g, 1) === q.dmg, lost(g, 1))

    fight(g, sable, marrow, 200, 600)
    g.press(1, "right", false)                       // Marrow (right side) holds back
    tap(g, 0, "down"); run(g, 0.05); tap(g, 0, "down")
    g.press(0, "light", false)
    run(g, 3, function () { return lost(g, 1) > 0 })
    check("a blocked kite still chips a little", lost(g, 1) === Math.round(q.dmg * g.specialChip) && lost(g, 1) > 0, lost(g, 1))
    g.release(0, "light", false); g.release(1, "right", false)

    fight(g, marrow, sable, 200, 600)
    g.press(0, "down", false)
    run(g, 0.6)
    g.press(0, "heavy", false)
    check("Marrow: hold down, then Heavy is Quarry Slam", f(g, 0).move === "sp", f(g, 0).move)
    run(g, Fighters.at(marrow).special.startup + 0.02)
    check("Quarry Slam sends a ground wave", g.projectiles.length === 1 && g.projectiles[0].kind === "wave" && g.projectiles[0].h === 0)
    g.release(0, "heavy", false); g.release(0, "down", false)

    fight(g, marrow, sable, 200, 600)
    g.press(0, "down", false)
    run(g, 0.2)
    g.press(0, "heavy", false)
    check("a short charge is a plain crouching Heavy", f(g, 0).move === "cH", f(g, 0).move)
    g.release(0, "heavy", false); g.release(0, "down", false)
    fight(g, marrow, sable, 200, 600)
    g.press(0, "down", false)
    run(g, 0.6)
    g.release(0, "down", false)
    run(g, 0.1)
    g.press(0, "heavy", false)
    check("a charge survives letting go of down for a moment", f(g, 0).move === "sp", f(g, 0).move)
    g.release(0, "heavy", false)
    // The wave is low: it passes under a jump, and a standing block can't stop it.
    run(g, 0.4, function () { return g.projectiles.length > 0 })
    p = f(g, 1)
    p.air = true; p.h = 120; p.vy = 0
    g.projectiles[0].x = p.x - 5
    g.step(1 / 240)
    check("a ground wave passes under a jump", lost(g, 1) === 0 && g.projectiles.length === 1, lost(g, 1))
    fight(g, marrow, sable, 200, 600)
    g.press(1, "right", false)                       // Sable on the right holds back, standing
    g.press(0, "down", false); run(g, 0.6); g.press(0, "heavy", false)
    run(g, 3, function () { return g.projectiles.length === 0 && g.clock > 0 && lost(g, 1) > 0 })
    check("a standing block can't stop the ground wave", lost(g, 1) === Fighters.at(marrow).special.dmg, lost(g, 1))
    g.release(1, "right", false); g.release(0, "heavy", false); g.release(0, "down", false)

    // ---- input buffering and cancels ---------------------------------------------------
    fight(g, sable, sable, 200, 600)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, Fighters.total(m) - 0.05)
    g.press(0, "light", false); g.release(0, "light", false)
    check("a button pressed during recovery waits...", f(g, 0).pending !== null && f(g, 0).moveT > 0.2, f(g, 0).moveT)
    run(g, 0.07)
    check("... and fires when the fighter is free", f(g, 0).state === "attack" && f(g, 0).moveT < 0.05, f(g, 0).moveT)
    run(g, 1)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, 0.05)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, Fighters.total(m) + 0.1)
    check("a button pressed too early is dropped", f(g, 0).state === "idle" && f(g, 0).pending === null, f(g, 0).state)

    fight(g, sable, sable, 300, 380)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, m.startup + 0.02)
    tap(g, 0, "down"); run(g, 0.03); tap(g, 0, "down")
    g.press(0, "light", false); g.release(0, "light", false)
    check("a Light that hit cancels into the special", f(g, 0).move === "sp", f(g, 0).move)
    run(g, 0.5, function () { return f(g, 1).combo >= 2 })
    check("the cancel combos: kite hits for 85%", lost(g, 1) === m.dmg + Math.round(q.dmg * 0.85) && f(g, 1).combo === 2, lost(g, 1))

    // ---- Ember: Kindle and Flare --------------------------------------------------------
    fight(g, sable, sable, 300, 380)
    g.press(0, "ember", false); g.release(0, "ember", false)
    check("Ember does nothing below a full meter", f(g, 0).kindleT === 0, f(g, 0).kindleT)
    f(g, 0).meter = 100
    g.press(0, "ember", false); g.release(0, "ember", false)
    check("a full meter Kindles and empties", f(g, 0).kindleT === g.kindleTime && f(g, 0).meter === 0, f(g, 0).kindleT)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, m.startup + 0.02)
    check("a Kindled hit does 30% more", lost(g, 1) === Math.round(m.dmg * 1.3), lost(g, 1))
    run(g, 0.6)
    before = hp(g, 1)
    g.press(1, "right", false)
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, m.startup + 0.02)
    check("a blocked Kindled hit chips", before - hp(g, 1) === Math.round(m.dmg * g.kindleChip * 1.3), before - hp(g, 1))
    g.release(1, "right", false)
    run(g, g.kindleTime)
    check("Kindle runs out", f(g, 0).kindleT === 0, f(g, 0).kindleT)

    fight(g, sable, sable, 300, 380)
    f(g, 1).meter = 100
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, m.startup + 0.02)
    var gap = f(g, 1).x - f(g, 0).x
    g.press(1, "ember", false); g.release(1, "ember", false)
    check("Flare breaks out of hitstun", f(g, 1).state === "idle" && f(g, 1).invulT > 0 && f(g, 1).meter === 0, f(g, 1).state)
    run(g, 0.3)
    check("Flare blows the attacker back and stuns them", f(g, 1).x - f(g, 0).x > gap + 40 && f(g, 0).state === "hitstun", f(g, 1).x - f(g, 0).x)

    // ---- rounds ---------------------------------------------------------------------
    fight(g, sable, sable, 300, 380)
    f(g, 1).hp = 10
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, m.startup + 0.02)
    check("a KO ends the round for the attacker", g.phase === "roundover" && g.roundWinner === 0 && g.winsP1 === 1 && g.roundReason === "ko", g.phase)
    run(g, g.roundPause + 0.05)
    check("then the next round starts, health full", g.phase === "ready" && g.round === 2 && hp(g, 1) === f(g, 1).maxHp, g.round)

    fight(g, marrow, kestrel, 300, 500)
    f(g, 0).hp = f(g, 0).maxHp * 0.5
    f(g, 1).hp = f(g, 1).maxHp * 0.6
    g.timeLeft = 0.01
    run(g, 0.05)
    check("time out: the bigger share of health wins", g.roundWinner === 1 && g.winsP2 === 1 && g.roundReason === "time", g.roundWinner)
    fight(g, marrow, kestrel, 300, 500)
    f(g, 0).hp = f(g, 0).maxHp * 0.5
    f(g, 1).hp = f(g, 1).maxHp * 0.5
    g.timeLeft = 0.01
    run(g, 0.05)
    check("time out with equal shares is a draw", g.phase === "roundover" && g.roundWinner === -1 && g.winsP1 === 0 && g.winsP2 === 0, g.roundWinner)

    fight(g, sable, sable, 300, 380)
    f(g, 0).hp = 10; f(g, 1).hp = 10
    g.press(0, "light", false); g.press(1, "light", false)
    run(g, m.startup + 0.02)
    check("a trade that KOs both is a draw", g.phase === "roundover" && g.roundWinner === -1 && g.roundReason === "double", g.roundReason)

    // Best of three.
    fight(g, sable, kestrel, 300, 500)
    g.endRound(0, "ko"); run(g, g.roundPause + 0.05)
    g.phase = "play"; g.endRound(1, "ko"); run(g, g.roundPause + 0.05)
    check("one round each goes to a third round", g.round === 3 && g.phase === "ready" && g.winsP1 === 1 && g.winsP2 === 1, g.round)
    g.phase = "play"; g.endRound(0, "ko"); run(g, g.roundPause + 0.05)
    check("two round wins take the match", g.phase === "over" && g.matchWinner === 0 && g.tallyP1 === 1, g.phase)
    check("a versus match never touches the high score", g.score === 0 && !g.beatHigh)

    // ---- 1 player ladder and score ---------------------------------------------------------
    g.seed = 7; g.newGame()
    g.startMatch("cpu", sable, -1, 1)
    check("vs CPU: player 2 is the CPU at the difficulty's level",
          f(g, 1).cpu && g.cpuLevel === Fighters.DIFFICULTY[1].level && f(g, 1).d === Fighters.ladderOpponent(sable, 1), g.cpuLevel)
    var lv = g.cpuLevel
    g.phase = "play"; g.endRound(0, "ko")
    check("a round win scores its bonus", g.score >= 1000 * g.levelMul(), g.score)
    run(g, g.roundPause + 0.05)
    g.phase = "play"; g.endRound(0, "ko"); run(g, g.roundPause + 0.05)
    check("winning a match climbs the ladder: next fighter, sharper CPU",
          g.stage === 2 && g.cpuLevel === lv + 1 && f(g, 1).d === Fighters.ladderOpponent(sable, 2) && g.phase === "ready", g.stage)
    check("the new stage is announced on the round call",
          g.hudView.callText.indexOf("STAGE 2") === 0 && g.hudView.callText.indexOf("ROUND 1") > 0, g.hudView.callText)
    g.phase = "play"; g.endRound(1, "ko"); run(g, g.roundPause + 0.05)
    g.phase = "play"; g.endRound(1, "ko"); run(g, g.roundPause + 0.05)
    check("losing a match vs the CPU is game over", g.phase === "over" && !g.champion && g.stage === 2, g.phase)
    g.startMatch("cpu", sable, -1, 2)
    g.stage = Fighters.LADDER
    g.phase = "play"; g.endRound(0, "ko"); run(g, g.roundPause + 0.05)
    g.phase = "play"; g.endRound(0, "ko"); run(g, g.roundPause + 0.05)
    check("winning the last stage makes you champion", g.phase === "over" && g.champion, g.phase)

    g.highScore = 500
    g.startMatch("cpu", sable, -1, 1)
    g.score = 490
    g.addScore(10)
    check("tying the high score is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(1)
    check("beating it is", g.beatHigh && g.highScore === 501, g.highScore)

    // ---- the CPU ------------------------------------------------------------------
    function hi(v) { return function () { return v } }
    var ctx = { level: 3, dist: 500, range: 130, input: "dd", specialReady: false, charging: false, threat: "",
                threatIsShot: false, oppRecovering: false, oppDown: false, meter: 0, stunned: false }
    check("CPU: far away it walks in", AI.decide(ctx, hi(0.99)).why === "approach", AI.decide(ctx, hi(0.99)).why)
    ctx.dist = 100; ctx.threat = "low"; ctx.level = 8
    var d = AI.decide(ctx, hi(0.01))
    check("CPU: a sharp CPU crouch-blocks a low attack", d.why === "block" && d.dir === -1 && d.down, d.why)
    ctx.level = 1
    check("CPU: a level-1 CPU often doesn't", AI.decide(ctx, hi(0.5)).why !== "block", AI.decide(ctx, hi(0.5)).why)
    ctx.threat = ""; ctx.oppRecovering = true; ctx.level = 5
    check("CPU: punishes a whiffed move in range", AI.decide(ctx, hi(0.1)).button === "heavy", AI.decide(ctx, hi(0.1)).why)

    function cpuRun() {
      g.seed = 7; g.newGame()
      g.startMatch("cpu", kestrel, sable, 1)
      run(g, 6)
      return g.decisionLog.join(",") + "|" + Math.round(f(g, 0).x) + "," + Math.round(f(g, 1).x) + "," + hp(g, 0)
    }
    var log1 = cpuRun(), n1 = g.decisionLog.length
    var log2 = cpuRun()
    check("CPU: the same seed plays the same fight", log1 === log2 && n1 > 5, n1)
    check("CPU: from across the stage it first closes in or zones", ["approach", "zone", "jump in"].indexOf(g.decisionLog[0]) >= 0, g.decisionLog[0])

    // In a real fight: a level-8 CPU sees a Heavy coming and blocks it.
    g.seed = 7; g.newGame()
    g.startMatch("cpu", sable, sable, 2)
    run(g, 2, function () { return g.phase === "play" })
    g.cpuLevel = 8
    place(g, 300, 400)
    f(g, 1).aiT = 0.02
    g.press(0, "heavy", false); g.release(0, "heavy", false)
    run(g, Fighters.at(sable).moves.sH.startup + 0.03)
    check("CPU: blocks an incoming Heavy at level 8", f(g, 1).state === "blockstun" && lost(g, 1) === 0, f(g, 1).state + " " + f(g, 1).lastDecision)
    g.press(1, "heavy", false)
    check("a person's P2 keys do nothing while the CPU plays P2", f(g, 1).held.heavy === false && f(g, 1).pending === null)

    // ---- keys ------------------------------------------------------------------------
    var ka = g.keyAction(Qt.Key_F), kb = g.keyAction(Qt.Key_Shift), kc = g.keyAction(Qt.Key_Return)
    check("keys: F is P1 Light, Shift is P2 Heavy, Enter is P2 Ember",
          ka.player === 0 && ka.act === "light" && kb.player === 1 && kb.act === "heavy" && kc.player === 1 && kc.act === "ember")

    // ---- pause and focus -------------------------------------------------------------
    fight(g, sable, sable, 300, 500)
    g.press(0, "right", false); g.press(1, "down", false)
    var t0 = g.timeLeft
    g.pause()
    for (i = 0; i < 120; i++) if (g.fighting()) g.step(1 / 240)
    check("pause freezes the round clock", g.phase === "paused" && g.timeLeft === t0, g.timeLeft)
    g.resume()
    check("resume returns to the fight", g.phase === "play", g.phase)
    g.lostFocus()
    check("losing focus pauses and forgets held keys",
          g.phase === "paused" && !f(g, 0).held.right && !f(g, 1).held.down, JSON.stringify(f(g, 0).held))
    g.resume()
    before = f(g, 0).x
    run(g, 0.3)
    check("after losing focus nobody keeps walking", f(g, 0).x === before, f(g, 0).x - before)

    // ---- new game resets --------------------------------------------------------------
    g.startMatch("cpu", sable, -1, 1)
    g.phase = "play"; g.endRound(0, "ko")
    g.tallyP1 = 3
    g.newGame()
    check("a new game resets everything",
          g.phase === "select" && g.score === 0 && !g.beatHigh && g.stage === 1 && g.winsP1 === 0
          && g.tallyP1 === 0 && g.projectiles.length === 0 && g.decisionLog.length === 0, g.phase)

    // ---- drawing -----------------------------------------------------------------------
    fight(g, sable, kestrel, 250, 520)
    g.publish()
    var fv0 = g.fighterView.itemAt(0), fv1 = g.fighterView.itemAt(1)
    check("the drawn fighters stand where the model says",
          fv0 && fv1 && Math.abs(fv0.x - 250) < 0.01 && Math.abs(fv1.x - 520) < 0.01, fv0 ? fv0.x : "none")
    f(g, 0).x = 333; f(g, 1).h = 40
    g.publish()
    check("the drawn fighter moves when the fighter does",
          Math.abs(g.fighterView.itemAt(0).x - 333) < 0.01 && Math.abs(g.fighterView.itemAt(1).y - (g.groundY - 40)) < 0.01,
          g.fighterView.itemAt(0).x)
    g.spawnShot(f(g, 0))
    g.publish()
    q = g.projectiles[0]
    check("a drawn kite starts at its model", g.shotView.itemAt(0) && Math.abs(g.shotView.itemAt(0).x - q.x) < 0.01)
    g.projectiles[0].x = 410
    g.publish()
    check("the drawn kite moves when the kite does", Math.abs(g.shotView.itemAt(0).x - 410) < 0.01, g.shotView.itemAt(0).x)
    // The drawing waits for publish(): a substep alone doesn't move it.
    fight(g, sable, kestrel, 300, 500)
    g.publish()
    f(g, 0).x = 420
    g.step(1 / 240)
    check("a substep without publish() leaves the drawing where it was",
          Math.abs(g.fighterView.itemAt(0).x - 300) < 0.01, g.fighterView.itemAt(0).x)
    g.publish()
    check("... and publish() brings it up to date", Math.abs(g.fighterView.itemAt(0).x - 420) < 0.01, g.fighterView.itemAt(0).x)

    // ---- review additions --------------------------------------------------------------
    // Two kites meeting cancel out.
    fight(g, sable, sable, 200, 600)
    tap(g, 0, "down"); tap(g, 1, "down"); run(g, 0.05); tap(g, 0, "down"); tap(g, 1, "down")
    g.press(0, "light", false); g.press(1, "light", false)
    run(g, Fighters.at(sable).special.startup + 0.02)
    var bothKites = g.projectiles.length === 2
    g.release(0, "light", false); g.release(1, "light", false)
    run(g, 2.5, function () { return g.projectiles.length === 0 })
    check("opposing kites cancel each other out", bothKites && g.projectiles.length === 0 && lost(g, 0) === 0 && lost(g, 1) === 0,
          bothKites + " " + lost(g, 0) + "/" + lost(g, 1))

    // Kindled, the kite flies faster.
    fight(g, sable, marrow, 200, 600)
    f(g, 0).kindleT = 5
    tap(g, 0, "down"); run(g, 0.05); tap(g, 0, "down")
    g.press(0, "light", false); g.release(0, "light", false)
    run(g, Fighters.at(sable).special.startup + 0.02)
    check("a Kindled kite flies 35% faster",
          g.projectiles.length === 1 && Math.abs(g.projectiles[0].vx - Fighters.at(sable).special.projectile.speed * 1.35) < 0.01,
          g.projectiles.length ? g.projectiles[0].vx : "none")

    // A round's end clears shots still in flight.
    fight(g, sable, marrow, 200, 600)
    g.spawnShot(f(g, 0))
    var hadShot = g.projectiles.length === 1
    g.endRound(0, "ko")
    check("a round's end clears the shots in flight", hadShot && g.projectiles.length === 0, g.projectiles.length)

    // A drawn ladder match is fought again, same stage, same opponent.
    g.seed = 7; g.newGame()
    g.startMatch("cpu", sable, -1, 1)
    var opp = f(g, 1).d
    g.winsP1 = 1; g.winsP2 = 1; g.round = g.maxRounds
    g.phase = "play"; g.endRound(-1, "time"); run(g, g.roundPause + 0.05)
    check("a drawn ladder match is a rematch", g.phase === "ready" && g.stage === 1 && f(g, 1).d === opp
          && g.round === 1 && g.winsP1 === 0 && g.winsP2 === 0, g.phase + " " + g.stage)
    check("the rematch is announced", g.hudView.callText.indexOf("REMATCH") === 0, g.hudView.callText)

    // The perfect-round bonus.
    g.startMatch("cpu", sable, -1, 1)
    g.phase = "play"; g.endRound(0, "ko")
    check("a perfect round adds 2000", g.perfect && g.score === Math.round((1000 + 20 * g.roundTime + 2000) * g.levelMul()), g.score)
    g.startMatch("cpu", sable, -1, 1)
    f(g, 0).hp = f(g, 0).maxHp - 1
    g.phase = "play"; g.endRound(0, "ko")
    check("a round won with a scratch is not perfect", !g.perfect && g.score === Math.round((1000 + 20 * g.roundTime) * g.levelMul()), g.score)

    // Only the health actually taken scores.
    g.startMatch("cpu", sable, -1, 1)
    run(g, 2, function () { return g.phase === "play" })
    place(g, 300, 380)
    f(g, 1).hp = 10
    before = g.score
    g.resolveHit(0, m, false, false)
    check("overkill damage doesn't score", g.score - before === Math.round(10 * g.levelMul()), g.score - before)

    // The CPU doesn't queue a jump while it's busy.
    fight(g, sable, sable, 300, 500)
    p = f(g, 0)
    g.press(0, "light", false); g.release(0, "light", false)
    g.cpuApply(p, { dir: 0, down: false, jump: true, button: "", why: "t" })
    var queued = p.held.up
    run(g, Fighters.total(m) + 0.1)
    check("a CPU jump decided mid-move is dropped, not fired late", !queued && !p.air && p.h === 0, queued + " " + p.h)
    g.cpuApply(p, { dir: 0, down: false, jump: true, button: "", why: "t" })
    g.step(1 / 240)
    check("a CPU jump decided while free still jumps", p.air, p.state)
  }
}
