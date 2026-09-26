.pragma library

// Solder Snap levels. Each level has a move limit, a score target for the level,
// component goals ("salvage N of this kind") and some fried parts to repair. A
// level is won the moment every goal is met; running out of moves first ends the
// game. After the hand-made boards, levels keep getting tighter by formula.

// The six components, in kind order. `color` is the theme key, `fallback` the
// color used when the theme has none.
var KINDS = [
  { name: "Resistor",   plural: "resistors",   color: "yellow",  fallback: "#e0af68" },
  { name: "Capacitor",  plural: "capacitors",  color: "blue",    fallback: "#7aa2f7" },
  { name: "LED",        plural: "LEDs",        color: "red",     fallback: "#f7768e" },
  { name: "Chip",       plural: "chips",       color: "green",   fallback: "#9ece6a" },
  { name: "Transistor", plural: "transistors", color: "magenta", fallback: "#bb9af7" },
  { name: "Coil",       plural: "coils",       color: "cyan",    fallback: "#7dcfff" }
]

var POINTS_PER_TILE = 10          // times the cascade number
var SPECIAL_BONUS = { h: 60, v: 60, x: 90, core: 150 }
var MOVE_BONUS = 120              // per move left when a level is won

var LEVELS = [
  { name: "Breadboard",   kinds: 5, moves: 20, target: 1200, goals: [{ kind: 2, n: 14 }], fried: 0 },
  { name: "Through-Hole", kinds: 5, moves: 20, target: 1600, goals: [{ kind: 0, n: 16 }, { kind: 1, n: 16 }], fried: 0 },
  { name: "Burnt Relay",  kinds: 5, moves: 24, target: 1600, goals: [], fried: 6 },
  { name: "Signal Chain", kinds: 6, moves: 24, target: 1500, goals: [{ kind: 3, n: 16 }], fried: 2 },
  { name: "Power Rail",   kinds: 6, moves: 22, target: 1800, goals: [{ kind: 4, n: 16 }, { kind: 5, n: 16 }], fried: 0 },
  { name: "Mainboard",    kinds: 6, moves: 24, target: 1900, goals: [{ kind: 2, n: 14 }], fried: 5 }
]

function level(n) {
  if (n >= 1 && n <= LEVELS.length) return LEVELS[n - 1]
  var e = n - LEVELS.length
  return {
    name: "Prototype " + e,
    kinds: 6,
    moves: Math.max(15, 23 - e),
    target: 1900 + 150 * e,
    goals: [{ kind: n % 6, n: Math.min(28, 14 + 2 * e) }],
    fried: Math.min(10, 4 + e)
  }
}
