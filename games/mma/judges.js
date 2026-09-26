.pragma library

// Three judges score every round on the 10-point must system. Each weighs the
// round's stats a little differently (one likes strikes, one likes grappling,
// one sits between), so close fights can split.
//
// Round stats for one fighter: { dmg, td, ctrl, kd, subAtt }
//   dmg    : damage landed (head + body + legs)
//   td     : takedowns and throws landed
//   ctrl   : control time, seconds (weighted by position)
//   kd     : knockdowns scored
//   subAtt : submission attempts

var JUDGES = [
  { name: "Judge A", dmg: 1.0,  td: 4, ctrl: 0.25, kd: 10, sub: 2 },
  { name: "Judge B", dmg: 0.7,  td: 7, ctrl: 0.6,  kd: 8,  sub: 4 },
  { name: "Judge C", dmg: 0.85, td: 5, ctrl: 0.4,  kd: 9,  sub: 3 }
]
var EVEN = 2          // a margin under this is a 10-10 round
var ROUT = 40         // a margin this big (or two knockdowns more) is 10-8

function points(j, s) { return j.dmg * s.dmg + j.td * s.td + j.ctrl * s.ctrl + j.kd * s.kd + j.sub * s.subAtt }

// One judge's card for one round: [p1 points, p2 points].
function scoreRound(j, a, b) {
  var m = points(j, a) - points(j, b)
  if (Math.abs(m) < EVEN) return [10, 10]
  var rout = Math.abs(m) >= ROUT || Math.abs(a.kd - b.kd) >= 2
  return m > 0 ? [10, rout ? 8 : 9] : [rout ? 8 : 9, 10]
}

// All three judges for one round: [[a, b], [a, b], [a, b]].
function scoreAll(a, b) {
  var out = []
  for (var i = 0; i < JUDGES.length; i++) out.push(scoreRound(JUDGES[i], a, b))
  return out
}

// The decision from every round's cards (an array of scoreAll() results).
// Returns { winner: 0 | 1 | -1, kind, totals: [[a, b] per judge] }, kind being
// UNANIMOUS, SPLIT, MAJORITY, or for a draw SPLIT DRAW, MAJORITY DRAW, DRAW.
function decide(rounds) {
  var totals = [], w0 = 0, w1 = 0, even = 0
  for (var j = 0; j < JUDGES.length; j++) {
    var a = 0, b = 0
    for (var r = 0; r < rounds.length; r++) { a += rounds[r][j][0]; b += rounds[r][j][1] }
    totals.push([a, b])
    if (a > b) w0++
    else if (b > a) w1++
    else even++
  }
  var winner = -1, kind = "DRAW"
  if (w0 >= 2 || w1 >= 2) {
    winner = w0 >= 2 ? 0 : 1
    var other = winner === 0 ? w1 : w0
    kind = (w0 === 3 || w1 === 3) ? "UNANIMOUS" : (other === 1 ? "SPLIT" : "MAJORITY")
  } else if (w0 === 1 && w1 === 1) kind = "SPLIT DRAW"
  else if (even === 2) kind = "MAJORITY DRAW"
  return { winner: winner, kind: kind, totals: totals }
}
