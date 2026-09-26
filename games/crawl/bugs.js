.pragma library

// The four bugs that crawl the board, and the pure rules that steer them.
//
//   Null  heads straight for Byte's tile.
//   Race  heads for the tile about four ahead of Byte, to cut him off.
//   Leak  wanders: it takes a seeded random turn at every junction.
//   Loop  patrols its own corner and only gives chase when Byte comes within
//         about six tiles.
//
// Modes alternate on countdowns: in "scatter" every bug heads for its corner, in
// "chase" each follows its own rule. After a debug chip every bug on the board is
// "patched" for a while: it turns around, slows down, wanders at random and can
// be squashed. A squashed bug runs home to the pen and comes out again.
//
// Directions are indexes into DIRS. Ties go to the first in this order.

var DIRS = [
  { dx: 0, dy: -1, name: "up" },
  { dx: -1, dy: 0, name: "left" },
  { dx: 0, dy: 1, name: "down" },
  { dx: 1, dy: 0, name: "right" }
]

var DEFS = [
  { name: "Null", color: "red",     fallback: "#f7768e", corner: "topRight",    home: "outside", release: 0 },
  { name: "Race", color: "yellow",  fallback: "#e0af68", corner: "topLeft",     home: 0,         release: 1.5 },
  { name: "Leak", color: "magenta", fallback: "#bb9af7", corner: "bottomRight", home: -2,        release: 5 },
  { name: "Loop", color: "green",   fallback: "#9ece6a", corner: "bottomLeft",  home: 2,         release: 9 }
]

var RACE_AHEAD = 4        // tiles in front of Byte that Race aims for
var LOOP_RANGE = 6        // Loop gives chase within this many tiles

// Scatter targets sit just outside the board so a bug circles the nearest block.
function corner(which, w, h) {
  switch (which) {
  case "topRight": return { c: w - 2, r: -3 }
  case "topLeft": return { c: 1, r: -3 }
  case "bottomRight": return { c: w - 1, r: h + 1 }
  default: return { c: 0, r: h + 1 }
  }
}

function defByName(name) {
  for (var i = 0; i < DEFS.length; i++) if (DEFS[i].name === name) return DEFS[i]
  return null
}

// Where a bug is heading, or null for "turn at random" (Leak on the chase).
//   bug:  { c, r } its tile        hero: { c, r, fx, fy } Byte's tile and facing
//   mode: "scatter" | "chase"      w, h: board size
function targetFor(name, bug, hero, mode, w, h) {
  var def = defByName(name)
  var home = corner(def ? def.corner : "bottomLeft", w, h)
  if (mode === "scatter") return home
  switch (name) {
  case "Null": return { c: hero.c, r: hero.r }
  case "Race": return { c: hero.c + RACE_AHEAD * hero.fx, r: hero.r + RACE_AHEAD * hero.fy }
  case "Leak": return null
  case "Loop":
    var dc = bug.c - hero.c, dr = bug.r - hero.r
    return dc * dc + dr * dr <= LOOP_RANGE * LOOP_RANGE ? { c: hero.c, r: hero.r } : home
  }
  return home
}

// Which of `options` (DIRS indexes) brings a bug at `from` closest to `target`,
// by straight-line distance from the next tile. Ties go to the earliest in DIRS.
function chooseDir(options, from, target) {
  var best = -1, bestD = Infinity
  for (var i = 0; i < options.length; i++) {
    var d = DIRS[options[i]]
    var nc = from.c + d.dx - target.c, nr = from.r + d.dy - target.r
    var dist = nc * nc + nr * nr
    if (dist < bestD || (dist === bestD && options[i] < best)) { bestD = dist; best = options[i] }
  }
  return best
}

function reverseOf(i) { return i < 0 ? -1 : (i + 2) % 4 }

function dirIndex(dx, dy) {
  for (var i = 0; i < DIRS.length; i++) if (DIRS[i].dx === dx && DIRS[i].dy === dy) return i
  return -1
}

// Squashing patched bugs with one chip: 200, 400, 800, 1600.
function squashPoints(chain) { return 200 * Math.pow(2, Math.min(chain, 3)) }
var ALL_FOUR_BONUS = 1000  // all four squashed on one chip: a full debug

// How long a chip keeps the bugs patched; it shrinks every level.
function patchSeconds(level) { return Math.max(1.5, 7 - (level - 1) * 0.9) }

// When each bug leaves the pen at the start of a life (seconds); sooner each level.
function releaseSeconds(def, level) { return def.release * Math.max(0.35, 1 - 0.12 * (level - 1)) }

// Scatter / chase countdowns (seconds). Even entries are scatter; after the list
// the bugs chase for good.
function schedule(level) {
  if (level <= 1) return [7, 20, 7, 20, 5, 20, 5]
  if (level <= 4) return [7, 20, 7, 20, 5, 60, 1]
  return [5, 20, 5, 20, 3, 80, 1]
}
