import QtQuick
import Quickshell
import Quickshell.Io
import "mazes.js" as Mazes
import "bugs.js" as Bugs
import "motion.js" as Motion

// Headless rules test for Circuit Crawl. tests/run.sh stages games/crawl/ and this
// file in one temp folder, runs it offscreen and reads the JSON written to
// $ARCADE_TEST_OUT: {"passed": n, "failed": [..]}.
ShellRoot {
  id: root
  property var failures: []
  property int passed: 0

  function check(name, ok, detail) {
    if (ok) passed++
    else failures.push(name + (detail !== undefined ? " (" + detail + ")" : ""))
  }
  function near(a, b, eps) { return Math.abs(a - b) < (eps || 0.01) }

  // Step the game for `seconds` in 1/240 s steps, or until `until()` holds.
  function run(g, seconds, until) {
    var steps = Math.ceil(seconds * 240)
    for (var i = 0; i < steps; i++) {
      if (g.phase === "over" || g.phase === "paused") return
      g.step(1 / 240)
      if (until && until()) return
    }
  }
  function bug(g, name) {
    for (var i = 0; i < g.bugs.length; i++) if (g.bugs[i].name === name) return g.bugs[i]
    return null
  }
  // Every bug waits in the pen for good, so a rule sees only what it sets up.
  function park(g) {
    for (var i = 0; i < g.bugs.length; i++) {
      var b = g.bugs[i]
      b.state = "pen"; b.release = 1e9; b.patched = false
      b.x = g.maze.penCenter.c; b.y = g.maze.penCenter.r; b.dx = 0; b.dy = 0
    }
  }
  function place(a, x, y, dx, dy) { a.x = x; a.y = y; a.dx = dx; a.dy = dy; if (a.ndx !== undefined) { a.ndx = 0; a.ndy = 0 } }
  function activate(b, x, y, dx, dy) { b.state = "active"; b.release = 0; place(b, x, y, dx, dy) }
  // A new game, straight into play, bugs parked.
  function play(g, seed) {
    g.newGame(seed === undefined ? 7 : seed)
    g.arm(); g.readyTime = 0; g.step(1 / 240)
    park(g)
  }
  function kill(g, c, r) {
    var i = g.bitIndex[r * g.maze.w + c]
    if (i !== undefined && g.bitModel.get(i).alive) { g.bitModel.setProperty(i, "alive", false); g.bitsLeft-- }
  }
  function aliveAt(g, c, r) {
    var i = g.bitIndex[r * g.maze.w + c]
    return i !== undefined && g.bitModel.get(i).alive
  }

  FloatingWindow {
    implicitWidth: 580; implicitHeight: 616
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
    var b, s, i, x0

    // ---- mazes -------------------------------------------------------------------
    check("two boards, Motherboard then Northbridge", Mazes.MAZES.length === 2
          && Mazes.MAZES[0].name === "Motherboard" && Mazes.MAZES[1].name === "Northbridge")
    check("a mirrored row is half + reverse(half minus its last)", Mazes.mirrorRow("ab#c") === "ab#c#ba", Mazes.mirrorRow("ab#c"))
    for (var mi = 0; mi < Mazes.MAZES.length; mi++) {
      var nm = Mazes.MAZES[mi].name
      var halvesOk = Mazes.MAZES[mi].half.every(function (h) { return h.length === 11 && !/[^#.o \-BPT]/.test(h) })
      check(nm + ": halves are 11 known characters", halvesOk)
      var mz = Mazes.parse(Mazes.expand(Mazes.MAZES[mi].half))
      check(nm + ": 21x21 and rectangular after mirroring", mz.rectangular && mz.w === 21 && mz.h === 21, mz.w + "x" + mz.h)
      check(nm + ": one start, a pen and one door", mz.starts === 1 && mz.pen.length >= 1 && mz.doors === 1, mz.starts + "/" + mz.pen.length + "/" + mz.doors)
      var problems = Mazes.validate(mz)
      check(nm + ": every bit and chip is reachable from the start, the pen exit too", problems.length === 0, problems.join("; "))
      check(nm + ": has bits and at least four chips", mz.bits > 100 && mz.chips >= 4, mz.bits + "/" + mz.chips)
      check(nm + ": the tunnel wraps (column -1 is column 20)", mz.tunnels.length === 2
            && Mazes.walkable(mz, -1, mz.tunnels[0].r) && Mazes.tile(mz, -1, mz.tunnels[0].r) === "T")
      check(nm + ": Byte can't walk through the door or into the pen",
            !Mazes.walkable(mz, mz.door.c, mz.door.r) && !Mazes.walkable(mz, mz.penCenter.c, mz.penCenter.r))
    }
    // The validator does catch a broken board.
    var broken = Mazes.parse(Mazes.expand(["###########", "#.#.......P", "###########"]))
    check("the validator reports an unreachable bit", Mazes.validate(broken).some(function (p) { return p.indexOf("unreachable") === 0 }))

    // ---- a new game -----------------------------------------------------------------
    g.newGame(7)
    var total = g.bitsTotal
    check("new game: ready and waiting for a key", g.phase === "ready" && !g.armed, g.phase)
    run(g, 3)
    check("the first READY waits for input", g.phase === "ready", g.phase)
    g.setDir(-1, 0)
    check("a direction key arms the start", g.armed)
    run(g, g.readyDelay - 0.1)
    check("READY counts down in step()", g.phase === "ready", g.phase)
    run(g, 0.2)
    check("then play starts", g.phase === "play", g.phase)
    check("three lives, level 1 on Motherboard", g.lives === 3 && g.level === 1 && g.mazeName === "Motherboard")
    check("Byte starts at P", g.maze.start.c === 10 && g.maze.start.r === 15)

    // ---- movement -------------------------------------------------------------------
    play(g)
    place(g.hero, 10, 15, -1, 0)
    run(g, 0.5)
    check("Byte crawls left at his speed", near(g.hero.x, 10 - g.heroSpeed() * 0.5) && g.hero.y === 15, g.hero.x)
    run(g, 2)
    check("a wall stops Byte at a tile centre", g.hero.x === 4 && g.hero.dx === 0 && g.hero.dy === 0, g.hero.x + "," + g.hero.dx)

    play(g)
    place(g.hero, 10, 15, -1, 0)
    g.setDir(0, -1)          // up is a wall here; the turn waits for the junction at column 9
    run(g, 0.05)
    check("a buffered turn waits while the way is shut", g.hero.dx === -1 && g.hero.y === 15 && g.hero.ndy === -1)
    run(g, 1, function () { return g.hero.dy !== 0 })
    check("the buffered turn is taken at the next open centre", g.hero.dy === -1 && near(g.hero.x, 9, 1e-6), g.hero.x + "," + g.hero.y)
    run(g, 0.3)
    check("after the turn Byte is on the new axis", g.hero.x === 9 && g.hero.y < 15, g.hero.y)

    play(g)
    place(g.hero, 9.4, 15, -1, 0)
    g.setDir(1, 0)
    check("reversing is instant, mid-tile", g.hero.dx === 1 && near(g.hero.x, 9.4), g.hero.dx + " @" + g.hero.x)

    play(g)
    place(g.hero, 2, 9, -1, 0)
    run(g, 0.6)
    check("the tunnel wraps Byte to the far side", g.hero.x > 15 && g.hero.x < 20.5 && g.hero.y === 9 && g.hero.dx === -1, g.hero.x)

    play(g)
    place(g.hero, -0.3, 9, -1, 0)
    b = bug(g, "Null"); activate(b, 20.2, 9, 1, 0)
    g.step(1 / 240)
    check("a bug touches Byte across the tunnel seam", g.phase === "dying", g.phase)

    // ---- bug targeting (pure, fixed inputs) ------------------------------------------
    var heroT = { c: 5, r: 7, fx: 1, fy: 0 }
    var t = Bugs.targetFor("Null", { c: 1, r: 1 }, heroT, "chase", 21, 21)
    check("Null targets Byte's tile", t.c === 5 && t.r === 7, JSON.stringify(t))
    t = Bugs.targetFor("Race", { c: 1, r: 1 }, heroT, "chase", 21, 21)
    check("Race targets four tiles ahead of Byte", t.c === 9 && t.r === 7, JSON.stringify(t))
    t = Bugs.targetFor("Race", { c: 1, r: 1 }, { c: 5, r: 7, fx: 0, fy: -1 }, "chase", 21, 21)
    check("Race leads Byte whichever way he faces", t.c === 5 && t.r === 3, JSON.stringify(t))
    t = Bugs.targetFor("Loop", { c: 1, r: 19 }, { c: 15, r: 3, fx: 1, fy: 0 }, "chase", 21, 21)
    var loopCorner = Bugs.corner("bottomLeft", 21, 21)
    check("Loop far from Byte patrols its corner", t.c === loopCorner.c && t.r === loopCorner.r, JSON.stringify(t))
    t = Bugs.targetFor("Loop", { c: 5, r: 11 }, { c: 5, r: 7, fx: 1, fy: 0 }, "chase", 21, 21)
    check("Loop near Byte gives chase", t.c === 5 && t.r === 7, JSON.stringify(t))
    check("Leak on the chase turns at random", Bugs.targetFor("Leak", { c: 1, r: 1 }, heroT, "chase", 21, 21) === null)
    t = Bugs.targetFor("Null", { c: 1, r: 1 }, heroT, "scatter", 21, 21)
    check("in scatter a bug heads for its corner", t.c === 19 && t.r === -3, JSON.stringify(t))
    check("greedy choice: the way that gets closest", Bugs.chooseDir([0, 2, 3], { c: 5, r: 5 }, { c: 9, r: 5 }, 21) === 3)
    check("greedy ties go up, left, down, right", Bugs.chooseDir([2, 0], { c: 5, r: 5 }, { c: 5, r: 5 }, 21) === 0)

    // Bug fix: Loop's proximity check and chooseDir's greedy pick used to
    // measure straight-line distance only, so a bug just across the tunnel
    // seam looked far away, and a bug near the seam picked the long way round.
    t = Bugs.targetFor("Loop", { c: 0, r: 10 }, { c: 20, r: 10, fx: 1, fy: 0 }, "chase", 21, 21)
    check("Loop notices Byte just across the tunnel seam", t.c === 20 && t.r === 10, JSON.stringify(t))
    check("chooseDir picks the short way across the seam, not the long way round",
          Bugs.chooseDir([1, 3], { c: 1, r: 5 }, { c: 19, r: 5 }, 21) === 1)

    // ---- bug decisions in the game ------------------------------------------------------
    play(g)
    g.mode = "chase"
    b = bug(g, "Null")
    activate(b, 4, 3, 1, 0)         // a four-way junction on the top corridor
    place(g.hero, 4, 13, 0, 0)
    g.bugDecide(b)
    check("Null at a junction turns toward Byte", b.dx === 0 && b.dy === 1, b.dx + "," + b.dy)
    activate(b, 4, 3, 1, 0)
    place(g.hero, 1, 3, 0, 0)       // straight behind it
    g.bugDecide(b)
    check("a bug never turns straight back at a junction", !(b.dx === -1 && b.dy === 0) && b.dy === -1, b.dx + "," + b.dy)

    var leak = bug(g, "Leak"), picks = {}, same = true, allowed = true
    for (s = 1; s <= 24; s++) {
      g.setSeed(s); activate(leak, 4, 3, 1, 0); g.bugDecide(leak)
      var first = leak.dx + "," + leak.dy
      g.setSeed(s); activate(leak, 4, 3, 1, 0); g.bugDecide(leak)
      if (leak.dx + "," + leak.dy !== first) same = false
      if (first === "-1,0") allowed = false
      picks[first] = true
    }
    check("Leak: the same seed makes the same turn", same)
    check("Leak: seeded turns vary and never reverse", Object.keys(picks).length >= 2 && allowed, Object.keys(picks).join(" "))

    // A dead end is the one place a bug turns back.
    g.maze = Mazes.parse(["#####", "#  ##", "#####"])
    b = bug(g, "Race")
    activate(b, 2, 1, 1, 0)
    g.bugDecide(b)
    check("a dead end turns a bug around", b.dx === -1 && b.dy === 0, b.dx + "," + b.dy)
    g.loadLevel()

    // Release from the pen on its countdown.
    play(g)
    b = bug(g, "Race")
    b.state = "pen"; b.release = 1.5; b.x = g.maze.door.c; b.y = g.maze.penCenter.r
    place(g.hero, 10, 15, 0, 0)
    run(g, 1.4)
    check("a bug waits in the pen until its countdown", b.state === "pen", b.state)
    run(g, 2, function () { return b.state === "active" })
    check("then it leaves through the door", b.state === "active" && b.x === g.maze.exit.c && b.y === g.maze.exit.r, b.state + " " + b.x + "," + b.y)
    check("release countdowns shorten with the level", Bugs.releaseSeconds(Bugs.DEFS[3], 4) < Bugs.releaseSeconds(Bugs.DEFS[3], 1))

    // Scatter -> chase turns the bugs around.
    play(g)
    b = bug(g, "Null")
    activate(b, 12.5, 7, -1, 0)
    place(g.hero, 10, 15, 0, 0)
    check("a life starts in scatter", g.mode === "scatter" && g.modeIndex === 0)
    g.modeTime = 0.001
    g.step(1 / 240)
    check("scatter ends in chase, and the bugs turn around", g.mode === "chase" && b.dx === 1, g.mode + " " + b.dx)

    // Bug fix: a scatter/chase reversal used to be silently overridden when a
    // bug sat exactly at a tile centre (a real junction), because the very
    // next decide() there could steer it somewhere other than the reversal.
    // Build a real 4-way junction and put Byte where the greedy pick would go
    // a different way (up, not back) to prove the forced reversal wins.
    play(g)
    g.maze = Mazes.parse(["#####", "#...#", "#...#", "#...#", "#####"])
    b = bug(g, "Null")
    activate(b, 2, 2, 1, 0)      // heading east, exactly at the junction centre
    place(g.hero, 2, 0, 0, 0)    // due north: the greedy choice would turn up, not back
    g.modeIndex = 0; g.modeTime = 0.001
    g.modeTick(0.002)
    g.bugStep(b, 1 / 240)
    check("a mode reversal at a junction centre is not swallowed by the junction pick",
          b.dx === -1 && b.dy === 0, b.dx + "," + b.dy)

    b = bug(g, "Race")
    activate(b, 2, 2, 1, 0)
    place(g.hero, 2, 0, 0, 0)
    g.startPatch()
    g.bugStep(b, 1 / 240)
    check("a patch's reversal at a junction centre is not swallowed either",
          b.dx === -1 && b.dy === 0 && b.patched, b.dx + "," + b.dy)
    g.loadLevel()

    // ---- debug chips -------------------------------------------------------------------------
    play(g)
    kill(g, 2, 15)
    b = bug(g, "Null")
    activate(b, 12.5, 7, -1, 0)
    place(g.hero, 2, 15, -1, 0)
    x0 = g.score
    run(g, 0.5, function () { return !aliveAt(g, 1, 15) })
    check("a chip scores 60", !aliveAt(g, 1, 15) && g.score === x0 + 60, g.score - x0)
    check("a chip patches the bugs for the level's time", near(g.patchTime, Bugs.patchSeconds(1), 0.02) && b.patched && bug(g, "Race").patched, g.patchTime)
    check("patched bugs turn around", b.dx === 1, b.dx)
    check("patched bugs are slower", near(g.speedOf(b), g.bugSpeed() * 0.55) && g.speedOf(b) < g.bugSpeed())
    check("patch time shrinks every level", Bugs.patchSeconds(3) < Bugs.patchSeconds(1) && Bugs.patchSeconds(20) >= 1.5)

    // Squash tiers: 150, 300, 600, 1200, and a full-debug bonus for all four.
    place(g.hero, 1, 15, 0, 0)
    var gains = [], names = ["Null", "Race", "Leak", "Loop"]
    for (i = 0; i < names.length; i++) {
      var sb = bug(g, names[i])
      activate(sb, g.hero.x, g.hero.y, 0, -1); sb.patched = true
      g.freezeTime = 0
      x0 = g.score
      g.step(1 / 240)
      gains.push(g.score - x0)
    }
    check("squashes score 150, 300, 600, then 1200 + 900 for all four", gains.join(",") === "150,300,600,2100", gains.join(","))
    check("a squashed bug runs home", bug(g, "Null").state === "return" && !bug(g, "Null").patched, bug(g, "Null").state)
    check("a squash holds the board still a moment", g.freezeTime > 0 && g.phase === "play")
    for (i = 1; i < 4; i++) { var ob = bug(g, names[i]); ob.state = "pen"; ob.release = 1e9; ob.x = 10; ob.y = 9 }
    b = bug(g, "Null")
    var reachedPen = false
    run(g, 10, function () { if (b.state === "pen") reachedPen = true; return reachedPen && b.state === "active" })
    check("it reaches the pen and comes out again, unpatched", reachedPen && b.state === "active" && !b.patched && g.phase === "play", b.state + " " + b.patched + " " + g.phase + " @" + b.x + "," + b.y + " d" + b.dx + "," + b.dy)

    play(g)
    b = bug(g, "Null"); activate(b, 12.5, 7, -1, 0)
    place(g.hero, 10, 15, 0, 0)
    g.startPatch()
    check("a new chip starts the squash count over", g.chain === 0 && b.patched)
    g.patchTime = 0.001
    g.step(1 / 240)
    check("when the patch runs out the bugs are live again", g.patchTime === 0 && !b.patched)

    // ---- death, lives, game over ----------------------------------------------------------
    play(g)
    place(g.hero, 10, 15, -1, 0)
    b = bug(g, "Null"); activate(b, 10.3, 15, 1, 0)
    g.step(1 / 240)
    check("touching a live bug costs the life", g.phase === "dying", g.phase)
    run(g, g.dyingDelay + 0.05, function () { return g.phase !== "dying" })
    check("after the death pause: one life fewer, READY again", g.lives === 2 && g.phase === "ready" && g.armed, g.lives + " " + g.phase)
    check("everyone is back at the start", g.hero.x === 10 && g.hero.y === 15 && bug(g, "Null").x === g.maze.exit.c && bug(g, "Race").state === "pen")

    play(g)
    g.lives = 1
    b = bug(g, "Null"); activate(b, g.hero.x, g.hero.y, 1, 0)
    run(g, 3)
    check("losing the last life ends the game", g.phase === "over" && g.lives === 0, g.phase)

    // ---- bits and board clear -------------------------------------------------------------
    play(g)
    place(g.hero, 10, 15, -1, 0)
    x0 = g.score
    var left0 = g.bitsLeft
    run(g, 0.3, function () { return !aliveAt(g, 9, 15) })
    check("a bit scores 12", g.score === x0 + 12 && g.bitsLeft === left0 - 1, g.score - x0)

    play(g)
    for (i = 0; i < g.bitModel.count; i++) {
      var p = g.bitModel.get(i)
      if (!(p.c === 9 && p.r === 15)) g.bitModel.setProperty(i, "alive", false)
    }
    g.bitsLeft = 1
    place(g.hero, 10, 15, -1, 0)
    var speed1 = g.bugSpeed(), hspeed1 = g.heroSpeed()
    run(g, 0.3, function () { return g.phase === "clear" })
    check("the last bit clears the board", g.phase === "clear", g.phase)
    run(g, g.clearDelay + 0.1, function () { return g.phase !== "clear" })
    var nb = Mazes.parse(Mazes.expand(Mazes.MAZES[1].half))
    check("the next level is Northbridge, fully loaded", g.level === 2 && g.mazeName === "Northbridge"
          && g.bitsLeft === nb.bits + nb.chips && g.phase === "ready", g.level + " " + g.mazeName + " " + g.bitsLeft)
    check("each level is faster", g.bugSpeed() > speed1 && g.heroSpeed() > hspeed1)
    check("after the last board the list starts over", Mazes.forLevel(3).name === "Motherboard")

    // Clearing the board while the bugs are patched unpatches them (review fix:
    // they used to stay grey through the clear flash).
    play(g)
    for (i = 0; i < g.bitModel.count; i++) {
      var p2 = g.bitModel.get(i)
      if (!(p2.c === 9 && p2.r === 15)) g.bitModel.setProperty(i, "alive", false)
    }
    g.bitsLeft = 1
    g.startPatch()
    place(g.hero, 10, 15, -1, 0)
    run(g, 0.3, function () { return g.phase === "clear" })
    check("a board clear ends the patch on every bug", g.phase === "clear" && g.patchTime === 0
          && g.bugs.every(function (q) { return !q.patched }), g.phase + " " + g.bugs.map(function (q) { return q.patched }).join(","))

    // ---- coffee and overclock -----------------------------------------------------------------
    play(g)
    place(g.hero, 10, 15, -1, 0)
    g.eaten = g.coffeeAt[0] - 1
    run(g, 0.3, function () { return g.coffeeOn })
    check("coffee appears after enough bits", g.coffeeOn && g.coffeeValue === 90 && g.coffeeShown === 1)
    run(g, g.coffeeSeconds + 0.1)
    check("coffee goes cold after a few seconds", !g.coffeeOn)
    check("coffee comes twice a board", g.coffeeAt.length === 2 && g.coffeeAt[1] > g.coffeeAt[0] && g.coffeeAt[1] < total)

    play(g)
    g.coffeeOn = true; g.coffeeTime = 9; g.coffeeValue = 100
    place(g.hero, 12, 11, -1, 0)
    var base = g.heroSpeed()
    x0 = g.score
    run(g, 1, function () { return !g.coffeeOn })
    check("drinking coffee scores its value", g.score === x0 + 100, g.score - x0)
    check("coffee overclocks Byte", g.overclock > 3.5 && near(g.heroSpeed(), base * g.overclockBoost), g.heroSpeed())
    run(g, g.overclockSeconds + 0.1)
    check("the overclock wears off", g.overclock === 0 && near(g.heroSpeed(), base), g.overclock)
    check("coffee is worth more each level", g.coffeeValueFor(1) < g.coffeeValueFor(3) && g.coffeeValueFor(3) < g.coffeeValueFor(12))

    // ---- extra life ---------------------------------------------------------------------------
    play(g)
    g.score = 14990
    g.addScore(10)
    check("15000 points earns a life", g.lives === 4 && g.extraGiven, g.lives)
    g.addScore(10000)
    check("only once", g.lives === 4, g.lives)

    // ---- difficulty curve -----------------------------------------------------------------------
    // Bug fix: bugSpeed() used to grow faster and cap higher than heroSpeed(),
    // so from level 7 on the bugs outran Byte and stayed ahead. Check every
    // level up to well past both caps that Byte is never slower.
    var everCrossed = false, crossLevel = 0
    for (var lv = 1; lv <= 30; lv++) {
      g.level = lv
      if (g.heroSpeed() < g.bugSpeed()) { everCrossed = true; crossLevel = lv }
    }
    check("Byte is never slower than the bugs, at any level", !everCrossed, "first crossed at level " + crossLevel)
    g.level = 1

    // ---- Byte's colour: a hue guard --------------------------------------------------------------
    // Bug fix (review item): a theme with a yellow accent would otherwise make
    // Byte yellow by coincidence; the guard nudges only that hue band.
    g.theme = ({ accent: "#ffd000" })          // squarely in the classic-hero yellow band
    var yellowHero = g.hexToHsl(g.heroColor())
    check("a yellow accent is nudged off the classic hero's hue",
          !(yellowHero.h >= g.yellowHueLo && yellowHero.h <= g.yellowHueHi), yellowHero.h)
    g.theme = ({ accent: "#7aa2f7" })          // an ordinary blue accent
    check("a non-yellow accent passes through unchanged", g.heroColor() === "#7aa2f7", g.heroColor())
    g.theme = ({})

    // ---- pause and focus ---------------------------------------------------------------------
    play(g)
    place(g.hero, 10, 15, -1, 0)
    g.togglePause()
    x0 = g.hero.x
    g.step(1 / 60)
    check("pause freezes the board", g.phase === "paused" && g.hero.x === x0, g.phase)
    g.togglePause()
    check("resume plays on", g.phase === "play", g.phase)
    g.setDir(0, -1)
    g.lostFocus()
    check("losing focus pauses", g.phase === "paused", g.phase)
    check("losing focus forgets the buffered turn", g.hero.ndx === 0 && g.hero.ndy === 0)
    g.resume()
    g.newGame(3); g.arm(); run(g, 0.5)
    g.pause()
    var rt = g.readyTime
    g.step(0.1)
    check("a pause holds the READY countdown", g.phase === "paused" && g.readyTime === rt)
    g.resume()
    check("and resuming returns to READY", g.phase === "ready", g.phase)

    // ---- a whole game, played by a random thumb --------------------------------------------------
    g.newGame(11); g.arm()
    var offTrace = "", frames = 0
    for (var f = 0; f < 240 * 90 && g.phase !== "over"; f++) {
      if (f % 60 === 0) { var d = Bugs.DIRS[Math.floor(Motion.rand({ s: f * 13 + 5 }) * 4)]; g.setDir(d.dx, d.dy) }
      g.step(1 / 240)
      if (f % 4 === 0) g.publish()
      if (g.phase !== "play") continue
      if (!Mazes.walkable(g.maze, Math.round(g.hero.x), Math.round(g.hero.y))) offTrace = "Byte at " + g.hero.x + "," + g.hero.y
      for (i = 0; i < g.bugs.length; i++) {
        var q = g.bugs[i]
        if ((q.state === "active" || q.state === "return") && !Mazes.walkable(g.maze, Math.round(q.x), Math.round(q.y)))
          offTrace = q.name + " at " + q.x + "," + q.y
      }
    }
    check("in a long random game nobody leaves the traces", offTrace === "", offTrace)
    check("a random game scores and the bugs catch Byte", g.score > 0 && g.lives < 3, g.score + " " + g.lives)

    // ---- new game and high score ---------------------------------------------------------------
    g.newGame(5)
    check("new game resets everything", g.level === 1 && g.lives === 3 && g.score === 0 && g.phase === "ready" && !g.armed
          && g.bitsLeft === total && g.patchTime === 0 && !g.coffeeOn && g.overclock === 0 && !g.extraGiven && g.mazeName === "Motherboard")
    g.highScore = 500
    g.addScore(500)
    check("a tie is not a new high score", !g.beatHigh && g.highScore === 500, g.beatHigh)
    g.addScore(10)
    check("beating the best is a new high score", g.beatHigh && g.highScore === 510, g.highScore)
    g.newGame(5)
    check("a new game clears the new-high-score flag", !g.beatHigh)

    // ---- HUD -------------------------------------------------------------------------------------
    play(g)
    g.lives = 3
    check("every life is drawn, not just the spares", g.livesView.count === 3, g.livesView.count)
    g.lives = 1
    check("down to one life, one icon is still drawn", g.livesView.count === 1, g.livesView.count)

    g.newGame(5)
    check("the title screen leads with the start key",
          g.hintText.text.indexOf("Space or an arrow to start") === 0, g.hintText.text)

    check("OVERCLOCK is legible, not low-contrast orange", g.overclockLabel.color == "#c0caf5", g.overclockLabel.color)

    // ---- drawing follows the model ----------------------------------------------------------------
    play(g)
    b = bug(g, "Null"); activate(b, 12.5, 7, -1, 0)
    place(g.hero, 7, 15, -1, 0)
    g.publish()
    var bv = g.bugView.itemAt(0)
    check("the drawn bug is where the bug is", !!bv && near(bv.x, 12.5 * g.tile) && near(bv.y, 7 * g.tile), bv ? bv.x + "," + bv.y : "no item")
    b.x = 14
    g.publish()
    check("the drawn bug moves when the bug does", near(g.bugView.itemAt(0).x, 14 * g.tile), g.bugView.itemAt(0).x)
    check("the drawn Byte is where Byte is", near(g.byteItem.x, 7 * g.tile) && near(g.byteItem.y, 15 * g.tile), g.byteItem.x)
    g.hero.x = 6.5
    g.publish()
    check("the drawn Byte moves when Byte does", near(g.byteItem.x, 6.5 * g.tile), g.byteItem.x)
    var pi = g.bitIndex[15 * 21 + 5]
    check("a bit is drawn on its tile", g.bitView.itemAt(pi).visible && near(g.bitView.itemAt(pi).x, 5 * g.tile))
    kill(g, 5, 15)
    check("an eaten bit disappears", !g.bitView.itemAt(pi).visible)

    // A squashed bug heading home is drawn as a flattened hollow shell, not as
    // floating eyes (review fix, for a look of our own).
    check("a live bug is drawn whole", !g.bugView.itemAt(0).home)
    b.state = "return"
    g.publish()
    check("a returning bug is drawn as its hollow shell, home-bound", g.bugView.itemAt(0).home
          && near(g.bugView.itemAt(0).x, 14 * g.tile), g.bugView.itemAt(0).x)
  }
}
