import QtQuick
import Quickshell
import Quickshell.Io

// Brick Blitz runs as its own Quickshell process (bin/arcade: quickshell -n -p
// game/shell.qml), never inside the Omarchy bar, so nothing it does can take the
// shell down. It reads the active Omarchy theme for its colors and keeps one
// number on disk: the high score.
ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")
  readonly property string scoreFile: stateHome + "/omarchy-arcade/brick.json"
  readonly property string themeColors: stateHome + "/omarchy/current/theme/colors.toml"

  property var theme: ({})
  property int savedHigh: 0
  property bool quitting: false

  // colors.toml is flat `key = "#rrggbb"` lines; that is all we need from it.
  FileView {
    path: root.themeColors
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var out = {}
      var re = /^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?)"/gm
      var m, t = text()
      while ((m = re.exec(t)) !== null) out[m[1]] = m[2]
      root.theme = out
    }
  }

  FileView {
    id: scoreView
    path: root.scoreFile
    printErrors: false
    // quit() writes and exits right away: the write must finish first.
    blockWrites: true
    onLoaded: {
      try {
        var n = parseInt(JSON.parse(text()).high, 10)
        if (n > 0) { root.savedHigh = n; if (n > game.highScore) game.highScore = n }
      } catch (e) {}
    }
  }

  function saveHigh() {
    if (game.highScore <= root.savedHigh) return
    root.savedHigh = game.highScore
    scoreView.setText(JSON.stringify({ high: game.highScore }) + "\n")
  }

  function quit() {
    if (root.quitting) return
    root.quitting = true
    saveHigh()
    Qt.quit()
  }

  // Save a new high score a moment after it stops climbing, not on every point.
  Timer { id: saveTimer; interval: 1500; onTriggered: root.saveHigh() }

  FloatingWindow {
    id: window
    title: "Brick Blitz"
    color: root.theme.background || "#1a1b26"
    implicitWidth: 960
    implicitHeight: 720
    minimumSize: Qt.size(480, 360)

    // Quickshell keeps running when its last window closes; closing the window
    // (Super+W, the titlebar) ends the game.
    onVisibleChanged: if (!visible) root.quit()

    Game {
      id: game
      anchors.fill: parent
      anchors.margins: 12
      focus: true
      theme: root.theme
      // Live play seeds every new game from the clock; the tests set a seed.
      autoSeed: true
      // ARCADE_BRICK_DROP=0..1 sets how often a broken brick drops a power-up
      // (for trying them out; the bar never sets it).
      dropChance: {
        var v = parseFloat(Quickshell.env("ARCADE_BRICK_DROP") || "")
        return isNaN(v) ? 0.18 : Math.max(0, Math.min(1, v))
      }
      onQuitRequested: root.quit()
      onNewHighScore: saveTimer.restart()
      onPhaseChanged: if (phase === "over") root.saveHigh()
    }
  }
}
