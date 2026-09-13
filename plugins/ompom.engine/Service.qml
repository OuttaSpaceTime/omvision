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

  // All note/state filesystem work (mkdir, read, append, day rollover) is
  // delegated to notes-helper.py — a fixed interpreter/script pair, never a
  // shell — which holds validated, no-follow directory file descriptors for
  // the whole operation. That closes a gap this same choreography had here
  // in QML: doing it as several separate FileView/Process steps meant an
  // intermediate directory swapped for a symlink between two of those steps
  // could redirect a read, write, or rollover move outside ~/Notes/Ompom or
  // ~/.local/state/ompom. See notes-helper.py's own docstring for the rest.
  readonly property string pythonBin: "/usr/bin/python3"
  readonly property string notesHelperPath: decodeURIComponent(
    Qt.resolvedUrl("notes-helper.py").toString().replace(/^file:\/\//, ""))

  // Belt-and-suspenders: the helper enforces this same ceiling itself
  // (it's the actual trust boundary), but trimming here too means an
  // oversized paste is never even written to the subprocess's stdin.
  readonly property int maxNoteInputChars: 20000

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

  // extend deliberately behaves like focus here: no overlay, normal desktop
  // use, just a ticking bar countdown you can't pause or escape via mode
  // switch until it runs out and drops you back at the prompt overlay.
  // break is the mirror case: overlay stays up, and togglePause/cycleMode
  // both refuse to act, so there's no way to pause or mode-switch your way
  // out of it early either — it only ends on its own.
  readonly property bool overlayVisible: mode !== "off" && (phase === "prompt" || phase === "break")

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
    noteEdit.text = ""
  }

  function cycleMode() {
    if (root.phase === "extend" || root.phase === "break") return root.statusJson()
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
      // A genuinely new break cycle starting -- clear any note left over
      // from the previous one. Re-opening notes *within* the same cycle
      // (including through an extend) must not clear it; see openNotes().
      root.phase = "prompt"
      noteEdit.text = ""
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
    if (root.phase !== "prompt") return
    root.phase = "break"
    root.remaining = root.breakSecFor
  }

  function openNotes() {
    // Deliberately doesn't clear noteEdit.text: reopening notes within the
    // same break/prompt cycle (e.g. after Discard just to look at something
    // else) should pick back up where you left off. It's only cleared when
    // a new cycle actually starts (tick()'s focus->prompt transition) or a
    // note is actually saved (saveNote()).
    root.notesOpen = true
    Qt.callLater(function() { noteEdit.forceActiveFocus() })
  }

  function discardNotes() {
    root.notesOpen = false
  }

  function saveNote() {
    var text = String(noteEdit.text || "")
    if (text.trim().length === 0) {
      root.notesOpen = false
      return
    }
    if (text.length > root.maxNoteInputChars) text = text.slice(0, root.maxNoteInputChars)
    root.pendingNoteText = text
    // Cleared immediately rather than waiting for the save process to exit:
    // its content is now captured in pendingNoteText, and leaving it in the
    // box would duplicate it into a second saved block if Save is pressed
    // again later in the same break.
    noteEdit.text = ""
    // stdinEnabled must be re-armed before every run: Process.write() is a
    // no-op once it's been turned off, and it's turned off below right
    // after writing so the helper's stdin read() sees EOF.
    saveNoteProc.stdinEnabled = true
    saveNoteProc.running = true
  }

  // One trusted absolute interpreter running one fixed, plugin-local script
  // — never a shell, never anything resolved via PATH. The note text goes
  // over stdin rather than argv, so there's no argument for anything to
  // reinterpret and no length limit to fight. The save is best-effort from
  // this side either way: the UI resets as soon as the helper exits,
  // whatever its exit code (see notes-helper.py for what "best-effort"
  // actually means on disk — nothing is ever silently corrupted or
  // partially written, worst case a note just isn't appended).
  Process {
    id: saveNoteProc
    command: [root.pythonBin, root.notesHelperPath, "save-note"]
    onStarted: {
      saveNoteProc.write(root.pendingNoteText)
      saveNoteProc.stdinEnabled = false
    }
    onExited: {
      root.pendingNoteText = ""
      root.notesOpen = false
    }
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
        text: root.phase === "break" ? "Break" : "Focus complete"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.phase === "break"
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

    // --- notes view ---
    // Plain text, deliberately: QML's TextEdit has no supported way to apply
    // rich formatting to text as it's being typed without either a C++
    // QSyntaxHighlighter (unavailable to a QML-only Quickshell plugin) or
    // round-tripping through TextEdit's own Markdown (de)serializer, which
    // in practice escapes literal "#"/"**" characters and grows the buffer
    // on every keystroke instead of ever converting anything (verified by
    // hand). So no live rendering here -- just calm, minimal plain text,
    // with Return smart enough to continue a bullet/numbered list.
    Item {
      anchors.fill: parent
      anchors.margins: Style.space(120)
      visible: root.notesOpen

      Column {
        anchors.fill: parent
        spacing: Style.space(28)

        Text {
          text: "What's your focus?"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.heading
        }

        Flickable {
          width: parent.width
          height: parent.height - notesButtonRow.height - Style.space(28) * 2 - Style.font.heading
          clip: true
          contentWidth: width
          contentHeight: Math.max(height, noteEdit.paintedHeight)

          TextEdit {
            id: noteEdit
            width: parent.width
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            selectByMouse: true
            focus: root.notesOpen
            Keys.onEscapePressed: root.discardNotes()

            // Continues a "- ", "* ", or "1. " list line onto the next line,
            // auto-incrementing numbered markers. Pressing Return on an
            // already-empty list line ends the list instead of piling up
            // empty markers.
            Keys.onReturnPressed: function(event) {
              event.accepted = true
              var pos = noteEdit.cursorPosition
              var text = noteEdit.text
              var lineStart = text.lastIndexOf("\n", pos - 1) + 1
              var lineEnd = text.indexOf("\n", lineStart)
              if (lineEnd === -1) lineEnd = text.length
              var line = text.substring(lineStart, lineEnd)

              var bullet = line.match(/^(\s*)([-*])\s+(.*)$/)
              var numbered = line.match(/^(\s*)(\d+)\.\s+(.*)$/)
              var marker = bullet || numbered

              if (marker && marker[3].trim().length === 0) {
                noteEdit.remove(lineStart, lineEnd)
                noteEdit.insert(lineStart, "\n")
                noteEdit.cursorPosition = lineStart + 1
                return
              }

              var continuation = "\n"
              if (bullet) {
                continuation += bullet[1] + bullet[2] + " "
              } else if (numbered) {
                continuation += numbered[1] + (parseInt(numbered[2], 10) + 1) + ". "
              }
              noteEdit.insert(pos, continuation)
              noteEdit.cursorPosition = pos + continuation.length
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
