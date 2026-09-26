import QtQuick
import "fighters.js" as Fighters
import "grapple.js" as Grapple

// Everything written on screen: the two damage panels (head, body and leg
// damage filling toward the finish line, plus stamina and knockdowns), the
// round clock, score, where the fight is, the submission struggle, every call
// and message, the select screen with stat cards, the broadcast result card,
// PAUSED and GAME OVER. Fighters are read only through game.fighterAt(i).
Item {
  id: hud
  property var game

  readonly property color fg: game.color("foreground", "#a9b1d6")
  readonly property color bright: game.color("bright_foreground", "#c0caf5")
  readonly property color accent: game.color("accent", "#7aa2f7")
  readonly property color panel: game.color("dark_background", "#13141c")
  readonly property color edge: game.color("lighter_background", "#24283b")
  readonly property color warn: game.color("red", "#f7768e")
  readonly property bool inFight: game.phase !== "select"
  readonly property string mono: "monospace"

  // Damage colors: green while healthy, yellow, then red near the finish.
  function dmgColor(r) {
    return r < 0.5 ? game.color("green", "#9ece6a") : r < 0.75 ? game.color("yellow", "#e0af68") : warn
  }
  function whereText() {
    if (game.phase !== "play") return ""
    switch (game.pos) {
    case "clinch": return "CLINCH · " + game.fighterAt(game.clinchS.owner).name.toUpperCase() + " HAS THE INSIDE"
    case "ground": return Grapple.POS_NAMES[game.gnd.pos] + " · " + game.fighterAt(game.gnd.top).name.toUpperCase() + " ON TOP"
    case "sub": return Fighters.SUB_NAMES[game.subS.kind] || ""
    }
    return ""
  }

  // ---- top bar: one panel per fighter ---------------------------------------------
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
      objectName: "panel-" + index
      readonly property bool onRight: index === 1
      readonly property real barW: 270   // leaves the centre free for the clock and the score line
      x: onRight ? game.fieldW - 16 - barW : 16
      y: 8
      width: barW; height: 84

      Text {
        x: side.onRight ? side.barW - width : 0
        text: (side.onRight ? (game.mode === "cpu" ? "CPU" : "P2") : "P1") + " · " + game.fighterAt(side.index).name.toUpperCase()
        color: hud.bright; font.pixelSize: 14; font.bold: true; font.family: hud.mono
      }
      // Knockdowns this round
      Row {
        x: side.onRight ? 0 : side.barW - width
        y: 3; spacing: 4
        Repeater {
          model: game.fighterAt(side.index).kd || 0
          delegate: Rectangle { width: 10; height: 10; radius: 5; color: hud.warn }
        }
      }
      // Head, body, leg: damage fills from the inside edge toward the limit.
      Repeater {
        model: [["HEAD", "head"], ["BODY", "body"], ["LEG", "leg"]]
        delegate: Item {
          id: dbar
          required property var modelData
          required property int index
          readonly property real ratio: Math.min(1, (game.fighterAt(side.index)[modelData[1]] || 0) / game.limit)
          y: 20 + index * 15
          width: side.barW; height: 12
          Text {
            x: side.onRight ? side.barW - width : 0
            text: dbar.modelData[0]; color: hud.fg; font.pixelSize: 10; font.family: hud.mono
          }
          Rectangle {
            x: side.onRight ? 0 : 40
            width: side.barW - 40; height: 10; radius: 3
            color: hud.edge
            Rectangle {
              objectName: "dmg-" + side.index + "-" + dbar.modelData[1]   // the rules test finds it by name
              x: side.onRight ? parent.width - width : 0
              width: parent.width * dbar.ratio; height: parent.height; radius: 3
              color: hud.dmgColor(dbar.ratio)
            }
          }
        }
      }
      // Stamina
      Item {
        y: 66; width: side.barW; height: 12
        Text {
          x: side.onRight ? side.barW - width : 0
          text: "GAS"; color: game.fighterAt(side.index).stamina < 30 ? hud.warn : hud.fg; font.pixelSize: 10; font.family: hud.mono
        }
        Rectangle {
          x: side.onRight ? 0 : 40
          width: side.barW - 40; height: 8; radius: 3
          color: hud.edge
          Rectangle {
            x: side.onRight ? parent.width - width : 0
            width: parent.width * Math.max(0, Math.min(1, game.fighterAt(side.index).stamina / 100)); height: parent.height; radius: 3
            color: game.fighterAt(side.index).stamina < 30 ? game.color("orange", "#ff9e64") : game.color("cyan", "#7dcfff")
          }
        }
      }
    }
  }

  // Round clock (time left in the round) and round number
  Rectangle {
    visible: hud.inFight
    x: (game.fieldW - 92) / 2; y: 8
    width: 92; height: 44; radius: 6
    color: hud.edge
    border.width: 2; border.color: game.timeLeft < 10 && game.phase === "play" ? hud.warn : hud.accent
    Text {
      anchors.centerIn: parent
      readonly property int s: Math.max(0, Math.ceil(game.timeLeft))
      text: Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
      color: hud.bright; font.pixelSize: 26; font.bold: true; font.family: hud.mono
    }
  }
  Text {
    objectName: "hud-round"
    visible: hud.inFight
    anchors.horizontalCenter: parent.horizontalCenter
    y: 55
    text: "ROUND " + game.round + "/" + game.maxRounds + " · " + (game.mode === "cpu"
      ? "FIGHT " + game.stage + "/" + Fighters.LADDER + " · LV " + game.cpuLevel
      : "P1 " + game.tallyP1 + " – " + game.tallyP2 + " P2")
    color: hud.fg; font.pixelSize: 10; font.family: hud.mono
  }
  // Score and high score (1 player only: nothing scores in a 2-player fight)
  Text {
    objectName: "hud-score"
    visible: hud.inFight && game.mode === "cpu"
    anchors.horizontalCenter: parent.horizontalCenter
    y: 70
    text: "SCORE " + game.score + "  ·  HIGH " + game.highScore
    color: hud.bright; font.pixelSize: 13; font.bold: true; font.family: hud.mono
  }

  // Where the fight is
  Text {
    visible: text !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    y: game.hudH + 6
    text: hud.whereText()
    color: hud.accent; font.pixelSize: 13; font.bold: true; font.family: hud.mono
  }

  // ---- the submission struggle -------------------------------------------------------
  Column {
    visible: game.pos === "sub" && (game.phase === "play" || game.phase === "paused")
    anchors.horizontalCenter: parent.horizontalCenter
    y: 150
    spacing: 4
    Repeater {
      model: [["TAP", "tap"], ["ESCAPE", "esc"]]
      delegate: Row {
        id: srow
        required property var modelData
        spacing: 8
        Text { width: 60; text: srow.modelData[0]; color: hud.bright; font.pixelSize: 12; font.bold: true; font.family: hud.mono }
        Rectangle {
          width: 260; height: 14; radius: 4; color: hud.edge
          border.width: 1; border.color: hud.panel
          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, (game.subS[srow.modelData[1]] || 0) / 100))
            height: parent.height; radius: 4
            color: srow.modelData[1] === "tap" ? hud.warn : game.color("green", "#9ece6a")
          }
        }
      }
    }
  }

  // What each player can do right now (clinch, ground, submission). Each gets
  // its own line, P1 above P2, so neither has to share the width with the other.
  Repeater {
    model: hud.inFight ? 2 : 0
    delegate: Text {
      required property int index
      readonly property string hint: game.hintFor(index)
      objectName: "hint-" + index
      visible: hint !== "" && !game.fighterAt(index).cpu
      x: index === 0 ? 12 : game.fieldW - 12 - width
      y: game.fieldH - (index === 0 ? 32 : 17)
      width: Math.min(implicitWidth, game.fieldW - 24)
      elide: Text.ElideRight
      text: hint
      color: hud.fg; opacity: 0.8; font.pixelSize: 10; font.family: hud.mono
    }
  }

  // ---- round calls and banners ------------------------------------------------------
  readonly property string callText: {
    if (game.phase === "ready") return game.readyT > 0.45
        ? (game.banner !== "" ? game.banner + "\n" : "") + (game.round >= game.maxRounds ? "FINAL ROUND" : "ROUND " + game.round)
        : "FIGHT!"
    if (game.phase === "roundover") return "END OF ROUND " + game.round
    if (game.banner !== "" && game.phase === "play") return game.banner
    return ""
  }
  Text {
    visible: hud.callText !== ""
    anchors.horizontalCenter: parent.horizontalCenter
    y: game.pos === "sub" ? 206 : 170
    text: hud.callText
    horizontalAlignment: Text.AlignHCenter
    color: hud.bright
    style: Text.Outline; styleColor: hud.panel
    font.pixelSize: 38; font.bold: true; font.family: hud.mono
  }

  // ---- select screen -----------------------------------------------------------------
  Rectangle {
    visible: game.phase === "select"
    x: 70; y: 6; width: 660; height: 226; radius: 10
    color: hud.panel; opacity: 0.94
    border.width: 1; border.color: hud.edge

    Column {
      anchors.horizontalCenter: parent.horizontalCenter
      y: 6
      spacing: 3
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "SUPER MMA FIGHTER"
        color: hud.accent; font.pixelSize: 28; font.bold: true; font.family: hud.mono
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
            case "mode": return game.selMode === "cpu" ? "1 PLAYER vs CPU LADDER" : "2 PLAYERS"
            case "diff": return "CPU: " + Fighters.DIFFICULTY[game.selDiff].name.toUpperCase()
            case "p1": return "P1: " + Fighters.at(game.selP1).name.toUpperCase()
            case "p2": return "P2: " + Fighters.at(game.selP2).name.toUpperCase()
            }
            return ""
          }
          color: picked ? hud.bright : hud.fg
          font.pixelSize: 16; font.bold: picked; font.family: hud.mono
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 2
        objectName: "select-prompt"
        text: "↑↓ choose  ·  ←→ change  ·  F or Enter to fight  ·  P pause  ·  Esc quit"
        color: hud.fg; font.pixelSize: 11; font.family: hud.mono
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        horizontalAlignment: Text.AlignHCenter
        text: "P1  " + game.keyNames.p1 + "\nP2  " + game.keyNames.p2
            + "\nstrike: jab · toward cross · back hook · down body shot"
            + "\nkick: body · toward head · down leg · back or close knee"
            + "\nhold back block · tap down slip, then counter · hold down sprawl"
            + "\ngrapple: clinch up close, shoot from range · in a lock: mash"
        color: hud.fg; font.pixelSize: 10; font.family: hud.mono; opacity: 0.85
      }
    }
  }

  // Stat cards: who you picked and who you face first.
  Repeater {
    model: game.phase === "select" ? 2 : 0
    delegate: Rectangle {
      id: card
      required property int index
      readonly property var def: game.lookOf(index)
      x: index === 0 ? game.fieldW / 2 - 6 - width : game.fieldW / 2 + 6
      y: 238; width: 300; height: 296; radius: 8
      color: hud.panel; opacity: 0.94
      border.width: 2; border.color: game.color(def.colorKey, def.colorFb)
      Column {
        objectName: "card-col-" + card.index
        x: 10; y: 8; width: parent.width - 20
        spacing: 2
        Text {
          width: parent.width; elide: Text.ElideRight
          text: card.def.name.toUpperCase() + (card.index === 1 && game.selMode === "cpu" ? "  · FIRST UP" : "")
          color: hud.bright; font.pixelSize: 14; font.bold: true; font.family: hud.mono
        }
        Text {
          width: parent.width; elide: Text.ElideRight
          text: "\"" + card.def.nick + "\" · " + card.def.home
          color: game.color(card.def.colorKey, card.def.colorFb); font.pixelSize: 11; font.family: hud.mono
        }
        Text {
          width: parent.width; wrapMode: Text.WordWrap
          text: card.def.archetype.toUpperCase() + ", " + card.def.stance.toUpperCase() + ": " + card.def.style
          color: hud.fg; font.pixelSize: 10; font.family: hud.mono
        }
        Repeater {
          model: Fighters.RATING_KEYS.length
          delegate: Row {
            id: rrow
            required property int index
            readonly property real v: card.def.ratings[Fighters.RATING_KEYS[index]]
            spacing: 6
            Text { width: 76; text: Fighters.RATING_LABELS[rrow.index]; color: hud.fg; font.pixelSize: 10; font.family: hud.mono }
            Rectangle {
              y: 2; width: 170; height: 9; radius: 3; color: hud.edge
              Rectangle { width: parent.width * rrow.v / 10; height: parent.height; radius: 3; color: game.color(card.def.colorKey, card.def.colorFb) }
            }
            Text { text: rrow.v.toFixed(1); color: hud.fg; font.pixelSize: 10; font.family: hud.mono }
          }
        }
        Text {
          text: Fighters.finishLine(card.def)
          color: hud.bright; font.pixelSize: 10; font.family: hud.mono
        }
        Text {
          objectName: "card-special-" + card.index
          width: parent.width; wrapMode: Text.WordWrap
          text: "SPECIAL " + card.def.special.name.toUpperCase() + ": " + card.def.special.hint
          color: hud.fg; font.pixelSize: 10; font.family: hud.mono
        }
      }
    }
  }

  // ---- the broadcast result card ---------------------------------------------------------
  Rectangle {
    id: resultCard
    visible: game.phase === "result" || (game.phase === "paused" && game.pausedFrom === "result")
    anchors.horizontalCenter: parent.horizontalCenter
    y: 130; width: 460; height: resultCol.height + 28; radius: 8
    color: hud.panel; opacity: 0.95
    border.width: 2; border.color: hud.accent
    Column {
      id: resultCol
      anchors.horizontalCenter: parent.horizontalCenter
      y: 14; spacing: 4
      readonly property var r: game.result
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: resultCol.r.winner < 0 ? "DRAW" : game.fighterAt(resultCol.r.winner).name.toUpperCase() + " WINS"
        color: hud.bright; font.pixelSize: 26; font.bold: true; font.family: hud.mono
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: resultCol.r.method === "DEC"
          ? (resultCol.r.winner < 0 ? resultCol.r.detail : resultCol.r.detail + " DECISION")
          : resultCol.r.method + " (" + resultCol.r.detail + ") · ROUND " + resultCol.r.round + " · " + resultCol.r.time
        color: hud.accent; font.pixelSize: 14; font.bold: true; font.family: hud.mono
      }
      Repeater {
        model: resultCol.r.totals ? resultCol.r.totals.length : 0
        delegate: Text {
          required property int index
          anchors.horizontalCenter: parent.horizontalCenter
          text: "JUDGE " + String.fromCharCode(65 + index) + "   " + resultCol.r.totals[index][0] + " – " + resultCol.r.totals[index][1]
          color: hud.fg; font.pixelSize: 12; font.family: hud.mono
        }
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        topPadding: 4
        text: "Enter to continue"
        color: hud.fg; opacity: 0.7; font.pixelSize: 11; font.family: hud.mono
      }
    }
  }

  // ---- paused and game over ------------------------------------------------------------
  Rectangle {
    visible: endText.visible
    anchors.centerIn: endText
    width: endText.width + 56; height: endText.height + 36; radius: 8
    color: hud.panel; opacity: 0.94
    border.width: 1; border.color: hud.edge
  }
  Column {
    id: endText
    visible: (game.phase === "paused" && game.pausedFrom !== "result") || game.phase === "over"
    anchors.centerIn: parent
    spacing: 10
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: {
        if (game.phase === "paused") return "PAUSED"
        if (game.mode === "cpu") return game.champion ? "CHAMPION!" : "GAME OVER"
        var w = game.result.winner
        return w < 0 ? "DRAW" : (w === 0 ? "PLAYER 1 WINS" : "PLAYER 2 WINS")
      }
      color: hud.bright; font.pixelSize: 40; font.bold: true; font.family: hud.mono
    }
    Text {
      objectName: "end-sub"
      anchors.horizontalCenter: parent.horizontalCenter
      horizontalAlignment: Text.AlignHCenter
      text: {
        if (game.phase === "paused") return "P or Space to resume  ·  Esc to quit"
        var tail = "\nEnter for the select screen  ·  Esc to quit"
        if (game.mode === "cpu")
          return (game.champion ? "All " + Fighters.LADDER + " fights won" : "Lost at fight " + game.stage + " of " + Fighters.LADDER)
            + "\nScore " + game.score + (game.beatHigh ? "  ·  new high score!" : "  ·  best " + game.highScore) + tail
        return "Fights  P1 " + game.tallyP1 + " – " + game.tallyP2 + " P2" + tail
      }
      color: hud.fg; font.pixelSize: 16; font.family: hud.mono
    }
  }
  // The paused banner over the result card
  Text {
    visible: game.phase === "paused" && game.pausedFrom === "result"
    anchors.horizontalCenter: parent.horizontalCenter
    y: resultCard.y - 44
    objectName: "paused-over-result"
    text: "PAUSED  ·  P or Space to resume"
    color: hud.bright; style: Text.Outline; styleColor: hud.panel
    font.pixelSize: 26; font.bold: true; font.family: hud.mono
  }
}
