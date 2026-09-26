import QtQuick

// The night market: a dark sky, a row of stall roofs, two strings of paper
// lanterns that sway, and a boardwalk floor. All theme colors.
Item {
  id: stage
  property var game

  readonly property color sky: game.color("dark_background", "#13141c")
  readonly property color mid: game.color("background", "#1a1b26")
  readonly property color roof: game.color("lighter_background", "#24283b")
  readonly property var lanternKeys: ["red", "orange", "yellow", "magenta", "green", "cyan"]
  readonly property var lanternFb: ["#f7768e", "#ff9e64", "#e0af68", "#bb9af7", "#9ece6a", "#7dcfff"]

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: stage.sky }
      GradientStop { position: 0.75; color: stage.mid }
    }
  }

  // A low moon.
  Rectangle {
    x: 612; y: 120; width: 54; height: 54; radius: 27
    color: stage.game.color("foreground", "#c0caf5"); opacity: 0.16
  }

  // Stall roofs: fixed shapes, not random, so the stage never changes.
  Repeater {
    model: [
      { x: 0, w: 150, h: 120 }, { x: 140, w: 110, h: 150 }, { x: 240, w: 170, h: 105 },
      { x: 400, w: 120, h: 160 }, { x: 510, w: 150, h: 118 }, { x: 650, w: 150, h: 140 }
    ]
    delegate: Item {
      required property var modelData
      x: modelData.x; y: stage.game.groundY - modelData.h
      width: modelData.w; height: modelData.h
      Rectangle { y: 18; width: parent.width; height: parent.height - 18; color: stage.roof; opacity: 0.55 }
      Rectangle { x: -6; width: parent.width + 12; height: 20; radius: 4; color: stage.roof; opacity: 0.85 }
      // lit window
      Rectangle {
        x: parent.width * 0.3; y: 40; width: parent.width * 0.4; height: 22; radius: 2
        color: stage.game.color("yellow", "#e0af68"); opacity: 0.18
      }
    }
  }

  // Lantern strings.
  Repeater {
    model: 2
    delegate: Item {
      id: string
      required property int index
      readonly property real yTop: 112 + index * 48
      readonly property real sag: 34
      Repeater {
        model: 9
        delegate: Item {
          required property int index
          readonly property real u: (index + 0.5 + string.index * 0.5) / 9.5
          x: u * stage.width
          y: string.yTop + string.sag * 4 * u * (1 - u)
          rotation: 6 * Math.sin(stage.game.drawT * 1.6 + index + string.index * 2)
          transformOrigin: Item.Top
          Rectangle { x: -1; width: 2; height: 8; color: stage.roof }
          Rectangle {
            x: -9; y: 8; width: 18; height: 22; radius: 8
            color: stage.game.color(stage.lanternKeys[(index + string.index * 3) % 6], stage.lanternFb[(index + string.index * 3) % 6])
            opacity: 0.8
            Rectangle { x: 3; y: 5; width: parent.width - 6; height: 3; color: stage.sky; opacity: 0.35 }
            Rectangle { x: 3; y: 14; width: parent.width - 6; height: 3; color: stage.sky; opacity: 0.35 }
          }
        }
      }
    }
  }

  // Boardwalk floor.
  Rectangle {
    y: stage.game.groundY; width: parent.width; height: parent.height - stage.game.groundY
    color: stage.roof
    Rectangle { width: parent.width; height: 3; color: stage.game.color("accent", "#7aa2f7"); opacity: 0.6 }
    Repeater {
      model: 16
      delegate: Rectangle {
        required property int index
        x: index * 52 + 20; y: 10; width: 2; height: parent.height - 10
        color: stage.sky; opacity: 0.35
      }
    }
  }
}
