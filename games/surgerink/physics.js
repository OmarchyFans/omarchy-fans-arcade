.pragma library

// Surge Rink physics: pure helpers, no QML. Game.qml owns the objects and calls
// these once per fixed substep (1/240 s).
//
// The table is seen from above, P1 defends the left end, P2 the right end.
//   puck    { x, y, vx, vy, spin, hot, owner }   spin in rad/s, hot in seconds
//   striker { x, y, vx, vy }                      moved by Game.qml; vx/vy are how
//                                                 far it moved this substep / dt
//   table   { L, R, T, B, cy, mouth, r, sr }      edges, goal-mouth half height,
//                                                 puck and striker radii

var FRICTION = 0.42        // 1/s: speed *= exp(-FRICTION * dt) on a cold puck
var HOT_FRICTION = 0.04    // a surged puck barely slows ...
var WALL_E = 0.86          // ... and a cold one loses a little at every wall
var HOT_WALL_E = 0.98
var STRIKE_E = 0.9         // restitution between striker and puck
var MAX_SPEED = 1500       // px/s, hard cap
var SPIN_DECAY = 1.1       // 1/s
var SPIN_K = 0.0032        // rad/s of spin per px/s of glancing striker motion
var MAX_SPIN = 2.6         // rad/s

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
function speed(o) { return Math.hypot(o.vx, o.vy) }

function setSpeed(o, s) {
  var cur = speed(o)
  if (cur < 1e-6) return
  o.vx *= s / cur; o.vy *= s / cur
}

// Swerve: a spinning puck's path bends. The velocity turns by spin*dt each step
// (the speed stays), and the spin fades.
function applySpin(p, dt) {
  if (p.spin === 0) return
  var a = p.spin * dt, c = Math.cos(a), s = Math.sin(a)
  var vx = p.vx * c - p.vy * s
  p.vy = p.vx * s + p.vy * c
  p.vx = vx
  p.spin *= Math.exp(-SPIN_DECAY * dt)
  if (Math.abs(p.spin) < 0.02) p.spin = 0
}

// Circle-against-point: the puck bounces off a goal post (the corner of a mouth).
function hitPoint(p, px, py, r, e) {
  var dx = p.x - px, dy = p.y - py
  var d = Math.hypot(dx, dy)
  if (d >= r || d < 1e-6) return false
  var nx = dx / d, ny = dy / d
  p.x = px + nx * r; p.y = py + ny * r
  var vn = p.vx * nx + p.vy * ny
  if (vn < 0) { p.vx -= (1 + e) * vn * nx; p.vy -= (1 + e) * vn * ny }
  return true
}

// One substep for the puck. Returns { goal, wall }:
//   goal 1 = P1 scored (the puck went into the right mouth), 2 = P2 scored,
//   0 = none; wall = true when it bounced off a rail or post this step.
function stepPuck(p, dt, t) {
  var out = { goal: 0, wall: false }
  applySpin(p, dt)
  var hot = p.hot > 0
  p.vx *= Math.exp(-(hot ? HOT_FRICTION : FRICTION) * dt)
  p.vy *= Math.exp(-(hot ? HOT_FRICTION : FRICTION) * dt)
  if (speed(p) > MAX_SPEED) setSpeed(p, MAX_SPEED)
  if (hot) { p.hot = Math.max(0, p.hot - dt); if (p.hot === 0) p.owner = -1 }
  p.x += p.vx * dt
  p.y += p.vy * dt

  var e = hot ? HOT_WALL_E : WALL_E
  var r = t.r
  // Long rails (top and bottom).
  if (p.y - r < t.T) { p.y = t.T + r; p.vy = Math.abs(p.vy) * e; p.spin *= 0.5; out.wall = true }
  if (p.y + r > t.B) { p.y = t.B - r; p.vy = -Math.abs(p.vy) * e; p.spin *= 0.5; out.wall = true }

  // End rails with a goal mouth in the middle. Inside the mouth the only thing in
  // the way is the pair of posts; past the goal line (centre over it) is a goal.
  var inMouth = Math.abs(p.y - t.cy) < t.mouth
  if (p.x - r < t.L) {
    if (inMouth) {
      if (hitPoint(p, t.L, t.cy - t.mouth, r, e) || hitPoint(p, t.L, t.cy + t.mouth, r, e)) out.wall = true
      if (p.x < t.L) out.goal = 2
    } else { p.x = t.L + r; p.vx = Math.abs(p.vx) * e; p.spin *= 0.5; out.wall = true }
  }
  if (p.x + r > t.R) {
    if (inMouth) {
      if (hitPoint(p, t.R, t.cy - t.mouth, r, e) || hitPoint(p, t.R, t.cy + t.mouth, r, e)) out.wall = true
      if (p.x > t.R) out.goal = 1
    } else { p.x = t.R - r; p.vx = -Math.abs(p.vx) * e; p.spin *= 0.5; out.wall = true }
  }
  return out
}

