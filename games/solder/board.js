.pragma library

// Solder Snap board rules: pure functions over an 8×8 board, no QML.
//
// A board is { k: [64 kinds], s: [64 specials] }, indexed r * 8 + c with row 0 at
// the top. Kinds 0..5 are the six components (see levels.js); CORE is the wild
// "Core" chip made by a five-in-a-row; FRIED is a burnt-out part that never matches
// and is repaired (cleared) by a line touching it (corners count) or a blast over it; EMPTY is a
// hole waiting for gravity. A special rides on a normal tile:
//   "h" H-bus  clears its whole row when it goes off
//   "v" V-bus  clears its whole column
//   "x" Surge  clears a diamond (every cell within two steps, 13 cells)

var N = 8
var EMPTY = -1
var CORE = 6
var FRIED = 7

function idx(r, c) { return r * N + c }
function rowOf(i) { return Math.floor(i / N) }
function colOf(i) { return i % N }
function matchable(k) { return k >= 0 && k < CORE }
function inside(i) { return i >= 0 && i < N * N }

function adjacent(a, b) {
  if (!inside(a) || !inside(b)) return false
  return Math.abs(rowOf(a) - rowOf(b)) + Math.abs(colOf(a) - colOf(b)) === 1
}

// The cell dr rows and dc columns away, or -1 off the board (no wrap-around).
function neighbor(i, dr, dc) {
  var r = rowOf(i) + dr, c = colOf(i) + dc
  return (r < 0 || r >= N || c < 0 || c >= N) ? -1 : idx(r, c)
}

function neighbors(i) {
  var out = [], d = [[-1, 0], [1, 0], [0, -1], [0, 1]]
  for (var n = 0; n < 4; n++) {
    var j = neighbor(i, d[n][0], d[n][1])
    if (j >= 0) out.push(j)
  }
  return out
}

// The up-to-eight cells touching i, corners included (what a line repairs).
function touching(i) {
  var out = []
  for (var dr = -1; dr <= 1; dr++)
    for (var dc = -1; dc <= 1; dc++) {
      if (dr === 0 && dc === 0) continue
      var j = neighbor(i, dr, dc)
      if (j >= 0) out.push(j)
    }
  return out
}

// mulberry32: one step of the seeded generator. Returns the next state and a
// value in [0, 1). The game keeps the state; nothing here is global.
function mulberry(state) {
  var a = (state + 0x6D2B79F5) | 0
  var t = a
  t = Math.imul(t ^ (t >>> 15), t | 1)
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
  return { state: a, value: ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
}

// Every maximal straight line of three or more equal components.
// Each run is { dir: "h" | "v", kind, cells: [indices in order] }.
function findRuns(k) {
  var runs = [], r, c, e, kind, cells, j
  for (r = 0; r < N; r++) {
    c = 0
    while (c < N) {
      kind = k[idx(r, c)]
      e = c + 1
      while (e < N && k[idx(r, e)] === kind) e++
      if (matchable(kind) && e - c >= 3) {
        cells = []
        for (j = c; j < e; j++) cells.push(idx(r, j))
        runs.push({ dir: "h", kind: kind, cells: cells })
      }
      c = e
    }
  }
  for (c = 0; c < N; c++) {
    r = 0
    while (r < N) {
      kind = k[idx(r, c)]
      e = r + 1
      while (e < N && k[idx(e, c)] === kind) e++
      if (matchable(kind) && e - r >= 3) {
        cells = []
        for (j = r; j < e; j++) cells.push(idx(j, c))
        runs.push({ dir: "v", kind: kind, cells: cells })
      }
      r = e
    }
  }
  return runs
}

function hasMatch(k) { return findRuns(k).length > 0 }

// Runs that share a cell are one group: an L, a T or a plus is one match.
// Each group is { kind, cells: [unique], runs: [...] }, in run order.
function groupRuns(runs) {
  var parent = [], owner = {}, i, j
  for (i = 0; i < runs.length; i++) parent.push(i)
  function find(x) { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x] } return x }
  for (i = 0; i < runs.length; i++) {
    for (j = 0; j < runs[i].cells.length; j++) {
      var cell = runs[i].cells[j]
      if (owner[cell] === undefined) owner[cell] = i
      else { var a = find(owner[cell]), b = find(i); if (a !== b) parent[Math.max(a, b)] = Math.min(a, b) }
    }
  }
  var byRoot = {}, groups = []
  for (i = 0; i < runs.length; i++) {
    var root = find(i)
    if (byRoot[root] === undefined) { byRoot[root] = groups.length; groups.push({ kind: runs[i].kind, cells: [], runs: [], seen: {} }) }
    var g = groups[byRoot[root]]
    g.runs.push(runs[i])
    for (j = 0; j < runs[i].cells.length; j++) {
      var c2 = runs[i].cells[j]
      if (!g.seen[c2]) { g.seen[c2] = true; g.cells.push(c2) }
    }
  }
  for (i = 0; i < groups.length; i++) delete groups[i].seen
  return groups
}

