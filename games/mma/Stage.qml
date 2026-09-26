import QtQuick

// The Dodecage: our own twelve-sided cage seen from the side. Behind the fighters
// a crowd in the dark, a ring of arena lights, the far cage wall (chain-link
// mesh between padded posts) and the canvas with the SMF mark. The two near
// posts stand at the cage's walls (game.wallL / wallR). All theme colors.
Item {
  id: stage
  property var game

  readonly property color sky: game.color("dark_background", "#13141c")
  readonly property color mid: game.color("background", "#1a1b26")
  readonly property color panel: game.color("lighter_background", "#24283b")
  readonly property color accent: game.color("accent", "#7aa2f7")
  readonly property color fg: game.color("foreground", "#c0caf5")
  readonly property real wallTop: game.groundY - 150
  readonly property real farFloor: game.groundY - 34

  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: 0.0; color: stage.sky }
      GradientStop { position: 0.7; color: stage.mid }
    }
  }

  // Arena lights: a ring of lamps high up.
  Repeater {
    model: 9
    delegate: Rectangle {
      required property int index
      x: 60 + index * 85; y: 104 + 10 * Math.sin(index * 0.9)
      width: 16; height: 6; radius: 3
      color: stage.fg; opacity: 0.35
    }
  }

  // The crowd: three rows of heads and shoulders, fixed so the stage never changes.
  Repeater {
    model: 3
    delegate: Item {
      id: row
      required property int index
      Repeater {
        model: 34
        delegate: Item {
          required property int index
          readonly property real bob: stage.game.phase === "play" ? 1.5 * Math.sin(stage.game.drawT * (2 + (index % 3)) + index) : 0
          x: index * 24 - 8 + (row.index % 2) * 12
          y: stage.wallTop - 44 + row.index * 22 + ((index * 7) % 5) + bob
          Rectangle { width: 18; height: 22; radius: 9; color: stage.panel; opacity: 0.35 + 0.15 * row.index }
          Rectangle { x: 3; y: -9; width: 12; height: 12; radius: 6; color: stage.panel; opacity: 0.4 + 0.15 * row.index }
        }
      }
    }
  }

  // Far cage wall: mesh between posts, a padded top rail.
  Canvas {
    id: mesh
    x: stage.game.wallL; y: stage.wallTop
    width: stage.game.wallR - stage.game.wallL; height: stage.farFloor - stage.wallTop
    property color line: stage.fg
    onLineChanged: requestPaint()
    onPaint: {
      var c = getContext("2d")
      c.clearRect(0, 0, width, height)
      c.strokeStyle = line
      c.globalAlpha = 0.16
      c.lineWidth = 1
      c.beginPath()
      for (var i = -height; i < width; i += 14) {
        c.moveTo(i, height); c.lineTo(i + height, 0)
        c.moveTo(i, 0); c.lineTo(i + height, height)
      }
      c.stroke()
    }
  }
  Repeater {   // far posts: the cage's twelve sides show five from here
    model: 5
    delegate: Rectangle {
      required property int index
      x: stage.game.wallL + 70 + index * (stage.game.wallR - stage.game.wallL - 140) / 4 - 4
      y: stage.wallTop - 4
      width: 8; height: stage.farFloor - stage.wallTop + 4; radius: 3
      color: stage.panel
    }
  }
  Rectangle {
    x: stage.game.wallL; y: stage.wallTop - 8
    width: stage.game.wallR - stage.game.wallL; height: 8; radius: 4
    color: stage.accent; opacity: 0.55
  }

  // The canvas.
  Rectangle {
    x: stage.game.wallL - 20; y: stage.farFloor
    width: stage.game.wallR - stage.game.wallL + 40; height: parent.height - stage.farFloor
    color: stage.panel
    Rectangle { width: parent.width; height: 2; color: stage.accent; opacity: 0.5 }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 6
      text: "SMF · DODECAGE"
      color: stage.fg; opacity: 0.12
      font.pixelSize: 28; font.bold: true; font.family: "monospace"
      transform: Scale { yScale: 0.6 }
    }
  }

  // Near posts at the cage walls, padded.
  Repeater {
    model: 2
    delegate: Item {
      required property int index
      x: index === 0 ? stage.game.wallL - 14 : stage.game.wallR
      y: stage.wallTop - 30
      Rectangle { width: 14; height: stage.game.groundY - stage.wallTop + 36; radius: 5; color: stage.panel; border.width: 2; border.color: stage.sky }
      Rectangle { y: 40; width: 14; height: 70; radius: 5; color: stage.accent; opacity: 0.8 }
    }
  }
}
