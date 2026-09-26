.pragma library

// Surge Rink physics: pure helpers, no QML. Game.qml owns the objects and calls
// these once per fixed substep (1/240 s).
//
// The table is seen from above, P1 defends the left end, P2 the right end.
//   puck    { x, y, vx, vy, spin, hot, owner }   spin in rad/s, hot in seconds
//   striker { x, y, vx, vy, touching }            moved by Game.qml; vx/vy are how
//                                                 far it moved this substep / dt;
//                                                 touching: in contact since the
//                                                 last substep (strike() keeps it)
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
// `dir` is the way into the table from that end (+1 at the left end, -1 at the
// right); a puck centred exactly on the post is pushed that way.
function hitPoint(p, px, py, r, e, dir) {
  var dx = p.x - px, dy = p.y - py
  var d = Math.hypot(dx, dy)
  if (d >= r) return false
  var nx, ny
  if (d < 1e-6) { nx = dir || 1; ny = 0 } else { nx = dx / d; ny = dy / d }
  p.x = px + nx * r; p.y = py + ny * r
  var vn = p.vx * nx + p.vy * ny
  if (vn < 0) { p.vx -= (1 + e) * vn * nx; p.vy -= (1 + e) * vn * ny }
  return true
}

// One end rail (x0 = t.L with dir +1, or t.R with dir -1) with its goal mouth.
// Inside the mouth band the only things in the way are the two posts; outside it
// the flat rail. `oy` is the puck's y before this move: a puck that was inside the
// band, close to the goal line, can't leave the band sideways without meeting the
// post, so it is put back on the band side and bounces off the post instead of
// jumping through it onto the rail (the old clamp moved it out to x0 + r). Returns true when it touched.
function endRail(p, t, x0, dir, e, oy) {
  var r = t.r
  if ((p.x - x0) * dir >= r) return false
  var top = t.cy - t.mouth, bot = t.cy + t.mouth
  var inBand = Math.abs(p.y - t.cy) < t.mouth
  if (!inBand && oy !== undefined && Math.abs(oy - t.cy) < t.mouth) {
    // Back to where its edge first met the post, just inside; hitPoint below
    // then bounces it off the post along the real contact normal.
    var ex = (p.x - x0) * dir
    var h = Math.sqrt(Math.max(0, r * r - ex * ex)) * 0.999
    p.y = p.y < t.cy ? top + h : bot - h
    inBand = true
  }
  if (inBand) {
    var a = hitPoint(p, x0, top, r, e, dir)
    var b = hitPoint(p, x0, bot, r, e, dir)
    return a || b
  }
  p.x = x0 + dir * r; p.vx = dir * Math.abs(p.vx) * e; p.spin *= 0.5
  return true
}

// Keep the puck on the table: the long rails, then both end rails and posts.
// Velocity into a rail is reflected with restitution e. Returns true when any
// rail or post was touched.
function confine(p, t, e, oy) {
  var r = t.r, hit = false
  if (p.y - r < t.T) { p.y = t.T + r; p.vy = Math.abs(p.vy) * e; p.spin *= 0.5; hit = true }
  if (p.y + r > t.B) { p.y = t.B - r; p.vy = -Math.abs(p.vy) * e; p.spin *= 0.5; hit = true }
  if (endRail(p, t, t.L, 1, e, oy)) hit = true
  if (endRail(p, t, t.R, -1, e, oy)) hit = true
  return hit
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
  var oy = p.y
  p.x += p.vx * dt
  p.y += p.vy * dt

  out.wall = confine(p, t, hot ? HOT_WALL_E : WALL_E, oy)
  // Past a goal line (centre over it) inside the mouth is a goal.
  if (Math.abs(p.y - t.cy) < t.mouth) {
    if (p.x < t.L) out.goal = 2
    else if (p.x > t.R) out.goal = 1
  }
  return out
}

