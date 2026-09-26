.pragma library

// Brick Blitz layouts. Every row is 12 columns.
//   .    empty
//   a-e  one-hit bricks, colored by letter
//   #    takes two hits
//   *    takes three hits
// After the last layout the list starts over, a little faster each time.

var COLS = 12

var LAYOUTS = [
  { name: "Warm-up", rows: [
    "aaaaaaaaaaaa",
    "bbbbbbbbbbbb",
    "cccccccccccc",
    "dddddddddddd",
    "eeeeeeeeeeee"
  ] },
  { name: "Pyramid", rows: [
    ".....##.....",
    "....aaaa....",
    "...bbbbbb...",
    "..cccccccc..",
    ".dddddddddd.",
    "eeeeeeeeeeee"
  ] },
  { name: "Checkers", rows: [
    "a.b.c.d.e.a.",
    ".#.#.#.#.#.#",
    "c.d.e.a.b.c.",
    "#.#.#.#.#.#.",
    "e.a.b.c.d.e."
  ] },
  { name: "Fortress", rows: [
    "############",
    "#aaaaaaaaaa#",
    "#b........b#",
    "#b..****..b#",
    "#b........b#",
    "#cccccccccc#"
  ] },
  { name: "Diamond", rows: [
    ".....ee.....",
    "....edde....",
    "...edccde...",
    "..edc**cde..",
    "...edccde...",
    "....edde....",
    ".....ee....."
  ] }
]

function hitsFor(ch) {
  if (ch === "#") return 2
  if (ch === "*") return 3
  return 1
}

// Points for breaking a brick (each extra hit on a tough brick scores 10).
function pointsFor(ch) {
  switch (ch) {
  case "a": return 50
  case "b": return 40
  case "c": return 30
  case "d": return 20
  case "e": return 10
  case "#": return 80
  case "*": return 120
  }
  return 0
}

function layout(level) { // level counts from 1
  return LAYOUTS[(level - 1) % LAYOUTS.length]
}
