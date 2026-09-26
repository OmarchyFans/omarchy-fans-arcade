.pragma library

// Input buffering and special-move detection. Pure helpers: Game.qml keeps, per
// fighter, a short history of direction presses (`buf`, oldest first) as
// { k, t } where k is F (toward the opponent), B (away), U or D, and t is the
// game clock when it was pressed. Directions are stored relative to the way the
// fighter faced at that moment, so a motion reads the same on either side.

var HISTORY = 8          // direction presses kept
var TAP_GAP = 0.25       // the two taps of a double tap must be this close
var WINDOW = 0.30        // ... and the button must come this soon after the second
var BUFFER = 0.12        // a button pressed while busy is kept this long
var CHARGE = 0.5         // hold down this long to charge
var CHARGE_GRACE = 0.2   // a charge survives letting go of down this long

function push(buf, k, t) {
  buf.push({ k: k, t: t })
  while (buf.length > HISTORY) buf.shift()
}

// The last two direction presses are both `k`, tapped close together, and the
// second one is recent. Anything pressed in between breaks the motion.
function doubleTap(buf, k, now) {
  var n = buf.length
  if (n < 2) return false
  var a = buf[n - 2], b = buf[n - 1]
  return a.k === k && b.k === k && b.t - a.t <= TAP_GAP && now - b.t <= WINDOW && b.t > a.t
}

// Does pressing `button` now complete this special's input?
//   dash   : F F + Light
//   dd     : D D + Light
//   charge : down held CHARGE s (or let go within CHARGE_GRACE) + Heavy
function special(sp, button, buf, now, chargeReady) {
  if (!sp || button !== sp.button) return false
  switch (sp.input) {
  case "dash": return doubleTap(buf, "F", now)
  case "dd": return doubleTap(buf, "D", now)
  case "charge": return chargeReady === true
  }
  return false
}

// Which way is `dir` ("left"/"right"/"up"/"down") for a fighter facing `facing`
// (+1 = right)?
function relative(dir, facing) {
  if (dir === "up") return "U"
  if (dir === "down") return "D"
  var toward = (dir === "right") === (facing > 0)
  return toward ? "F" : "B"
}