// Striker against puck, once per substep for each striker.
//
// Position first: the two may never overlap. The puck is pushed out along the
// contact normal; if a rail, post or corner stops it (it is pinned), whatever
// overlap is left pushes the striker back instead, inside its bounds `b`. So a
// puck can't be swallowed by a striker leaning on it against a rail.
//
// Then velocity. The striker is driven by a hand, so it is treated as infinitely
// heavy. On the first substep of a contact (s.touching false) the puck's velocity
// relative to the striker is reflected along the normal (restitution STRIKE_E),
// which hands the striker's own speed to the puck; a glancing, sideways striker
// motion also puts spin on it, and `mul` > 1 is a Surge smash (the outgoing speed
// is multiplied, with a floor). While the contact lasts (the striker keeps
// pushing, or the puck is pinned) there is no more restitution, spin or smash:
// the puck only stops closing on the striker, so it can never go faster than the
// striker pushes it. A pinned puck also loses any velocity into the rail that
// holds it (it can only slide along it). That is what stops a pinned puck from
// being pumped faster every substep.
// Returns true for a real strike (first contact, closing), not for a push.
function strike(p, s, t, mul, b) {
  var min = t.r + t.sr
  var dx = p.x - s.x, dy = p.y - s.y
  var d = Math.hypot(dx, dy)
  // A contact ends once they are clearly apart (1 px of slack), not on the
  // substep a push leaves them exactly touching.
  if (d >= min) { if (d >= min + 1) s.touching = false; return false }
  var fresh = !s.touching
  s.touching = true
  var nx, ny
  if (d < 1e-6) { nx = s.x < (t.L + t.R) / 2 ? 1 : -1; ny = 0 } else { nx = dx / d; ny = dy / d }

  // Position: the puck out along the normal and kept on the table ...
  var oy = p.y, tx = s.x + nx * min, ty = s.y + ny * min
  p.x = tx; p.y = ty
  confine(p, t, WALL_E, oy)
  // ... and if the table pushed it back (pinned), the rest comes out of the
  // striker. mx, my: the way the rail or post holds the puck (into the table).
  var mx = p.x - tx, my = p.y - ty, ml = Math.hypot(mx, my)
  var pinned = ml > 1e-6
  var svx = s.vx, svy = s.vy
  if (pinned) {
    mx /= ml; my /= ml
    dx = p.x - s.x; dy = p.y - s.y; d = Math.hypot(dx, dy)
    if (d > 1e-6) { nx = dx / d; ny = dy / d }
    if (d < min) {
      s.x = p.x - nx * min; s.y = p.y - ny * min
      if (b) { s.x = clamp(s.x, b.x0, b.x1); s.y = clamp(s.y, b.y0, b.y1) }
      // A striker pushed back is no longer driving into the puck.
      var sn = s.vx * nx + s.vy * ny
      if (sn > 0) { s.vx -= sn * nx; s.vy -= sn * ny }
    }
  }

  // Velocity, from the striker's motion this substep.
  var rvx = p.vx - svx, rvy = p.vy - svy
  var vn = rvx * nx + rvy * ny
  var struck = false
  if (vn < 0) {
    if (fresh) {
      p.vx -= (1 + STRIKE_E) * vn * nx
      p.vy -= (1 + STRIKE_E) * vn * ny
      // Tangential striker speed (along the rim) becomes spin.
      var vt = -svx * ny + svy * nx
      p.spin = clamp(p.spin * 0.3 - vt * SPIN_K, -MAX_SPIN, MAX_SPIN)
      if (mul > 1) setSpeed(p, Math.max(speed(p), 420) * mul)
      struck = true
    } else {
      p.vx -= vn * nx; p.vy -= vn * ny
    }
  }
  if (pinned) {
    var vm = p.vx * mx + p.vy * my
    if (vm < 0) { p.vx -= vm * mx; p.vy -= vm * my }
  }
  if (speed(p) > MAX_SPEED) setSpeed(p, MAX_SPEED)
  return struck
}

// A last safety net after the strikes: the puck is on the table.
function keepIn(p, t, oy) { return confine(p, t, WALL_E, oy) }

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
