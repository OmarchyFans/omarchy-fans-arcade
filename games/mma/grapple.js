.pragma library

// The rules of contact, as pure functions of the two fighters' ratings (r: the
// `ratings` object from fighters.js) and their stamina (0..100). Game.qml rolls
// its seeded random number against these chances; the tests call them directly.

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

// Low stamina weakens everything: below 30 the multiplier falls toward 0.55.
function tired(stamina) { return stamina >= 30 ? 1 : 0.55 + 0.45 * Math.max(0, stamina) / 30 }

// ---- stand-up moves -------------------------------------------------------------
// Times in seconds (scaled by the fighter's tempo), reach in px between centers,
// damage before the fighter's multiplier. `kind` picks the multiplier: punch,
// kick or knee (clinch). `cost` is stamina before the cardio multiplier.
var MOVES = {
  jab:      { name: "JAB",        startup: 0.08, active: 0.06, recovery: 0.14, reach: 96,  zone: "head", dmg: 3.2, kind: "punch", cost: 2 },
  cross:    { name: "CROSS",      startup: 0.13, active: 0.06, recovery: 0.20, reach: 106, zone: "head", dmg: 7,   kind: "punch", cost: 4 },
  hook:     { name: "HOOK",       startup: 0.12, active: 0.07, recovery: 0.22, reach: 84,  zone: "head", dmg: 8.5, kind: "punch", cost: 5 },
  bodyshot: { name: "BODY SHOT",  startup: 0.11, active: 0.06, recovery: 0.20, reach: 90,  zone: "body", dmg: 6,   kind: "punch", cost: 4 },
  bodykick: { name: "BODY KICK",  startup: 0.17, active: 0.08, recovery: 0.26, reach: 128, zone: "body", dmg: 8,   kind: "kick",  cost: 7 },
  headkick: { name: "HEAD KICK",  startup: 0.24, active: 0.08, recovery: 0.32, reach: 132, zone: "head", dmg: 12,  kind: "kick",  cost: 10 },
  legkick:  { name: "LEG KICK",   startup: 0.14, active: 0.07, recovery: 0.22, reach: 118, zone: "leg",  dmg: 6,   kind: "kick",  cost: 5 },
  knee:     { name: "KNEE",       startup: 0.12, active: 0.07, recovery: 0.20, reach: 80,  zone: "body", dmg: 8,   kind: "knee",  cost: 5 },
  // Specials that are strikes.
  pinwheel: { name: "PINWHEEL KICK",    startup: 0.20, active: 0.08, recovery: 0.30, reach: 150, zone: "body", dmg: 13, kind: "kick",  cost: 10 },
  skyknee:  { name: "SKYWARD KNEE",     startup: 0.16, active: 0.12, recovery: 0.30, reach: 78,  zone: "head", dmg: 13, kind: "kick",  cost: 12, lunge: 380 },
  overhand: { name: "FREIGHT OVERHAND", startup: 0.30, active: 0.07, recovery: 0.36, reach: 108, zone: "head", dmg: 17, kind: "punch", cost: 12 },
  counter:  { name: "COUNTER LEFT",     startup: 0,    active: 0,    recovery: 0.18, reach: 130, zone: "head", dmg: 14, kind: "punch", cost: 0 }
}

// Grappling stamina costs (before the cardio multiplier).
var COST = { clinch: 6, shoot: 14, throw: 12, pull: 12, pass: 5, escape: 6, standup: 6, gnp: 3, elbow: 5, sub: 10, block: 1, dirty: 3 }

// ---- chances ---------------------------------------------------------------------
// A shot (double leg). Wrestling against wrestling and defense; a sprawl (the
// defender pressed or held down while the shot came in) takes a lot off,
// more for a good wrestler.
function takedownChance(a, d, staA, staD, sprawled, bonus) {
  var p = 0.45 + 0.055 * (a.wrestling - d.wrestling) + 0.03 * (a.wrestling - d.defense) + (bonus || 0)
  if (sprawled) p -= 0.15 + 0.035 * d.wrestling
  p *= tired(staA)
  p += 0.15 * (1 - tired(staD))           // a tired defender sprawls late
  return clamp(p, 0.05, 0.95)
}

