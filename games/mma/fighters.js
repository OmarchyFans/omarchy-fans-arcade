.pragma library

// Super MMA Fighter's roster: seven invented fighters, one per archetype.
//
// Every name, nickname, look, hometown and crest here is made up. Hometowns are
// invented places, not real countries, so no fighter can read as "a real fighter
// from country X with style Y". The only real-world input is statistical: each
// archetype's ratings (0-10) and finish split (share of wins by KO/TKO,
// submission, decision) are anonymous averages over several elite fighters'
// public records. Those numbers drive everything the fighter does (stats() below
// and plan() for the CPU), so a fighter plays like their numbers.
//
// The roster is one open class: ratings, not size, decide a fight (documented in
// Game.qml). Build only changes the drawing.
//
// Specials (the H / Enter key) are the archetype's signature, with our own names.
// Submissions a fighter knows, in order of preference:
//   armbar, triangle, rnc (rear-naked choke), guillotine, kimura, armtri (arm-triangle).

var RATING_KEYS = ["power", "speed", "kicks", "clinch", "wrestling", "grappling", "cardio", "defense"]
var RATING_LABELS = ["POWER", "SPEED", "KICKS", "CLINCH", "WRESTLING", "GRAPPLING", "CARDIO", "DEFENSE"]

var ROSTER = [
  {
    id: "brannoch", name: "Osric Brannoch", nick: "The Millstone", home: "Kestmark Steppe",
    archetype: "sambo grinder", sex: "m", build: "stocky", hair: "buzz", skin: 0.30,
    colorKey: "red", colorFb: "#f7768e", trimKey: "yellow", trimFb: "#e0af68",
    style: "Combat sambo and chain wrestling: cage pressure, top control, ground-and-pound.",
    ratings: { power: 6, speed: 5.5, kicks: 4.5, clinch: 8.5, wrestling: 9.5, grappling: 9.5, cardio: 9.5, defense: 9 },
    finishes: { ko: 22, sub: 41, dec: 36 },
    subs: ["armtri", "rnc", "kimura", "triangle"],
    special: { id: "chain", name: "Chain Shot", hint: "a shoot that re-shoots once if sprawled" }
  },
  {
    id: "castellane", name: "Tamsin Castellane", nick: "Two-Beat", home: "Port Varra",
    archetype: "power counter", sex: "f", build: "lean", hair: "ponytail", skin: 0.55,
    colorKey: "magenta", colorFb: "#bb9af7", trimKey: "cyan", trimFb: "#7dcfff",
    style: "Southpaw boxing at karate distance: counters in the pocket, early finishes.",
    ratings: { power: 9, speed: 8, kicks: 5.5, clinch: 5.5, wrestling: 5, grappling: 5.5, cardio: 5, defense: 6 },
    finishes: { ko: 67, sub: 23, dec: 10 },
    subs: ["guillotine", "rnc", "triangle", "armbar"],
    special: { id: "pocket", name: "Pocket Trap", hint: "a counter stance: slip their strike, fire back" }
  },
  {
    id: "dole", name: "Caspian Dole", nick: "The Surveyor", home: "Hollin Reach",
    archetype: "rangy technician", sex: "m", build: "tall", hair: "crop", skin: 0.35,
    colorKey: "blue", colorFb: "#7aa2f7", trimKey: "green", trimFb: "#9ece6a",
    style: "Long-reach all-rounder: jab and kicks at range, level changes, elbows from top.",
    ratings: { power: 6.3, speed: 7, kicks: 8.3, clinch: 8, wrestling: 8.3, grappling: 7.7, cardio: 9.7, defense: 9 },
    finishes: { ko: 34, sub: 25, dec: 41 },
    subs: ["guillotine", "rnc"],
    elbows: 1.3,
    special: { id: "pinwheel", name: "Pinwheel Kick", hint: "a spinning back kick to the body, longest reach" }
  },
  {
    id: "marrask", name: "Signe Marrask", nick: "Metronome", home: "Ostmere",
    archetype: "kickboxing sniper", sex: "f", build: "lean", hair: "braid", skin: 0.15,
    colorKey: "green", colorFb: "#9ece6a", trimKey: "orange", trimFb: "#ff9e64",
    style: "Kickboxing and clinch knees at long range; weak off her back.",
    ratings: { power: 8.7, speed: 7.7, kicks: 8.7, clinch: 6.7, wrestling: 2.3, grappling: 3.7, cardio: 6.7, defense: 6.3 },
    finishes: { ko: 70, sub: 4, dec: 25 },
    subs: ["triangle"],
    special: { id: "skyknee", name: "Skyward Knee", hint: "a flying knee that closes the distance" }
  },
  {
    id: "korrow", name: "Bastian Korrow", nick: "Rockfall", home: "Calder Isles",
    archetype: "heavy hitter", sex: "m", build: "heavy", hair: "beard", skin: 0.50,
    colorKey: "orange", colorFb: "#ff9e64", trimKey: "red", trimFb: "#f7768e",
    style: "Heavyweight power: one-shot punches, short fights, a short gas tank.",
    ratings: { power: 9.3, speed: 7.3, kicks: 5, clinch: 6.3, wrestling: 6.3, grappling: 6, cardio: 5.3, defense: 6.3 },
    finishes: { ko: 68, sub: 19, dec: 12 },
    subs: ["rnc", "guillotine", "kimura", "armbar"],
    special: { id: "overhand", name: "Freight Overhand", hint: "a slow looping right that ends nights" }
  },
  {
    id: "quenby", name: "Liora Quenby", nick: "The Vine", home: "Red Fen",
    archetype: "submission artist", sex: "f", build: "medium", hair: "bun", skin: 0.45,
    colorKey: "cyan", colorFb: "#7dcfff", trimKey: "magenta", trimFb: "#bb9af7",
    style: "Jiu-jitsu: chokes and joint locks from anywhere, dangerous even when losing.",
    ratings: { power: 7, speed: 7, kicks: 7, clinch: 7, wrestling: 5, grappling: 10, cardio: 7, defense: 4 },
    finishes: { ko: 27, sub: 59, dec: 14 },
    subs: ["triangle", "armbar", "rnc", "guillotine", "kimura"],
    special: { id: "vine", name: "Vine Pull", hint: "pull guard straight into a lock" }
  },
  {
    id: "tidewell", name: "Maren Tidewell", nick: "The Keel", home: "Sable Coast",
    archetype: "judo thrower", sex: "f", build: "medium", hair: "short", skin: 0.65,
    colorKey: "yellow", colorFb: "#e0af68", trimKey: "blue", trimFb: "#7aa2f7",
    style: "Judo: clinch throws and trips straight into armbars, heavy top control.",
    ratings: { power: 6, speed: 5.5, kicks: 2, clinch: 10, wrestling: 9, grappling: 9.5, cardio: 5, defense: 5 },
    finishes: { ko: 28, sub: 56, dec: 16 },
    subs: ["armbar", "kimura", "armtri"],
    special: { id: "wheel", name: "Harbor Wheel", hint: "a hip throw from close or the clinch, lands in side control" }
  }
]

