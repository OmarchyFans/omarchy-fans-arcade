import QtQuick
import "fighters.js" as Fighters

// Health bars (with a trailing damage bar), the round clock, round pips, the
// Ember meters, score, and every message: the select screen, round calls,
// PAUSED and the end of the match.
Item {
  id: hud
  property var game

  readonly property color fg: game.color("foreground", "#a9b1d6")
  readonly property color bright: game.color("bright_foreground", "#c0caf5")
  readonly property color accent: game.color("accent", "#7aa2f7")
  readonly property color panel: game.color("dark_background", "#13141c")
  readonly property color edge: game.color("lighter_background", "#24283b")
  readonly property bool inFight: game.phase !== "select"

  function hpColor(r) {
    return r > 0.5 ? game.color("green", "#9ece6a") : r > 0.25 ? game.color("yellow", "#e0af68") : game.color("red", "#f7768e")
  }

  // ---- top bar -----------------------------------------------------------------
  Rectangle {
    visible: hud.inFight
    width: parent.width; height: game.hudH
    color: hud.panel; opacity: 0.88
  }

  Repeater {
    model: hud.inFight ? 2 : 0
    delegate: Item {
      id: side
      required property int index
      readonly property bool onRight: index === 1
      readonly property real barW: 300
      x: onRight ? game.fieldW - 20 - barW : 20
      y: 14
      width: barW; height: 70

      // Health: drains toward the outer edge. The trail shows recent damage.
      Rectangle {
        width: side.barW; height: 22; radius: 4
        color: hud.edge
        border.width: 2; border.color: hud.panel
        Rectangle {
          x: side.onRight ? 2 : parent.width - 2 - width
          y: 2; height: parent.height - 4; radius: 3
          width: (parent.width - 4) * Math.max(0, game.fighterAt(side.index).trail / game.fighterAt(side.index).maxHp)
          color: game.color("red", "#f7768e"); opacity: 0.55
        }
        Rectangle {
          x: side.onRight ? 2 : parent.width - 2 - width
          y: 2; height: parent.height - 4; radius: 3
          width: (parent.width - 4) * Math.max(0, game.fighterAt(side.index).hp / game.fighterAt(side.index).maxHp)
          color: hud.hpColor(game.fighterAt(side.index).hp / game.fighterAt(side.index).maxHp)
        }
      }
      // Name and round pips
      Text {
        y: 26
        x: side.onRight ? side.barW - width : 0
        text: (side.onRight && game.mode === "cpu" ? "CPU · " : (side.onRight ? "P2 · " : "P1 · ")) + game.fighterAt(side.index).name
        color: hud.bright; font.pixelSize: 14; font.bold: true; font.family: "monospace"
      }
      Row {
        y: 28
        x: side.onRight ? 0 : side.barW - width
        spacing: 6
        layoutDirection: side.onRight ? Qt.LeftToRight : Qt.RightToLeft
        Repeater {
          model: game.winsNeeded
          delegate: Rectangle {
            required property int index
            width: 12; height: 12; radius: 6
            color: index < (side.onRight ? game.winsP2 : game.winsP1) ? hud.accent : "transparent"
            border.width: 2; border.color: hud.accent
          }
        }
      }
      // Ember meter
      Rectangle {
        y: 48
        x: side.onRight ? side.barW - width : 0
        width: 190; height: 10; radius: 5
        color: hud.edge
        readonly property real m: game.fighterAt(side.index).meter
        readonly property bool kindled: game.fighterAt(side.index).kindleT > 0
        Rectangle {
          x: side.onRight ? parent.width - width : 0
          height: parent.height; radius: 5
          width: parent.kindled ? parent.width * game.fighterAt(side.index).kindleT / game.kindleTime : parent.width * parent.m / 100
          color: game.color("orange", "#ff9e64")
          opacity: parent.m >= 100 ? 0.7 + 0.3 * Math.sin(game.drawT * 10) : 0.9
        }
      }
      Text {
        y: 45
        x: side.onRight ? side.barW - 190 - width - 8 : 198
        text: game.fighterAt(side.index).kindleT > 0 ? "KINDLED" : (game.fighterAt(side.index).meter >= 100 ? "EMBER!" : "EMBER")
        color: game.fighterAt(side.index).meter >= 100 || game.fighterAt(side.index).kindleT > 0 ? game.color("orange", "#ff9e64") : hud.fg
        font.pixelSize: 11; font.bold: true; font.family: "monospace"
      }
    }
  }

  // Round clock
  Rectangle {
    visible: hud.inFight
    x: (game.fieldW - 64) / 2; y: 10
    width: 64; height: 44; radius: 6
    color: hud.edge
    border.width: 2; border.color: game.timeLeft < 10 && game.phase === "play" ? game.color("red", "#f7768e") : hud.accent
    Text {
      anchors.centerIn: parent
      text: Math.ceil(game.timeLeft)
      color: hud.bright; font.pixelSize: 28; font.bold: true; font.family: "monospace"
    }
  }
  Text {
    visible: hud.inFight
    anchors.horizontalCenter: parent.horizontalCenter
    y: 58
    text: game.mode === "cpu"
      ? "STAGE " + game.stage + "/" + Fighters.LADDER + " · LV " + game.cpuLevel + "\n" + game.score + " · HI " + game.highScore
      : "ROUND " + game.round + "\nP1 " + game.tallyP1 + " – " + game.tallyP2 + " P2"
    horizontalAlignment: Text.AlignHCenter
    color: hud.fg; font.pixelSize: 11; font.family: "monospace"; lineHeight: 0.95
  }

  // Combo counter
  Text {
    visible: game.comboText !== "" && hud.inFight
    x: game.comboSide === 0 ? 30 : game.fieldW - 30 - width
    y: 120
    text: game.comboText
    color: game.color("yellow", "#e0af68")
    font.pixelSize: 26; font.bold: true; font.family: "monospace"
  }

  // ---- round calls ---------------------------------------------------------------
  readonly property string callText: {
    // A stage or rematch banner is flashed as the round call starts, so it is
    // shown here (above the round name), not only during play.
    if (game.phase === "ready") return game.readyT > 0.55
        ? (game.banner !== "" ? game.banner + "\n" : "") + (game.round >= game.maxRounds ? "FINAL ROUND" : "ROUND " + game.round)
        : "FIGHT!"
    if (game.phase === "roundover") {
      var head = game.roundReason === "time" ? "TIME" : (game.roundReason === "double" ? "DOUBLE K.O." : "K.O.")
      if (game.roundWinner < 0) return head + "\nDRAW"
      return head + "\n" + game.fighterAt(game.roundWinner).name.toUpperCase() + " WINS" + (game.perfect ? " · PERFECT" : "")
    }
    if (game.banner !== "" && game.phase === "play") return game.banner
    return ""
  }
  Text {
    visible: hud.callText !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    y: 190
    text: hud.callText
    horizontalAlignment: Text.AlignHCenter
    color: hud.bright
    style: Text.Outline; styleColor: hud.panel
    font.pixelSize: 44; font.bold: true; font.family: "monospace"
  }

  // ---- select screen -------------------------------------------------------------
  Rectangle {
    visible: game.phase === "select"
    x: 150; y: 24; width: 500; height: 250; radius: 10
    color: hud.panel; opacity: 0.94
    border.width: 1; border.color: hud.edge

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 14
      spacing: 6
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "EMBERBOUT"
        color: game.color("orange", "#ff9e64"); font.pixelSize: 38; font.bold: true; font.family: "monospace"
      }
      Repeater {
        model: game.phase === "select" ? game.selRows() : []
        delegate: Text {
          required property var modelData
          required property int index
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property bool picked: index === game.selRow
          text: (picked ? "◂ " : "  ") + label() + (picked ? " ▸" : "  ")
          function label() {
            switch (modelData) {
            case "mode": return game.selMode === "cpu" ? "1 PLAYER vs CPU" : "2 PLAYERS"
            case "diff": return "CPU: " + Fighters.DIFFICULTY[game.selDiff].name.toUpperCase()
            case "p1": return "P1: " + Fighters.at(game.selP1).name.toUpperCase()
            case "p2": return "P2: " + Fighters.at(game.selP2).name.toUpperCase()
            }
            return ""
          }
          color: picked ? hud.bright : hud.fg
          font.pixelSize: 18; font.bold: picked; font.family: "monospace"
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 6
        text: "↑↓ choose · ←→ change · F or Enter to fight · Esc quits"
        color: hud.fg; font.pixelSize: 12; font.family: "monospace"
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "P1  WASD move · F light · G heavy · H ember\nP2  arrows · Ctrl light · Shift heavy · Enter ember\nhold back to block · full Ember: Kindle, or Flare when hit"
        horizontalAlignment: Text.AlignHCenter
        color: hud.fg; font.pixelSize: 11; font.family: "monospace"; opacity: 0.85
      }
    }
  }

  // Fighter cards under the select panel, one per side.
  Repeater {
    model: game.phase === "select" ? 2 : 0
    delegate: Rectangle {
      id: card
      required property int index
      readonly property var def: game.lookOf(index)
      x: index === 0 ? game.fieldW / 2 - 6 - width : game.fieldW / 2 + 6
      y: 286; width: 240; height: 108; radius: 8
      color: hud.panel; opacity: 0.9
      border.width: 1; border.color: game.color(def.colorKey, def.colorFb)
      Column {
        x: 10; y: 8; width: parent.width - 20
        spacing: 2
        Text { text: card.def.name.toUpperCase() + (card.index === 1 && game.selMode === "cpu" ? "  · first up" : "") + "\n" + card.def.title; color: hud.bright; font.pixelSize: 13; font.bold: true; font.family: "monospace"; width: parent.width; elide: Text.ElideRight; lineHeight: 0.95 }
        Text { text: card.def.blurb; color: hud.fg; font.pixelSize: 11; font.family: "monospace"; width: parent.width; wrapMode: Text.WordWrap }
        Text { text: card.def.special.name + ": " + card.def.special.hint; color: game.color("orange", "#ff9e64"); font.pixelSize: 11; font.family: "monospace"; width: parent.width; wrapMode: Text.WordWrap }
      }
    }
  }

  // ---- paused and match over -------------------------------------------------------
  Rectangle {
    visible: game.phase === "paused" || game.phase === "over"
    anchors.centerIn: endText
    width: endText.width + 56; height: endText.height + 36; radius: 8
    color: hud.panel; opacity: 0.94
    border.width: 1; border.color: hud.edge
  }
  Column {
    id: endText
    visible: game.phase === "paused" || game.phase === "over"
    anchors.centerIn: parent
    spacing: 10
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: {
        if (game.phase === "paused") return "PAUSED"
        if (game.mode === "cpu") return game.champion ? "CHAMPION!" : "GAME OVER"
        return game.matchWinner < 0 ? "DRAW MATCH" : (game.matchWinner === 0 ? "PLAYER 1 WINS" : "PLAYER 2 WINS")
      }
      color: hud.bright; font.pixelSize: 40; font.bold: true; font.family: "monospace"
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      horizontalAlignment: Text.AlignHCenter
      text: {
        if (game.phase === "paused") return "P to resume · Esc to quit"
        var tail = "\nEnter for the select screen · Esc to quit"
        if (game.mode === "cpu")
          return (game.champion ? "All " + Fighters.LADDER + " stages cleared" : "Fell at stage " + game.stage)
            + "\nScore " + game.score + (game.beatHigh ? " · new high score!" : "") + tail
        return "Matches  P1 " + game.tallyP1 + " – " + game.tallyP2 + " P2" + tail
      }
      color: hud.fg; font.pixelSize: 16; font.family: "monospace"
    }
  }
}
