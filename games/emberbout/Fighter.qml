import QtQuick

// One fighter, drawn from rectangles: legs and arms are two-part limbs that
// rotate at the hip/shoulder and knee/elbow, following game.poseOf(slot).
// poseOf() returns a fresh object on every call, so these bindings update every
// frame the game publishes (holding a fighter object here would freeze it).
//
// Looks (all our own): Marrow is broad with a stone shoulder slab and a flat
// mason's cap; Kestrel is slim with a courier's scarf and a swept crest; Sable
// wears a long lamplighter's coat and a wide-brimmed hat.
Item {
  id: fig
  property var game
  property int slot: 0

  readonly property var pose: game.poseOf(slot)
  readonly property var look: game.lookOf(slot)
  readonly property bool mirror: slot === 1 && game.fighterAt(0).d === game.fighterAt(1).d

  // Feet at (x, groundY - h); everything else hangs off the hip.
  x: pose.x
  y: game.groundY - pose.h
  width: 0; height: 0
  z: pose.state === "attack" ? 2 : 1

  readonly property real tall: look.h
  readonly property real legLen: tall * 0.47
  readonly property real torsoLen: tall * 0.33
  readonly property real headR: tall * 0.085
  readonly property real legW: look.build === "heavy" ? 19 : (look.build === "light" ? 12 : 15)
  readonly property real armW: look.build === "heavy" ? 17 : (look.build === "light" ? 10 : 12)
  readonly property real torsoW: look.build === "heavy" ? look.w * 0.78 : look.w * 0.62
  readonly property real fist: armW + (look.build === "heavy" ? 7 : 3)

  readonly property color body: pose.flash ? game.color("bright_foreground", "#ffffff")
                              : mirror ? game.color(look.altKey, look.altFb) : game.color(look.colorKey, look.colorFb)
  readonly property color trim: pose.flash ? game.color("bright_foreground", "#ffffff") : game.color(look.trimKey, look.trimFb)
  readonly property color dark: game.color("dark_background", "#13141c")
  readonly property color skin: pose.flash ? game.color("bright_foreground", "#ffffff") : game.color("foreground", "#c0caf5")
  readonly property color back: Qt.darker(body, 1.35)

  // A limb: a rounded bar hanging from its top center, rotated by `a`, with a
  // lower part hanging from its end.
  component Limb: Rectangle {
    property real a: 0
    property real len: 30
    property real thick: 10
    width: thick; height: len + thick / 2
    x: -thick / 2
    radius: thick / 2
    transformOrigin: Item.Top
    rotation: a
    antialiasing: true
  }

  // Shadow on the floor, drawn unmirrored under the feet.
  Rectangle {
    x: -fig.look.w * 0.7; y: fig.pose.h - 5
    width: fig.look.w * 1.4; height: 10; radius: 5
    color: fig.dark
    opacity: 0.45 * Math.max(0.25, 1 - fig.pose.h / 260)
  }

  Item {
    id: flip
    transform: Scale { xScale: fig.pose.facing }
    opacity: fig.pose.invuln && fig.pose.state === "idle" ? 0.65 + 0.35 * Math.sin(fig.pose.t * 40) : 1

    Item {
      id: bodyRoot
      y: -fig.pose.lift
      transform: Rotation { origin.x: 0; origin.y: 0; angle: fig.pose.rot }

      // Kindle glow: a warm aura that breathes.
      Rectangle {
        visible: fig.pose.kindle
        x: -fig.torsoW; y: -fig.tall * 1.02
        width: fig.torsoW * 2; height: fig.tall * 1.02
        radius: fig.torsoW
        color: game.color("orange", "#ff9e64")
        opacity: 0.18 + 0.1 * Math.sin(fig.pose.t * 9)
      }

      // Back leg
      Item {
        y: -fig.legLen * fig.pose.hip
        Limb {
          len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lBu; color: fig.back
          Limb { x: 0; y: parent.len; len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lBl; color: fig.back
            Rectangle { x: -2; y: parent.height - 6; width: fig.legW + 8; height: 7; radius: 3; color: fig.dark }
          }
        }
      }

      // Torso, head and arms lean together around the hip.
      Item {
        id: torso
        y: -fig.legLen * fig.pose.hip
        rotation: fig.pose.lean
        transformOrigin: Item.TopLeft

        // Back arm (with Sable's hand lantern)
        Item {
          x: -fig.torsoW * 0.12; y: -fig.torsoLen + fig.armW * 0.6
          Limb {
            len: fig.torsoLen * 0.5; thick: fig.armW; a: fig.pose.aBu; color: fig.back
            Limb { x: 0; y: parent.len; len: fig.torsoLen * 0.48; thick: fig.armW; a: fig.pose.aBl; color: fig.back
              Rectangle { x: (parent.width - fig.fist) / 2; y: parent.height - fig.fist / 2; width: fig.fist; height: fig.fist; radius: 4; color: fig.skin }
              Rectangle {
                visible: fig.look.build === "coat"
                x: -3; y: parent.height + 6; width: 12; height: 14; radius: 3
                color: fig.game.color("yellow", "#e0af68")
                opacity: 0.75 + 0.25 * Math.sin(fig.pose.t * 6)
                border.width: 2; border.color: fig.dark
              }
            }
          }
        }

        // Sable's coat tails
        Rectangle {
          visible: fig.look.build === "coat"
          x: -fig.torsoW / 2 - 4; y: -fig.torsoLen * 0.25
          width: fig.torsoW + 8; height: fig.torsoLen * 0.25 + fig.legLen * 0.62
          radius: 4
          color: fig.back
          transformOrigin: Item.Top
          rotation: -fig.pose.lean * 0.6 + 4 * Math.sin(fig.pose.t * 3)
        }

        // Chest
        Rectangle {
          x: -fig.torsoW / 2; y: -fig.torsoLen
          width: fig.torsoW; height: fig.torsoLen + 4
          radius: fig.look.build === "heavy" ? 12 : 8
          color: fig.body
          antialiasing: true
          // sash / belt
          Rectangle { y: parent.height - 12; width: parent.width; height: 8; color: fig.trim }
          Rectangle {
            visible: fig.look.build === "coat"
            x: parent.width * 0.45; y: 4; width: 4; height: parent.height - 16; color: fig.trim; opacity: 0.8
          }
        }

        // Kestrel's scarf, streaming behind
        Repeater {
          model: fig.look.build === "light" ? 2 : 0
          delegate: Rectangle {
            required property int index
            x: -fig.torsoW * 0.2; y: -fig.torsoLen - 2 + index * 5
            width: 30 - index * 7; height: 6; radius: 3
            color: fig.trim
            transformOrigin: Item.Right
            rotation: 12 + index * 10 + 10 * Math.sin(fig.pose.t * 8 + index)
            transform: Translate { x: -24 }
          }
        }

        // Head
        Rectangle {
          id: head
          x: -fig.headR + 2; y: -fig.torsoLen - fig.headR * 2 - 2
          width: fig.headR * 2; height: fig.headR * 2
          radius: fig.look.build === "heavy" ? fig.headR * 0.55 : fig.headR
          color: fig.skin
          antialiasing: true
          // eye band
          Rectangle { x: parent.width * 0.5; y: parent.height * 0.36; width: parent.width * 0.42; height: 4; radius: 2; color: fig.dark }
          // Marrow: flat mason's cap
          Rectangle {
            visible: fig.look.build === "heavy"
            x: -3; y: -5; width: parent.width + 6; height: 9; radius: 2; color: fig.trim
          }
          // Kestrel: swept crest
          Rectangle {
            visible: fig.look.build === "light"
            x: -4; y: -4; width: parent.width * 0.9; height: 8; radius: 4; color: fig.body
            rotation: -18
          }
          // Sable: wide-brimmed hat
          Rectangle {
            visible: fig.look.build === "coat"
            x: -8; y: -1; width: parent.width + 16; height: 5; radius: 2; color: fig.dark
          }
          Rectangle {
            visible: fig.look.build === "coat"
            x: 2; y: -11; width: parent.width - 4; height: 11; radius: 3; color: fig.dark
            Rectangle { y: 6; width: parent.width; height: 3; color: fig.trim }
          }
        }

        // Marrow's stone shoulder slab (behind the front arm's fist)
        Rectangle {
          visible: fig.look.build === "heavy"
          x: fig.torsoW * 0.05; y: -fig.torsoLen - 6
          width: fig.torsoW * 0.5; height: 20; radius: 5
          color: fig.trim
          border.width: 2; border.color: fig.dark
        }

        // Front arm
        Item {
          x: fig.torsoW * 0.18; y: -fig.torsoLen + fig.armW * 0.6
          Limb {
            len: fig.torsoLen * 0.5; thick: fig.armW; a: fig.pose.aFu; color: fig.body
            Limb { x: 0; y: parent.len; len: fig.torsoLen * 0.48; thick: fig.armW; a: fig.pose.aFl; color: fig.body
              Rectangle {
                x: (parent.width - fig.fist) / 2; y: parent.height - fig.fist / 2
                width: fig.fist; height: fig.fist; radius: 4
                color: fig.skin
                border.width: fig.pose.kindle ? 3 : 0
                border.color: fig.game.color("orange", "#ff9e64")
              }
            }
          }
        }
      }

      // Front leg
      Item {
        y: -fig.legLen * fig.pose.hip
        x: 3
        Limb {
          len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lFu; color: fig.body
          Limb { x: 0; y: parent.len; len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lFl; color: fig.body
            Rectangle { x: -2; y: parent.height - 6; width: fig.legW + 8; height: 7; radius: 3; color: fig.dark }
          }
        }
      }
    }
  }
}
