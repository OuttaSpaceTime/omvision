import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons

// Bar icon for the Ompom pomodoro engine (ompom.engine). This widget owns no
// state itself — it polls the engine's IpcHandler once a second and renders
// whatever comes back, and sends control calls the same way. That keeps the
// two plugins independent: reloading one never disturbs the other's timer.
Item {
  id: root

  property var bar: null
  property string moduleName: ""
  property var settings: ({})

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int barSize: bar ? bar.barSize : 26

  property string mode: "normal"
  property string phase: "focus"
  property string remainingLabel: "--:--"
  property bool paused: false

  // SVGs (icons/*.svg), tinted at runtime via MultiEffect — no font/emoji
  // involved, so there's no risk of a missing glyph collapsing to zero width
  // (that's what broke the off -> on toggle earlier) and no baked-in emoji
  // color fighting the theme. pomodoro.svg is OpenMoji's black/outline
  // tomato (CC BY-SA 4.0, see icons/ATTRIBUTION.md); off reuses the exact
  // same icon rather than a different shape, distinguished only by color.
  readonly property url iconSource: paused ? Qt.resolvedUrl("icons/pause.svg")
    : Qt.resolvedUrl("icons/pomodoro.svg")

  implicitWidth: Math.max(Style.space(52), row.implicitWidth + Style.space(16))
  implicitHeight: barSize

  // Color.bar.text is the same token the clock/other bar text actually binds
  // to — root.foreground (bar.foreground) reads noticeably lighter than that
  // in this theme, which is what made "on" look washed out. off keeps that
  // lighter tone deliberately, so it reads as a distinct, faded state.
  readonly property color dotColor: mode === "off" ? root.foreground : Color.bar.text

  function runCommand(cmd) {
    if (bar && typeof bar.run === "function") bar.run(cmd)
    else Quickshell.execDetached(["bash", "-c", cmd])
  }

  function handleClick(button) {
    if (button === Qt.LeftButton) root.runCommand("omarchy-shell -q ompom togglePause")
    else root.runCommand("omarchy-shell -q ompom cycleMode")
  }

  // The bar's own per-slot pointer layer only shows a pointing-hand cursor,
  // and only routes left-clicks through its own dispatcher, for modules that
  // implement triggerPress(button) — otherwise it falls back to plain
  // fallthrough hit-testing, which delivered clicks fine but left the cursor
  // stuck at a plain arrow. Implementing it fixes the hover cursor and keeps
  // left-clicks and right-clicks going through the exact same handleClick().
  function triggerPress(button) {
    root.handleClick(button)
  }

  function applyStatus(raw) {
    var parsed
    try { parsed = JSON.parse(raw) } catch (e) { return }
    if (!parsed) return
    root.mode = parsed.mode || "normal"
    root.phase = parsed.phase || "focus"
    root.remainingLabel = parsed.remainingLabel || "--:--"
    root.paused = !!parsed.paused
  }

  function labelText() {
    if (root.mode === "off") return ""
    if (root.phase !== "focus") return "break " + root.remainingLabel
    return root.remainingLabel
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // The main icon: the tomato normally (dimmed when off), swapped for the
    // pause glyph only while paused — not a second icon added alongside it.
    Item {
      id: icon
      anchors.verticalCenter: parent.verticalCenter
      width: Style.font.body
      height: Style.font.body

      Image {
        id: iconSvg
        anchors.fill: parent
        source: root.iconSource
        sourceSize.width: icon.width
        sourceSize.height: icon.height
        smooth: true
        visible: false
      }

      MultiEffect {
        anchors.fill: parent
        source: iconSvg
        colorization: 1.0
        colorizationColor: root.dotColor
        brightness: 1.0
      }
    }

    Text {
      id: label
      anchors.verticalCenter: parent.verticalCenter
      visible: text.length > 0
      color: root.dotColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      text: root.labelText()
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onClicked: function(mouse) { root.handleClick(mouse.button) }
    onEntered: if (bar && typeof bar.showTooltip === "function")
      bar.showTooltip(root, "Ompom — left: pause/resume · right: mode (" + root.mode + ")")
    onExited: if (bar && typeof bar.hideTooltip === "function") bar.hideTooltip(root)
    hoverEnabled: true
  }

  Process {
    id: pollProc
    command: ["bash", "-lc", "omarchy-shell ompom status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!pollProc.running) pollProc.running = true
  }
}
