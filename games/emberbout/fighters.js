.pragma library

// Emberbout's roster. Every fighter, name, look and special move here is our own.
//
// Times are seconds, distances are field pixels (the field is 800 wide).
// A move has three parts: startup (winding up), active (the hitbox is out) and
// recovery (open to punishment). On a hit the defender is stunned for `hitstun`,
// on a block for `blockstun`.
//
//   reach / from : the hitbox runs from `from` to `reach` px in front of the
//                  attacker's center;
//   yLo / yHi    : its height range above the attacker's feet;
//   level        : "mid" (any block stops it), "low" (only a crouching block),
//                  "high" (air attacks: only a standing block);
//   knock        : a hit knocks the defender down;
//   push         : how far a block (or hit) slides the defender back;
//   armor        : Marrow's stonework: one hit taken while winding up or
//                  swinging does half damage and doesn't interrupt the move.
//
// Specials (one per fighter) have their own input:
//   "dash"   : forward, forward, then Light   (two taps toward the opponent)
//   "dd"     : down, down, then Light         (two taps down)
//   "charge" : hold down for CHARGE seconds, then Heavy (see input.js)

var ROSTER = [
  {
    id: "marrow", name: "Marrow", title: "the quarry mason",
    blurb: "Slow and heavy; his Heavy and Slam shrug off a hit.",
    hp: 1200, walk: 128, jumpV: 700, jumpX: 150, w: 70, h: 166,
    build: "heavy", colorKey: "orange", colorFb: "#e0af68", altKey: "yellow", altFb: "#e5c07b",
    trimKey: "red", trimFb: "#f7768e",
    moves: {
      sL: { startup: 0.09, active: 0.08, recovery: 0.18, dmg: 55,  hitstun: 0.28, blockstun: 0.16, reach: 96,  from: 16, yLo: 80, yHi: 132, level: "mid",  push: 22 },
      sH: { startup: 0.20, active: 0.10, recovery: 0.34, dmg: 120, hitstun: 0.44, blockstun: 0.26, reach: 122, from: 16, yLo: 70, yHi: 138, level: "mid",  push: 40, armor: true },
      cL: { startup: 0.10, active: 0.08, recovery: 0.18, dmg: 45,  hitstun: 0.26, blockstun: 0.15, reach: 100, from: 16, yLo: 0,  yHi: 42,  level: "low",  push: 18 },
      cH: { startup: 0.20, active: 0.12, recovery: 0.40, dmg: 100, hitstun: 0.50, blockstun: 0.26, reach: 126, from: 16, yLo: 0,  yHi: 36,  level: "low",  push: 30, knock: true },
      jL: { startup: 0.07, active: 0.14, recovery: 0.10, dmg: 60,  hitstun: 0.30, blockstun: 0.18, reach: 82,  from: 0,  yLo: -30, yHi: 70, level: "high", push: 20 },
      jH: { startup: 0.12, active: 0.14, recovery: 0.12, dmg: 105, hitstun: 0.42, blockstun: 0.24, reach: 96,  from: 0,  yLo: -40, yHi: 60, level: "high", push: 30 }
    },
    special: {
      id: "quarry", name: "Quarry Slam", input: "charge", button: "heavy", hint: "hold ↓ ½ s, then Heavy",
      startup: 0.26, active: 0.06, recovery: 0.44, dmg: 125, hitstun: 0.60, blockstun: 0.30,
      level: "low", push: 36, knock: true, armor: true,
      projectile: { kind: "wave", speed: 340, w: 46, hgt: 34, y: 0, life: 2.4 }
    }
  },
  {
    id: "kestrel", name: "Kestrel", title: "the rooftop courier",
    blurb: "Fast feet, light hands. Gets in, gets out.",
    hp: 900, walk: 212, jumpV: 800, jumpX: 222, w: 50, h: 150,
    build: "light", colorKey: "cyan", colorFb: "#7dcfff", altKey: "green", altFb: "#9ece6a",
    trimKey: "blue", trimFb: "#7aa2f7",
    moves: {
      sL: { startup: 0.05, active: 0.07, recovery: 0.12, dmg: 38, hitstun: 0.26, blockstun: 0.14, reach: 90,  from: 14, yLo: 76, yHi: 124, level: "mid",  push: 18 },
      sH: { startup: 0.13, active: 0.09, recovery: 0.26, dmg: 85, hitstun: 0.40, blockstun: 0.22, reach: 126, from: 14, yLo: 60, yHi: 130, level: "mid",  push: 32 },
      cL: { startup: 0.05, active: 0.07, recovery: 0.13, dmg: 32, hitstun: 0.24, blockstun: 0.13, reach: 96,  from: 14, yLo: 0,  yHi: 40,  level: "low",  push: 16 },
      cH: { startup: 0.12, active: 0.10, recovery: 0.30, dmg: 75, hitstun: 0.46, blockstun: 0.22, reach: 132, from: 14, yLo: 0,  yHi: 34,  level: "low",  push: 26, knock: true },
      jL: { startup: 0.05, active: 0.14, recovery: 0.08, dmg: 42, hitstun: 0.28, blockstun: 0.16, reach: 78,  from: 0,  yLo: -30, yHi: 66, level: "high", push: 16 },
      jH: { startup: 0.09, active: 0.14, recovery: 0.10, dmg: 80, hitstun: 0.40, blockstun: 0.22, reach: 92,  from: 0,  yLo: -40, yHi: 56, level: "high", push: 26 }
    },
    special: {
      id: "talon", name: "Talon Rush", input: "dash", button: "light", hint: "→ → (toward), then Light",
      startup: 0.10, active: 0.24, recovery: 0.30, dmg: 110, hitstun: 0.50, blockstun: 0.22,
      reach: 58, from: -10, yLo: 20, yHi: 124, level: "mid", push: 40, knock: true,
      rush: 600
    }
  },
  {
    id: "sable", name: "Sable", title: "the lamplighter",
    blurb: "Keeps you at arm's length, then a kite's length.",
    hp: 1040, walk: 170, jumpV: 770, jumpX: 186, w: 58, h: 158,
    build: "coat", colorKey: "magenta", colorFb: "#bb9af7", altKey: "blue", altFb: "#7aa2f7",
    trimKey: "yellow", trimFb: "#e0af68",
    moves: {
      sL: { startup: 0.07, active: 0.08, recovery: 0.15, dmg: 45,  hitstun: 0.27, blockstun: 0.15, reach: 100, from: 14, yLo: 78, yHi: 128, level: "mid",  push: 20 },
      sH: { startup: 0.16, active: 0.10, recovery: 0.30, dmg: 100, hitstun: 0.42, blockstun: 0.24, reach: 132, from: 14, yLo: 64, yHi: 134, level: "mid",  push: 36 },
      cL: { startup: 0.08, active: 0.08, recovery: 0.16, dmg: 38,  hitstun: 0.25, blockstun: 0.14, reach: 106, from: 14, yLo: 0,  yHi: 40,  level: "low",  push: 16 },
      cH: { startup: 0.16, active: 0.12, recovery: 0.36, dmg: 88,  hitstun: 0.48, blockstun: 0.24, reach: 136, from: 14, yLo: 0,  yHi: 34,  level: "low",  push: 28, knock: true },
      jL: { startup: 0.06, active: 0.14, recovery: 0.09, dmg: 50,  hitstun: 0.29, blockstun: 0.17, reach: 80,  from: 0,  yLo: -30, yHi: 68, level: "high", push: 18 },
      jH: { startup: 0.10, active: 0.14, recovery: 0.11, dmg: 92,  hitstun: 0.41, blockstun: 0.23, reach: 94,  from: 0,  yLo: -40, yHi: 58, level: "high", push: 28 }
    },
    special: {
      id: "kite", name: "Kite Lantern", input: "dd", button: "light", hint: "↓ ↓, then Light",
      startup: 0.18, active: 0.05, recovery: 0.40, dmg: 105, hitstun: 0.50, blockstun: 0.26,
      level: "mid", push: 30,
      projectile: { kind: "kite", speed: 290, w: 30, hgt: 30, y: 70, life: 3.2 }
    }
  }
]

function count() { return ROSTER.length }
function at(i) { return ROSTER[((i % ROSTER.length) + ROSTER.length) % ROSTER.length] }
function indexOf(id) {
  for (var i = 0; i < ROSTER.length; i++) if (ROSTER[i].id === id) return i
  return -1
}
// A move by its key: sL sH cL cH jL jH, or "sp" for the special.
function move(def, key) { return key === "sp" ? def.special : def.moves[key] }
function total(m) { return m.startup + m.active + m.recovery }

// 1 player vs CPU is a ladder of LADDER matches. Stage s faces the fighter s
// places after your own in the roster (so the mirror match comes third and sixth),
// and the CPU gets one level sharper every stage.
var LADDER = 6
var DIFFICULTY = [
  { name: "Easy",   level: 1 },
  { name: "Normal", level: 3 },
  { name: "Hard",   level: 5 }
]
var MAX_LEVEL = 8
function ladderOpponent(p1, stage) { return (p1 + stage) % ROSTER.length }
function cpuLevel(diff, stage) { return Math.min(MAX_LEVEL, DIFFICULTY[diff].level + stage - 1) }
