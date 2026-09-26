.pragma library

// Circuit Crawl boards. Each maze is 21x21 tiles, written as LEFT HALVES of 11
// characters and mirrored at load: full row = half + reverse(half without its
// last character), so column 10 is the centre line.
//   #  wall (board copper and solder mask)
//   .  bit, 10 points
//   o  debug chip, 50 points: bugs become patchable
//   ' ' path without a bit
//   -  pen door (bugs pass, Byte does not)
//   B  pen tile (where the bugs wait)
//   P  Byte's start
//   T  tunnel tile: the row wraps left <-> right
// After the last maze the list starts over, a little faster each time.

var MAZES = [
  { name: "Motherboard", half: [
    "###########",
    "#o........#",
    "#.##.####.#",
    "#..........",
    "#.##.#.####",
    "#....#....#",
    "####.####.#",
    "####.#     ",
    "####.# ###-",
    "T   .  #BBB",
    "####.# ####",
    "####.#     ",
    "####.#.####",
    "#.........#",
    "#.##.####.#",
    "#o.#......P",
    "##.#.#.####",
    "#....#....#",
    "#.#######.#",
    "#..........",
    "###########"
  ] },
  { name: "Northbridge", half: [
    "###########",
    "#o...#....#",
    "#.#.#.###.#",
    "#.#........",
    "#...##.#.##",
    "###....#...",
    "###.##.####",
    "###.#      ",
    "###.# ####-",
    "T   . ##BBB",
    "###.# #####",
    "###.#      ",
    "###.#.###.#",
    "#.....#....",
    "#.###.#.##.",
    "#o..#....#P",
    "###.#.##.##",
    "#.....#....",
    "#.###.#.###",
    "#o.........",
    "###########"
  ] }
]

function mirrorRow(half) {
  return half + half.slice(0, -1).split("").reverse().join("")
}

function expand(half) {
  var out = []
  for (var i = 0; i < half.length; i++) out.push(mirrorRow(half[i]))
  return out
}

function forLevel(level) { // level counts from 1
  return MAZES[(level - 1) % MAZES.length]
}

// Everything the game needs to know about one maze.
function parse(rows) {
  var m = {
    rows: rows, h: rows.length, w: rows.length ? rows[0].length : 0,
    start: null, starts: 0, pen: [], door: null, doors: 0,
    bits: 0, chips: 0, tunnels: [], rectangular: true
  }
  for (var r = 0; r < rows.length; r++) {
    if (rows[r].length !== m.w) m.rectangular = false
    for (var c = 0; c < rows[r].length; c++) {
      var ch = rows[r].charAt(c)
      if (ch === "P") { m.start = { c: c, r: r }; m.starts++ }
      else if (ch === "B") m.pen.push({ c: c, r: r })
      else if (ch === "-") { m.door = { c: c, r: r }; m.doors++ }
      else if (ch === ".") m.bits++
      else if (ch === "o") m.chips++
      else if (ch === "T") m.tunnels.push({ c: c, r: r })
    }
  }
  if (m.door) {
    m.exit = { c: m.door.c, r: m.door.r - 1 }      // the path tile just outside the door
    m.penCenter = { c: m.door.c, r: m.door.r + 1 } // where a bug waits and lands
    m.coffee = { c: m.door.c, r: m.door.r + 3 }    // the bonus spot below the pen
  }
  return m
}

function wrapCol(m, c) { return ((c % m.w) + m.w) % m.w }

function tile(m, c, r) {
  r = Math.round(r)
  if (r < 0 || r >= m.h) return "#"
  return m.rows[r].charAt(wrapCol(m, Math.round(c)))
}

// Where an actor may walk in normal movement. The door and the pen are only
// crossed by the bugs' scripted moves (leaving the pen, landing after a squash).
function walkable(m, c, r) {
  var t = tile(m, c, r)
  return t !== "#" && t !== "-" && t !== "B" && t !== ""
}

function key(m, c, r) { return r * m.w + wrapCol(m, c) }

// Breadth-first search over walkable tiles (with the tunnel wrap).
// Returns { dist: {key: steps}, first: {key: index into DIRS of the first step} }.
var DIRS = [{ dx: 0, dy: -1 }, { dx: -1, dy: 0 }, { dx: 0, dy: 1 }, { dx: 1, dy: 0 }]

function bfs(m, from) {
  var dist = {}, first = {}
  var q = [{ c: wrapCol(m, from.c), r: from.r }]
  dist[key(m, from.c, from.r)] = 0
  for (var qi = 0; qi < q.length; qi++) {
    var cur = q[qi], ck = key(m, cur.c, cur.r)
    for (var d = 0; d < DIRS.length; d++) {
      var nc = wrapCol(m, cur.c + DIRS[d].dx), nr = cur.r + DIRS[d].dy
      if (!walkable(m, nc, nr)) continue
      var nk = key(m, nc, nr)
      if (dist[nk] !== undefined) continue
      dist[nk] = dist[ck] + 1
      first[nk] = qi === 0 ? d : first[ck]
      q.push({ c: nc, r: nr })
    }
  }
  return { dist: dist, first: first }
}

// The first step (index into DIRS) of a shortest path from -> to, or -1.
// Used by a squashed bug heading home, so it can never orbit a block forever.
function stepToward(m, from, to) {
  // Search backwards from the goal: the best step from `from` is the neighbour
  // closest to the goal.
  var back = bfs(m, to)
  var best = -1, bestD = 1e9
  for (var d = 0; d < DIRS.length; d++) {
    var nc = from.c + DIRS[d].dx, nr = from.r + DIRS[d].dy
    if (!walkable(m, nc, nr)) continue
    var dd = back.dist[key(m, nc, nr)]
    if (dd !== undefined && dd < bestD) { bestD = dd; best = d }
  }
  return best
}

// The rules every maze must meet. Returns a list of problems ([] = valid).
function validate(m) {
  var out = []
  if (!m.rectangular || m.w !== 21 || m.h !== 21) out.push("not 21x21")
  for (var r = 0; r < m.h; r++)
    for (var c = 0; c < m.w; c++)
      if (m.rows[r].charAt(c) !== m.rows[r].charAt(m.w - 1 - c)) { out.push("not mirrored at row " + r); r = m.h; break }
  if (m.starts !== 1) out.push(m.starts + " starts")
  if (m.pen.length < 1) out.push("no pen")
  if (m.doors !== 1) out.push(m.doors + " doors")
  if (!m.start) return out
  var seen = bfs(m, m.start).dist
  for (r = 0; r < m.h; r++)
    for (c = 0; c < m.w; c++) {
      var ch = m.rows[r].charAt(c)
      if ((ch === "." || ch === "o") && seen[key(m, c, r)] === undefined) out.push("unreachable " + ch + " at " + c + "," + r)
    }
  if (m.exit && seen[key(m, m.exit.c, m.exit.r)] === undefined) out.push("pen exit unreachable")
  if (m.coffee && !walkable(m, m.coffee.c, m.coffee.r)) out.push("coffee spot is not a path")
  return out
}
