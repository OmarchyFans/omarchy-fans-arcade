.pragma library

// The CPU fighter. Game.qml calls decide() every thinkTime(level) seconds (a
// countdown in step(), never a Timer) with a snapshot of the fight and the
// game's seeded random function, and turns the answer into the same held
// directions and key presses a person would make. So the CPU obeys every rule a
// player does.
//
// Its game plan comes from its fighter's numbers (fighters.js plan()): a
// grinder with a big submission share shoots and grinds on top, a kickboxer
// with a big KO share keeps range and kicks, a jiu-jitsu fighter attacks locks
// off her back.
//
// ctx:
//   level        1..8
//   plan         fighters.js plan()
//   sit          "stand" | "clinch" | "top" | "bottom" | "subAtt" | "subDef" | "busy"
//   dist         distance between the fighters
//   threat       "" | "head" | "body" | "leg": a strike about to land
//   oppShooting  the opponent is shooting a takedown
//   oppDown      the opponent is knocked down
//   oppRecovering the opponent is stuck in a move's recovery
//   oppRocked    the opponent is rocked
//   stamina      0..100
//   owner        (clinch) this fighter controls the clinch
//   pos          (ground) the position
//   subHere      a submission this fighter knows works from here
//   special      its special's id; specialOk: in range for it
//
// Returns { dir: 1 toward | -1 away | 0 (held while standing), down, tap: ""|"up"|
//   "down"|"toward"|"away" (a direction tapped once), button: ""|strike|kick|
//   special|grapple, why }.

function thinkTime(level) { return Math.max(0.14, 0.5 - 0.045 * level) }
function blockChance(level) { return Math.min(0.9, 0.1 + 0.1 * level) }
function mashRate(level) { return 3 + 0.9 * level }          // key presses per second in a lock

function act(dir, down, tap, button, why) {
  return { dir: dir, down: !!down, tap: tap || "", button: button || "", why: why }
}

// Pick one of { key: weight }.
function pick(weights, rand) {
  var sum = 0, k
  for (k in weights) sum += Math.max(0, weights[k])
  if (sum <= 0) return ""
  var r = rand() * sum
  for (k in weights) { r -= Math.max(0, weights[k]); if (r < 0) return k }
  return k
}

function strikeChoice(ctx, rand) {
  var p = ctx.plan
  if (ctx.dist < 80 && rand() < 0.3) return act(-1, false, "", "kick", "knee")
  if (rand() < p.kickPref) {
    var r = rand()
    if (ctx.dist <= 118 && r < 0.35) return act(0, true, "", "kick", "leg kick")
    if (r < 0.75 || ctx.dist > 132) return act(0, false, "", "kick", "body kick")
    return act(1, false, "", "kick", "head kick")
  }
  var q = rand()
  if (q < 0.4) return act(0, false, "", "strike", "jab")
  if (q < 0.75) return act(1, false, "", "strike", "cross")
  if (q < 0.9) return act(-1, false, "", "strike", "hook")
  return act(0, true, "", "strike", "body shot")
}

