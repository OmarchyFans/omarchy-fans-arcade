import QtQuick
import "fighters.js" as Fighters

// One fighter, drawn from rectangles: legs and arms are two-part limbs that
// rotate at the hip/shoulder and knee/elbow, following game.poseOf(slot).
// poseOf() returns a fresh object on every call, so these bindings update every
// frame the game publishes (holding a fighter object here would freeze it).
//
// Looks (all our own, see fighters.js): fight shorts in the fighter's color with
// their own trunk pattern, small open-finger gloves in the trim color, a sports
// top for the women, one of seven hair styles and a facial-hair style.
//
// Stance: the pose's "front" limbs are the lead side. An orthodox fighter leads
// with the side nearest the camera, so the lead arm and leg are drawn in front in
// full color; a southpaw leads with the far side, so the lead limbs are drawn
// behind the body, shaded, and the rear ones in front.
//
// Skin tones are the lighter of the theme's foreground and background, warmed and
// then darkened by the fighter's `skin` value (0 light .. 1 deep), so the roster
// keeps its light-to-deep spread in dark and light themes alike.
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
  readonly property bool southpaw: look.stance === "southpaw"

  readonly property color bright: game.color("bright_foreground", "#ffffff")
  readonly property color dark: game.color("dark_background", "#13141c")
  readonly property color themeFg: game.color("foreground", "#c0caf5")
  readonly property color themeBg: game.color("background", "#1a1b26")
  readonly property color skinBase: themeFg.hslLightness >= themeBg.hslLightness ? themeFg : themeBg
  readonly property color gear: pose.flash ? bright : game.color(look.colorKey, look.colorFb)
  readonly property color trim: pose.flash ? bright : game.color(look.trimKey, look.trimFb)
  readonly property color skin: pose.flash ? bright
      : Qt.darker(Qt.tint(skinBase, Qt.rgba(0.85, 0.55, 0.35, 0.45)), 1 + look.skin * 1.5)
  readonly property color skinBack: Qt.darker(skin, 1.25)
  readonly property color gearBack: Qt.darker(gear, 1.3)
  readonly property color trimBack: Qt.darker(trim, 1.3)
  readonly property color hair: Qt.darker(game.color("dark_background", "#13141c"), 1.1)
  // Near the camera: full color; far side: shaded. Stance decides which is the lead.
  readonly property color leadSkin: southpaw ? skinBack : skin
  readonly property color rearSkin: southpaw ? skin : skinBack
  readonly property color leadGear: southpaw ? gearBack : gear
  readonly property color rearGear: look.pattern === "split" ? (southpaw ? trim : trimBack) : (southpaw ? gear : gearBack)
  readonly property color leadTrim: southpaw ? trimBack : trim
  readonly property color rearTrim: southpaw ? trim : trimBack

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

  // The trunks' pattern, drawn over one leg of the shorts (`w` x `h`).
  component Trunks: Item {
    property real w: 10
    property real h: 10
    property color ink: fig.bright
    Rectangle { objectName: "pattern-band"; visible: fig.look.pattern === "band"; y: parent.h - 9; width: parent.w; height: 8; color: parent.ink }
    Rectangle { objectName: "pattern-stripe"; visible: fig.look.pattern === "stripe"; x: parent.w / 2 - 1.5; width: 3; height: parent.h; color: parent.ink }
    Rectangle { objectName: "pattern-panel"; visible: fig.look.pattern === "panel"; x: parent.w / 2; width: parent.w / 2; height: parent.h; color: Qt.darker(parent.ink, 1.2); opacity: 0.8 }
    Repeater {
      model: fig.look.pattern === "dots" ? 2 : 0
      delegate: Rectangle { required property int index; objectName: "pattern-dots"; x: 3; y: 4 + index * 9; width: 4; height: 4; radius: 2; color: parent.ink }
    }
    Repeater {
      model: fig.look.pattern === "hoops" ? 2 : 0
      delegate: Rectangle { required property int index; objectName: "pattern-hoops"; y: parent.h * (0.3 + 0.3 * index); width: parent.w; height: 2; color: parent.ink }
    }
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

      // Rear leg (in front of the body for a southpaw)
      Item {
        objectName: "rearLeg"
        z: fig.southpaw ? 1 : -1
        y: -fig.legLen * fig.pose.hip
        Limb {
          len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lBu; color: fig.rearSkin
          Rectangle { width: parent.width + 2; x: -1; height: parent.height * 0.62; radius: 3; color: fig.rearGear }
          Limb { x: 0; y: parent.len; len: fig.legLen / 2; thick: fig.legW * 0.9; a: fig.pose.lBl; color: fig.rearSkin
            Rectangle { x: -2; y: parent.height - 7; width: fig.legW + 6; height: 7; radius: 3; color: fig.rearSkin }
          }
        }
      }

      // Torso, head and arms lean together around the hip.
      Item {
        id: torso
        y: -fig.legLen * fig.pose.hip
        rotation: fig.pose.lean
        transformOrigin: Item.TopLeft

        // Rear arm (in front of the body for a southpaw)
        Item {
          objectName: "rearArm"
          z: fig.southpaw ? 3 : -1
          x: -fig.torsoW * 0.1; y: -fig.torsoLen + fig.armW * 0.6
          Limb {
            len: fig.torsoLen * 0.5; thick: fig.armW; a: fig.pose.aBu; color: fig.rearSkin
            Limb { x: 0; y: parent.len; len: fig.torsoLen * 0.48; thick: fig.armW; a: fig.pose.aBl; color: fig.rearSkin
              Rectangle { x: (parent.width - fig.fist) / 2; y: parent.height - fig.fist / 2; width: fig.fist; height: fig.fist; radius: 5; color: fig.rearTrim }
            }
          }
        }

        // Braid or ponytail, behind the head.
        Rectangle {
          objectName: "hair-" + fig.look.hair + "-tail"
          visible: fig.look.hair === "braid" || fig.look.hair === "ponytail"
          x: -fig.headR * 1.3; y: -fig.torsoLen - fig.headR * 1.6
          width: fig.look.hair === "braid" ? 6 : 9; height: fig.look.hair === "braid" ? fig.torsoLen * 0.7 : fig.torsoLen * 0.4
          radius: 3; color: fig.hair
          transformOrigin: Item.Top
          rotation: 18 + 6 * Math.sin(fig.pose.t * 6)
        }
        // Curls: a round crown of hair, wider than the head.
        Rectangle {
          objectName: "hair-curls"
          visible: fig.look.hair === "curls"
          x: -fig.headR * 1.35 + 3; y: -fig.torsoLen - fig.headR * 2.45
          width: fig.headR * 2.7; height: fig.headR * 1.9; radius: height / 2
          color: fig.hair
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
          // Hair on top: a cap for most styles, higher or lower by style.
          Rectangle {
            objectName: "hair-cap"
            visible: fig.look.hair !== "mohawk" && fig.look.hair !== "undercut"
            x: -2; y: -3
            width: parent.width + 2
            height: parent.height * (fig.look.hair === "buzz" ? 0.24 : (fig.look.hair === "topknot" ? 0.32 : 0.42))
            radius: fig.headR; color: fig.hair
          }
          Rectangle {   // topknot: a small knot on the crown
            objectName: "hair-topknot"
            visible: fig.look.hair === "topknot"
            x: parent.width * 0.3; y: -fig.headR * 0.55; width: fig.headR * 0.8; height: fig.headR * 0.8; radius: width / 2; color: fig.hair
          }
          Rectangle {   // mohawk: a tall strip down the middle, shaved sides
            objectName: "hair-mohawk"
            visible: fig.look.hair === "mohawk"
            x: parent.width * 0.28; y: -fig.headR * 0.7; width: parent.width * 0.44; height: fig.headR * 1.2; radius: 4; color: fig.hair
          }
          Rectangle {   // undercut: long on top toward the front, the back shaved
            objectName: "hair-undercut"
            visible: fig.look.hair === "undercut"
            x: parent.width * 0.25; y: -5; width: parent.width * 0.85; height: parent.height * 0.36; radius: 6; color: fig.hair
          }
          // Facial hair
          Rectangle {
            objectName: "beard-moustache"
            visible: fig.look.beard === "moustache"
            x: parent.width * 0.6; y: parent.height * 0.62; width: parent.width * 0.36; height: 4; radius: 2; color: fig.hair
          }
          Rectangle {
            objectName: "beard-goatee"
            visible: fig.look.beard === "goatee"
            x: parent.width * 0.62; y: parent.height * 0.72; width: parent.width * 0.3; height: parent.height * 0.34; radius: 4; color: fig.hair
          }
          Rectangle {
            objectName: "beard-stubble"
            visible: fig.look.beard === "stubble"
            x: parent.width * 0.3; y: parent.height * 0.58; width: parent.width * 0.7; height: parent.height * 0.42; radius: 6; color: fig.hair
            opacity: 0.35
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

        // Lead arm (behind the body for a southpaw)
        Item {
          objectName: "leadArm"
          z: fig.southpaw ? -1 : 2
          x: fig.torsoW * 0.18; y: -fig.torsoLen + fig.armW * 0.6
          Limb {
            objectName: "leadArmUpper"
            len: fig.torsoLen * 0.5; thick: fig.armW; a: fig.pose.aFu; color: fig.leadSkin
            Limb { x: 0; y: parent.len; len: fig.torsoLen * 0.48; thick: fig.armW; a: fig.pose.aFl; color: fig.leadSkin
              Rectangle {
                x: (parent.width - fig.fist) / 2; y: parent.height - fig.fist / 2
                width: fig.fist; height: fig.fist; radius: 5
                color: fig.leadTrim
                Rectangle { x: 2; y: parent.height * 0.55; width: parent.width - 4; height: 3; color: fig.dark; opacity: 0.4 }
              }
            }
          }
        }
      }

      // Lead leg (behind the body for a southpaw)
      Item {
        objectName: "leadLeg"
        z: fig.southpaw ? -1 : 1
        y: -fig.legLen * fig.pose.hip
        x: 3
        Limb {
          len: fig.legLen / 2; thick: fig.legW; a: fig.pose.lFu; color: fig.leadSkin
          Rectangle {
            width: parent.width + 2; x: -1; height: parent.height * 0.62; radius: 3; color: fig.leadGear
            Rectangle { y: parent.height - 4; width: parent.width; height: 3; color: fig.leadTrim }
            Trunks { w: parent.width; h: parent.height; ink: fig.leadTrim }
          }
          Limb { x: 0; y: parent.len; len: fig.legLen / 2; thick: fig.legW * 0.9; a: fig.pose.lFl; color: fig.leadSkin
            Rectangle { x: -2; y: parent.height - 7; width: fig.legW + 6; height: 7; radius: 3; color: fig.leadSkin }
          }
        }
      }
    }
  }
}
