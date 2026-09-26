.pragma library

// Lattice Siege flight paths and the difficulty curve. Pure functions only, so
// the rules test can check them directly.

// ---- entry paths ----------------------------------------------------------------
// A constellation flies in along a cubic Bezier curve that starts off the field
// and ends on its slot. The slot is passed in on every step (the formation
// sways), so the curve always lands exactly where the slot is now.
var KINDS = ["swoopL", "spiralR", "drop", "swoopR", "spiralL"]

function mirror(p, W) { return { x: W - p.x, y: p.y } }

// The first three control points; the fourth is the slot.
function controls(kind, sx, sy, W, H) {
  switch (kind) {
  case "swoopL":  return [{ x: -40, y: H * 0.70 }, { x: W * 0.45, y: H * 0.10 }, { x: W * 0.62, y: H * 0.92 }]
  case "swoopR":  return [mirror({ x: -40, y: H * 0.70 }, W), mirror({ x: W * 0.45, y: H * 0.10 }, W), mirror({ x: W * 0.62, y: H * 0.92 }, W)]
  case "spiralL": return [{ x: W * 0.30, y: -40 }, { x: W * 1.05, y: H * 0.70 }, { x: -W * 0.05, y: H * 0.70 }]
  case "spiralR": return [mirror({ x: W * 0.30, y: -40 }, W), mirror({ x: W * 1.05, y: H * 0.70 }, W), mirror({ x: -W * 0.05, y: H * 0.70 }, W)]
  default:        return [{ x: sx, y: -40 }, { x: sx + W * 0.28, y: H * 0.45 }, { x: sx - W * 0.28, y: H * 0.55 }]   // drop
  }
}

function bezier(p0, p1, p2, p3, u) {
  var v = 1 - u
  var a = v * v * v, b = 3 * v * v * u, c = 3 * v * u * u, d = u * u * u
  return { x: a * p0.x + b * p1.x + c * p2.x + d * p3.x, y: a * p0.y + b * p1.y + c * p2.y + d * p3.y }
}

// Where an entering enemy is at progress u (0..1) toward the slot (sx, sy).
function point(kind, u, sx, sy, W, H) {
  var c = controls(kind, sx, sy, W, H)
  return bezier(c[0], c[1], c[2], { x: sx, y: sy }, Math.max(0, Math.min(1, u)))
}

// ---- difficulty curve ----------------------------------------------------------
// Everything rises with the stage number and levels off at a cap.
function entryTime(stage)    { return Math.max(1.6, 2.5 - 0.06 * (stage - 1)) }        // s per entry flight
function groupGap(stage)     { return Math.max(0.45, 0.8 - 0.03 * (stage - 1)) }       // s between constellations
function diveInterval(stage) { return Math.max(0.55, 2.6 - 0.2 * (stage - 1)) }        // s between dive orders
function diveSpeed(stage)    { return Math.min(330, 175 + 12 * (stage - 1)) }          // px/s
function maxDivers(stage)    { return Math.min(6, 1 + Math.floor(stage / 2)) }
function shotsPerDive(stage) { return Math.min(3, 1 + Math.floor((stage - 1) / 3)) }
function shotSpeed(stage)    { return Math.min(380, 210 + 14 * (stage - 1)) }          // px/s
function squadChance(stage)  { return stage < 3 ? 0 : Math.min(0.6, 0.25 + 0.05 * (stage - 3)) }
// From stage 2 the formation itself takes pot shots, more often later.
function formFireInterval(stage) { return stage < 2 ? 0 : Math.max(0.9, 4.5 - 0.35 * (stage - 2)) }

// ---- the Monolith ----------------------------------------------------------------
// The first Monolith (k=1) is eased a little: fewer HP and a slower shield spin, so
// its gaps are easier to time for a player meeting it for the first time. Later ones
// (k>=2) keep the original curve, so they stay just as hard as before.
function bossHp(k)        { return k === 1 ? 26 : 36 + 24 * (k - 1) }
function bossPlates(k)    { return Math.min(6, 3 + k) }
function bossSpin(k)      { return k === 1 ? 0.8 : 1.0 + 0.25 * k }              // rad/s
function bossFireGap(k)   { return Math.max(0.9, 2.6 - 0.25 * k) }
function bossSpawnGap(k)  { return Math.max(2.4, 5.0 - 0.5 * k) }
function bossBonus(k)     { return 2000 + 1000 * k }

// ---- starfield (drawing only) -------------------------------------------------
function starX(i)     { return (i * 7919 + 13) % 800 }
function starY(i)     { return (i * 104729 + 71) % 600 }
function starSpeed(i) { return 12 + (i % 3) * 16 }
function starSize(i)  { return i % 5 === 0 ? 2 : 1 }
