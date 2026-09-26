.pragma library

// Input helpers. Keys are flags held per fighter (Game.qml); a button pressed
// while the fighter is busy is kept for BUFFER seconds and fires the moment the
// fighter is free. Directions are read relative to the way the fighter faces,
// so a move reads the same on either side of the cage.

var BUFFER = 0.14          // a button pressed while busy is kept this long
var SLIP_TIME = 0.28       // a tap of down: head strikes miss for this long
var SLIP_COOLDOWN = 0.55   // ... and it can't be repeated sooner than this
var COUNTER_TIME = 0.6     // after a slip, the next strike is a counter

// Which way is "left"/"right" for a fighter facing `facing` (+1 = right)?
function relative(dir, facing) {
  if (dir === "up") return "U"
  if (dir === "down") return "D"
  var toward = (dir === "right") === (facing > 0)
  return toward ? "F" : "B"
}

// The stand-up strike for a button and the directions held:
//   strike: jab | toward cross | back hook | down body shot
//   kick:   body kick | toward head kick | down leg kick | back (or close) knee
function strikeFor(btn, toward, back, down, close) {
  if (btn === "strike") return down ? "bodyshot" : (toward ? "cross" : (back ? "hook" : "jab"))
  if (btn === "kick") return down ? "legkick" : (toward ? "headkick" : ((back || close) ? "knee" : "bodykick"))
  return ""
}
