.pragma library

// Pure helpers for Tetherwake: the seeded PRNG, wrap-around geometry and the
// shapes and tables of the hazards. Nothing here touches the game state.

// mulberry32: a small seeded PRNG. `rng` is { s: int }; returns [0, 1).
function rand(rng) {
  var a = (rng.s + 0x6D2B79F5) | 0
  rng.s = a
  var t = Math.imul(a ^ (a >>> 15), 1 | a)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}

// The field wraps: a coordinate that leaves one edge comes back on the other.
function wrap(v, size) {
  v = v % size
  return v < 0 ? v + size : v
}

// The shortest signed distance from a to b on a wrapped axis of `size`.
function delta(a, b, size) {
  var d = (b - a) % size
  if (d > size / 2) d -= size
  if (d < -size / 2) d += size
  return d
}

// Wrapped distance between two points in a W×H field.
function dist(ax, ay, bx, by, W, H) {
  return Math.hypot(delta(ax, bx, W), delta(ay, by, H))
}

// ---- debris ---------------------------------------------------------------
// Hull debris comes in three sizes. A bullet shatters a slab into two plates,
// a plate into two shards, and a shard is gone.
var DEBRIS = {
  3: { r: 36, points: 20, mass: 3, name: "slab" },
  2: { r: 21, points: 50, mass: 2, name: "plate" },
  1: { r: 11, points: 100, mass: 1, name: "shard" }
}
var MINE_POINTS = 150
var CARRIER_POINTS = 1500

function debrisRadius(size) { return DEBRIS[size] ? DEBRIS[size].r : 10 }
function debrisPoints(size) { return DEBRIS[size] ? DEBRIS[size].points : 0 }
function debrisMass(size) { return DEBRIS[size] ? DEBRIS[size].mass : 1 }

// A torn hull plate: an irregular polygon with one straight "cut" edge, so
// debris reads as wreckage rather than round rock. Points are in units of the
// radius (-1..1), centered on the piece.
function debrisShape(rng) {
  var n = 7 + Math.floor(rand(rng) * 3)
  var cut = Math.floor(rand(rng) * n)
  var pts = []
  for (var i = 0; i < n; i++) {
    var a = (i / n) * Math.PI * 2 + (rand(rng) - 0.5) * 0.5
    var k = i === cut || i === (cut + 1) % n ? 0.62 : 0.72 + rand(rng) * 0.28
    pts.push({ x: Math.cos(a) * k, y: Math.sin(a) * k })
  }
  return pts
}

// ---- waves --------------------------------------------------------------------
// What wave n brings. Storms start on wave 3, the carrier on wave 4.
function wave(n) {
  return {
    debris: Math.min(2 + n, 9),
    mines: Math.min(Math.max(0, n - 1), 6),
    speed: Math.min(1 + 0.07 * (n - 1), 1.9),
    storms: n >= 3,
    carrier: n >= 4,
    carrierHp: 6 + Math.max(0, n - 4),
    carrierFire: Math.max(1.1, 2.6 - 0.12 * (n - 4)),
    mineSpeed: Math.min(115 + 8 * (n - 1), 190)
  }
}

// A fixed star field (cosmetic, not from the game's PRNG).
function stars(count, W, H) {
  var rng = { s: 9173 }, out = []
  for (var i = 0; i < count; i++)
    out.push({ x: rand(rng) * W, y: rand(rng) * H, b: 0.25 + rand(rng) * 0.55, s: rand(rng) < 0.15 ? 2 : 1 })
  return out
}