function stand(ctx, rand) {
  var lv = ctx.level, p = ctx.plan
  if (ctx.oppShooting && rand() < blockChance(lv)) return act(0, true, "", "", "sprawl")
  if (ctx.threat !== "" && rand() < blockChance(lv)) {
    if (ctx.threat === "head" && (p.counter || lv >= 5) && rand() < 0.5) return act(0, false, "down", "", "slip")
    if (ctx.threat !== "leg") return act(-1, false, "", "", "block")
  }
  if (ctx.oppDown) {
    if (ctx.dist < 160 && p.gnp + p.subTop > 0.6) return act(0, false, "", "grapple", "pounce")
    return act(1, false, "", "", "stalk")
  }
  if (ctx.stamina < 18 && rand() < 0.6) return act(-1, false, "", "", "breathe")
  if (ctx.oppRecovering && ctx.dist <= 110 && rand() < 0.3 + 0.07 * lv) return strikeChoice(ctx, rand)

  var reach = p.range + 10
  var w = {
    strike: p.strike * (ctx.dist <= reach + 15 ? 1 : 0.15),
    shoot: ctx.dist >= 90 && ctx.dist <= 200 ? p.shoot * 1.3 : 0,
    clinch: ctx.dist < 92 ? p.clinch * 1.4 : 0,
    special: ctx.specialOk ? 0.16 + 0.02 * lv : 0,
    approach: ctx.dist > reach ? 0.6 + (ctx.dist > 200 ? 1 : 0) : 0,
    range: ctx.dist < p.range - 25 ? p.strike * p.kickPref * 1.6 : 0,
    wait: 0.12
  }
  if (ctx.oppRocked) { w.strike *= 2; w.shoot *= 0.5 }
  switch (pick(w, rand)) {
  case "strike": return strikeChoice(ctx, rand)
  case "shoot": return act(0, false, "", "grapple", "shoot")
  case "clinch": return act(0, false, "", "grapple", "clinch")
  case "special": return act(0, false, "", "special", "special")
  case "approach": return act(1, false, "", "", "approach")
  case "range": return act(-1, false, "", "", "keep range")
  }
  return act(0, false, "", "", "wait")
}

function clinch(ctx, rand) {
  var p = ctx.plan
  var w = {
    takedown: ctx.owner ? p.clinch + p.shoot * 0.6 : 0,
    pummel: ctx.owner ? 0 : p.clinch + 0.2,
    knee: 0.25 + p.strike * 0.5,
    dirty: 0.2 + p.strike * 0.2,
    guillotine: ctx.subHere ? p.subTop * 0.4 : 0,
    wheel: ctx.special === "wheel" ? 0.9 : 0,
    escape: p.range >= 120 ? 1.0 : (p.shoot + p.clinch < 0.4 ? 0.6 : 0.1)
  }
  switch (pick(w, rand)) {
  case "takedown": return act(0, false, "", "grapple", "clinch takedown")
  case "pummel": return act(0, false, "", "grapple", "pummel")
  case "knee": return act(0, false, "", "kick", "clinch knee")
  case "dirty": return act(0, false, "", "strike", "dirty boxing")
  case "guillotine": return act(0, true, "", "grapple", "guillotine")
  case "wheel": return act(0, false, "", "special", "hip throw")
  }
  return act(0, false, "away", "", "break")
}

function top(ctx, rand) {
  var p = ctx.plan
  var w = {
    sub: ctx.subHere ? p.subTop * 1.6 : 0,
    advance: ctx.pos !== "back" ? 0.35 + p.subTop : 0,
    gnp: p.gnp,
    elbow: p.gnp * 0.5,
    stand: p.range >= 120 ? 0.35 : 0.02
  }
  switch (pick(w, rand)) {
  case "sub": return act(0, false, "", "grapple", "submission")
  case "advance": return act(0, false, "up", "", "advance")
  case "gnp": return act(0, false, "", "strike", "ground and pound")
  case "elbow": return act(0, false, "", "kick", "elbows")
  }
  return act(0, false, "down", "", "stand up")
}

function bottom(ctx, rand) {
  var p = ctx.plan
  var canStand = ctx.pos === "guard" || ctx.pos === "half"
  var w = {
    sub: ctx.subHere ? p.bottomSub * 1.5 : 0,
    stand: canStand ? 1.1 - p.bottomSub : 0,
    escape: 0.6,
    strike: ctx.pos === "guard" ? 0.15 : 0
  }
  switch (pick(w, rand)) {
  case "sub": return act(0, false, "", "grapple", "attack from bottom")
  case "stand": return act(0, false, "up", "", "stand up")
  case "strike": return act(0, false, "", "strike", "strikes from guard")
  }
  return act(0, false, "toward", "", "escape")
}

function decide(ctx, rand) {
  switch (ctx.sit) {
  case "stand": return stand(ctx, rand)
  case "clinch": return clinch(ctx, rand)
  case "top": return top(ctx, rand)
  case "bottom": return bottom(ctx, rand)
  case "subAtt": return act(0, false, "", "grapple", "squeeze")
  case "subDef": return act(0, false, "", "", "fight the hands")
  }
  return act(0, false, "", "", "wait")
}
