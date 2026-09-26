import QtQuick
import "board.js" as Board

// One Solder Snap part drawn with plain rectangles in a 58×58 box on its plate:
// resistor, capacitor, LED, chip, transistor, coil, the wild Core, or a fried
// part. `special` adds the Bus rails ("h", "v") or the Surge ring ("x"). Colors
// come from `host` (the active Omarchy theme, with fallbacks).
Item {
  id: art
  property var host: null
  property int kind: -1
  property string special: ""
  readonly property real glow: host ? host.glow : 0.7
  function col(key, fallback) { return host ? host.color(key, fallback) : fallback }
  readonly property color tint: host ? host.kindColor(kind) : "#a9b1d6"
  readonly property color ink: col("dark_background", "#16161e")
  readonly property color lead: col("foreground", "#a9b1d6")
  readonly property color shine: col("bright_foreground", "#c0caf5")
  width: 58; height: 58

  Rectangle {
    anchors.fill: parent
    radius: 10
    color: art.kind === Board.FRIED ? art.col("background", "#1a1b26") : art.col("lighter_background", "#24283b")
    border.width: 1
    border.color: art.kind === Board.FRIED ? art.col("red", "#f7768e") : Qt.rgba(art.tint.r, art.tint.g, art.tint.b, 0.35)
  }
  Loader {
    anchors.fill: parent
    sourceComponent: art.kind === 0 ? resistorArt : art.kind === 1 ? capacitorArt : art.kind === 2 ? ledArt
                   : art.kind === 3 ? chipArt : art.kind === 4 ? transistorArt : art.kind === 5 ? coilArt
                   : art.kind === Board.CORE ? coreArt : art.kind === Board.FRIED ? friedArt : null
  }

  // Specials: a Bus has bright rails along two edges, a Surge a glowing diamond.
  Rectangle { visible: art.special === "h"; x: 4; y: 3; width: 50; height: 4; radius: 2; color: art.shine; opacity: art.glow }
  Rectangle { visible: art.special === "h"; x: 4; y: 51; width: 50; height: 4; radius: 2; color: art.shine; opacity: art.glow }
  Rectangle { visible: art.special === "v"; x: 3; y: 4; width: 4; height: 50; radius: 2; color: art.shine; opacity: art.glow }
  Rectangle { visible: art.special === "v"; x: 51; y: 4; width: 4; height: 50; radius: 2; color: art.shine; opacity: art.glow }
  Rectangle {
    visible: art.special === "x"
    anchors.centerIn: parent
    width: 40; height: 40; radius: 6; rotation: 45
    color: "transparent"; border.width: 3; border.color: art.shine; opacity: art.glow
  }

  Component {
    id: resistorArt
    Item {
      Rectangle { x: 3; y: 27; width: 52; height: 4; radius: 2; color: art.lead }
      Rectangle { x: 11; y: 18; width: 36; height: 22; radius: 9; color: art.tint }
      Repeater {
        model: 3
        delegate: Rectangle { required property int index; x: 19 + index * 7; y: 18; width: 4; height: 22; color: art.ink; opacity: 0.7 }
      }
      Rectangle { x: 38; y: 18; width: 3; height: 22; color: art.shine; opacity: 0.6 }
    }
  }
  Component {
    id: capacitorArt
    Item {
      Rectangle { x: 21; y: 42; width: 3; height: 12; color: art.lead }
      Rectangle { x: 34; y: 42; width: 3; height: 9; color: art.lead }
      Rectangle { x: 15; y: 6; width: 28; height: 38; radius: 7; color: art.tint }
      Rectangle { x: 15; y: 6; width: 28; height: 7; radius: 3; color: Qt.lighter(art.tint, 1.3) }
      Rectangle { x: 33; y: 15; width: 6; height: 26; radius: 2; color: art.ink; opacity: 0.5 }
      Rectangle { x: 34.5; y: 20; width: 3; height: 2; color: art.shine }
      Rectangle { x: 34.5; y: 28; width: 3; height: 2; color: art.shine }
    }
  }
  Component {
    id: ledArt
    Item {
      Rectangle { x: 5; y: 1; width: 48; height: 48; radius: 24; color: art.tint; opacity: 0.12 + 0.18 * art.glow }
      Rectangle { x: 21; y: 38; width: 3; height: 16; color: art.lead }
      Rectangle { x: 34; y: 38; width: 3; height: 12; color: art.lead }
      Rectangle { x: 16; y: 7; width: 26; height: 30; radius: 13; color: art.tint }
      Rectangle { x: 16; y: 23; width: 26; height: 14; color: art.tint }
      Rectangle { x: 13; y: 35; width: 32; height: 5; radius: 2; color: Qt.darker(art.tint, 1.3) }
      Rectangle { x: 21; y: 12; width: 6; height: 11; radius: 3; color: art.shine; opacity: 0.55 }
    }
  }
  Component {
    id: chipArt
    Item {
      Repeater {
        model: 6
        delegate: Rectangle {
          required property int index
          x: index < 3 ? 6 : 44; y: 16 + (index % 3) * 10
          width: 8; height: 4; radius: 1; color: art.lead
        }
      }
      Rectangle { x: 12; y: 10; width: 34; height: 38; radius: 3; color: art.ink; border.width: 2; border.color: art.tint }
      Rectangle { x: 17; y: 15; width: 6; height: 6; radius: 3; color: art.tint }
      Rectangle { x: 19; y: 29; width: 20; height: 3; radius: 1; color: art.tint; opacity: 0.7 }
      Rectangle { x: 19; y: 36; width: 13; height: 3; radius: 1; color: art.tint; opacity: 0.5 }
    }
  }
  Component {
    id: transistorArt
    Item {
      Repeater {
        model: 3
        delegate: Rectangle { required property int index; x: 18 + index * 9; y: 38; width: 3; height: 16; color: art.lead }
      }
      Rectangle { x: 15; y: 4; width: 28; height: 17; radius: 3; color: art.lead; opacity: 0.85 }
      Rectangle { x: 25; y: 7; width: 8; height: 8; radius: 4; color: art.ink }
      Rectangle { x: 14; y: 18; width: 30; height: 22; radius: 3; color: art.tint }
      Rectangle { x: 18; y: 22; width: 22; height: 3; radius: 1; color: art.ink; opacity: 0.45 }
    }
  }
  Component {
    id: coilArt
    Item {
      Rectangle { x: 8; y: 8; width: 42; height: 42; radius: 21; color: "transparent"; border.width: 11; border.color: art.tint }
      Repeater {
        model: 10
        delegate: Rectangle {
          required property int index
          x: 27.5; y: 7; width: 3; height: 13; color: art.ink; opacity: 0.55
          transform: Rotation { origin.x: 1.5; origin.y: 22; angle: index * 36 }
        }
      }
      Rectangle { x: 25; y: 25; width: 8; height: 8; radius: 4; color: art.lead; opacity: 0.6 }
    }
  }
  Component {
    id: coreArt
    Item {
      Rectangle { x: 3; y: 27; width: 52; height: 4; color: art.tint; opacity: 0.6 }
      Rectangle { x: 27; y: 3; width: 4; height: 52; color: art.tint; opacity: 0.6 }
      Rectangle {
        anchors.centerIn: parent
        width: 32; height: 32; radius: 5; rotation: 45
        color: art.tint; border.width: 2; border.color: art.shine
      }
      Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 3; color: art.ink }
      Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: art.shine; opacity: art.glow }
    }
  }
  Component {
    id: friedArt
    Item {
      Rectangle { x: 12; y: 10; width: 34; height: 38; radius: 3; color: art.ink; border.width: 2; border.color: art.col("lighter_background", "#24283b") }
      Rectangle { anchors.centerIn: parent; width: 5; height: 36; radius: 2; rotation: 45; color: art.col("red", "#f7768e"); opacity: 0.85 }
      Rectangle { anchors.centerIn: parent; width: 5; height: 36; radius: 2; rotation: -45; color: art.col("red", "#f7768e"); opacity: 0.85 }
      Rectangle { x: 36; y: 3; width: 10; height: 10; radius: 5; color: art.lead; opacity: 0.25 }
      Rectangle { x: 43; y: 0; width: 7; height: 7; radius: 4; color: art.lead; opacity: 0.18 }
    }
  }
}
