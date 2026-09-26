.pragma library

// Glintfall's piece family, its rotation and kick rules, and the seeded dice.
//
// The well is 12 columns by 22 visible rows, with 2 hidden rows on top where
// pieces appear. The pieces are Glintfall's own family: two small three-cell
// relief pieces and eight five-cell pieces. There are no four-cell pieces.
// Each shape lives in an N×N box and turns inside it: clockwise is
// (x, y) -> (N-1-y, x). Turning keeps the order of the cells, so a piece's glint
// (one marked cell, see Game.qml) stays on the same cell as it turns.

var COLS = 12
var ROWS = 22          // visible rows
var HIDDEN = 2         // rows above the well where pieces appear
var TOTAL = ROWS + HIDDEN

// color is a theme key; fallback is used when the theme has no such key.
// The theme only has 8 vivid keys (accent, red, orange, yellow, green, cyan, blue,
// magenta) for 10 shapes, so two pairs must still share; every other shape gets
// its own key so only crook/pip (yellow) and zig/flag (red) look alike.
var SHAPES = [
  { id: "hook",   name: "Hook",   color: "orange",  fallback: "#ff9e64", rows: ["#.", "##"] },
  { id: "pip",    name: "Pip",    color: "yellow",  fallback: "#e0af68", rows: ["...", "###", "..."] },
  { id: "arch",   name: "Arch",   color: "green",   fallback: "#9ece6a", rows: ["#.#", "###", "..."] },
  { id: "star",   name: "Star",   color: "magenta", fallback: "#bb9af7", rows: [".#.", "###", ".#."] },
  { id: "stair",  name: "Stair",  color: "blue",    fallback: "#7aa2f7", rows: ["#..", "##.", ".##"] },
  { id: "flag",   name: "Flag",   color: "red",     fallback: "#f7768e", rows: ["##.", "##.", "#.."] },
  { id: "anchor", name: "Anchor", color: "cyan",    fallback: "#7dcfff", rows: ["###", ".#.", ".#."] },
  { id: "branch", name: "Branch", color: "accent",  fallback: "#c0caf5", rows: ["....", "####", ".#..", "...."] },
  { id: "crook",  name: "Crook",  color: "yellow",  fallback: "#e0af68", rows: ["....", "####", "#...", "...."] },
  { id: "zig",    name: "Zig",    color: "red",     fallback: "#f7768e", rows: ["....", "##..", ".###", "...."] }
]

// Kicks: when a turn collides, try these offsets in order ([dx, dy], dy < 0 is
// up) and take the first that fits. Glintfall's rule: sideways by one (right
// first), then one row up, then sideways by two. If none fits, the turn fails.
var KICKS = [[0, 0], [1, 0], [-1, 0], [0, -1], [2, 0], [-2, 0]]

// Built once: ROT[shape index][rotation 0..3] = [[x, y], ...] in the shape's box.
var ROT = (function () {
  var all = []
  for (var s = 0; s < SHAPES.length; s++) {
    var rows = SHAPES[s].rows, n = rows.length, base = []
    for (var y = 0; y < n; y++)
      for (var x = 0; x < n; x++)
        if (rows[y].charAt(x) === "#") base.push([x, y])
    var rots = [base]
    for (var r = 1; r < 4; r++) {
      var prev = rots[r - 1], next = []
      for (var i = 0; i < prev.length; i++) next.push([n - 1 - prev[i][1], prev[i][0]])
      rots.push(next)
    }
    all.push(rots)
  }
  return all
})()

function indexOf(id) {
  for (var i = 0; i < SHAPES.length; i++) if (SHAPES[i].id === id) return i
  return -1
}
function shape(id) { var i = indexOf(id); return i >= 0 ? SHAPES[i] : null }
function size(id) { var s = shape(id); return s ? s.rows.length : 0 }
// The cells of a shape at a rotation (any integer; it wraps), relative to its box.
function cells(id, rot) {
  var i = indexOf(id)
  if (i < 0) return []
  return ROT[i][((rot % 4) + 4) % 4]
}

// The bounding box of a shape at a rotation, for centering previews.
function bounds(id, rot) {
  var c = cells(id, rot), b = { minX: 99, maxX: -1, minY: 99, maxY: -1 }
  for (var i = 0; i < c.length; i++) {
    b.minX = Math.min(b.minX, c[i][0]); b.maxX = Math.max(b.maxX, c[i][0])
    b.minY = Math.min(b.minY, c[i][1]); b.maxY = Math.max(b.maxY, c[i][1])
  }
  return b
}

// Points for rows cleared by one piece (times the level).
var ROW_POINTS = [0, 100, 250, 450, 700, 1000]
function rowPoints(n) { return ROW_POINTS[Math.min(n, ROW_POINTS.length - 1)] }
// Each cell a glint burst takes outside the cleared rows, and each burst itself.
var BURST_CELL = 20
var BURST_EACH = 50

// Level: one more every LINES_PER_LEVEL rows. Gravity: seconds per row.
var LINES_PER_LEVEL = 8
function fallInterval(level) { return Math.max(0.06, 0.8 * Math.pow(0.84, level - 1)) }
// Glints get rarer as the levels climb, so the helper thins out as the speed rises.
// Level 1 used to glint 40% of pieces, and a 3x3 burst clears so much of the board
// that early levels barely challenged anyone; started lower (18%) and thins out more
// gently so bursts stay a mid-game tool rather than a level-1 crutch.
function glintChance(level) { return Math.max(0.1, 0.18 - 0.015 * (level - 1)) }

// mulberry32: a tiny seeded PRNG. rand(state) -> { v: [0, 1), s: next state }.
function rand(state) {
  var s = (state + 0x6D2B79F5) | 0
  var t = s
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { v: ((t ^ (t >>> 14)) >>> 0) / 4294967296, s: s }
}