// Tying up at close range.
function clinchChance(a, d, staA, blocking) {
  return clamp((0.5 + 0.07 * (a.clinch - d.clinch) - (blocking ? 0.1 : 0)) * tired(staA), 0.1, 0.95)
}
// A takedown from the clinch: trips and body locks (clinch + wrestling).
function clinchTakedownChance(a, d, staA) {
  return clamp((0.35 + 0.06 * (a.clinch - d.clinch) + 0.03 * (a.wrestling - d.wrestling)) * tired(staA), 0.05, 0.9)
}
// The judo hip throw (Harbor Wheel): clinch skill, and a poor wrestler can't base out.
function throwChance(a, d, staA) {
  return clamp((0.4 + 0.06 * (a.clinch - d.clinch) + 0.03 * (10 - d.wrestling)) * tired(staA), 0.05, 0.92)
}
// The one not controlling the clinch fights for the inside position.
function pummelChance(me, opp, sta) { return clamp((0.35 + 0.07 * (me.clinch - opp.clinch)) * tired(sta), 0.05, 0.9) }
// Breaking away from the clinch; easier when you are not the one being held.
function breakChance(me, opp, sta, isOwner) {
  return clamp((0.3 + 0.05 * (me.clinch - opp.clinch) + (isOwner ? 0.25 : 0)) * tired(sta), 0.1, 0.95)
}

// ---- ground ------------------------------------------------------------------------
// Positions, worst to best for the one on top.
var POSITIONS = ["guard", "half", "side", "mount", "back"]
var POS_NAMES = { guard: "FULL GUARD", half: "HALF GUARD", side: "SIDE CONTROL", mount: "MOUNT", back: "BACK CONTROL" }
// Ground-and-pound power by position.
var GNP = { guard: 0.55, half: 0.75, side: 0.9, mount: 1.25, back: 1.0 }
// Seconds of control each position is worth to the judges (per second held).
var CTRL = { guard: 0.6, half: 0.8, side: 1.0, mount: 1.3, back: 1.4 }

function nextPos(pos) { var i = POSITIONS.indexOf(pos); return POSITIONS[Math.min(POSITIONS.length - 1, i + 1)] }
// Where the bottom fighter lands when they escape one step.
function escapePos(pos) {
  switch (pos) {
  case "half": return "guard"
  case "side": return "half"
  case "mount": return "guard"          // bridge and shrimp back to guard
  case "back": return "guard"           // turn in
  }
  return "guard"
}

// Top passes / advances: grappling vs grappling.
function passChance(t, b, staT) { return clamp((0.35 + 0.06 * (t.grappling - b.grappling)) * tired(staT), 0.05, 0.9) }
// Bottom improves a step (or sweeps from guard).
function escapeChance(b, t, staB, pos) {
  var p = 0.3 + 0.06 * (b.grappling - t.grappling)
  if (pos === "guard") p -= 0.1                // a sweep is harder than a shrimp
  if (pos === "mount" || pos === "back") p -= 0.05
  return clamp(p * tired(staB), 0.05, 0.85)
}
// Bottom stands up (guard or half guard only): wrestling to get up against the
// top fighter's grappling to hold them down.
function standupChance(b, t, staB, pos) {
  if (pos !== "guard" && pos !== "half") return 0
  return clamp((0.28 + 0.05 * (b.wrestling - t.grappling) + 0.02 * (b.speed - 5)) * tired(staB), 0.03, 0.8)
}

// Which submissions work from where, for the attacker's side.
var SUBS_AT = {
  "top:guard": [], "top:half": ["kimura", "armtri"], "top:side": ["kimura", "armtri"],
  "top:mount": ["armbar", "armtri", "kimura"], "top:back": ["rnc"],
  "bottom:guard": ["triangle", "armbar", "kimura"], "bottom:half": ["kimura"],
  "bottom:side": [], "bottom:mount": [], "bottom:back": [],
  "stand": ["guillotine"]
}
// The attacker's first known submission that works from here ("" if none).
function pickSub(known, where) {
  var ok = SUBS_AT[where] || []
  for (var i = 0; i < known.length; i++) if (ok.indexOf(known[i]) >= 0) return known[i]
  return ""
}
var SUB_POWER = { rnc: 1.25, armtri: 1.1, armbar: 1.1, triangle: 1.0, guillotine: 1.0, kimura: 0.95 }

// The submission struggle. The tap meter (0..100) climbs by itself at
// subRate() per second; each attacker squeeze adds squeeze(), each defender
// press (any key: mash) takes off mash() and adds escapeGain() to the escape
// meter. Tap 100 = TAP OUT. Escape 100 (or the tap meter back at 0, or the
// hold running out) = escaped.
function subRate(a, d, staD, kind) {
  return 12 + 5 * a.grappling * (SUB_POWER[kind] || 1) - 3.2 * d.grappling - 1.2 * d.cardio * clamp(staD, 0, 100) / 100
}
function squeeze(a) { return 1.5 + 0.4 * a.grappling }
function mash(d, staD) { return (2.2 + 0.55 * d.grappling) * tired(staD) }
function escapeGain(d, staD) { return (1.5 + 0.35 * d.grappling) * tired(staD) }
var SUB_MAX_TIME = 6

// Takes the damage a strike would do and what the defender's guard lets through.
function blocked(dmg, guard) { return dmg * guard }
