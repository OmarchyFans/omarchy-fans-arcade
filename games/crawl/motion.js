.pragma library

// Tile-grid movement shared by Byte and the bugs. Positions are in tile units:
// (c, r) is the centre of column c, row r. An actor moves along one axis at a
// time and may only change axis at a tile centre; `decide(actor)` is called at
// every centre it reaches and sets actor.dx / actor.dy (0, 0 = stop).
// Columns wrap (the tunnel): x stays in [-0.5, w - 0.5).

function atCenter(a) {
  return Math.abs(a.x - Math.round(a.x)) < 1e-6 && Math.abs(a.y - Math.round(a.y)) < 1e-6
}

function wrapX(a, w) {
  if (a.x < -0.5) a.x += w
  else if (a.x >= w - 0.5) a.x -= w
}

function advance(a, dist, w, decide) {
  for (var guard = 0; dist > 1e-9 && guard < 64; guard++) {
    if (atCenter(a)) {
      a.x = Math.round(a.x); a.y = Math.round(a.y)
      decide(a)
      if (a.dx === 0 && a.dy === 0) return
    }
    var horiz = a.dx !== 0
    // Stay on the grid line of the axis we are not moving along.
    if (horiz) a.y = Math.round(a.y); else a.x = Math.round(a.x)
    var s = horiz ? a.dx : a.dy
    var p = horiz ? a.x : a.y
    var target = s > 0 ? Math.floor(p + 1e-6) + 1 : Math.ceil(p - 1e-6) - 1
    var need = Math.abs(target - p)
    if (dist < need - 1e-9) {
      if (horiz) a.x += s * dist; else a.y += s * dist
      dist = 0
    } else {
      if (horiz) a.x = target; else a.y = target
      dist -= need
    }
    wrapX(a, w)
  }
}

// Straight-line distance; with a board width `w` it measures across the tunnel
// seam too, so nothing slips past something else at the wrap.
function dist(a, b, w) {
  var dx = Math.abs(a.x - b.x)
  if (w) dx = Math.min(dx, w - dx)
  return Math.hypot(dx, a.y - b.y)
}

// mulberry32: a small seeded PRNG. `rng` is { s: int }; returns [0, 1).
function rand(rng) {
  var a = (rng.s + 0x6D2B79F5) | 0
  rng.s = a
  var t = Math.imul(a ^ (a >>> 15), 1 | a)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}
