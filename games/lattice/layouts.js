.pragma library

// Lattice Siege formations. Every row is 10 columns.
//   .  empty slot
//   n  node      a spinning diamond drone, one hit
//   r  relay     a ringed satellite, one hit, worth more
//   p  prism     an eight-point star, two hits
//
// Enemies are wired together into constellations: every unbroken run of
// enemies in a row is one constellation, cut into pieces of at most three
// (a run of 8 becomes 3 + 3 + 2). A constellation flies in together and is
// drawn linked by lines; destroying all of it scores a bonus, and doing it
// fast (a "link snap") earns a wing drone.
//
// Every fourth stage is a Monolith (the boss) instead of a formation. The
// formations below repeat after the last one, the game getting harder as the
// stage number climbs.

var COLS = 10

var LAYOUTS = [
  { name: "Wedge", rows: [
    "....pp....",
    "...rrrr...",
    "..nnnnnn..",
    ".nnnnnnnn."
  ] },
  { name: "Crown", rows: [
    "pp..pp..pp",
    "rrr.rr.rrr",
    "nnnnnnnnnn",
    "..nn..nn.."
  ] },
  { name: "Twin Arrays", rows: [
    "rrr....rrr",
    "nnnnnnnnnn",
    "pp..pp..pp",
    "nnnnnnnnnn"
  ] },
  { name: "Arrowheads", rows: [
    ".pp....pp.",
    "rrrr..rrrr",
    "nnnnnnnnnn",
    ".nnn..nnn."
  ] },
  { name: "Columns", rows: [
    "rr..pp..rr",
    "nnrrnnrrnn",
    "nnnnnnnnnn",
    "nn.nnnn.nn"
  ] },
  { name: "Bastion", rows: [
    "pppppppppp",
    "rrrrrrrrrr",
    "nnnnnnnnnn",
    "nnnnnnnnnn"
  ] }
]

function isBoss(stage) { return stage > 0 && stage % 4 === 0 }
function bossNumber(stage) { return Math.floor(stage / 4) }   // 1 for stage 4, 2 for stage 8...

// The formation for a (non-boss) stage: formations count only non-boss stages.
function layoutFor(stage) {
  var n = stage - Math.floor(stage / 4)          // how many formation stages so far
  return LAYOUTS[(Math.max(1, n) - 1) % LAYOUTS.length]
}

function stageName(stage) { return isBoss(stage) ? "Monolith" : layoutFor(stage).name }

// A run of n enemies cut into constellations of at most three, as even as possible.
function chunk(n) {
  if (n <= 3) return [n]
  var k = Math.ceil(n / 3), base = Math.floor(n / k), extra = n % k, out = []
  for (var i = 0; i < k; i++) out.push(base + (i < extra ? 1 : 0))
  return out
}

function hpFor(kind) { return kind === "p" ? 2 : 1 }

// Points for destroying an enemy; one caught mid-dive is worth double. Our own
// numbers, deliberately not a famous formation shooter's bee/butterfly/boss table.
function pointsFor(kind, diving) {
  var p = kind === "p" ? 170 : (kind === "r" ? 90 : 40)
  return diving ? p * 2 : p
}

// Bonus for a whole constellation: 100 per member, doubled for a link snap.
function groupBonus(size, snap) { return size * 100 * (snap ? 2 : 1) }

// Rows -> the enemies (kind, slot, constellation and place in it) and the
// size of every constellation, top row first.
function build(rows) {
  var members = [], sizes = []
  for (var r = 0; r < rows.length; r++) {
    var c = 0
    while (c < COLS) {
      if (rows[r].charAt(c) === "." || rows[r].charAt(c) === "") { c++; continue }
      var start = c
      while (c < COLS && rows[r].charAt(c) !== "." && rows[r].charAt(c) !== "") c++
      var parts = chunk(c - start), col = start
      for (var p = 0; p < parts.length; p++) {
        var g = sizes.length
        sizes.push(parts[p])
        for (var k = 0; k < parts[p]; k++) {
          members.push({ kind: rows[r].charAt(col), col: col, row: r, group: g, order: k })
          col++
        }
      }
    }
  }
  return { members: members, sizes: sizes }
}
