.pragma library

// Brick Blitz power-ups. A broken brick sometimes drops a capsule; catch it with
// the paddle to use it. Only one capsule falls at a time, and none drop while
// more than one ball is in play.
//
// Paddle modes (one at a time; a new one replaces the old, losing a ball ends it):
//   wide   a wider paddle
//   catch  the ball sticks to the paddle; Space or a click lets it go
//   laser  Space or a click fires two bolts that break bricks
// One-shot:
//   slow   every ball slows down
//   multi  the ball splits into three
//   life   one more ball in reserve (up to the maximum)
//   warp   straight to the next level

var TYPES = [
  { id: "wide",  label: "WIDE",  color: "blue",    fallback: "#7aa2f7", weight: 20, banner: "Wide paddle" },
  { id: "catch", label: "CATCH", color: "green",   fallback: "#9ece6a", weight: 16, banner: "Catch: the ball sticks" },
  { id: "laser", label: "LASER", color: "red",     fallback: "#f7768e", weight: 16, banner: "Laser: Space to fire" },
  { id: "slow",  label: "SLOW",  color: "yellow",  fallback: "#e0af68", weight: 18, banner: "Slow ball" },
  { id: "multi", label: "MULTI", color: "magenta", fallback: "#ad8ee6", weight: 16, banner: "Multi-ball" },
  { id: "life",  label: "+1",    color: "cyan",    fallback: "#449dab", weight: 8,  banner: "Extra ball" },
  { id: "warp",  label: "WARP",  color: "orange",  fallback: "#eb927b", weight: 6,  banner: "Warp!" }
]

function byId(id) {
  for (var i = 0; i < TYPES.length; i++) if (TYPES[i].id === id) return TYPES[i]
  return null
}

// A weighted random pick; r is a number in [0, 1) so tests can choose.
function pick(r) {
  var total = 0, i
  for (i = 0; i < TYPES.length; i++) total += TYPES[i].weight
  var t = r * total
  for (i = 0; i < TYPES.length; i++) {
    t -= TYPES[i].weight
    if (t < 0) return TYPES[i].id
  }
  return TYPES[TYPES.length - 1].id
}