// What a group builds, or null for a plain three:
//   five or more in one line  -> "core"   (a wild Core chip)
//   two lines crossing (L/T/+) -> "x"      (Surge)
//   four in a row              -> "h"      (H-bus); four in a column -> "v"
// It is built on the first cell of `pref` inside the group (the tile the player
// moved), else where the lines cross, else near the middle of the longest line.
function specialFor(group, pref) {
  var longest = group.runs[0], i
  for (i = 1; i < group.runs.length; i++) if (group.runs[i].cells.length > longest.cells.length) longest = group.runs[i]
  var type
  if (longest.cells.length >= 5) type = "core"
  else if (group.runs.length >= 2) type = "x"
  else if (longest.cells.length === 4) type = longest.dir
  else return null
  var inGroup = {}
  for (i = 0; i < group.cells.length; i++) inGroup[group.cells[i]] = true
  var at = -1
  for (i = 0; pref && i < pref.length && at < 0; i++) if (inGroup[pref[i]]) at = pref[i]
  if (at < 0 && type === "x") {
    var count = {}
    for (i = 0; i < group.runs.length && at < 0; i++)
      for (var j = 0; j < group.runs[i].cells.length && at < 0; j++) {
        var c = group.runs[i].cells[j]
        count[c] = (count[c] || 0) + 1
        if (count[c] >= 2) at = c
      }
  }
  if (at < 0) at = longest.cells[Math.floor((longest.cells.length - 1) / 2)]
  return { type: type, at: at, kind: group.kind }
}

// Does the tile at i sit in a line of three?
function matchAt(k, i) {
  var kind = k[i]
  if (!matchable(kind)) return false
  var r = rowOf(i), c = colOf(i), n = 1, j
  for (j = c - 1; j >= 0 && k[idx(r, j)] === kind; j--) n++
  for (j = c + 1; j < N && k[idx(r, j)] === kind; j++) n++
  if (n >= 3) return true
  n = 1
  for (j = r - 1; j >= 0 && k[idx(j, c)] === kind; j--) n++
  for (j = r + 1; j < N && k[idx(j, c)] === kind; j++) n++
  return n >= 3
}

// Can the swap a <-> b be played? A Core goes with anything movable, two specials
// go off together, and anything else must make a line.
function swapWorks(b, i, j) {
  var ki = b.k[i], kj = b.k[j]
  if (ki < 0 || kj < 0 || ki === FRIED || kj === FRIED) return false
  if (ki === CORE || kj === CORE) return true
  if (b.s[i] && b.s[j]) return true
  if (ki === kj) return false
  b.k[i] = kj; b.k[j] = ki
  var ok = matchAt(b.k, i) || matchAt(b.k, j)
  b.k[i] = ki; b.k[j] = kj
  return ok
}

// The first playable swap, scanning from the top left, or null: no moves left.
function findMove(b) {
  for (var i = 0; i < N * N; i++) {
    var right = colOf(i) < N - 1 ? i + 1 : -1, down = rowOf(i) < N - 1 ? i + N : -1
    if (right >= 0 && swapWorks(b, i, right)) return [i, right]
    if (down >= 0 && swapWorks(b, i, down)) return [i, down]
  }
  return null
}

// Every playable swap (for the hint and for tests).
function allMoves(b) {
  var out = []
  for (var i = 0; i < N * N; i++) {
    var right = colOf(i) < N - 1 ? i + 1 : -1, down = rowOf(i) < N - 1 ? i + N : -1
    if (right >= 0 && swapWorks(b, i, right)) out.push([i, right])
    if (down >= 0 && swapWorks(b, i, down)) out.push([i, down])
  }
  return out
}

// The component kind with the most tiles on the board (lowest kind on a tie),
// or -1: what a Core clears when a blast sets it off.
function mostCommon(k) {
  var count = [0, 0, 0, 0, 0, 0], best = -1
  for (var i = 0; i < k.length; i++) if (matchable(k[i])) count[k[i]]++
  for (var n = 0; n < CORE; n++) if (count[n] > 0 && (best < 0 || count[n] > count[best])) best = n
  return best
}

// Cells a special covers when it goes off at i.
function reach(b, i) {
  var out = [], r = rowOf(i), c = colOf(i), j
  var s = b.s[i]
  if (s === "h") for (j = 0; j < N; j++) out.push(idx(r, j))
  else if (s === "v") for (j = 0; j < N; j++) out.push(idx(j, c))
  else if (s === "x") {
    for (var dr = -2; dr <= 2; dr++)
      for (var dc = -2; dc <= 2; dc++) {
        if (Math.abs(dr) + Math.abs(dc) > 2) continue
        var n = neighbor(i, dr, dc)
        if (n >= 0) out.push(n)
      }
  } else if (b.k[i] === CORE) {
    var t = mostCommon(b.k)
    for (j = 0; j < N * N; j++) if (t >= 0 && b.k[j] === t) out.push(j)
  }
  return out
}

// Chain reaction: clear `start`, and every special or Core caught in it goes off
// in turn. Cells in `done` are cleared but don't go off (a Core the player swapped
// already chose its kind). Returns every cell to clear, each once, in order.
function blast(b, start, done) {
  var hit = {}, order = [], q = start.slice(), fired = {}, key
  for (key in (done || {})) fired[key] = true
  while (q.length) {
    var i = q.shift()
    if (hit[i]) continue
    hit[i] = true
    order.push(i)
    if (fired[i]) continue
    fired[i] = true
    var more = reach(b, i)
    for (var j = 0; j < more.length; j++) if (!hit[more[j]]) q.push(more[j])
  }
  return order
}

function copy(b) { return { k: b.k.slice(), s: b.s.slice() } }

function countKinds(k) {
  var out = {}
  for (var i = 0; i < k.length; i++) out[k[i]] = (out[k[i]] || 0) + 1
  return out
}
