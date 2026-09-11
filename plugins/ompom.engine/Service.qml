import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Ompom pomodoro engine. Always running (keepLoaded), owns the timer state
// machine, and renders its own fullscreen blocking overlay directly (the same
// PanelWindow + WlrLayershell technique the lock screen and idle screensaver
// use) rather than being a separate summoned plugin. That keeps the block and
// the notes flow inside a single Wayland layer surface, so there's never a
// second layer-shell surface fighting it for exclusive keyboard focus.
// The block/notes buttons are OverlayButton.qml, a sibling file in this same
// plugin directory — QML resolves same-directory PascalCase files as types
// automatically, no import needed.
Item {
  id: root

  // Injected by omarchy-shell for first/third-party services. Unused here —
  // Ompom needs no host lookups — but declaring it matches the documented
  // service entry-point contract.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string notesDir: home + "/Notes/Ompom"
  readonly property string todayDir: notesDir + "/today"
  readonly property string graveDir: notesDir + "/grave"
  readonly property string todayFilePath: todayDir + "/ompom.md"
  readonly property string stateDir: home + "/.local/state/ompom"
  readonly property string dayMarkerPath: stateDir + "/notes-day"

  readonly property int normalFocusSec: 25 * 60
  readonly property int normalBreakSec: 5 * 60
  readonly property int longFocusSec: 50 * 60
  readonly property int longBreakSec: 10 * 60
  readonly property int extensionSec: 60
  readonly property int maxExtensions: 3

  readonly property int focusSecFor: mode === "long" ? longFocusSec : normalFocusSec
  readonly property int breakSecFor: mode === "long" ? longBreakSec : normalBreakSec

  // normal | long | off
  property string mode: "normal"
  // focus | prompt | extend | break
  property string phase: "focus"
  property bool paused: false
  property int remaining: normalFocusSec
  property int extensionsUsed: 0
  property bool notesOpen: false
  property string pendingNoteText: ""

  readonly property bool overlayVisible: mode !== "off" && phase !== "focus"

  function fmt(totalSeconds) {
    var s = Math.max(0, totalSeconds)
    var m = Math.floor(s / 60)
    var r = s % 60
    return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
  }

  function statusJson() {
    return JSON.stringify({
      mode: root.mode,
      phase: root.phase,
      remaining: root.remaining,
      remainingLabel: root.fmt(root.remaining),
      paused: root.paused,
      extensionsUsed: root.extensionsUsed,
      maxExtensions: root.maxExtensions,
      overlay: root.overlayVisible
    })
  }

  function resetRun() {
    root.paused = false
    root.extensionsUsed = 0
    root.phase = "focus"
    root.remaining = root.focusSecFor
    root.notesOpen = false
  }

  function cycleMode() {
    if (root.mode === "normal") root.mode = "long"
    else if (root.mode === "long") root.mode = "off"
    else root.mode = "normal"
    root.resetRun()
    return root.statusJson()
  }

  function togglePause() {
    if (root.mode === "off" || root.phase !== "focus") return root.statusJson()
    root.paused = !root.paused
    return root.statusJson()
  }

  function tick() {
    if (root.mode === "off" || root.paused) return
    if (root.remaining > 0) {
      root.remaining -= 1
      return
    }
    if (root.phase === "focus") {
      root.phase = "prompt"
    } else if (root.phase === "extend") {
      root.phase = "prompt"
    } else if (root.phase === "break") {
      root.phase = "focus"
      root.extensionsUsed = 0
      root.remaining = root.focusSecFor
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  function addExtension() {
    if (root.phase !== "prompt") return
    if (root.extensionsUsed >= root.maxExtensions) return
    root.extensionsUsed += 1
    root.phase = "extend"
    root.remaining = root.extensionSec
  }

  function startBreak() {
    if (root.phase !== "prompt" && root.phase !== "extend") return
    root.phase = "break"
    root.remaining = root.breakSecFor
  }

  function openNotes() {
    noteEdit.text = ""
    root.notesOpen = true
    Qt.callLater(function() { noteEdit.forceActiveFocus() })
  }

  function discardNotes() {
    root.notesOpen = false
  }

  function shQuote(s) {
    return "'" + String(s).replace(/'/g, "'\\''") + "'"
  }

  function todayStr() {
    var d = new Date()
    var mm = String(d.getMonth() + 1)
    var dd = String(d.getDate())
    return d.getFullYear() + "-" + (mm.length < 2 ? "0" + mm : mm) + "-" + (dd.length < 2 ? "0" + dd : dd)
  }

  // Guards the whole day-marker / today-file chain below. FileView performs
  // an implicit load as soon as it's created (e.g. on every shell restart),
  // which would otherwise cascade through handleDayMarker into
  // finishSaveNote and silently append a blank note block. Only an explicit
  // saveNote() call may flip this on, and every step bails out while it's off.
  property bool saveInProgress: false

  function saveNote() {
    var text = String(noteEdit.text || "")
    if (text.trim().length === 0) {
      root.notesOpen = false
      return
    }
    root.pendingNoteText = text
    root.saveInProgress = true
    ensureNotesDirsProc.running = true
  }

  Process {
    id: ensureNotesDirsProc
    command: ["bash", "-c", "mkdir -p " + root.shQuote(root.todayDir) + " " + root.shQuote(root.graveDir) + " " + root.shQuote(root.stateDir)]
    onExited: { if (root.saveInProgress) dayMarkerFile.reload() }
  }

  FileView {
    id: dayMarkerFile
    path: root.dayMarkerPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: { if (root.saveInProgress) root.handleDayMarker(text()) }
    onLoadFailed: { if (root.saveInProgress) root.handleDayMarker("") }
  }

  function handleDayMarker(raw) {
    var marker = String(raw || "").trim()
    var today = root.todayStr()
    if (marker.length > 0 && marker !== today) {
      rolloverProc.command = ["bash", "-c",
        "if [[ -f " + root.shQuote(root.todayFilePath) + " ]]; then mv " +
        root.shQuote(root.todayFilePath) + " " + root.shQuote(root.graveDir + "/" + marker + ".md") + "; fi"]
      rolloverProc.running = true
    } else {
      todayFileView.reload()
    }
  }

  Process {
    id: rolloverProc
    onExited: { if (root.saveInProgress) todayFileView.reload() }
  }

  FileView {
    id: todayFileView
    path: root.todayFilePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: { if (root.saveInProgress) root.finishSaveNote(text()) }
    onLoadFailed: { if (root.saveInProgress) root.finishSaveNote("") }
  }

  function finishSaveNote(existing) {
    var stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm")
    var block = "## " + stamp + "\n\n" + root.pendingNoteText.trim() + "\n\n"
    todayFileView.setText(String(existing || "") + block)
    dayMarkerFile.setText(root.todayStr())
    root.pendingNoteText = ""
    root.notesOpen = false
    root.saveInProgress = false
  }

  IpcHandler {
    target: "ompom"
    function status(): string { return root.statusJson() }
    function togglePause(): string { return root.togglePause() }
    function cycleMode(): string { return root.cycleMode() }
  }

  PanelWindow {
    id: overlay
    visible: root.overlayVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ompom-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: Color.background
      opacity: 0.92
    }

    // --- block view: prompt / extend / break ---
    Column {
      anchors.centerIn: parent
      visible: !root.notesOpen
      spacing: Style.space(20)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.mode === "long" ? "Long Focus" : "Normal"
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.phase === "break" ? "Break"
          : root.phase === "extend" ? "+1 minute"
          : "Focus complete"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.phase !== "prompt"
        text: root.fmt(root.remaining)
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.displayLarge
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)

        OverlayButton {
          visible: root.phase === "prompt" && root.extensionsUsed < root.maxExtensions
          label: "+1 minute (" + (root.maxExtensions - root.extensionsUsed) + " left)"
          onActivated: root.addExtension()
        }

        OverlayButton {
          visible: root.phase === "prompt"
          primary: true
          label: "Start break"
          onActivated: root.startBreak()
        }

        OverlayButton {
          label: "Take notes"
          onActivated: root.openNotes()
        }
      }
    }

    // --- notes view: Omawrite ---
    Item {
      anchors.fill: parent
      anchors.margins: Style.space(80)
      visible: root.notesOpen

      Column {
        anchors.fill: parent
        spacing: Style.space(14)

        Text {
          text: "Omawrite"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }

        Rectangle {
          width: parent.width
          height: parent.height - notesButtonRow.height - Style.space(60)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
          color: Color.popups.background
          border.color: Color.popups.border
          border.width: Style.space(1)

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(16)
            clip: true
            contentWidth: width
            contentHeight: Math.max(height, noteEdit.paintedHeight)

            TextEdit {
              id: noteEdit
              width: parent.width
              wrapMode: TextEdit.Wrap
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              selectByMouse: true
              focus: root.notesOpen
              Keys.onEscapePressed: root.discardNotes()
            }
          }
        }

        Row {
          id: notesButtonRow
          spacing: Style.space(16)

          OverlayButton {
            primary: true
            label: "Save"
            onActivated: root.saveNote()
          }

          OverlayButton {
            label: "Discard"
            onActivated: root.discardNotes()
          }
        }
      }
    }
  }
}
