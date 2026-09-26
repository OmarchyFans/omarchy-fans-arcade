.pragma library

// The CPU fighter. Game.qml calls decide() every `thinkTime(level)` seconds
// (a countdown in step(), never a Timer) with a snapshot of the fight and the
// game's seeded random function, and turns the answer into the same held
// directions and button presses a person would make. So the CPU obeys every
// rule a player does, specials included.
//
// ctx:
//   level          1..8
//   dist           distance between the fighters' centers
//   range          reach of this fighter's standing Heavy
//   input          its special's input: "dash" | "dd" | "charge"
//   specialReady   charge held long enough / no kite already in the air
//   charging       holding down right now
//   threat         "" | "mid" | "low" | "high": an attack or projectile about to land
//   threatIsShot   the threat is a projectile
//   oppRecovering  the opponent is stuck in the recovery of a move (punish!)
//   oppDown        the opponent is knocked down
//   meter          0..100 Ember
//   stunned        in hitstun or blockstun
//
// Returns { dir: 1 toward | -1 away | 0, down, jump, button: "" | light | heavy |
//           special | ember, why }.

function thinkTime(level) { return Math.max(0.12, 0.5 - 0.045 * level) }
function blockChance(level) { return Math.min(0.95, 0.10 + 0.11 * level) }
function aggression(level) { return Math.min(0.9, 0.45 + 0.05 * level) }

function act(dir, down, jump, button, why) {
  return { dir: dir, down: !!down, jump: !!jump, button: button || "", why: why }
}

function decide(ctx, rand) {
  var lv = ctx.level
  var chargeFighter = ctx.input === "charge"

  if (ctx.stunned) {
    // A full meter can Flare out of a combo; sharper CPUs think of it.
    if (ctx.meter >= 100 && lv >= 3 && rand() < 0.08 * lv) return act(0, false, false, "ember", "flare")
    return act(-1, ctx.threat === "low", false, "", "stunned")
  }

  if (ctx.oppDown) {
    if (ctx.dist > ctx.range * 0.9) return act(1, false, false, "", "close in")
    return act(0, chargeFighter, false, "", "wait")
  }

  if (ctx.threat !== "") {
    if (rand() < blockChance(lv)) {
      if (ctx.threatIsShot && lv >= 4 && rand() < 0.35) return act(1, false, true, "", "hop")
      return act(-1, ctx.threat === "low", false, "", "block")
    }
  }

  if (ctx.oppRecovering && ctx.dist <= ctx.range && rand() < 0.3 + 0.08 * lv)
    return act(0, rand() < 0.5, false, "heavy", "punish")

  if (ctx.meter >= 100 && ctx.dist < 260 && rand() < 0.35) return act(0, false, false, "ember", "kindle")

  if (ctx.dist > ctx.range + 40) {
    if (ctx.input === "dd" && ctx.specialReady && ctx.dist > 220 && rand() < 0.25 + 0.05 * lv)
      return act(0, false, false, "special", "zone")
    if (chargeFighter) {
      if (ctx.specialReady && ctx.dist > 200 && rand() < 0.3 + 0.04 * lv) return act(0, false, false, "special", "zone")
      if (!ctx.specialReady && rand() < 0.35) return act(0, true, false, "", "charge")
    }
    if (ctx.input === "dash" && ctx.dist < 330 && rand() < 0.15 + 0.04 * lv) return act(0, false, false, "special", "rush")
    if (rand() < 0.08 + 0.02 * lv) return act(1, false, true, "", "jump in")
    return act(1, false, false, "", "approach")
  }

  if (rand() < aggression(lv)) {
    var r = rand()
    if (r < 0.35) return act(0, false, false, "light", "jab")
    if (r < 0.55) return act(0, true, false, "light", "low jab")
    if (r < 0.80) return act(0, false, false, "heavy", "strike")
    return act(0, true, false, "heavy", "sweep")
  }
  if (rand() < 0.5) return act(-1, chargeFighter, false, "", "space")
  return act(0, chargeFighter, false, "", "wait")
}
