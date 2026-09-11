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

  // Trusted absolute executables — never resolved through a shell or PATH.
  readonly property string mkdirBin: "/usr/bin/mkdir"
  readonly property string mvBin: "/usr/bin/mv"

  // Day markers this engine itself ever writes are exactly today's date
  // (see todayStr()). Anything else read back — a corrupted or tampered
  // file — is rejected outright before it can be used to build a path, so
  // it can never steer the rollover mv outside the grave directory.
  readonly property var dayMarkerPattern: /^\d{4}-\d{2}-\d{2}$/

  // Hard ceilings so a single note or a runaway today-file can't grow
  // without bound: ~20k characters per saved note, ~2MB for the whole
  // day's file before this engine refuses to append further (existing
  // content is left untouched either way — never truncated or discarded).
  readonly property int maxNoteInputChars: 20000
  readonly property int maxNoteFileChars: 2000000

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
    if (root.mode === "off") return root.statusJson()
    if (root.phase !== "focus" && root.phase !== "extend") return root.statusJson()
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
    if (text.length > root.maxNoteInputChars) text = text.slice(0, root.maxNoteInputChars)
    root.pendingNoteText = text
    root.saveInProgress = true
    ensureNotesDirsProc.running = true
  }

  // Direct argv, no shell: mkdir/mv run as trusted absolute binaries with
  // their arguments passed literally, so there's no command string to quote
  // or escape — and nothing for a shell to reinterpret in the first place.
  Process {
    id: ensureNotesDirsProc
    command: [root.mkdirBin, "-p", root.todayDir, root.graveDir, root.stateDir]
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
    // The strict format check happens before marker touches any path — an
    // unrecognized marker (corrupted file, path separators, "..") is simply
    // never used, never concatenated into the mv destination, and rollover
    // is skipped for this save rather than guessed at.
    if (marker.length > 0 && marker !== today && root.dayMarkerPattern.test(marker)) {
      // mv exits non-zero (harmlessly) if todayFilePath doesn't exist yet —
      // no shell, so no "test -f" needed to guard the call.
      rolloverProc.command = [root.mvBin, root.todayFilePath, root.graveDir + "/" + marker + ".md"]
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
    var base = String(existing || "")
    // Refuse to grow an already-oversized file further. Existing content is
    // left completely untouched (no truncation) — this note just isn't
    // appended this time.
    if (base.length <= root.maxNoteFileChars) {
      var stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm")
      var block = "## " + stamp + "\n\n" + root.pendingNoteText.trim() + "\n\n"
      todayFileView.setText(base + block)
      dayMarkerFile.setText(root.todayStr())
    }
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

    // Quickshell only reserves pointer input over areas that actually have a
    // MouseArea (or similar), so without this, clicks over the plain
    // background Rectangle above fall through to whatever window is
    // underneath — the overlay looks blocking but the desktop keeps working
    // right through it. This absorbs every click that doesn't land on one of
    // the buttons below (those still win, since they're declared later and
    // stack on top).
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      hoverEnabled: true
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
          visible: root.phase === "extend"
          label: root.paused ? "Resume" : "Pause"
          onActivated: root.togglePause()
        }

        OverlayButton {
          visible: root.phase === "prompt" || root.phase === "extend"
          primary: true
          label: "Start break"
          onActivated: root.startBreak()
        }

        OverlayButton {
          label: root.mode === "long" ? "Mode: Long Focus" : "Mode: Normal"
          onActivated: root.cycleMode()
        }

        OverlayButton {
          label: "Take notes"
          onActivated: root.openNotes()
        }
      }
    }

    // --- notes view ---
    Item {
      anchors.fill: parent
      anchors.margins: Style.space(80)
      visible: root.notesOpen

      Column {
        anchors.fill: parent
        spacing: Style.space(14)

        Text {
          text: "What's on your mind?"
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
              textFormat: TextEdit.MarkdownText
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
