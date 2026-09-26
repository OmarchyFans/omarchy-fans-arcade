import QtQuick
import "mazes.js" as Mazes
import "bugs.js" as Bugs
import "motion.js" as Motion

// Circuit Crawl: the whole game. You are Byte, a small robot crawling the traces
// of a circuit board to collect every bit. Four bugs crawl after you (bugs.js).
// A debug chip patches them for a while: patched bugs turn around, slow down and
// can be squashed for 150, 300, 600 and 1200 (all four on one chip is a full
// debug, +900). Twice a board a coffee cup appears under the pen: it scores, and
// it overclocks Byte for a few seconds, so he outruns everything.
//
// The board is 21x21 tiles (mazes.js) drawn in a fixed 580x616 field scaled to
// the window. Every countdown lives in step(dt), which runs in fixed 1/240 s
// substeps; no Timer drives the game (the banner fade is the one exception).
//
// Controls: arrows or WASD steer (a turn is remembered until the next junction;
// reversing is instant). P or Space pauses, Esc quits, Enter starts over after a
// game over.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real fieldW: 580
  readonly property real fieldH: 616
  readonly property real hudH: 48
  readonly property real tile: 26
  readonly property real mazeX: (fieldW - 21 * tile) / 2
  readonly property real mazeY: hudH + 8
  readonly property int maxLives: 5
  // The famous original's bonus life lands at 10,000; ours is its own number.
  readonly property int extraLifeAt: 15000
  readonly property real hitRange: 0.6          // tiles between centres that count as a touch
  readonly property real readyDelay: 1.6        // seconds of READY before a life starts
  readonly property real dyingDelay: 1.6
  readonly property real clearDelay: 2.0
  readonly property real squashFreeze: 0.3      // the board holds still a moment on a squash
  readonly property real coffeeSeconds: 9
  readonly property real overclockSeconds: 4
  readonly property real overclockBoost: 1.35
  readonly property real returnSpeed: 13        // tiles/s: a squashed bug running home
  // Our own coffee-value table (the famous original's bonus-item values are
  // 100/300/500/700/1000/2000/3000/5000; ours climbs on a different curve).
  readonly property var coffeeValues: [90, 240, 420, 650, 950, 1500, 2300, 3400]

  // ---- state --------------------------------------------------------------------
  property string phase: "ready"               // ready | play | dying | clear | paused | over
  property string pausedFrom: ""
  property bool armed: false                   // the first READY waits for a key
  property real readyTime: 0
  property real dyingTime: 0
  property real clearTime: 0
  property real freezeTime: 0
  property int level: 1
  property int lives: 3
  property int score: 0
  property bool beatHigh: false
  property bool extraGiven: false
  property var maze: null                      // Mazes.parse() of the current board
  property int mazeRev: 0                      // bumps on every board load (repaints the walls)
  property string mazeName: ""
  property int bitsLeft: 0                     // bits and chips still on the board
  property int bitsTotal: 0
  property int eaten: 0
  property var hero: ({ x: 0, y: 0, dx: 0, dy: 0, ndx: 0, ndy: 0, fx: -1, fy: 0 })
  property var bugs: []                        // { name, color, fallback, x, y, dx, dy, state, patched, release }
  property string mode: "scatter"              // scatter | chase
  property int modeIndex: 0
  property real modeTime: 0
  property real patchTime: 0                   // > 0 while the bugs are patched
  property real patchTotal: 0
  property int chain: 0                        // squashes on the current chip
  property bool coffeeOn: false
  property real coffeeTime: 0
  property int coffeeValue: 0
  property int coffeeShown: 0
  property var coffeeAt: []                    // eaten-count thresholds for the two cups
  property real overclock: 0                   // seconds of speed boost left
  property var popups: []                      // { x, y, text, time }
  property string banner: ""
  property int seed: 1
  property var rng: ({ s: 1 })

  // Published once per frame for the drawing (see publish()).
  property real byteX: 0
  property real byteY: 0
  property int byteFx: -1
  property int byteFy: 0
  property real animT: 0
  property real animClock: 0
  property bool patchFlash: false              // patched bugs blink in the last two seconds
  property bool clearFlash: false
  property real dyingShown: 1
  property bool overclocked: false

  // Guarded against a theme with a hole or a null theme object (not verified
  // live: a defensive fix, not something the test suite alone can prove).
  function color(key, fallback) { return (theme && theme[key]) || fallback }
  function rand() { return Motion.rand(rng) }
  function setSeed(n) { seed = n | 0; rng.s = n | 0 }

  // ---- speeds --------------------------------------------------------------------
  // Bug fix (difficulty curve): bugSpeed() used to grow faster and cap higher
  // than heroSpeed(), so from level 7 on the bugs were quicker than Byte and
  // stayed that way. Same growth rate and cap as Byte now, just a lower base
  // (6.0 vs 6.5), so Byte is always a little ahead, level after level.
  function heroSpeed() { return 6.5 * Math.min(1 + 0.05 * (level - 1), 1.3) * (overclock > 0 ? overclockBoost : 1) }
  function bugSpeed() { return 6.0 * Math.min(1 + 0.05 * (level - 1), 1.3) }
  function inTunnel(b) {
    return maze.rows[Math.round(b.y)].indexOf("T") >= 0
        && (b.x < 3.5 || b.x > maze.w - 4.5)
  }
  function speedOf(b) {
    switch (b.state) {
    case "return": case "enter": return returnSpeed
    case "leave": return bugSpeed() * 0.6 * (b.patched ? 0.6 : 1)
    case "active": return bugSpeed() * (b.patched ? 0.55 : 1) * (inTunnel(b) ? 0.5 : 1)
    }
    return 0
  }
  function coffeeValueFor(lv) { return coffeeValues[Math.min(lv, coffeeValues.length) - 1] }

  // ---- Byte's own color: a small hue guard --------------------------------------
  // Byte's shape (a rounded-square robot with a visor, antenna and treads) is
  // already distinct from a wedge-with-a-mouth hero, but a theme whose accent is
  // yellow would still tint him yellow by pure coincidence. Nudge only that band
  // toward blue so no theme accidentally recreates the famous look; every other
  // accent colour passes through untouched.
  readonly property real yellowHueLo: 40
  readonly property real yellowHueHi: 70
  function hexToHsl(hex) {
    var h = ("" + hex).replace("#", "")
    if (h.length === 3) h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2]
    var r = parseInt(h.substr(0, 2), 16) / 255, g = parseInt(h.substr(2, 2), 16) / 255, b = parseInt(h.substr(4, 2), 16) / 255
    var max = Math.max(r, g, b), min = Math.min(r, g, b)
    var l = (max + min) / 2, d = max - min, hue = 0, s = 0
    if (d !== 0) {
      s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
      if (max === r) hue = ((g - b) / d + (g < b ? 6 : 0))
      else if (max === g) hue = (b - r) / d + 2
      else hue = (r - g) / d + 4
      hue *= 60
    }
    return { h: hue, s: s, l: l }
  }
  function hueToRgbChannel(p, q, t) {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  function hslToHex(h, s, l) {
    var hn = (((h % 360) + 360) % 360) / 360
    var r, g, b
    if (s === 0) { r = g = b = l }
    else {
      var q = l < 0.5 ? l * (1 + s) : l + s - l * s
      var p = 2 * l - q
      r = hueToRgbChannel(p, q, hn + 1 / 3); g = hueToRgbChannel(p, q, hn); b = hueToRgbChannel(p, q, hn - 1 / 3)
    }
    function toHex(x) { var v = Math.round(x * 255); return (v < 16 ? "0" : "") + v.toString(16) }
    return "#" + toHex(r) + toHex(g) + toHex(b)
  }
  // The colour Byte is actually drawn in: the theme's accent, unless its hue
  // falls in the classic-hero yellow band, in which case it's rotated to blue.
  function heroColor() {
    var hex = color("accent", "#7aa2f7")
    if (!/^#[0-9a-fA-F]{6}$/.test(hex)) return hex
    var hsl = hexToHsl(hex)
    if (hsl.h >= yellowHueLo && hsl.h <= yellowHueHi && hsl.s > 0.2) return hslToHex(210, hsl.s, hsl.l)
    return hex
  }

  // ---- drawing accessors (rule 5: never hold an element in a delegate) ------------
  readonly property var offField: ({ x: -9, y: -9, dx: 0, dy: 0, state: "pen", patched: false, color: "red", fallback: "#f7768e", text: "", time: 0, name: "" })
  function bugAt(i) { return bugs[i] || offField }
  function popupAt(i) { return popups[i] || offField }
  function publish() {
    bugs = bugs.slice()
    popups = popups.slice()
    byteX = hero.x; byteY = hero.y; byteFx = hero.fx; byteFy = hero.fy
    animT = animClock
    patchFlash = patchTime > 0 && patchTime < 2 && Math.floor(patchTime * 6) % 2 === 0
    clearFlash = phase === "clear" && Math.floor(clearTime * 5) % 2 === 0
    dyingShown = phase === "dying" ? Math.max(0, dyingTime / dyingDelay) : 1
    overclocked = overclock > 0
  }
  function flash(text) { banner = text; bannerTimer.restart() }

  ListModel { id: bitList }                    // { c, r, kind: "bit"|"chip", alive }
  property var bitIndex: ({})               // tile key -> model index
  readonly property alias bitModel: bitList
  readonly property alias bugView: bugView
  readonly property alias bitView: bitView
  readonly property alias byteItem: byteItem

  // ---- boards and lives ------------------------------------------------------------
  function loadLevel() {
    var def = Mazes.forLevel(level)
    maze = Mazes.parse(Mazes.expand(def.half))
    mazeName = def.name
    bitList.clear()
    var idx = {}, n = 0
    for (var r = 0; r < maze.h; r++)
      for (var c = 0; c < maze.w; c++) {
        var ch = maze.rows[r].charAt(c)
        if (ch !== "." && ch !== "o") continue
        idx[r * maze.w + c] = bitList.count
        bitList.append({ c: c, r: r, kind: ch === "o" ? "chip" : "bit", alive: true })
        n++
      }
    bitIndex = idx
    bitsLeft = n; bitsTotal = n; eaten = 0
    coffeeShown = 0
    coffeeAt = [Math.round(n * 0.3), Math.round(n * 0.7)]
    mazeRev++
    resetActors()
  }

  // Byte back at the start, Null outside the door, the others in the pen.
  function resetActors() {
    hero = { x: maze.start.c, y: maze.start.r, dx: -1, dy: 0, ndx: 0, ndy: 0, fx: -1, fy: 0 }
    var list = []
    for (var i = 0; i < Bugs.DEFS.length; i++) {
      var d = Bugs.DEFS[i]
      var b = { name: d.name, color: d.color, fallback: d.fallback, patched: false, dx: 0, dy: 0 }
      if (d.home === "outside") { b.x = maze.exit.c; b.y = maze.exit.r; b.dx = -1; b.state = "active"; b.release = 0 }
      else { b.x = maze.door.c + d.home; b.y = maze.penCenter.r; b.state = "pen"; b.release = Bugs.releaseSeconds(d, level) }
      list.push(b)
    }
    bugs = list
    patchTime = 0; chain = 0; freezeTime = 0
    modeIndex = 0; mode = "scatter"; modeTime = Bugs.schedule(level)[0]
    coffeeOn = false; overclock = 0
    popups = []
    publish()
  }

  function getReady() { phase = "ready"; readyTime = readyDelay }

  function newGame(seedValue) {
    setSeed(seedValue === undefined ? Date.now() % 2147483647 : seedValue)
    level = 1; lives = 3; score = 0; beatHigh = false; extraGiven = false
    banner = ""
    loadLevel()
    getReady()
    armed = false
  }
  function arm() { if (phase === "ready") armed = true }

  function addScore(points) {
    score += points
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
    if (!extraGiven && score >= extraLifeAt) {
      extraGiven = true
      lives = Math.min(lives + 1, maxLives)
      flash("Extra life!")
    }
  }

  function popup(x, y, text) { popups.push({ x: x, y: y, text: text, time: 1.0 }) }

  function die() {
    phase = "dying"
    dyingTime = dyingDelay
    hero.ndx = 0; hero.ndy = 0
  }
  function afterDeath() {
    lives--
    if (lives <= 0) { phase = "over"; banner = ""; coffeeOn = false; return }
    resetActors()
    flash(lives === 1 ? "Last life!" : lives + " lives left")
    getReady()
  }

  function boardClear() {
    phase = "clear"
    clearTime = clearDelay
    coffeeOn = false
    endPatch()          // no grey, half-patched bugs hanging about on the flash
  }
  function nextLevel() {
    level++
    loadLevel()
    flash("Level " + level + " · " + mazeName)
    getReady()
  }

  // ---- pause -------------------------------------------------------------------
  function pause() {
    if (phase !== "play" && phase !== "ready" && phase !== "dying" && phase !== "clear") return
    pausedFrom = phase
    phase = "paused"
  }
  function resume() {
    if (phase !== "paused") return
    phase = pausedFrom || "play"
  }
  function togglePause() { if (phase === "paused") resume(); else pause() }

  // Key releases don't arrive while away, and a turn buffered before leaving
  // shouldn't fire on return.
  function lostFocus() {
    hero.ndx = 0; hero.ndy = 0
    pause()
  }

  // ---- Byte ----------------------------------------------------------------------
  // A new direction is remembered and taken at the next tile centre where it is
  // open; the opposite direction is taken at once, anywhere.
  function setDir(dx, dy) {
    if (phase === "ready") arm()
    if (phase === "over" || phase === "paused") return
    hero.ndx = dx; hero.ndy = dy
    if ((hero.dx !== 0 || hero.dy !== 0) && dx === -hero.dx && dy === -hero.dy) {
      hero.dx = dx; hero.dy = dy; hero.fx = dx; hero.fy = dy
      hero.ndx = 0; hero.ndy = 0
    }
  }

  function heroDecide(a) {
    if ((a.ndx !== 0 || a.ndy !== 0) && Mazes.walkable(maze, a.x + a.ndx, a.y + a.ndy)) {
      a.dx = a.ndx; a.dy = a.ndy; a.ndx = 0; a.ndy = 0
    } else if ((a.dx !== 0 || a.dy !== 0) && !Mazes.walkable(maze, a.x + a.dx, a.y + a.dy)) {
      a.dx = 0; a.dy = 0
    }
    if (a.dx !== 0 || a.dy !== 0) { a.fx = a.dx; a.fy = a.dy }
  }

  // A reused object (never held past the call that reads it): heroTile() used to
  // allocate fresh every call, and it's read every physics substep from eat() and
  // at every bug decision, so mutating one cache in place avoids that hot-loop
  // churn.
  property var heroTileCache: ({ c: 0, r: 0, fx: -1, fy: 0 })
  function heroTile() {
    var t = heroTileCache
    t.c = Mazes.wrapCol(maze, Math.round(hero.x)); t.r = Math.round(hero.y)
    t.fx = hero.fx; t.fy = hero.fy
    return t
  }

  // Byte eats what is on the tile under him once he is near its centre.
  function eat() {
    if (Math.abs(hero.x - Math.round(hero.x)) > 0.3 || Math.abs(hero.y - Math.round(hero.y)) > 0.3) return
    var t = heroTile()
    var i = bitIndex[t.r * maze.w + t.c]
    if (i === undefined || !bitList.get(i).alive) return
    var kind = bitList.get(i).kind
    bitList.setProperty(i, "alive", false)
    bitsLeft--
    eaten++
    // Our own points per pickup: the famous original's are 10 for a plain dot
    // and 50 for a power item; ours are 12 and 60.
    if (kind === "chip") { addScore(60); startPatch() }
    else addScore(12)
    if (coffeeShown < coffeeAt.length && eaten >= coffeeAt[coffeeShown]) {
      coffeeShown++
      coffeeOn = true
      coffeeTime = coffeeSeconds
      coffeeValue = coffeeValueFor(level)
    }
    if (bitsLeft <= 0) boardClear()
  }

  // Coffee: points, and an overclock (Byte runs faster for a few seconds).
  function drinkCoffee() {
    coffeeOn = false
    addScore(coffeeValue)
    overclock = overclockSeconds
    popup(maze.coffee.c, maze.coffee.r, "" + coffeeValue)
    flash("Overclocked!")
  }

  // ---- bugs ----------------------------------------------------------------------
  function startPatch() {
    patchTotal = Bugs.patchSeconds(level)
    patchTime = patchTotal
    chain = 0
    for (var i = 0; i < bugs.length; i++) {
      var b = bugs[i]
      if (b.state === "return" || b.state === "enter") continue
      b.patched = true
      if (b.state === "active") {
        b.dx = -b.dx; b.dy = -b.dy
        holdReversal(b)
      }
    }
  }
  // Bug fix: a forced reversal (patch or scatter/chase switch) used to be
  // silently undone when a bug was exactly at a tile centre, because the very
  // next decide() (in the same frame) would re-pick a direction at that
  // junction and could choose something other than the reversal. Holding the
  // flip for one decide() makes the reversal always take effect, as intended.
  function holdReversal(b) {
    if (Motion.atCenter(b) && Mazes.walkable(maze, b.x + b.dx, b.y + b.dy)) b.holdDir = true
  }
  function endPatch() {
    patchTime = 0
    for (var i = 0; i < bugs.length; i++) bugs[i].patched = false
  }

  function squash(b) {
    var pts = Bugs.squashPoints(chain)
    chain++
    addScore(pts)
    popup(b.x, b.y, "" + pts)
    b.patched = false
    b.state = "return"
    freezeTime = squashFreeze
    if (chain === 4) { addScore(Bugs.ALL_FOUR_BONUS); flash("Full debug! +" + Bugs.ALL_FOUR_BONUS) }
  }

  // Directions a bug at a tile centre may take: open tiles, never straight back
  // unless it is a dead end.
  function bugOptions(b) {
    var back = Bugs.reverseOf(Bugs.dirIndex(b.dx, b.dy)), opts = []
    for (var d = 0; d < 4; d++) {
      if (d === back) continue
      if (Mazes.walkable(maze, b.x + Bugs.DIRS[d].dx, b.y + Bugs.DIRS[d].dy)) opts.push(d)
    }
    if (opts.length === 0 && back >= 0 && Mazes.walkable(maze, b.x + Bugs.DIRS[back].dx, b.y + Bugs.DIRS[back].dy)) opts.push(back)
    return opts
  }

  function setBugDir(b, d) {
    if (d < 0) { b.dx = 0; b.dy = 0; return }
    b.dx = Bugs.DIRS[d].dx; b.dy = Bugs.DIRS[d].dy
  }

  function bugDecide(b) {
    if (b.holdDir) { b.holdDir = false; return }         // a just-forced reversal stands as-is
    var here = { c: Mazes.wrapCol(maze, b.x), r: b.y }
    if (b.state === "return") {
      if (here.c === maze.exit.c && here.r === maze.exit.r) { b.state = "enter"; b.dx = 0; b.dy = 0; return }
      setBugDir(b, Mazes.stepToward(maze, here, maze.exit))
      return
    }
    var opts = bugOptions(b)
    if (opts.length === 0) { setBugDir(b, -1); return }
    var target = b.patched ? null : Bugs.targetFor(b.name, here, heroTile(), mode, maze.w, maze.h)
    var pick
    if (target === null) pick = opts.length === 1 ? opts[0] : opts[Math.floor(rand() * opts.length)]
    else pick = Bugs.chooseDir(opts, here, target, maze.w)
    setBugDir(b, pick)
  }

  // Scripted moves through the door: x first, then y. True once there.
  function scriptMove(b, tx, ty, d) {
    if (Math.abs(b.x - tx) > 1e-6) {
      var sx = tx > b.x ? 1 : -1
      b.x += sx * Math.min(d, Math.abs(tx - b.x)); b.dx = sx; b.dy = 0
      return false
    }
    b.x = tx
    if (Math.abs(b.y - ty) > 1e-6) {
      var sy = ty > b.y ? 1 : -1
      b.y += sy * Math.min(d, Math.abs(ty - b.y)); b.dx = 0; b.dy = sy
      return false
    }
    b.y = ty
    return true
  }

  function bugStep(b, dt) {
    var d = speedOf(b) * dt
    switch (b.state) {
    case "pen":
      b.release -= dt
      if (b.release <= 0) b.state = "leave"
      return
    case "leave":
      if (scriptMove(b, maze.exit.c, maze.exit.r, d)) { b.state = "active"; b.dx = -1; b.dy = 0 }
      return
    case "enter":
      if (scriptMove(b, maze.penCenter.c, maze.penCenter.r, d)) { b.state = "pen"; b.release = 0.6; b.dx = 0; b.dy = 0 }
      return
    case "active": case "return":
      Motion.advance(b, d, maze.w, bugDecide)
      return
    }
  }

  // Scatter and chase take turns; a switch turns every free bug around.
  function modeTick(dt) {
    var sched = Bugs.schedule(level)
    if (modeIndex >= sched.length) return
    modeTime -= dt
    if (modeTime > 0) return
    modeIndex++
    mode = modeIndex % 2 === 0 ? "scatter" : "chase"
    modeTime = modeIndex < sched.length ? sched[modeIndex] : 0
    for (var i = 0; i < bugs.length; i++)
      if (bugs[i].state === "active" && !bugs[i].patched) {
        bugs[i].dx = -bugs[i].dx; bugs[i].dy = -bugs[i].dy
        holdReversal(bugs[i])
      }
  }

  function collide() {
    for (var i = 0; i < bugs.length; i++) {
      var b = bugs[i]
      var out = b.state === "active" || (b.state === "leave" && b.y <= maze.door.r)
      if (!out || Motion.dist(hero, b, maze.w) >= hitRange) continue
      if (b.patched) squash(b)
      else { die(); return }
    }
  }

  // ---- the step -------------------------------------------------------------------
  function step(dt) {
    animClock += dt
    for (var p = popups.length - 1; p >= 0; p--) {
      popups[p].time -= dt
      if (popups[p].time <= 0) popups.splice(p, 1)
    }
    switch (phase) {
    case "ready":
      if (!armed) return
      readyTime -= dt
      if (readyTime <= 0) phase = "play"
      return
    case "dying":
      dyingTime -= dt
      if (dyingTime <= 0) afterDeath()
      return
    case "clear":
      clearTime -= dt
      if (clearTime <= 0) nextLevel()
      return
    case "play":
      break
    default:
      return
    }
    if (freezeTime > 0) { freezeTime -= dt; return }

    if (patchTime > 0) { patchTime -= dt; if (patchTime <= 0) endPatch() }
    else modeTick(dt)
    if (overclock > 0) overclock = Math.max(0, overclock - dt)
    if (coffeeOn) { coffeeTime -= dt; if (coffeeTime <= 0) coffeeOn = false }

    Motion.advance(hero, heroSpeed() * dt, maze.w, heroDecide)
    eat()
    if (phase !== "play") return
    // Inlined rather than Motion.dist(hero, {x:..,y:..}) so this per-substep
    // check (every 1/240 s while coffee is out) doesn't allocate a point object.
    if (coffeeOn && Math.hypot(hero.x - maze.coffee.c, hero.y - maze.coffee.r) < hitRange) drinkCoffee()

    collide()
    if (phase !== "play") return
    for (var i = 0; i < bugs.length; i++) bugStep(bugs[i], dt)
    collide()
  }

  FrameAnimation {
    running: game.phase === "play" || game.phase === "ready" || game.phase === "dying" || game.phase === "clear"
    onTriggered: {
      var dt = Math.min(frameTime, 1 / 30)
      var n = Math.ceil(dt / (1 / 240))
      for (var i = 0; i < n; i++) game.step(dt / n)
      game.publish()
    }
  }

  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }

  Keys.onPressed: function (e) {
    // Key repeats are ignored: a held arrow repeating would overwrite a turn
    // tapped since, and a buffered turn waits for its junction anyway.
    if (e.isAutoRepeat) { e.accepted = true; return }
    var dir = null
    switch (e.key) {
    case Qt.Key_Up: case Qt.Key_W: dir = [0, -1]; break
    case Qt.Key_Down: case Qt.Key_S: dir = [0, 1]; break
    case Qt.Key_Left: case Qt.Key_A: dir = [-1, 0]; break
    case Qt.Key_Right: case Qt.Key_D: dir = [1, 0]; break
    }
    if (dir) { setDir(dir[0], dir[1]); e.accepted = true; return }
    switch (e.key) {
    case Qt.Key_Space:
      if (phase === "ready" && !armed) arm(); else togglePause()
      break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter:
      if (phase === "over") newGame(); else if (phase === "ready") arm(); else if (phase === "paused") resume()
      break
    case Qt.Key_Escape: quitRequested(); break
    default: return
    }
    e.accepted = true
  }

  Component.onCompleted: newGame()

  // ---- drawing --------------------------------------------------------------------
  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)

    Rectangle { anchors.fill: parent; color: game.color("dark_background", "#13141c"); radius: 6 }

    // HUD
    Rectangle {
      width: parent.width; height: game.hudH
      color: game.color("lighter_background", "#24283b")
      radius: 6
      Column {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.leftMargin: 14
        Text { text: "SCORE " + game.score; color: game.color("bright_foreground", "#c0caf5"); font.pixelSize: 16; font.bold: true; font.family: "monospace" }
        Text { text: "HIGH  " + game.highScore; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 13; font.family: "monospace" }
      }
      Column {
        anchors.centerIn: parent
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "LEVEL " + game.level
          color: game.color("accent", "#7aa2f7"); font.pixelSize: 15; font.bold: true; font.family: "monospace"
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: game.mazeName.toUpperCase()
          color: game.color("foreground", "#a9b1d6"); font.pixelSize: 11; font.family: "monospace"
        }
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 14
        spacing: 6
        Text {
          visible: game.overclocked
          anchors.verticalCenter: parent.verticalCenter
          text: "OVERCLOCK"
          color: game.color("orange", "#ff9e64")
          font.pixelSize: 12; font.bold: true; font.family: "monospace"
          rightPadding: 6
        }
        // Spare lives, as little Byte heads.
        Repeater {
          model: Math.max(0, game.lives - 1)
          delegate: Rectangle {
            width: 14; height: 12; radius: 3
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            color: game.heroColor()
            Rectangle { x: 3; y: 3; width: 8; height: 3; radius: 1.5; color: game.color("dark_background", "#13141c") }
          }
        }
      }
    }

    // The board. Actors near the tunnel mouths are clipped at its edge.
    Item {
      id: board
      x: game.mazeX; y: game.mazeY
      width: 21 * game.tile; height: 21 * game.tile
      clip: true

      // Walls: solder-mask blocks with copper traces along their edges, pads at
      // the trace ends and joints, and vias dotted through the solid areas.
      Canvas {
        id: walls
        anchors.fill: parent
        property int rev: game.mazeRev
        property var th: game.theme
        property bool fl: game.clearFlash
        onRevChanged: requestPaint()
        onThChanged: requestPaint()
        onFlChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var m = game.maze
          if (!m) return
          var t = game.tile, ins = 4
          var mask = game.color("lighter_background", "#24283b")
          var trace = game.clearFlash ? game.color("bright_foreground", "#c0caf5") : game.color("cyan", "#7dcfff")
          var hole = game.color("dark_background", "#13141c")
          function wall(c, r) { return c >= 0 && c < m.w && r >= 0 && r < m.h && m.rows[r].charAt(c) === "#" }
          function open(c, r) { return c >= 0 && c < m.w && r >= 0 && r < m.h && m.rows[r].charAt(c) !== "#" }
          function edge(c, r) {
            if (!wall(c, r)) return false
            for (var dr = -1; dr <= 1; dr++) for (var dc = -1; dc <= 1; dc++) if (open(c + dc, r + dr)) return true
            return false
          }
          var r, c
          ctx.fillStyle = mask
          for (r = 0; r < m.h; r++)
            for (c = 0; c < m.w; c++) {
              if (!wall(c, r)) continue
              var x0 = c * t + (wall(c - 1, r) || c === 0 ? 0 : ins), x1 = (c + 1) * t - (wall(c + 1, r) || c === m.w - 1 ? 0 : ins)
              var y0 = r * t + (wall(c, r - 1) || r === 0 ? 0 : ins), y1 = (r + 1) * t - (wall(c, r + 1) || r === m.h - 1 ? 0 : ins)
              ctx.fillRect(x0, y0, x1 - x0, y1 - y0)
            }
          // Traces between neighbouring edge tiles.
          ctx.strokeStyle = trace
          ctx.lineWidth = 2
          ctx.globalAlpha = 0.8
          ctx.beginPath()
          for (r = 0; r < m.h; r++)
            for (c = 0; c < m.w; c++) {
              if (!edge(c, r)) continue
              var cx = c * t + t / 2, cy = r * t + t / 2
              if (edge(c + 1, r)) { ctx.moveTo(cx, cy); ctx.lineTo(cx + t, cy) }
              if (edge(c, r + 1)) { ctx.moveTo(cx, cy); ctx.lineTo(cx, cy + t) }
            }
          ctx.stroke()
          // Pads where a trace ends or branches; vias in the solid areas.
          ctx.globalAlpha = 1
          for (r = 0; r < m.h; r++)
            for (c = 0; c < m.w; c++) {
              if (!wall(c, r)) continue
              var px = c * t + t / 2, py = r * t + t / 2
              if (edge(c, r)) {
                var deg = (edge(c + 1, r) ? 1 : 0) + (edge(c - 1, r) ? 1 : 0) + (edge(c, r + 1) ? 1 : 0) + (edge(c, r - 1) ? 1 : 0)
                var straight = (edge(c + 1, r) && edge(c - 1, r)) || (edge(c, r + 1) && edge(c, r - 1))
                if (deg === 2 && straight) continue
                ctx.fillStyle = trace
                ctx.beginPath(); ctx.arc(px, py, 4, 0, Math.PI * 2); ctx.fill()
                ctx.fillStyle = hole
                ctx.beginPath(); ctx.arc(px, py, 1.6, 0, Math.PI * 2); ctx.fill()
              } else if ((c * 7 + r * 3) % 5 === 0) {
                ctx.globalAlpha = 0.35
                ctx.fillStyle = trace
                ctx.beginPath(); ctx.arc(px, py, 2.2, 0, Math.PI * 2); ctx.fill()
                ctx.globalAlpha = 1
              }
            }
          // The pen door: a dashed bar only the bugs cross.
          ctx.fillStyle = game.color("magenta", "#bb9af7")
          for (r = 0; r < m.h; r++)
            for (c = 0; c < m.w; c++)
              if (m.rows[r].charAt(c) === "-")
                for (var k = 0; k < 4; k++) ctx.fillRect(c * t + 1 + k * 6.5, r * t + t / 2 - 1.5, 4, 3)
        }
      }

      // Bits (tiny squares) and debug chips (little ICs with legs).
      Repeater {
        id: bitView
        model: bitList
        delegate: Item {
          required property int c
          required property int r
          required property string kind
          required property bool alive
          visible: alive
          x: c * game.tile; y: r * game.tile
          width: game.tile; height: game.tile
          Rectangle {
            visible: kind === "bit"
            anchors.centerIn: parent
            width: 4; height: 4
            color: game.color("foreground", "#a9b1d6")
          }
          Item {
            visible: kind === "chip"
            anchors.centerIn: parent
            width: 14; height: 14
            Repeater {
              model: 6
              delegate: Rectangle {
                required property int index
                x: 3 + (index % 3) * 3.5; y: index < 3 ? 0 : 11
                width: 1.6; height: 3
                color: game.color("bright_foreground", "#c0caf5")
              }
            }
            Rectangle {
              x: 1; y: 2.5; width: 12; height: 9; radius: 1.5
              color: game.color("foreground", "#a9b1d6")
              Rectangle { x: 2; y: 2; width: 2.5; height: 2.5; radius: 1.25; color: game.color("dark_background", "#13141c") }
              // Its status LED pulses; the chip itself stays put.
              Rectangle {
                x: 7.5; y: 5; width: 2.5; height: 2.5; radius: 1.25
                color: game.color("green", "#9ece6a")
                opacity: 0.4 + 0.6 * Math.abs(Math.sin(game.animT * 3))
              }
            }
          }
        }
      }

      // Coffee: a mug with steam.
      Item {
        id: coffeeItem
        visible: game.coffeeOn && !!game.maze && !!game.maze.coffee
        x: game.maze && game.maze.coffee ? game.maze.coffee.c * game.tile : 0
        y: game.maze && game.maze.coffee ? game.maze.coffee.r * game.tile : 0
        width: game.tile; height: game.tile
        Repeater {
          model: 2
          delegate: Rectangle {
            required property int index
            x: 9 + index * 5 + Math.sin(game.animT * 4 + index) * 1.2
            y: 2; width: 1.6; height: 6; radius: 0.8
            color: game.color("foreground", "#a9b1d6")
            opacity: 0.6
          }
        }
        Rectangle {
          x: 6; y: 9; width: 12; height: 12; radius: 2
          color: game.color("orange", "#ff9e64")
          Rectangle { x: 2; y: 2; width: 8; height: 2; color: game.color("dark_background", "#13141c"); opacity: 0.5 }
        }
        Rectangle {
          x: 17; y: 11; width: 5; height: 7; radius: 2.5
          color: "transparent"; border.width: 2; border.color: game.color("orange", "#ff9e64")
        }
      }

      // The bugs: round bodies, six legs, two antennae. Patched bugs go grey with a
      // plaster across the back and blink near the end; a squashed bug crawls home
      // flattened, as a hollow outline of its shell with no legs or eyes.
      Repeater {
        id: bugView
        model: game.bugs.length
        delegate: Item {
          id: bugItem
          required property int index
          readonly property string st: game.bugAt(index).state
          readonly property bool patched: game.bugAt(index).patched
          readonly property int ddx: game.bugAt(index).dx
          readonly property int ddy: game.bugAt(index).dy
          readonly property color base: game.color(game.bugAt(index).color, game.bugAt(index).fallback)
          readonly property color bodyColor: patched ? (game.patchFlash ? game.color("bright_foreground", "#c0caf5") : game.color("lighter_background", "#414868")) : base
          readonly property bool home: st === "return" || st === "enter"
          x: game.bugAt(index).x * game.tile
          y: game.bugAt(index).y * game.tile + (st === "pen" ? Math.sin(game.animT * 5 + index) * 2.5 : 0)
          width: game.tile; height: game.tile
          visible: game.phase !== "dying" || game.dyingShown > 0.75

          // Legs, three a side, scuttling.
          Repeater {
            model: bugItem.home ? 0 : 6
            delegate: Rectangle {
              required property int index
              readonly property bool onRight: index >= 3
              x: onRight ? 17 : 2; y: 8 + (index % 3) * 4.5
              width: 7; height: 2; radius: 1
              color: Qt.darker(bugItem.bodyColor, 1.5)
              rotation: (onRight ? 1 : -1) * ((index % 3) - 1) * 25 + Math.sin(game.animT * 22 + index) * 12
            }
          }
          // Antennae
          Repeater {
            model: 2
            delegate: Item {
              required property int index
              x: index === 0 ? 9 : 17; y: 5
              rotation: index === 0 ? -30 : 30
              opacity: bugItem.home ? 0.6 : 1
              Rectangle { x: -0.75; y: -5; width: 1.5; height: 6; color: Qt.darker(bugItem.bodyColor, 1.3) }
              Rectangle { x: -1.75; y: -7; width: 3.5; height: 3.5; radius: 1.75; color: bugItem.bodyColor }
            }
          }
          // Body
          Rectangle {
            x: bugItem.home ? 3 : 5; y: bugItem.home ? 10 : 5
            width: bugItem.home ? 20 : 16; height: bugItem.home ? 9 : 17
            radius: bugItem.home ? 4.5 : 8
            color: bugItem.home ? "transparent" : bugItem.bodyColor
            border.width: bugItem.home ? 1.5 : (bugItem.patched ? 1 : 0)
            border.color: bugItem.home ? bugItem.base : game.color("foreground", "#a9b1d6")
            opacity: bugItem.home ? 0.75 : 1
            // A seam down the shell.
            Rectangle { visible: !bugItem.home; x: 7.5; y: 4; width: 1; height: 12; color: Qt.darker(bugItem.bodyColor, 1.35) }
            // The patch: a plaster across the back.
            Rectangle {
              visible: bugItem.patched
              anchors.centerIn: parent
              anchors.verticalCenterOffset: 2
              width: 14; height: 4; radius: 1
              rotation: -30
              color: game.color("foreground", "#a9b1d6")
            }
          }
          // Eyes look the way the bug is going (a flattened bug heading home has none).
          Repeater {
            model: bugItem.home ? 0 : 2
            delegate: Rectangle {
              required property int index
              x: (index === 0 ? 8 : 14) + bugItem.ddx * 1.5
              y: 8 + bugItem.ddy * 1.5
              width: 5; height: 5; radius: 2.5
              color: game.color("bright_foreground", "#c0caf5")
              Rectangle {
                x: 1.5 + bugItem.ddx * 1.2; y: 1.5 + bugItem.ddy * 1.2
                width: 2; height: 2; radius: 1
                color: game.color("dark_background", "#13141c")
              }
            }
          }
        }
      }

      // Byte: a rounded-square robot with a visor and an antenna.
      Item {
        id: byteItem
        x: game.byteX * game.tile; y: game.byteY * game.tile
        width: game.tile; height: game.tile
        visible: game.phase !== "over"
        readonly property color body: game.heroColor()
        readonly property bool rolling: game.phase === "play"
        scale: game.dyingShown
        rotation: game.phase === "dying" ? (1 - game.dyingShown) * 540 : 0
        // Antenna and its blinking tip.
        Rectangle { x: 12; y: 1; width: 2; height: 6; color: Qt.darker(byteItem.body, 1.3) }
        Rectangle {
          x: 10.5; y: -0.5; width: 5; height: 5; radius: 2.5
          color: game.overclocked ? game.color("orange", "#ff9e64")
               : (Math.floor(game.animT * 2) % 2 === 0 ? game.color("bright_foreground", "#c0caf5") : byteItem.body)
        }
        // Treads
        Rectangle {
          x: 3; y: 19 + (byteItem.rolling && Math.floor(game.animT * 16) % 2 === 0 ? 0.6 : 0)
          width: 7; height: 5; radius: 1.5
          color: game.color("foreground", "#a9b1d6")
        }
        Rectangle {
          x: 16; y: 19 + (byteItem.rolling && Math.floor(game.animT * 16) % 2 === 1 ? 0.6 : 0)
          width: 7; height: 5; radius: 1.5
          color: game.color("foreground", "#a9b1d6")
        }
        // Body
        Rectangle {
          x: 4; y: 6; width: 18; height: 15; radius: 5
          color: byteItem.body
          border.width: 1
          border.color: Qt.darker(byteItem.body, 1.4)
          // Visor, turned the way Byte faces.
          Rectangle {
            x: 3 + game.byteFx * 2; y: 3 + game.byteFy * 1.5
            width: 12; height: 6; radius: 3
            color: game.color("dark_background", "#13141c")
            Rectangle {
              x: 3 + game.byteFx * 2.5; y: 2 + game.byteFy * 1
              width: 6; height: 2; radius: 1
              color: game.overclocked ? game.color("orange", "#ff9e64") : game.color("cyan", "#7dcfff")
            }
          }
          // A little speaker grille.
          Rectangle { x: 6; y: 11; width: 6; height: 1.4; color: Qt.darker(byteItem.body, 1.5) }
        }
      }

      // Points that float up where they were scored.
      Repeater {
        model: game.popups.length
        delegate: Text {
          required property int index
          x: game.popupAt(index).x * game.tile + game.tile / 2 - width / 2
          y: game.popupAt(index).y * game.tile - (1 - game.popupAt(index).time) * 14
          text: game.popupAt(index).text
          color: game.color("bright_foreground", "#c0caf5")
          font.pixelSize: 12; font.bold: true; font.family: "monospace"
        }
      }
    }

    // Messages. Paused and game-over messages get a backdrop.
    Rectangle {
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 28
      radius: 8
      visible: game.phase === "paused" || game.phase === "over" || (game.phase === "ready" && !game.armed)
      color: game.color("dark_background", "#13141c")
      opacity: 0.92
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.centerIn: parent
      anchors.verticalCenterOffset: 36
      spacing: 8
      visible: title.text !== ""
      Text {
        id: title
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : game.phase === "ready" && !game.armed ? "CIRCUIT CRAWL"
            : game.phase === "clear" ? "BOARD CLEAR"
            : game.banner !== "" ? game.banner
            : game.phase === "ready" ? "READY" : ""
        color: game.color("bright_foreground", "#c0caf5")
        font.pixelSize: game.phase === "ready" && game.armed ? 26 : 34; font.bold: true; font.family: "monospace"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "Score " + game.score + (game.beatHigh ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "ready" && !game.armed ? "Arrows or WASD to crawl  ·  P pause\nCollect every bit. Debug chips make bugs squashable.\nCoffee overclocks you."
            : game.phase === "ready" && game.banner !== "" ? "READY" : ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 14; font.family: "monospace"
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: {
        game.forceActiveFocus()
        if (game.phase === "over") game.newGame()
        else if (game.phase === "ready") game.arm()
        else if (game.phase === "paused") game.resume()
      }
    }
  }
}