// Striker against puck. The striker is driven by a hand, so it is treated as
// infinitely heavy: the puck's velocity relative to the striker is reflected along
// the contact normal (restitution STRIKE_E), which hands the striker's own speed
// to the puck. A glancing, sideways striker motion also puts spin on the puck.
// `mul` > 1 is a Surge smash: the outgoing speed is multiplied (with a floor).
// Returns true when the two actually struck (were closing), not just touched.
function strike(p, s, t, mul) {
  var dx = p.x - s.x, dy = p.y - s.y
  var d = Math.hypot(dx, dy), min = t.r + t.sr
  if (d >= min) return false
  var nx, ny
  if (d < 1e-6) { nx = 1; ny = 0 } else { nx = dx / d; ny = dy / d }
  p.x = s.x + nx * min; p.y = s.y + ny * min
  var rvx = p.vx - s.vx, rvy = p.vy - s.vy
  var vn = rvx * nx + rvy * ny
  if (vn >= 0) return false
  p.vx -= (1 + STRIKE_E) * vn * nx
  p.vy -= (1 + STRIKE_E) * vn * ny
  // Tangential striker speed (along the rim) becomes spin.
  var vt = -s.vx * ny + s.vy * nx
  p.spin = clamp(p.spin * 0.3 - vt * SPIN_K, -MAX_SPIN, MAX_SPIN)
  if (mul > 1) setSpeed(p, Math.max(speed(p), 420) * mul)
  if (speed(p) > MAX_SPEED) setSpeed(p, MAX_SPEED)
  return true
}

// Keep a pushed puck inside the rails (outside the mouths), so a striker can't
// shove it through a wall.
function keepIn(p, t) {
  p.y = clamp(p.y, t.T + t.r, t.B - t.r)
  if (Math.abs(p.y - t.cy) >= t.mouth) p.x = clamp(p.x, t.L + t.r, t.R - t.r)
}

// Where a striker may go: its own half, inside the rails.
function bounds(side, t) {
  var mid = (t.L + t.R) / 2
  return side === 0
    ? { x0: t.L + t.sr, x1: mid - t.sr, y0: t.T + t.sr, y1: t.B - t.sr }
    : { x0: mid + t.sr, x1: t.R - t.sr, y0: t.T + t.sr, y1: t.B - t.sr }
}

// Move striker s toward (tx, ty) at no more than maxSpeed, inside `b`, and
// record the velocity it actually moved with (what a strike hands the puck).
function moveTo(s, tx, ty, maxSpeed, dt, b) {
  var ox = s.x, oy = s.y
  var dx = tx - s.x, dy = ty - s.y
  var d = Math.hypot(dx, dy), step = maxSpeed * dt
  if (d > step) { dx *= step / d; dy *= step / d }
  s.x = clamp(s.x + dx, b.x0, b.x1)
  s.y = clamp(s.y + dy, b.y0, b.y1)
  s.vx = (s.x - ox) / dt; s.vy = (s.y - oy) / dt
}

// Move striker s by a velocity (keyboard), inside `b`, recording what it did.
function moveBy(s, vx, vy, dt, b) {
  var ox = s.x, oy = s.y
  s.x = clamp(s.x + vx * dt, b.x0, b.x1)
  s.y = clamp(s.y + vy * dt, b.y0, b.y1)
  s.vx = (s.x - ox) / dt; s.vy = (s.y - oy) / dt
}
