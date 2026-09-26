.pragma library

// Dockhop's warehouse, row by row, and the pure helpers the game uses.
//
// The floor is a 15 x 13 grid of tiles. Row 0 is the dock wall with four bays;
// rows 1-4 are the drop shaft (fall in and you're gone) where hover pallets and
// flicker pads drift by; row 5 is the loading strip (safe, where parcels turn
// up); rows 6-11 are the traffic floor (carts, sweepers, forklifts, tug trains);
// row 12 is the start strip. The split is deliberately lopsided (six lanes of
// traffic, four of shaft, four bays) so the floor is our own, not the classic
// crossing game's five-and-five with five homes.

var COLS = 15
var ROWS = 13
var DOCK_ROW = 0
var STRIP_ROW = 5
var START_ROW = 12
var DOCK_COLS = [2, 5, 9, 12]

// kind: "dock" | "shaft" | "strip" | "floor" | "start"
// For moving lanes: dir (+1 right, -1 left), base speed in tiles/s, object
// length in tiles, how many objects share the loop, and what they are.
var BASE = [
  { kind: "dock" },
  { kind: "shaft", dir: -1, speed: 1.05, len: 3, count: 4, type: "pallet" },
  { kind: "shaft", dir:  1, speed: 1.45, len: 2, count: 5, type: "pad" },
  { kind: "shaft", dir: -1, speed: 0.85, len: 4, count: 3, type: "pallet" },
  { kind: "shaft", dir:  1, speed: 1.15, len: 3, count: 4, type: "pad" },
  { kind: "strip" },
  { kind: "floor", dir:  1, speed: 1.35, len: 1, count: 4, type: "cart" },
  { kind: "floor", dir: -1, speed: 1.05, len: 2, count: 3, type: "sweeper" },
  { kind: "floor", dir:  1, speed: 2.10, len: 1, count: 2, type: "forklift" },
  { kind: "floor", dir: -1, speed: 0.85, len: 3, count: 2, type: "tug" },
  { kind: "floor", dir:  1, speed: 1.60, len: 1, count: 3, type: "cart" },
  { kind: "floor", dir: -1, speed: 1.20, len: 1, count: 3, type: "cart" },
  { kind: "start" }
]

// Everything speeds up 15% a level, up to 2.2x.
function speedFactor(level) { return Math.min(1 + 0.15 * (level - 1), 2.2) }

// A courier gets less time on later shifts, never under 20 s.
function timeLimit(level) { return Math.max(20, 30 - (level - 1)) }

// Shift names for the HUD, cycling.
var SHIFTS = ["Morning", "Rush", "Noon", "Swing", "Evening", "Night", "Graveyard", "Peak"]
function shiftName(level) { return SHIFTS[(level - 1) % SHIFTS.length] }

// Flicker pads: on, blinking (warning), then powered down.
var PAD_ON = 3.2
var PAD_WARN = 0.9
var PAD_OFF = 1.4
function padCycle() { return PAD_ON + PAD_OFF }
function padState(clock) {
  var t = clock % padCycle()
  if (t < 0) t += padCycle()
  if (t < PAD_ON - PAD_WARN) return "on"
  if (t < PAD_ON) return "warn"
  return "off"
}

// mulberry32: a small seeded PRNG. `rng` is { s: int }; returns [0, 1).
function rand(rng) {
  rng.s = (rng.s + 0x6D2B79F5) | 0
  var t = rng.s
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

// The lanes for a level. Later shifts: faster, shorter pallets from level 4,
// extra carts every two levels, and pads that power down from level 2.
function lanesFor(level) {
  var f = speedFactor(level)
  var out = []
  for (var r = 0; r < BASE.length; r++) {
    var b = BASE[r], l = { row: r, kind: b.kind }
    if (b.dir) {
      l.dir = b.dir
      l.speed = b.speed * f                 // tiles per second
      l.type = b.type
      l.len = b.len
      l.count = b.count
      if (b.kind === "shaft" && level >= 4 && l.len >= 3) l.len--
      if (b.kind === "floor" && b.type === "cart") l.count += Math.min(2, Math.floor((level - 1) / 2))
      l.pad = b.type === "pad" && level >= 2
      l.padOffset = r * 1.3                 // lanes blink out of step
    }
    out.push(l)
  }
  return out
}

// Objects spread around each lane's loop. Positions are in pixels (left edge);
// the loop runs `margin` px past both sides of the field so long objects wrap
// out of sight. Jitter keeps at least about one tile between two objects.
function build(lanes, rng, tile, fieldW, margin) {
  var loop = fieldW + 2 * margin
  var objs = []
  for (var r = 0; r < lanes.length; r++) {
    var l = lanes[r]
    if (!l.dir) continue
    var spacing = loop / l.count
    var lenPx = l.len * tile
    var slack = Math.max(0, (spacing - lenPx - tile) * 0.5)
    var start = rand(rng) * spacing
    for (var i = 0; i < l.count; i++) {
      var p = (start + i * spacing + rand(rng) * slack) % loop
      objs.push({ row: r, x: p - margin, len: lenPx, type: l.type })
    }
  }
  return objs
}

// Move an object and wrap it around its lane's loop.
function advance(o, dir, pxPerSec, dt, fieldW, margin) {
  var loop = fieldW + 2 * margin
  o.x += dir * pxPerSec * dt
  if (o.x > fieldW + margin) o.x -= loop
  else if (o.x < -margin) o.x += loop
}

// The dock bay a courier at pixel x can drive into, or -1. `tol` is how far off
// center (px) still counts.
function dockAt(x, tile, tol) {
  for (var i = 0; i < DOCK_COLS.length; i++)
    if (Math.abs(x - (DOCK_COLS[i] + 0.5) * tile) <= tol) return i
  return -1
}
