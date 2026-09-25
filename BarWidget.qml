import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Arcade bar chip. A click opens a small menu of games; picking one runs
// bin/arcade, which starts Brick Blitz in its own Quickshell window or checks
// your ROMs and starts a MAME game. Nothing heavy lives in the bar process.
//
// Nothing is looked up on PATH and no shell string is built: bash is an
// absolute path, the script is this plugin's own checkout, the argv is fixed,
// and the child gets a fixed system PATH.
//
// Updates (lib/update.sh): the published version is checked on load and every
// six hours (cached, one small request). When a newer one is out, a dot appears
// on the chip and the menu opens with what changed and an Update… button; Later
// hides that version.
BarWidget {
  id: root
  moduleName: "fans.omarchy.arcade"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string home: Quickshell.env("HOME") || ""
  // This file's folder as a plain path. Qt.resolvedUrl gives a file:// URL.
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property var childEnv: ({ "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/share/omarchy/bin" })

  readonly property var games: [
    { id: "brick",  title: "Brick Blitz",             note: "built in" },
    { id: "pacman", title: "Pac-Man",                 note: "MAME · your ROM" },
    { id: "galaga", title: "Galaga",                  note: "MAME · your ROM" },
    { id: "ssf2",   title: "Super Street Fighter II", note: "MAME · your ROM" }
  ]

  function arcade(args) {
    menu.open = false
    Quickshell.execDetached({
      command: ["/usr/bin/bash", root.pluginDir + "/bin/arcade"].concat(args),
      environment: root.childEnv,
      workingDirectory: root.home
    })
  }

  // ---- updates ----------------------------------------------------------------
  property string version: ""
  property var updateInfo: null
  readonly property bool updateAvailable: !!updateInfo && updateInfo.update_available === true
                                          && updateInfo.dismissed !== updateInfo.latest
  readonly property bool updateMismatch: !!updateInfo && updateInfo.mismatch === true
  // What the alert is about: the newer version, or "mismatch". Update… and Later
  // hide that key only, so the next version (or a new mismatch) shows again.
  readonly property string updateKey: updateAvailable ? String(updateInfo.latest) : (updateMismatch ? "mismatch" : "")
  property string updateHiddenKey: ""
  readonly property bool updatePending: updateKey !== "" && updateKey !== updateHiddenKey

  FileView {
    path: root.pluginDir + "/manifest.json"
    printErrors: false
    onLoaded: {
      try { root.version = String(JSON.parse(text()).version || "") } catch (e) { root.version = "" }
      root.checkUpdates()
    }
  }
  function checkUpdates() {
    if (root.setting("update_check", true) === false || updateProc.running) return
    updateProc.command = ["/usr/bin/bash", root.pluginDir + "/lib/update.sh", "check", root.version]
    updateProc.running = true
  }
  Process {
    id: updateProc
    environment: root.childEnv
    stdout: StdioCollector { id: updateOut; waitForEnd: true }
    onExited: function(code) { try { root.updateInfo = JSON.parse(String(updateOut.text || "")) } catch (e) { root.updateInfo = null } }
  }
  Timer { interval: 6 * 3600 * 1000; running: true; repeat: true; onTriggered: root.checkUpdates() }
  function runUpdate() {
    root.updateHiddenKey = root.updateKey
    menu.open = false
    Quickshell.execDetached({
      command: ["/usr/bin/bash", root.pluginDir + "/lib/update.sh", "run", root.updateAvailable ? "all" : "install"],
      environment: root.childEnv,
      workingDirectory: root.home
    })
  }
  function dismissUpdate() {
    root.updateHiddenKey = root.updateKey
    if (root.updateAvailable && root.updateInfo.latest)
      Quickshell.execDetached({
        command: ["/usr/bin/bash", root.pluginDir + "/lib/update.sh", "dismiss", String(root.updateInfo.latest)],
        environment: root.childEnv,
        workingDirectory: root.home
      })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""              // nf-fa-gamepad
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: "Arcade" + (root.updateAvailable ? " · Arcade " + root.updateInfo.latest + " is available" : (root.updateMismatch ? " · finish updating" : ""))
    onPressed: menu.open = !menu.open
    Rectangle {
      visible: root.updatePending
      anchors.top: parent.top; anchors.right: parent.right
      anchors.margins: Style.space(3)
      width: Style.space(6); height: width; radius: width / 2
      color: Color.accent
    }
  }

  PopupCard {
    id: menu
    anchorItem: button
    bar: root.bar
    contentWidth: fittedContentWidth(Style.space(340))
    contentHeight: fittedContentHeight(col.implicitHeight)
    Column {
      id: col
      width: parent.width
      spacing: Style.space(4)

      // Update banner (lib/update.sh), above the games.
      Column {
        visible: root.updatePending
        width: parent.width
        spacing: Style.space(3)
        Text {
          width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
          text: root.updateAvailable
                ? "Arcade " + root.updateInfo.latest + " is available (you have " + root.version + ")"
                : "Finish updating Arcade"
          color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
        }
        Repeater {
          model: root.updateAvailable ? root.updateInfo.notes.slice(0, 4) : []
          delegate: Text {
            required property var modelData
            width: col.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
            text: "•  " + modelData
            color: Color.popups.text; opacity: 0.8; font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
        }
        Text {
          width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
          text: root.updateAvailable
                ? "Update opens a terminal: omarchy plugin update shows the changes and asks first."
                : "Run install.sh once so the files match. It only creates Arcade's own folders."
          color: Color.popups.text; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption
        }
        Row {
          spacing: Style.space(4)
          Button { text: root.updateAvailable ? "Update…" : "Finish update…"; bordered: true; foreground: Color.accent; onClicked: root.runUpdate() }
          Button { text: "Later"; bordered: true; foreground: Color.popups.text; onClicked: root.dismissUpdate() }
        }
        Rectangle { width: parent.width; height: 1; color: Color.popups.text; opacity: 0.15 }
      }

      Text {
        width: parent.width; textFormat: Text.PlainText
        text: "Arcade"
        color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; font.bold: true
      }
      Repeater {
        model: root.games
        delegate: Row {
          required property var modelData
          spacing: Style.space(4)
          Button {
            text: modelData.title
            bordered: modelData.id === "brick"
            foreground: modelData.id === "brick" ? Color.accent : Color.popups.text
            onClicked: root.arcade(["play", modelData.id])
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: modelData.note
            color: Color.popups.text; opacity: 0.55; font.family: Style.font.family; font.pixelSize: Style.font.caption
          }
        }
      }
      Text {
        width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: "MAME games need MAME (pacman -S mame) and your own ROM files. Arcade never downloads games."
        color: Color.popups.text; opacity: 0.6; font.family: Style.font.family; font.pixelSize: Style.font.caption
      }
      Button { text: "Open ROM folder"; foreground: Color.popups.text; onClicked: root.arcade(["rom-dir", "--open"]) }
    }
  }
}