var SUB_NAMES = { armbar: "ARMBAR", triangle: "TRIANGLE", rnc: "REAR-NAKED CHOKE", guillotine: "GUILLOTINE", kimura: "KIMURA", armtri: "ARM-TRIANGLE" }

function count() { return ROSTER.length }
function at(i) { return ROSTER[((i % ROSTER.length) + ROSTER.length) % ROSTER.length] }
function indexOf(id) {
  for (var i = 0; i < ROSTER.length; i++) if (ROSTER[i].id === id) return i
  return -1
}

// The select screen's style record line.
function finishLine(def) {
  var f = def.finishes
  return "Finishes: " + f.ko + "% KO · " + f.sub + "% SUB · " + f.dec + "% DEC"
}

// Everything a fighter's ratings do, in one place. Game.qml and grapple.js read
// these numbers; nothing else about a fighter is hand-tuned.
function stats(def) {
  var r = def.ratings
  return {
    walk: 110 + 14 * r.speed,                    // px/s
    tempo: 1.3 - 0.045 * r.speed,                // move time multiplier (lower = faster)
    punch: 0.5 + 0.08 * r.power,                 // punch damage multiplier
    kick: 0.5 + 0.08 * r.kicks,                  // kick damage multiplier
    knee: 0.5 + 0.08 * r.clinch,                 // clinch strike multiplier
    elbow: def.elbows || 1,                      // top elbows bonus
    cost: 1.55 - 0.06 * r.cardio,                // stamina cost multiplier
    regen: 4 + 1.2 * r.cardio,                   // stamina per second at rest
    guard: 0.45 - 0.03 * r.defense,              // share of damage a block lets through
    w: def.build === "heavy" ? 64 : (def.build === "stocky" ? 58 : (def.build === "tall" ? 50 : 52)),
    h: def.build === "tall" ? 172 : (def.build === "heavy" ? 170 : (def.build === "stocky" ? 156 : (def.sex === "f" ? 154 : 160)))
  }
}

// The CPU's game plan, from the finish split and ratings (see ai.js).
//   shoot  : how much it wants takedowns
//   clinch : how much it wants to tie up
//   strike : how much it wants to trade
//   kickPref: share of its strikes that are kicks
//   range  : the distance it likes to stand at
//   subTop / gnp : on top, how it prefers to finish
//   bottomSub : from its back, attack a lock rather than stand up
function plan(def) {
  var r = def.ratings, f = def.finishes
  var ko = f.ko / 100, sub = f.sub / 100, dec = f.dec / 100
  var wrest = Math.max(0, r.wrestling - 4) / 6
  return {
    shoot: wrest * (0.4 + sub + 0.6 * dec),
    clinch: Math.max(0, r.clinch - 6) / 4 * (0.3 + sub),
    strike: (0.35 + ko) * (r.power + r.kicks) / 17,
    kickPref: r.kicks / (r.kicks + r.power),
    range: r.kicks >= 8 && r.wrestling < 5 ? 125 : (r.wrestling >= 8 || r.clinch >= 9 ? 85 : 100),
    subTop: sub * r.grappling / 10,
    gnp: ko + 0.3,
    bottomSub: r.grappling >= 9.5 || (sub >= 0.5 && r.grappling >= 9) ? 0.8 : (r.grappling >= 7 ? 0.35 : 0.05),
    counter: def.special.id === "pocket"
  }
}

// 1 player vs CPU is a ladder through the other six fighters; the CPU gets one
// level sharper every fight.
var LADDER = 6
var DIFFICULTY = [
  { name: "Easy",   level: 1 },
  { name: "Normal", level: 3 },
  { name: "Hard",   level: 5 }
]
var MAX_LEVEL = 8
function ladderOpponent(p1, stage) { return (p1 + stage) % ROSTER.length }
function cpuLevel(diff, stage) { return Math.min(MAX_LEVEL, DIFFICULTY[diff].level + stage - 1) }
