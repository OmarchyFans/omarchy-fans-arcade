.pragma library

// The CPU opponent. Pure: Game.qml calls decide() every `react` seconds (a
// countdown inside step(), never a Timer) and moves the CPU striker toward the
// returned target at `speed`. Every random choice comes from the `rand` it is
// handed (the game's seeded mulberry32), so a fixed seed replays exactly.

var LEVELS = [
  { name: "Easy", tier: 1 },
  { name: "Normal", tier: 3 },
  { name: "Hard", tier: 5 }
]

// A tier's skill. Tier 1 is gentle; each match won in a 1P run moves the CPU up
// one tier, so the run gets harder. It stops improving at tier 9.
function params(tier) {
  var n = Math.max(1, Math.min(tier, 9)) - 1
  return {
    speed: 380 + 75 * n,                  // px/s the CPU striker can move
    react: Math.max(0.24 - 0.022 * n, 0.07), // s between decisions
    err: Math.max(46 - 5 * n, 6),         // px of aim error
    lead: 0.04 + 0.02 * n,                // s of puck motion it anticipates
    aim: Math.min(1, 0.35 + 0.1 * n),     // how far from centre it dares aim
    bank: n < 3 ? 0 : Math.min(0.08 * (n - 2), 0.35), // chance of a rail bank shot
    surge: n < 2 ? 0 : Math.min(0.12 * (n - 1), 0.7)   // chance to charge an attack
  }
}

// Where the puck's straight path crosses the line x = lineX, folded back off the
// long rails (a paper bank; spin and friction ignored).
function crossY(t, p, lineX) {
  if (Math.abs(p.vx) < 1) return p.y
  var y = p.y + p.vy * ((lineX - p.x) / p.vx)
  var span = (t.B - t.T) - 2 * t.r
  var rel = ((y - t.T - t.r) % (2 * span) + 2 * span) % (2 * span)
  return t.T + t.r + (rel > span ? 2 * span - rel : rel)
}

// Distance from point (px, py) to the segment (ax, ay)-(bx, by).
function segDist(ax, ay, bx, by, px, py) {
  var dx = bx - ax, dy = by - ay, l2 = dx * dx + dy * dy
  var u = l2 > 0 ? Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) : 0
  return Math.hypot(ax + dx * u - px, ay + dy * u - py)
}

// ctx: { side (1 = CPU defends the right end), puck, self, foe, table, p, serving }
// Returns { x, y, surge, mode } where mode is "attack", "reset", "block" or "defend".
function decide(ctx, rand) {
  var t = ctx.table, p = ctx.puck, s = ctx.self, k = ctx.p
  var mid = (t.L + t.R) / 2
  var dir = ctx.side === 1 ? -1 : 1           // +x points at the goal it attacks
  var homeX = ctx.side === 1 ? t.R - 70 : t.L + 70
  var goalX = ctx.side === 1 ? t.L : t.R      // the goal it shoots at
  var ownHalf = ctx.side === 1 ? p.x > mid : p.x < mid
  var towardMe = (p.vx * dir) < 0
  var jitter = (rand() * 2 - 1) * k.err

  // A fast puck coming at the goal while the CPU is goal-side of it: block. Meet
  // it on its line at the striker's own depth (never further out than home).
  var threat = towardMe && Math.abs(p.vx) > 260 && (s.x - p.x) * dir < 0
  if (threat) {
    var bx = ctx.side === 1 ? Math.min(Math.max(s.x, p.x + 10), homeX) : Math.max(Math.min(s.x, p.x - 10), homeX)
    var by = crossY(t, p, bx) + jitter * 0.4
    return { x: bx, y: by, surge: false, mode: "block" }
  }

  // Puck in the CPU's half and slow, or coming at it: go and hit it.
  if (ownHalf && (Math.abs(p.vx) < 260 || towardMe || ctx.serving)) {
    var px = p.x + p.vx * k.lead, py = p.y + p.vy * k.lead
    // Aim for the part of the mouth the other striker isn't covering; better
    // CPUs aim closer to the post, and sometimes bank it off a rail.
    var foe = ctx.foe
    var open = foe ? (foe.y > t.cy ? -1 : 1) : (rand() < 0.5 ? -1 : 1)
    var gx = goalX, gy = t.cy + open * (t.mouth - 24) * k.aim + jitter
    if (rand() < k.bank) gy = open < 0 ? 2 * t.T - gy : 2 * t.B - gy   // mirror in the rail
    var ux = gx - px, uy = gy - py, ul = Math.hypot(ux, uy) || 1
    ux /= ul; uy /= ul
    // Behind the puck (on the far side from the target goal): drive through it.
    var behind = (s.x - px) * ux + (s.y - py) * uy < -8
    if (behind) {
      return { x: px + ux * 30, y: py + uy * 30, surge: rand() < k.surge, mode: "attack" }
    }
    // Between the puck and the goal: go round it, to the side it is already on.
    var side = ((s.x - px) * -uy + (s.y - py) * ux) >= 0 ? 1 : -1
    var back = t.r + t.sr + 26
    var rx = px - ux * back - uy * side * back * 0.8
    var ry = py - uy * back + ux * side * back * 0.8
    // If the straight way there runs through the puck, step to its side first
    // (pushing it toward our own goal is how own goals happen).
    if (segDist(s.x, s.y, rx, ry, px, py) < t.r + t.sr + 4) {
      rx = px - uy * side * (back + 6)
      ry = py + ux * side * (back + 6)
    }
    return { x: rx, y: ry, surge: false, mode: "reset" }
  }

  // Otherwise guard the mouth. If the puck is on its way, meet it where it will
  // cross the guard line (bouncing off the rails on paper); if not, shadow it.
  var gyTarget = t.cy + (p.y - t.cy) * 0.5
  if (towardMe && Math.abs(p.vx) > 1) gyTarget = crossY(t, p, homeX)
  gyTarget = Math.max(t.cy - t.mouth - 10, Math.min(t.cy + t.mouth + 10, gyTarget + jitter * 0.5))
  return { x: homeX, y: gyTarget, surge: false, mode: "defend" }
}
