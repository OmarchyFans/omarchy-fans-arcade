import QtQuick
import "lanes.js" as Lanes

// Dockhop: the whole game. A courier bot hops tile by tile across a warehouse:
// first the traffic floor (carts, sweepers, forklifts, tug trains), then the
// drop shaft, where it must ride hover pallets and flicker pads, to park in one
// of the four dock bays in the wall at the top. Park in all four to clear the
// shift. It plays in a fixed 780x752 field scaled to fit the window.
//
// Controls: arrows or WASD hop one tile. Space (or Enter) boosts: a two-tile leap in the
// direction you last hopped that sails over whatever is in the tile between
// (two charges, one comes back every 6 s). P pauses, Esc quits, Enter starts
// over after a game over.
//
// Parcels: now and then a parcel turns up on the loading strip. Pick it up and
// carry it into a bay for a bonus; crash and it's lost.
FocusScope {
  id: game
  focus: true

  property var theme: ({})
  property int highScore: 0
  signal quitRequested()
  signal newHighScore(int score)

  // ---- field and tuning ---------------------------------------------------------
  readonly property real tile: 52
  readonly property real hudH: 48
  readonly property real barH: 28                     // the clock bar under the floor
  readonly property real fieldW: Lanes.COLS * tile    // 780
  readonly property real floorH: Lanes.ROWS * tile    // 676
  readonly property real fieldH: hudH + floorH + barH // 752
  readonly property real margin: 4 * tile             // lanes loop this far past each side
  readonly property real hopTime: 0.14                // s for a one-tile hop
  readonly property real boostTime: 0.22              // s for a two-tile boost
  readonly property real hitHalf: 0.32 * tile         // the bot's half width against traffic
  readonly property real standGrace: 0.1 * tile       // how far past a pallet's end you still stand
  readonly property real deathTime: 1.1
  readonly property real clearTime: 1.6
  readonly property int maxLives: 5
  readonly property int boostMax: 2
  readonly property real boostRecharge: 6
  readonly property int rowPoints: 10
  readonly property int dockPoints: 100
  readonly property int secondPoints: 10              // per whole second left on the clock
  readonly property int parcelPoints: 300
  readonly property int shiftPoints: 1200

  // ---- state --------------------------------------------------------------------
  property string phase: "ready"                      // ready | play | paused | over
  property int level: 1
  property int lives: 3
  property int score: 0
  property bool beatHigh: false
  property int seed: 1
  property var rng: ({ s: 1 })
  property var lanes: Lanes.lanesFor(1)
  property var objects: []                            // { row, x, len, type }
  // padClock drives every flicker pad lane. It's physics, advanced every 1/240 s
  // substep in step(); drawPadClock is the once-per-frame copy publish() takes of
  // it, which is what the pads are actually drawn from (GAMES.md rule 5 — a plain
  // property read straight from a delegate binding repaints every time it
  // changes, so an unpublished padClock would repaint the pads up to 4x more
  // often than the screen does).
  property real padClock: 0
  property real drawPadClock: 0

  // heroX/heroY are the bot's physics position, written every substep by step();
  // drawHeroX/drawHeroY are publish()'s once-per-frame copies, and the only ones
  // heroItem below is drawn from (same rule 5 reasoning as padClock above).
  property real heroX: startX()                       // px, center (physics)
  property real heroY: rowCenter(Lanes.START_ROW)     // px, center (physics)
  property real drawHeroX: startX()                   // px, center (drawn; see publish())
  property real drawHeroY: rowCenter(Lanes.START_ROW) // px, center (drawn; see publish())
  property int heroRow: Lanes.START_ROW               // the row it stands on (the one it left, mid-hop)
  property string facing: "up"
  property bool hopping: false
  property real hopT: 0                               // 0..1 through the hop
  property real hopDur: hopTime
  property real hopFromX: 0
  property real hopFromY: 0
  property real hopToX: 0
  property int hopToRow: 0
  property var queued: null                           // one buffered hop { dc, dr }
  property real bumpT: 0                              // a blocked hop's little shake

  property real timeLeft: Lanes.timeLimit(1)          // s left, physics (see step())
  property real drawTimeLeft: Lanes.timeLimit(1)      // s left, drawn (see publish())
  property int bestRow: Lanes.START_ROW
  property real deathT: 0                             // > 0: crashed, respawning
  property string deathCause: ""                      // hit | fell | swept | time
  property real clearT: 0                             // > 0: shift cleared, next one loading
  property int boosts: boostMax
  property real boostT: 0                             // until the next charge comes back
  property int parcelCol: -1                          // a parcel waiting on the strip, or -1
  property bool carrying: false
  property real parcelT: 4                            // until the next parcel turns up
  property int docked: 0
  property string banner: ""

  function color(key, fallback) { return theme[key] || fallback }
  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function rand() { return Lanes.rand(rng) }
  function setSeed(n) { seed = n | 0; rng = ({ s: n | 0 }) }
  function rowTop(r) { return hudH + r * tile }
  function rowCenter(r) { return hudH + (r + 0.5) * tile }
  function colCenter(c) { return (c + 0.5) * tile }
  function startX() { return colCenter(Math.floor(Lanes.COLS / 2)) }
  function colOf(x) { return clamp(Math.floor(x / tile), 0, Lanes.COLS - 1) }
  function lane(r) { return lanes[r] || ({ kind: "" }) }
  function laneSpeedPx(r) { return (lane(r).speed || 0) * tile }
  function timeLimit() { return Lanes.timeLimit(level) }
  function flash(text) { banner = text; bannerTimer.restart() }

  // A pad lane's state: "on", "warn" (blinking) or "off" (powered down). Physics
  // (platformUnder, below) always reads this live off padClock, so a bot's
  // footing is checked against the real, current clock, not a throttled one.
  function padStateOf(r) {
    var l = lane(r)
    return l.pad ? Lanes.padState(padClock + l.padOffset) : "on"
  }
  // The same, but off drawPadClock: the once-per-frame copy the pads are
  // painted with (GAMES.md rule 5), so they don't repaint on every substep.
  function drawPadStateOf(r) {
    var l = lane(r)
    return l.pad ? Lanes.padState(drawPadClock + l.padOffset) : "on"
  }

  // Drawing reads the objects through these (see docs/GAMES.md, rule 5).
  readonly property var offField: ({ row: 0, x: -9999, len: 0, type: "" })
  function objAt(i) { return objects[i] || offField }
  // Called once per frame (see the FrameAnimation below), never per substep:
  // republishes the traffic array and copies the physics hero position, clock
  // and pad clock into their drawn counterparts, so every drawing binding that
  // reads them repaints once per frame instead of once per 1/240 s substep
  // (GAMES.md rule 5).
  function publish() {
    objects = objects.slice()
    drawHeroX = heroX
    drawHeroY = heroY
    drawTimeLeft = timeLeft
    drawPadClock = padClock
  }

  ListModel { id: docks }                             // { col, filled, parcel }
  readonly property alias dockModel: docks
  readonly property alias objView: objView
  readonly property alias heroItem: heroItem
  readonly property alias hintText: text2 // the pause/ready/game-over hint line (tests/dockhop_test.qml)

  // ---- game flow ------------------------------------------------------------------
  function newGame(seedValue) {
    setSeed(seedValue === undefined ? Date.now() % 2147483647 : seedValue)
    level = 1; lives = 3; score = 0; beatHigh = false
    loadLevel()
    flash("Level 1 · " + Lanes.shiftName(1) + " shift")
  }

  function loadLevel() {
    lanes = Lanes.lanesFor(level)
    objects = Lanes.build(lanes, rng, tile, fieldW, margin)
    padClock = 0
    docks.clear()
    for (var i = 0; i < Lanes.DOCK_COLS.length; i++) docks.append({ col: Lanes.DOCK_COLS[i], filled: false, parcel: false })
    docked = 0
    parcelCol = -1; carrying = false; parcelT = 4
    boosts = boostMax; boostT = 0
    deathT = 0; clearT = 0
    phase = "ready"
    spawnHero()
  }

  // A fresh courier on the start strip, with a full clock.
  function spawnHero() {
    heroRow = Lanes.START_ROW
    heroX = startX()
    heroY = rowCenter(heroRow)
    hopping = false; hopT = 0; queued = null; bumpT = 0
    facing = "up"
    bestRow = Lanes.START_ROW
    timeLeft = timeLimit()
  }

  function addScore(points) {
    score += points
    if (score > highScore) { highScore = score; beatHigh = true; newHighScore(score) }
  }

  function pause() { if (phase === "play") phase = "paused" }
  function resume() { if (phase === "paused") phase = "play" }
  function togglePause() { if (phase === "play") pause(); else if (phase === "paused") resume() }
  // What a click on the field does, by phase (same effect as Enter on GAME OVER
  // and P/Space/Enter on PAUSED); a named function so the headless test can call
  // it without simulating a real mouse click.
  function click() { if (phase === "over") newGame(); else if (phase === "paused") resume() }

  // Crashed: a life is gone (and any parcel with it); respawn after a moment.
  function die(cause) {
    if (deathT > 0 || clearT > 0) return
    lives--
    deathCause = cause
    deathT = deathTime
    hopping = false; queued = null
    if (carrying) { carrying = false; parcelT = 6 }
  }

  // Into an open bay: points for the bay and the clock, the parcel bonus, and a
  // new courier on the start strip. The last bay clears the shift.
  function enterDock(i) {
    docks.setProperty(i, "filled", true)
    addScore(dockPoints + secondPoints * Math.floor(timeLeft))
    if (carrying) {
      docks.setProperty(i, "parcel", true)
      addScore(parcelPoints)
      carrying = false
      parcelT = 6
      flash("Parcel delivered +" + parcelPoints)
    }
    docked++
    if (docked >= docks.count) {
      addScore(shiftPoints)
      if (lives < maxLives) lives++
      clearT = clearTime
      hopping = false; queued = null
      flash("Shift clear +" + shiftPoints)
      return
    }
    spawnHero()
  }

  function nextLevel() {
    level++
    loadLevel()
    flash("Level " + level + " · " + Lanes.shiftName(level) + " shift")
  }

  // ---- hopping ----------------------------------------------------------------
  function dirVector(f) {
    switch (f) {
    case "left": return { dc: -1, dr: 0 }
    case "right": return { dc: 1, dr: 0 }
    case "down": return { dc: 0, dr: 1 }
    default: return { dc: 0, dr: -1 }
    }
  }
  function facingOf(dc, dr) { return dc < 0 ? "left" : dc > 0 ? "right" : dr > 0 ? "down" : "up" }
  function canAct() { return phase !== "over" && phase !== "paused" && deathT <= 0 && clearT <= 0 }

  // An arrow key. Mid-hop, the next hop waits (one is remembered).
  function hop(dc, dr) {
    if (!canAct()) return false
    if (hopping) { queued = { dc: dc, dr: dr }; return true }
    if (!startHop(dc, dr, 1)) return false
    if (phase === "ready") phase = "play"          // a blocked first press doesn't start the clock
    return true
  }

  // Space: a two-tile boost the way the bot faces, if a charge is left.
  function boost() {
    if (!canAct() || hopping || boosts <= 0) return false
    var v = dirVector(facing)
    if (!startHop(v.dc, v.dr, 2)) return false
    if (phase === "ready") phase = "play"
    boosts--
    if (boostT <= 0) boostT = boostRecharge
    return true
  }

  // Where a hop of `dist` tiles lands, or null when it's blocked: the edges of
  // the floor, the dock wall between bays, and a bay already taken.
  function hopTarget(dc, dr, dist) {
    var tr = heroRow + dr * dist
    var tx = heroX + dc * dist * tile
    if (tr < 0 || tr > Lanes.START_ROW || tx < 0 || tx > fieldW) return null
    if (tr === Lanes.DOCK_ROW) {
      var d = Lanes.dockAt(tx, tile, tile / 2)
      if (d < 0 || docks.get(d).filled) return null
      return { row: tr, x: colCenter(docks.get(d).col), dock: d }
    }
    // Off the shaft the bot keeps to the tile grid; over it, it keeps its drift.
    if (lane(tr).kind !== "shaft") tx = colCenter(colOf(tx))
    return { row: tr, x: tx, dock: -1 }
  }

  function startHop(dc, dr, dist) {
    facing = facingOf(dc, dr)
    var t = hopTarget(dc, dr, dist)
    if (!t && dist > 1) { t = hopTarget(dc, dr, 1); dist = 1 }   // a boost into the wall is a hop
    if (!t) { bumpT = 0.15; return false }
    hopping = true
    hopT = 0
    hopDur = dist > 1 ? boostTime : hopTime
    hopFromX = heroX; hopFromY = heroY
    hopToX = t.x; hopToRow = t.row
    return true
  }

  function land() {
    hopping = false
    heroRow = hopToRow
    heroX = hopToX
    heroY = rowCenter(heroRow)
    if (heroRow < bestRow) { addScore(rowPoints * (bestRow - heroRow)); bestRow = heroRow }
    if (heroRow === Lanes.DOCK_ROW) {
      var d = Lanes.dockAt(heroX, tile, tile / 2)
      queued = null
      if (d >= 0) enterDock(d)
    }
    // A buffered hop waits until step() has checked the row just landed on.
  }

  // The pallet or pad holding up a bot at x on a shaft row, or null. A pad that
  // has powered down holds nothing.
  function platformUnder(x, r) {
    if (padStateOf(r) === "off") return null
    for (var i = 0; i < objects.length; i++) {
      var o = objects[i]
      if (o.row === r && x >= o.x - standGrace && x <= o.x + o.len + standGrace) return o
    }
    return null
  }

  function trafficHit(x, r) {
    for (var i = 0; i < objects.length; i++) {
      var o = objects[i]
      if (o.row === r && x + hitHalf > o.x + 3 && x - hitHalf < o.x + o.len - 3) return true
    }
    return false
  }

  // ---- the fixed step ---------------------------------------------------------
  function step(dt) {
    if (phase === "paused" || phase === "over") return   // the whole floor freezes
    var i
    padClock += dt
    for (i = 0; i < objects.length; i++) {
      var o = objects[i]
      Lanes.advance(o, lane(o.row).dir, laneSpeedPx(o.row), dt, fieldW, margin)
    }
    if (bumpT > 0) bumpT = Math.max(0, bumpT - dt)

    if (deathT > 0) {
      deathT -= dt
      if (deathT <= 0) { deathT = 0; if (lives <= 0) { phase = "over"; banner = "" } else spawnHero() }
      return
    }
    if (clearT > 0) {
      clearT -= dt
      if (clearT <= 0) { clearT = 0; nextLevel() }
      return
    }
    if (phase !== "play") return

    // Boost charges come back one at a time.
    if (boosts < boostMax) {
      boostT -= dt
      if (boostT <= 0) { boosts++; boostT = boosts < boostMax ? boostRecharge : 0 }
    }

    // A parcel turns up on the loading strip now and then.
    if (parcelCol < 0 && !carrying) {
      parcelT -= dt
      if (parcelT <= 0) parcelCol = 1 + Math.floor(rand() * (Lanes.COLS - 2))
    }

    timeLeft -= dt
    if (timeLeft <= 0) { timeLeft = 0; die("time"); return }

    if (hopping) {
      hopT += dt / hopDur
      if (hopT < 1) {
        heroX = hopFromX + (hopToX - hopFromX) * hopT
        heroY = hopFromY + (rowCenter(hopToRow) - hopFromY) * hopT
        return                                  // airborne: nothing can touch it
      }
      land()
      if (deathT > 0 || clearT > 0 || heroRow === Lanes.DOCK_ROW) return
    }

    var k = lane(heroRow).kind
    if (k === "shaft") {
      var p = platformUnder(heroX, heroRow)
      if (!p) { die("fell"); return }
      heroX += lane(heroRow).dir * laneSpeedPx(heroRow) * dt
      if (heroX < 0 || heroX > fieldW) { die("swept"); return }
    } else if (k === "floor") {
      if (trafficHit(heroX, heroRow)) { die("hit"); return }
    } else if (k === "strip" && parcelCol >= 0 && colOf(heroX) === parcelCol) {
      carrying = true
      parcelCol = -1
      flash("Parcel! Carry it to a bay")
    }

    // The row held: now a hop pressed mid-air can go.
    if (queued) { var q = queued; queued = null; startHop(q.dc, q.dr, 1) }
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

  Timer { id: bannerTimer; interval: 1800; onTriggered: game.banner = "" }

  Connections {
    target: Qt.application
    function onStateChanged() { if (Qt.application.state !== Qt.ApplicationActive) game.lostFocus() }
  }
  // Away from the window: pause, and drop a buffered hop so nothing happens on return.
  function lostFocus() {
    queued = null
    pause()
  }

  // Every hop is its own key press: holding an arrow does not keep hopping.
  Keys.onPressed: function (e) {
    if (e.isAutoRepeat) { e.accepted = true; return }
    switch (e.key) {
    case Qt.Key_Up: case Qt.Key_W: hop(0, -1); break
    case Qt.Key_Down: case Qt.Key_S: hop(0, 1); break
    case Qt.Key_Left: case Qt.Key_A: hop(-1, 0); break
    case Qt.Key_Right: case Qt.Key_D: hop(1, 0); break
    case Qt.Key_Space: if (phase === "paused") resume(); else boost(); break
    case Qt.Key_P: togglePause(); break
    case Qt.Key_Return: case Qt.Key_Enter: if (phase === "over") newGame(); else if (phase === "paused") resume(); else boost(); break
    case Qt.Key_Escape: quitRequested(); break
    default: return
    }
    e.accepted = true
  }

  Component.onCompleted: newGame()

  // ---- drawing ----------------------------------------------------------------------
  Item {
    id: field
    width: game.fieldW
    height: game.fieldH
    anchors.centerIn: parent
    scale: Math.min(game.width / game.fieldW, game.height / game.fieldH)
    clip: true

    Rectangle { anchors.fill: parent; color: game.color("dark_background", "#13141c"); radius: 6 }

    // Lane bands.
    Repeater {
      model: Lanes.ROWS
      delegate: Item {
        id: band
        required property int index
        readonly property string kind: game.lane(index).kind
        x: 0; y: game.rowTop(index)
        width: game.fieldW; height: game.tile

        // Dock wall: panels between the bays.
        Rectangle {
          visible: band.kind === "dock"
          anchors.fill: parent
          color: game.color("lighter_background", "#24283b")
          Repeater {
            model: Lanes.COLS
            delegate: Rectangle {
              required property int index
              x: index * game.tile + 2; y: 6; width: game.tile - 4; height: game.tile - 12
              radius: 3
              color: "transparent"
              border.width: 1
              border.color: game.color("background", "#1a1b26")
              opacity: 0.8
            }
          }
        }
        // The drop shaft: dark, with faint rails and depth marks.
        Rectangle {
          visible: band.kind === "shaft"
          anchors.fill: parent
          color: Qt.darker(game.color("dark_background", "#13141c"), 1.35)
          Rectangle { width: parent.width; height: 1; color: game.color("blue", "#7aa2f7"); opacity: 0.22 }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: game.tile * 1.5
            x: (band.index % 2) * game.tile * 0.75
            Repeater {
              model: 9
              delegate: Rectangle { width: 10; height: 2; radius: 1; color: game.color("blue", "#7aa2f7"); opacity: 0.18 }
            }
          }
          // Hazard stripes along the shaft's two edges.
          Canvas {
            id: stripes
            visible: band.index === 1 || band.index === Lanes.STRIP_ROW - 1
            width: parent.width; height: 6
            y: band.index === 1 ? 0 : parent.height - height
            readonly property color ink: game.color("yellow", "#e0af68")
            onInkChanged: requestPaint()
            onPaint: {
              var c = getContext("2d")
              c.clearRect(0, 0, width, height)
              c.fillStyle = ink
              for (var sx = -height; sx < width; sx += 16) {
                c.beginPath()
                c.moveTo(sx, height); c.lineTo(sx + 8, height); c.lineTo(sx + 8 + height, 0); c.lineTo(sx + height, 0)
                c.closePath(); c.fill()
              }
            }
            opacity: 0.75
          }
        }
        // Loading strip and start strip: safe concrete with a safety line.
        Rectangle {
          visible: band.kind === "strip" || band.kind === "start"
          anchors.fill: parent
          color: game.color("lighter_background", "#24283b")
          Row {
            anchors.bottom: band.kind === "strip" ? parent.bottom : undefined
            anchors.top: band.kind === "start" ? parent.top : undefined
            spacing: 10
            Repeater {
              model: Math.ceil(game.fieldW / 30)
              delegate: Rectangle { width: 20; height: 4; color: game.color("yellow", "#e0af68"); opacity: 0.7 }
            }
          }
        }
        // Traffic floor with dashed lane lines.
        Rectangle {
          visible: band.kind === "floor"
          anchors.fill: parent
          color: game.color("background", "#1a1b26")
          Row {
            visible: band.index < 11
            anchors.bottom: parent.bottom
            spacing: 18
            Repeater {
              model: Math.ceil(game.fieldW / 44)
              delegate: Rectangle { width: 26; height: 2; color: game.color("foreground", "#a9b1d6"); opacity: 0.18 }
            }
          }
        }
      }
    }

    // Dock bays.
    Repeater {
      id: dockView
      model: docks
      delegate: Item {
        required property int col
        required property bool filled
        required property bool parcel
        x: col * game.tile; y: game.rowTop(0)
        width: game.tile; height: game.tile
        Rectangle {
          anchors.fill: parent; anchors.margins: 3
          radius: 4
          color: game.color("dark_background", "#13141c")
          border.width: 2
          border.color: filled ? game.color("green", "#9ece6a") : game.color("accent", "#7aa2f7")
        }
        // Chevron pointing in for an open bay.
        Text {
          visible: !filled
          anchors.centerIn: parent
          text: "▲"
          color: game.color("accent", "#7aa2f7")
          opacity: 0.45
          font.pixelSize: 18
        }
        // A parked bot, and its parcel if it brought one.
        Rectangle {
          visible: filled
          anchors.centerIn: parent
          width: game.tile * 0.52; height: game.tile * 0.46; radius: 5
          color: game.color("green", "#9ece6a")
          Rectangle { x: 4; y: 5; width: parent.width - 8; height: 5; radius: 2; color: game.color("dark_background", "#13141c") }
        }
        Rectangle {
          visible: parcel
          x: parent.width - 16; y: 4; width: 12; height: 11; radius: 2
          color: game.color("yellow", "#e0af68")
          Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height; color: game.color("orange", "#ff9e64") }
        }
      }
    }

    // A parcel waiting on the loading strip.
    Rectangle {
      visible: game.parcelCol >= 0
      x: game.colCenter(Math.max(0, game.parcelCol)) - width / 2
      y: game.rowCenter(Lanes.STRIP_ROW) - height / 2
      width: 22; height: 18; radius: 3
      color: game.color("yellow", "#e0af68")
      border.width: 1; border.color: game.color("orange", "#ff9e64")
      Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 3; height: parent.height; color: game.color("orange", "#ff9e64") }
      SequentialAnimation on opacity {
        running: game.parcelCol >= 0; loops: Animation.Infinite
        NumberAnimation { to: 0.55; duration: 450 }
        NumberAnimation { to: 1; duration: 450 }
      }
    }

    // Everything that moves on the lanes.
    Repeater {
      id: objView
      model: game.objects.length
      delegate: Item {
        id: obj
        required property int index
        readonly property string kind: game.objAt(index).type
        readonly property int row: game.objAt(index).row
        readonly property int dir: game.lane(row).dir || 1
        readonly property string pad: kind === "pad" ? game.drawPadStateOf(row) : "on"
        x: game.objAt(index).x
        y: game.rowTop(row)
        width: game.objAt(index).len
        height: game.tile

        // Hover pallet: slatted deck on a glow.
        Rectangle {
          visible: obj.kind === "pallet"
          x: 2; y: 8; width: parent.width - 4; height: parent.height - 16; radius: 4
          color: game.color("orange", "#ff9e64")
          border.width: 1; border.color: Qt.darker(game.color("orange", "#ff9e64"), 1.4)
          Row {
            anchors.fill: parent; anchors.margins: 5
            spacing: 6
            Repeater {
              model: Math.max(1, Math.floor((obj.width - 14) / 12))
              delegate: Rectangle { width: 6; height: parent.height; radius: 1; color: Qt.darker(game.color("orange", "#ff9e64"), 1.25) }
            }
          }
        }
        // Flicker pad: a lit plate that blinks, then powers down.
        Rectangle {
          visible: obj.kind === "pad"
          x: 3; y: 9; width: parent.width - 6; height: parent.height - 18; radius: height / 2
          color: obj.pad === "off" ? "transparent" : game.color("cyan", "#7dcfff")
          border.width: 2
          border.color: game.color("cyan", "#7dcfff")
          opacity: obj.pad === "off" ? 0.3 : obj.pad === "warn" ? (Math.floor(game.drawPadClock * 8) % 2 ? 0.45 : 0.95) : 0.95
          Rectangle {
            visible: obj.pad !== "off"
            anchors.centerIn: parent; width: parent.width * 0.6; height: 3; radius: 1
            color: game.color("dark_background", "#13141c"); opacity: 0.5
          }
        }
        // Cart: a boxy hand cart.
        Item {
          visible: obj.kind === "cart"
          anchors.fill: parent
          Rectangle { x: 6; y: 12; width: parent.width - 12; height: parent.height - 24; radius: 4; color: game.color("red", "#f7768e") }
          Rectangle { x: obj.dir > 0 ? 4 : parent.width - 8; y: 10; width: 4; height: parent.height - 20; radius: 2; color: game.color("bright_foreground", "#c0caf5") }
          Rectangle { x: 10; y: parent.height - 14; width: 8; height: 8; radius: 4; color: game.color("dark_background", "#13141c") }
          Rectangle { x: parent.width - 18; y: parent.height - 14; width: 8; height: 8; radius: 4; color: game.color("dark_background", "#13141c") }
        }
        // Sweeper: a long body with a spinning brush at the front.
        Item {
          visible: obj.kind === "sweeper"
          anchors.fill: parent
          Rectangle { x: 6; y: 10; width: parent.width - 12; height: parent.height - 20; radius: 8; color: game.color("green", "#9ece6a") }
          Rectangle { x: obj.dir > 0 ? parent.width - 26 : 26 - 18; y: 14; width: 18; height: 10; radius: 3; color: game.color("dark_background", "#13141c"); opacity: 0.6 }
          Rectangle {
            x: obj.dir > 0 ? parent.width - 16 : -2; anchors.verticalCenter: parent.verticalCenter
            width: 18; height: 18; radius: 9
            color: "transparent"; border.width: 3; border.color: game.color("yellow", "#e0af68")
          }
        }
        // Forklift: a cab with forks sticking out ahead.
        Item {
          visible: obj.kind === "forklift"
          anchors.fill: parent
          Rectangle {
            x: obj.dir > 0 ? parent.width - 14 : -4; y: 16; width: 18; height: 3; color: game.color("bright_foreground", "#c0caf5")
          }
          Rectangle {
            x: obj.dir > 0 ? parent.width - 14 : -4; y: parent.height - 19; width: 18; height: 3; color: game.color("bright_foreground", "#c0caf5")
          }
          Rectangle { x: obj.dir > 0 ? 4 : 14; y: 9; width: parent.width - 18; height: parent.height - 18; radius: 5; color: game.color("magenta", "#bb9af7") }
          Rectangle { x: obj.dir > 0 ? 10 : 22; y: 15; width: 12; height: parent.height - 30; radius: 2; color: game.color("dark_background", "#13141c"); opacity: 0.55 }
        }
        // Tug train: a tractor and its trailers.
        Row {
          visible: obj.kind === "tug"
          anchors.verticalCenter: parent.verticalCenter
          x: 3
          spacing: 4
          layoutDirection: obj.dir > 0 ? Qt.RightToLeft : Qt.LeftToRight
          Repeater {
            model: Math.max(1, Math.round(obj.width / game.tile))
            delegate: Rectangle {
              required property int index
              width: game.tile - 6 - (index === 0 ? 0 : 4)
              height: index === 0 ? game.tile - 16 : game.tile - 22
              anchors.verticalCenter: parent ? parent.verticalCenter : undefined
              radius: 4
              color: index === 0 ? game.color("blue", "#7aa2f7") : Qt.darker(game.color("blue", "#7aa2f7"), 1.3)
              border.width: index === 0 ? 0 : 1
              border.color: game.color("blue", "#7aa2f7")
            }
          }
        }
      }
    }

    // The courier bot.
    Item {
      id: heroItem
      readonly property real lift: game.hopping ? Math.sin(Math.PI * game.hopT) : 0
      readonly property bool crashed: game.deathT > 0
      visible: game.clearT <= 0 && game.phase !== "over"
      x: game.drawHeroX - game.tile / 2 + (game.bumpT > 0 ? Math.sin(game.bumpT * 90) * 3 : 0)
      y: game.drawHeroY - game.tile / 2
      width: game.tile; height: game.tile

      // Shadow on the ground; it stays put while the bot is in the air.
      Rectangle {
        visible: !heroItem.crashed
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 12
        width: parent.width * 0.55; height: 7; radius: 4
        color: Qt.darker(game.color("dark_background", "#13141c"), 1.6); opacity: 0.35 - heroItem.lift * 0.15
      }
      Item {
        id: bot
        visible: !heroItem.crashed || game.deathCause === "fell"
        anchors.centerIn: parent
        width: game.tile * 0.68; height: game.tile * 0.68
        anchors.verticalCenterOffset: -heroItem.lift * 8
        scale: heroItem.crashed ? Math.max(0.05, game.deathT / game.deathTime) : 1 + heroItem.lift * 0.14
        rotation: heroItem.crashed ? (1 - game.deathT / game.deathTime) * 360
                : game.facing === "right" ? 90 : game.facing === "down" ? 180 : game.facing === "left" ? 270 : 0

        // Wheels, body, visor and antenna. The visor faces the way it hops.
        Rectangle { x: -3; y: 6; width: 6; height: parent.height - 12; radius: 2; color: game.color("foreground", "#a9b1d6") }
        Rectangle { x: parent.width - 3; y: 6; width: 6; height: parent.height - 12; radius: 2; color: game.color("foreground", "#a9b1d6") }
        Rectangle {
          anchors.fill: parent
          radius: 8
          color: game.color("accent", "#7aa2f7")
          border.width: 2
          border.color: Qt.lighter(game.color("accent", "#7aa2f7"), 1.35)
        }
        Rectangle {
          x: 5; y: 5; width: parent.width - 10; height: 7; radius: 3
          color: game.color("bright_foreground", "#c0caf5")
          Rectangle { x: 4; y: 2; width: 4; height: 3; radius: 1; color: game.color("dark_background", "#13141c") }
          Rectangle { x: parent.width - 8; y: 2; width: 4; height: 3; radius: 1; color: game.color("dark_background", "#13141c") }
        }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: -6; width: 2; height: 7; color: game.color("foreground", "#a9b1d6") }
        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: -9; width: 5; height: 5; radius: 3; color: game.color("red", "#f7768e") }
        // The carried parcel rides on its back.
        Rectangle {
          visible: game.carrying
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height * 0.42
          width: parent.width * 0.55; height: parent.height * 0.42; radius: 2
          color: game.color("yellow", "#e0af68")
          Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 3; height: parent.height; color: game.color("orange", "#ff9e64") }
        }
      }
      // A crash in traffic, off the edge, or out of time: sparks.
      Repeater {
        model: heroItem.crashed && game.deathCause !== "fell" ? 8 : 0
        delegate: Rectangle {
          required property int index
          readonly property real a: index * Math.PI / 4
          readonly property real r: (1 - game.deathT / game.deathTime) * game.tile * 0.7 + 4
          x: heroItem.width / 2 + Math.cos(a) * r - 4
          y: heroItem.height / 2 + Math.sin(a) * r - 4
          width: 8; height: 8; radius: 2; rotation: 45
          color: index % 2 ? game.color("yellow", "#e0af68") : game.color("red", "#f7768e")
          opacity: game.deathT / game.deathTime
        }
      }
    }

    // HUD
    Rectangle {
      width: parent.width; height: game.hudH
      color: game.color("lighter_background", "#24283b")
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left; anchors.leftMargin: 16
        spacing: 22
        Text { text: "SCORE " + game.score; color: game.color("bright_foreground", "#c0caf5"); font.pixelSize: 18; font.bold: true; font.family: "monospace" }
        Text { text: "HIGH " + game.highScore; color: game.color("foreground", "#a9b1d6"); font.pixelSize: 18; font.family: "monospace" }
      }
      Text {
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: 40
        text: "LEVEL " + game.level + " · " + Lanes.shiftName(game.level).toUpperCase() + " SHIFT"
        color: game.color("accent", "#7aa2f7"); font.pixelSize: 15; font.bold: true; font.family: "monospace"
      }
      Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 16
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "BOOST"; rightPadding: 2
          color: game.color("foreground", "#a9b1d6"); font.pixelSize: 12; font.family: "monospace"
        }
        Repeater {
          model: game.boostMax
          delegate: Rectangle {
            required property int index
            anchors.verticalCenter: parent.verticalCenter
            width: 8; height: 16; radius: 2
            color: index < game.boosts ? game.color("cyan", "#7dcfff") : "transparent"
            border.width: 1; border.color: game.color("cyan", "#7dcfff")
          }
        }
        Item { width: 12; height: 1 }
        Repeater {
          model: game.lives
          delegate: Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 4
            color: game.color("accent", "#7aa2f7")
            Rectangle { x: 2; y: 3; width: 10; height: 3; radius: 1; color: game.color("bright_foreground", "#c0caf5") }
          }
        }
      }
    }

    // The clock.
    Item {
      y: game.hudH + game.floorH
      width: parent.width; height: game.barH
      Text {
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        text: "CLOCK"
        color: game.color("foreground", "#a9b1d6"); font.pixelSize: 12; font.bold: true; font.family: "monospace"
      }
      Rectangle {
        id: clockTrack
        x: 70; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 140; height: 10; radius: 5
        color: game.color("lighter_background", "#24283b")
        Rectangle {
          readonly property real f: game.clamp(game.drawTimeLeft / game.timeLimit(), 0, 1)
          width: parent.width * f; height: parent.height; radius: 5
          color: f > 0.5 ? game.color("green", "#9ece6a") : f > 0.25 ? game.color("yellow", "#e0af68") : game.color("red", "#f7768e")
        }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right; anchors.rightMargin: 12
        text: Math.ceil(game.drawTimeLeft) + "s"
        color: game.color("bright_foreground", "#c0caf5"); font.pixelSize: 13; font.bold: true; font.family: "monospace"
      }
    }

    // Messages, with a backdrop for pause, game over and the start prompt.
    Rectangle {
      anchors.centerIn: messages
      width: messages.width + 48; height: messages.height + 32
      radius: 8
      visible: messages.visible && (game.phase !== "play")
      color: game.color("dark_background", "#13141c")
      opacity: 0.92
      border.width: 1
      border.color: game.color("lighter_background", "#24283b")
    }
    Column {
      id: messages
      anchors.centerIn: parent
      anchors.verticalCenterOffset: game.phase === "play" ? -game.tile * 0.1 : 0
      spacing: 10
      visible: text1.text !== ""
      Text {
        id: text1
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "GAME OVER"
            : game.phase === "paused" ? "PAUSED"
            : game.banner !== "" ? game.banner
            : game.phase === "ready" ? "DOCKHOP" : ""
        color: game.color("bright_foreground", "#c0caf5")
        style: Text.Outline; styleColor: game.color("dark_background", "#13141c")
        font.pixelSize: game.phase === "play" ? 30 : 40; font.bold: true; font.family: "monospace"
      }
      Text {
        id: text2
        anchors.horizontalCenter: parent.horizontalCenter
        text: game.phase === "over" ? "Score " + game.score + (game.beatHigh ? "  ·  new high score!" : "") + "\nEnter to play again  ·  Esc to quit"
            : game.phase === "paused" ? "P or Space to resume  ·  Esc to quit"
            : game.phase === "ready" ? "Hop to start  ·  Arrows or WASD hop  ·  Space boosts two tiles  ·  P pause\nPark in all four bays  ·  ride pallets over the shaft  ·  grab parcels for a bonus" : ""
        horizontalAlignment: Text.AlignHCenter
        color: game.color("foreground", "#a9b1d6")
        font.pixelSize: 15; font.family: "monospace"
      }
    }

    MouseArea { anchors.fill: parent; onClicked: { game.forceActiveFocus(); game.click() } }
  }
}
