import QtQuick
import "fighters.js" as Fighters

// One fighter, drawn from rectangles: legs and arms are two-part limbs that
// rotate at the hip/shoulder and knee/elbow, following game.poseOf(slot).
// poseOf() returns a fresh object on every call, so these bindings update every
// frame the game publishes (holding a fighter object here would freeze it).
//
// Looks (all our own): fight shorts in the fighter's color with a trim band,
// small open-finger gloves in the trim color, a sports top for the women, and
// one of seven hair styles. Skin tones are the theme's foreground warmed and
// darkened by the fighter's `skin` value, so they follow any theme.
Item {
  id: fig
  property var game
  property int slot: 0

  readonly property var pose: game.poseOf(slot)
  readonly property var look: game.lookOf(slot)
  readonly property var st: Fighters.stats(look)

  // Feet at (x, groundY); everything else hangs off the hip.
  x: pose.x
  y: game.groundY
  width: 0; height: 0
  z: pose.state === "attack" || pose.state === "shoot" ? 2 : 1

  readonly property real tall: st.h
  readonly property real legLen: tall * 0.47
  readonly property real torsoLen: tall * 0.33
  readonly property real headR: tall * 0.075
  readonly property string build: look.build
  readonly property real legW: build === "heavy" ? 20 : (build === "stocky" ? 18 : (build === "lean" ? 13 : 15))
  readonly property real armW: build === "heavy" ? 17 : (build === "stocky" ? 15 : (build === "lean" ? 11 : 12))
  readonly property real torsoW: build === "heavy" ? st.w * 0.8 : (build === "stocky" ? st.w * 0.74 : st.w * 0.6)
  readonly property real fist: armW + 5

  readonly property color bright: game.color("bright_foreground", "#ffffff")
  readonly property color dark: game.color("dark_background", "#13141c")
  readonly property color gear: pose.flash ? bright : game.color(look.colorKey, look.colorFb)
  readonly property color trim: pose.flash ? bright : game.color(look.trimKey, look.trimFb)
  readonly property color skin: pose.flash ? bright
      : Qt.darker(Qt.tint(game.color("foreground", "#c0caf5"), Qt.rgba(0.85, 0.55, 0.35, 0.45)), 1 + look.skin * 0.9)
  readonly property color skinBack: Qt.darker(skin, 1.25)
  readonly property color gearBack: Qt.darker(gear, 1.3)
  readonly property color hair: Qt.darker(game.color("dark_background", "#13141c"), 1.1)

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

  // Shadow on the canvas, drawn unmirrored under the body.
  Rectangle {
    x: -fig.st.w * 0.8 - (fig.pose.rot < -40 ? fig.pose.facing * fig.tall * 0.45 : 0); y: -5
    width: fig.st.w * 1.6 + (fig.pose.rot < -40 ? fig.tall * 0.4 : 0); height: 10; radius: 5
    color: fig.dark
    opacity: 0.4
  }

  Item {
    id: flip
    transform: Scale { xScale: fig.pose.facing }

    Item {
      id: bodyRoot
      y: -fig.pose.lift
      transform: Rotation { origin.x: 0; origin.y: 0; angle: fig.pose.rot }

      // Back leg
      Item {
        y: -fig.legLen * fig.pose.hip
        Limb {
          len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lBu; color: fig.skinBack
          Rectangle { width: parent.width + 2; x: -1; height: parent.height * 0.62; radius: 3; color: fig.gearBack }
          Limb { x: 0; y: parent.len; len: fig.legLen / 2; thick: fig.legW * 0.9; a: fig.pose.lBl; color: fig.skinBack
            Rectangle { x: -2; y: parent.height - 7; width: fig.legW + 6; height: 7; radius: 3; color: fig.skinBack }
          }
        }
      }

      // Torso, head and arms lean together around the hip.
      Item {
        id: torso
        y: -fig.legLen * fig.pose.hip
        rotation: fig.pose.lean
        transformOrigin: Item.TopLeft

        // Back arm
        Item {
          x: -fig.torsoW * 0.1; y: -fig.torsoLen + fig.armW * 0.6
          Limb {
            len: fig.torsoLen * 0.5; thick: fig.armW; a: fig.pose.aBu; color: fig.skinBack
            Limb { x: 0; y: parent.len; len: fig.torsoLen * 0.48; thick: fig.armW; a: fig.pose.aBl; color: fig.skinBack
              Rectangle { x: (parent.width - fig.fist) / 2; y: parent.height - fig.fist / 2; width: fig.fist; height: fig.fist; radius: 5; color: Qt.darker(fig.trim, 1.3) }
            }
          }
        }

        // Braid or ponytail, behind the head.
        Rectangle {
          visible: fig.look.hair === "braid" || fig.look.hair === "ponytail"
          x: -fig.headR * 1.3; y: -fig.torsoLen - fig.headR * 1.6
          width: fig.look.hair === "braid" ? 6 : 9; height: fig.look.hair === "braid" ? fig.torsoLen * 0.7 : fig.torsoLen * 0.4
          radius: 3; color: fig.hair
          transformOrigin: Item.Top
          rotation: 18 + 6 * Math.sin(fig.pose.t * 6)
        }

        // Chest: skin, with a sports top for the women.
        Rectangle {
          x: -fig.torsoW / 2; y: -fig.torsoLen
          width: fig.torsoW; height: fig.torsoLen + 4
          radius: fig.build === "heavy" ? 12 : 8
          color: fig.skin
          antialiasing: true
          Rectangle {
            visible: fig.look.sex === "f"
            y: 6; width: parent.width; height: parent.height * 0.42; radius: 5
            color: fig.gear
            Rectangle { y: parent.height - 4; width: parent.width; height: 4; color: fig.trim }
          }
          // a hint of abs / chest line
          Rectangle { visible: fig.look.sex === "m"; x: parent.width * 0.55; y: parent.height * 0.3; width: 3; height: parent.height * 0.45; radius: 1; color: fig.skinBack; opacity: 0.6 }
          // waistband of the shorts
          Rectangle { y: parent.height - 12; width: parent.width; height: 12; radius: 3; color: fig.gear
            Rectangle { y: 2; width: parent.width; height: 3; color: fig.trim }
          }
        }

        // Head
        Rectangle {
          id: head
          x: -fig.headR + 3; y: -fig.torsoLen - fig.headR * 2 - 3
          width: fig.headR * 2; height: fig.headR * 2.1
          radius: fig.headR
          color: fig.skin
          antialiasing: true
          // eyes and brow
          Rectangle { x: parent.width * 0.56; y: parent.height * 0.36; width: parent.width * 0.3; height: 3; radius: 1; color: fig.dark }
          // hair: a cap on top for everyone but the bald-with-beard look
          Rectangle {
            visible: fig.look.hair !== "beard"
            x: -2; y: -3
            width: parent.width + 2; height: fig.look.hair === "buzz" ? parent.height * 0.3 : parent.height * 0.42
            radius: fig.headR; color: fig.hair
          }
          Rectangle {   // bun
            visible: fig.look.hair === "bun"
            x: -fig.headR * 0.4; y: -fig.headR * 0.5; width: fig.headR * 1.1; height: fig.headR * 1.1; radius: width / 2; color: fig.hair
          }
          Rectangle {   // beard
            visible: fig.look.hair === "beard"
            x: parent.width * 0.2; y: parent.height * 0.55; width: parent.width * 0.85; height: parent.height * 0.5; radius: 6; color: fig.hair
          }
          // Rocked: three little circles orbit the head.
          Repeater {
            model: fig.pose.rocked ? 3 : 0
            delegate: Rectangle {
              required property int index
              readonly property real a: fig.pose.t * 7 + index * 2.1
              x: head.width / 2 + Math.cos(a) * fig.headR * 1.5 - 3
              y: -6 + Math.sin(a) * 5
              width: 6; height: 6; radius: 3
              color: fig.game.color("yellow", "#e0af68")
            }
          }
        }

        // Front arm
        Item {
          x: fig.torsoW * 0.18; y: -fig.torsoLen + fig.armW * 0.6
          Limb {
            len: fig.torsoLen * 0.5; thick: fig.armW; a: fig.pose.aFu; color: fig.skin
            Limb { x: 0; y: parent.len; len: fig.torsoLen * 0.48; thick: fig.armW; a: fig.pose.aFl; color: fig.skin
              Rectangle {
                x: (parent.width - fig.fist) / 2; y: parent.height - fig.fist / 2
                width: fig.fist; height: fig.fist; radius: 5
                color: fig.trim
                Rectangle { x: 2; y: parent.height * 0.55; width: parent.width - 4; height: 3; color: fig.dark; opacity: 0.4 }
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
          len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lFu; color: fig.skin
          Rectangle { width: parent.width + 2; x: -1; height: parent.height * 0.62; radius: 3; color: fig.gear
            Rectangle { y: parent.height - 4; width: parent.width; height: 3; color: fig.trim }
          }
          Limb { x: 0; y: parent.len; len: fig.legLen / 2; thick: fig.legW * 0.9; a: fig.pose.lFl; color: fig.skin
            Rectangle { x: -2; y: parent.height - 7; width: fig.legW + 6; height: 7; radius: 3; color: fig.skin }
          }
        }
      }
    }
  }
}
