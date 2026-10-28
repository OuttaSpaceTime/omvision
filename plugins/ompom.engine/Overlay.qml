import QtQuick
import qs.Commons

// The break overlay's screens: the prompt and the break's countdown, the
// notes page, and the goal picker, and the night's three: "Time to sleep",
// the countdown to morning, and the journal (NightJournal.qml). Holds no
// cycle state of its own -- it reads Engine.qml and calls its functions --
// so Service.qml can put it in the layer-shell window omarchy-shell shows,
// and tests/engine in a FloatingWindow offscreen.
Item {
  id: overlay

  required property var engine

  // Ctrl+G's goal picker. How the screen looks rather than part of the
  // cycle, so it's the overlay's: closed again whenever the phase moves on
  // (the Connections below), which is every way a break ends.
  property bool goalPickerOpen: false

  // The writing size: omvision's journal type exactly (Theme.writingPointSize
  // there), in points for the same reason -- the highlighter's character
  // formats are point-sized, and mixing pixel and point sizes on one run of
  // text gives Qt two systems to reconcile.
  readonly property real writingPointSize: 15

  // The notes are set to one measure and centred in it, rather than run
  // edge to edge across a 1440px screen -- a line that long is
  // unreadable, and it was the one thing that made this screen look
  // nothing like the journal in Omvision. Measured in characters off the
  // live font, so a change of font size or scale moves the column with it.
  readonly property int writingColumns: 70
  readonly property real writingWidth: writingMetrics.advanceWidth("0") * writingColumns

  FontMetrics {
    id: writingMetrics
    font.family: Style.font.family
    font.pointSize: overlay.writingPointSize
  }

  // The overlay's three tiers of text (see the block view below), each
  // set in one place.
  component Caption: Text {
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 2
  }
  component Subtitle: Text {
    color: Color.muted
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
  }
  component Heading: Text {
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.display
    font.bold: true
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background
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

  // Window shortcuts rather than each field's Keys handlers: the break's
  // countdown screen has no focused item to hang a handler on, and on the
  // notes page Escape would have to be on all six fields. A TextEdit never
  // claims Escape for itself, so it reaches this from inside the notes too.
  // Ctrl+G is the countdown's alone: the notes page is for writing, and
  // the goal has no place on it.
  Shortcut {
    sequences: ["Ctrl+G"]
    enabled: overlay.engine.phase === "break" && !overlay.engine.notesOpen
    // A no-op with nothing to pick: no focusable goal, and no active goal
    // for "No goal" to drop.
    onActivated: if (overlay.engine.canPickGoal) overlay.goalPickerOpen = !overlay.goalPickerOpen
  }

  // The picker first, since it sits on top of whichever view opened it.
  Shortcut {
    sequences: ["Escape"]
    enabled: overlay.goalPickerOpen || overlay.engine.notesOpen
    onActivated: {
      if (overlay.goalPickerOpen) overlay.goalPickerOpen = false
      else overlay.engine.closeNotes()
    }
  }

  // Demo only: the overlay takes exclusive keyboard focus and covers the
  // screen, so the demo needs an exit that works from every screen.
  // Application-wide so it works whichever field has focus. The label
  // says it is a demo, so it is never mistaken for a real break.
  Shortcut {
    sequences: ["Ctrl+Q"]
    context: Qt.ApplicationShortcut
    enabled: overlay.engine.demo
    onActivated: if (overlay.engine.demo) Qt.quit()
  }

  Caption {
    visible: overlay.engine.demo
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(24)
    z: 10
    text: "DEMO  ·  Ctrl+Q quits"
    color: Util.alpha(Color.popups.text, 0.6)
  }

  // --- block view: prompt / break / bedtime / sleep ---
  // Three tiers, and they have to read as three: a quiet uppercase label
  // for which mode you are in, the state you are in at heading weight, and
  // the countdown as the one large thing on the screen.
  Column {
    anchors.centerIn: parent
    visible: !overlay.engine.notesOpen
    spacing: Style.space(14)

    Caption {
      anchors.horizontalCenter: parent.horizontalCenter
      text: (overlay.engine.atNight ? "Bedtime" : overlay.engine.mode === "long" ? "Long Focus" : "Normal").toUpperCase()
    }

    Heading {
      anchors.horizontalCenter: parent.horizontalCenter
      text: overlay.engine.phase === "bedtime" ? "Time to sleep"
        : overlay.engine.phase === "sleep" ? "Good night"
        : overlay.engine.phase !== "break" ? "Focus complete"
        : overlay.engine.breakIsLong ? "Long break" : "Break"
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: overlay.engine.hasNotes
      text: overlay.engine.countdownLabel
      color: Color.accent
      font.family: Style.font.family
      // The hero of this screen, and sized like it: no token goes big
      // enough, so it is derived from the largest one rather than typed
      // in as a pixel count that a font-scale change would leave behind.
      font.pixelSize: Math.round(Style.font.displayLarge * 2.2)
    }

    // What the night's countdown counts down to.
    Subtitle {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: overlay.engine.phase === "sleep"
      text: "until " + overlay.engine.wakeLabel
    }

    // The quiet goal line: the selected goal, which the next run starts on
    // (the finished run's own is pinned apart, in Engine.runGoalSlug), and
    // the Ctrl+G hint even before a goal has ever been picked. Absent when
    // Ctrl+G would open nothing (Engine.canPickGoal).
    Subtitle {
      anchors.horizontalCenter: parent.horizontalCenter
      visible: overlay.engine.phase === "break" && overlay.engine.canPickGoal
      text: (overlay.engine.activeGoalTitle.length > 0 ? "Goal: " + overlay.engine.activeGoalTitle : "No goal set")
            + "  ·  Ctrl+G to change"
    }

    // The one sign that a write was refused -- quiet by design (no dialog),
    // Color.urgent so it still reads as a warning. A journal that couldn't be
    // read has nothing unsaved; the page itself says so.
    Subtitle {
      objectName: "notesNotSaved"
      anchors.horizontalCenter: parent.horizontalCenter
      readonly property bool journalUnsaved: overlay.engine.journalFailed && overlay.engine.journalLoaded
      visible: overlay.engine.notesSaveFailed || journalUnsaved
      text: journalUnsaved ? "Journal not saved" : "Notes not saved"
      color: Color.urgent
    }

    // The buttons are a separate decision from the reading above them, so
    // they get their own gap rather than the stack's rhythm.
    Item {
      width: 1
      height: Style.space(18)
    }

    // One group per screen, each shown as a whole; a Row leaves hidden
    // children out, so the groups need no spacing of their own between
    // them beyond the outer Row's.
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(16)

      Row {
        visible: overlay.engine.phase === "prompt"
        spacing: parent.spacing

        OverlayButton {
          objectName: "extendRunButton"
          visible: overlay.engine.extensionsUsed < overlay.engine.maxExtensions
          label: "+1 minute (" + (overlay.engine.maxExtensions - overlay.engine.extensionsUsed) + " left)"
          onActivated: overlay.engine.addExtension()
        }

        OverlayButton {
          objectName: "startBreakButton"
          primary: true
          label: "Start break"
          onActivated: overlay.engine.startBreak()
        }
      }

      // The same three minutes the focus run gets, and gone at 21:50 with
      // this whole screen.
      Row {
        visible: overlay.engine.phase === "bedtime"
        spacing: parent.spacing

        OverlayButton {
          objectName: "snoozeButton"
          visible: overlay.engine.snoozesUsed < overlay.engine.maxSnoozes
          label: "+1 minute (" + (overlay.engine.maxSnoozes - overlay.engine.snoozesUsed) + " left)"
          onActivated: overlay.engine.snooze()
        }

        OverlayButton {
          objectName: "goodNightButton"
          primary: true
          label: "Good night"
          onActivated: overlay.engine.startSleep()
        }
      }

      Row {
        visible: overlay.engine.phase === "break" && !overlay.engine.notesSaveFailed
        spacing: parent.spacing

        Repeater {
          model: [1, 2, 3]
          OverlayButton {
            required property int modelData
            objectName: "extendBreakButton:" + modelData
            label: "+" + modelData + " min"
            onActivated: overlay.engine.extendBreak(modelData)
          }
        }
      }

      Row {
        visible: overlay.engine.phase === "break" && overlay.engine.notesSaveFailed
        spacing: parent.spacing

        OverlayButton {
          objectName: "tryAgainButton"
          primary: true
          label: "Try again"
          onActivated: overlay.engine.saveNote()
        }

        OverlayButton {
          objectName: "skipButton"
          label: "Skip"
          onActivated: overlay.engine.skipUnsavedNotes()
        }
      }

      OverlayButton {
        objectName: "takeNotesButton"
        // Only once the break has actually started -- the prompt is a
        // "focus just ended, what now" decision point, not a writing
        // moment. The night's one button.
        visible: overlay.engine.hasNotes
        primary: !overlay.engine.notesSaveFailed
        label: "Take notes"
        onActivated: overlay.engine.openNotes()
      }
    }
  }

  // --- the night's notes view: the journal ---
  NightJournal {
    anchors.fill: parent
    visible: overlay.engine.notesOpen && overlay.engine.phase === "sleep"
    engine: overlay.engine
    pointSize: overlay.writingPointSize
    columnWidth: overlay.writingWidth
  }

  // --- notes view: the break's three sections ---
  Item {
    id: notesPage
    anchors.fill: parent
    anchors.margins: Style.space(120)
    // The header sits close to the top edge, and the writing runs as close
    // to the bottom one, so the page gets the screen's height; only the
    // sides keep the wide margin, which is what centres the measure.
    anchors.topMargin: Style.space(32)
    anchors.bottomMargin: Style.space(32)
    visible: overlay.engine.notesOpen && overlay.engine.phase === "break"

    readonly property real headerHeight: notesHeaderColumn.implicitHeight + Style.space(16)
    // In page order: the Repeater's sections as the Column holds them (the
    // Repeater itself is one of its children too).
    readonly property var sections: Array.from(notesColumn.children).filter(function(c) { return c.heading !== undefined })

    // Where the caret goes when the page opens: the first open section's
    // text, or the first heading when every one is folded.
    function focusFirstOpenSection() {
      for (var i = 0; i < sections.length; i++) {
        if (sections[i].open) { sections[i].edit.forceActiveFocus(); return }
      }
      sections[0].heading.forceActiveFocus()
    }

    // The page reads as one markdown file, so the arrows run through it as
    // through one: off the top or bottom line of a heading or a section's
    // text, or past either end of it, the caret goes on to the next line
    // over, keeping its column on Up and Down. A folded section's text is
    // skipped, as an editor skips a folded block. Only plain arrows cross:
    // with Shift, Ctrl or Alt they keep their meaning inside the field,
    // since a selection can't span two fields. Anything that doesn't cross
    // goes on to the field.
    function moveAcross(field, event) {
      event.accepted = false
      var back = event.key === Qt.Key_Up || event.key === Qt.Key_Left
      var vertical = event.key === Qt.Key_Up || event.key === Qt.Key_Down
      if (!back && !vertical && event.key !== Qt.Key_Right) return
      if (event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier)) return

      // At the edge it's heading for: the first or last line for Up and
      // Down, the first or last character for Left and Right.
      var edge = back ? 0 : field.length
      var caret = field.cursorRectangle
      var edgeLine = field.positionToRectangle(edge).y
      if (vertical ? (back ? caret.y > edgeLine : caret.y < edgeLine) : field.cursorPosition !== edge) return

      var lines = []
      for (var i = 0; i < sections.length; i++) {
        lines.push(sections[i].heading)
        if (sections[i].open) lines.push(sections[i].edit)
      }
      var to = lines[lines.indexOf(field) + (back ? -1 : 1)]
      if (!to) return

      // Into the far end of the line before, or the near end of the one
      // after; Up and Down keep the caret's column on that line.
      var pos = back ? to.length : 0
      if (vertical) {
        var line = to.positionToRectangle(pos)
        pos = to.positionAt(caret.x, line.y + line.height / 2)
      }
      event.accepted = true
      to.forceActiveFocus()
      to.cursorPosition = pos
    }

    // Every section opens unfolded at the start of a break, and the caret
    // goes to the first open one whenever the page opens. Within a break
    // the folds stay as they were left, like the text: the notes are one
    // page you come back to, not a form you resubmit.
    Connections {
      target: overlay.engine
      function onPhaseChanged() {
        overlay.goalPickerOpen = false
        if (!overlay.engine.hasNotes) return
        for (var i = 0; i < notesPage.sections.length; i++) notesPage.sections[i].open = true
      }
      function onNotesOpenChanged() {
        if (overlay.engine.notesOpen && overlay.engine.phase === "break") Qt.callLater(notesPage.focusFirstOpenSection)
      }
    }

    Flickable {
      id: noteFlick
      objectName: "notesPage"
      anchors.fill: parent
      clip: true
      contentWidth: width
      // Room under the caret's line, so writing at the end of the page
      // happens just above the bottom edge, not pressed against it. A
      // margin's worth, no more: a third of the page used to be kept free,
      // and the page started scrolling its headings away halfway down the
      // screen, with the bottom third never written on.
      readonly property real bottomRoom: Style.space(32)
      contentHeight: Math.max(height, notesColumn.y + notesColumn.implicitHeight + bottomRoom)

      // TextEdit has no auto-scroll of its own inside a Flickable, so this
      // runs on every caret move, including the one Return causes: the
      // caret is kept below the floating header and above bottomRoom.
      // Mapped through the page, not read off the edit's own y: that is
      // its offset inside its section, the bug that kept Return on the
      // last section from ever scrolling.
      function ensureCursorVisible(field) {
        var caret = field.mapToItem(noteFlick.contentItem, field.cursorRectangle)
        var top = caret.y - notesPage.headerHeight
        var bottom = caret.y + caret.height + bottomRoom
        if (top < noteFlick.contentY) {
          noteFlick.contentY = Math.max(0, top)
        } else if (bottom > noteFlick.contentY + noteFlick.height) {
          noteFlick.contentY = bottom - noteFlick.height
        }
      }

      Column {
        id: notesColumn
        // Centred on the measure, not filling the page -- see
        // overlay.writingWidth.
        x: Math.round((noteFlick.width - width) / 2)
        // A clear gap under the header so the caption reads as a label,
        // not as the first line of the writing.
        y: notesPage.headerHeight + Style.space(32)
        width: Math.min(overlay.writingWidth, noteFlick.width)
        spacing: Style.space(32)

        Repeater {
          // The engine's notes, in the order the log writes them.
          model: overlay.engine.notes

          NoteSection {
            required property var modelData
            objectName: "noteSection:" + modelData.key
            width: notesColumn.width
            title: modelData.title
            text: overlay.engine[modelData.field]
            pointSize: overlay.writingPointSize
            onEdited: function(text) { overlay.engine.setNote(modelData.field, text) }
            onCursorMoved: function(field) { noteFlick.ensureCursorVisible(field) }
            onKeyPressed: function(field, event) { notesPage.moveAcross(field, event) }
          }
        }
      }
    }

    // Floats over the scrollable text instead of reserving its own
    // permanent row, so scrolled-past lines disappear behind it like a
    // normal editor's sticky header. Opaque (matching the overlay's own
    // background) rather than translucent so scrolled text doesn't show
    // through illegibly.
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      height: notesPage.headerHeight
      color: Color.background
      z: 2

      Column {
        id: notesHeaderColumn
        anchors.left: parent.left
        // Starts at the writing column's own left edge rather than the
        // page's, so the header reads as belonging to the text under it.
        anchors.leftMargin: Math.max(0, Math.round((parent.width - notesColumn.width) / 2))
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(4)

        // Kept light -- small, regular weight, slim button -- so the header
        // reads as chrome and the section headings below stay the focus.
        Row {
          spacing: Style.space(12)

          OverlayButton {
            objectName: "notesBackButton"
            // Icon-only, deliberately minimal: a label would compete with
            // the caption right next to it for attention.
            label: "←"
            implicitHeight: Style.space(22)
            implicitWidth: Style.space(28)
            onActivated: overlay.engine.closeNotes()
          }

          Caption {
            anchors.verticalCenter: parent.verticalCenter
            // A caption, same tier as the block view's mode label, but at
            // partial text alpha rather than Color.muted, which on light
            // themes is too close to the background to read. The
            // countdown is here too: the break ends, and the notes are
            // logged, whether or not this page is open.
            text: "BREAK NOTES  ·  " + overlay.engine.countdownLabel
            color: Util.alpha(Color.popups.text, 0.6)
          }
        }

        Subtitle {
          visible: overlay.engine.notesSaveFailed
          text: "Notes not saved — Esc, then Try again"
          color: Color.urgent
        }
      }
    }
  }

  // --- goal picker: Ctrl+G on the break's countdown ---
  // Opaque backdrop, same reasoning as the floating header: it fully
  // occludes what's underneath rather than showing through it, and takes
  // every click that misses a button. Escape and Ctrl+G close it. Inside,
  // the block view's idiom: centred column, caption, display heading, a
  // row of OverlayButtons.
  Rectangle {
    objectName: "goalPicker"
    anchors.fill: parent
    visible: overlay.goalPickerOpen
    color: Color.background
    z: 3

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(20)

      Caption {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "NEXT RUN"
      }

      Heading {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Pick a goal"
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)

        Repeater {
          model: overlay.engine.pickableGoals
          OverlayButton {
            required property var modelData
            objectName: "pickGoal:" + modelData.slug
            primary: modelData.slug === overlay.engine.activeGoalSlug
            label: modelData.title || modelData.slug || ""
            onActivated: {
              overlay.engine.chooseGoal(modelData.slug)
              overlay.goalPickerOpen = false
            }
          }
        }

        // Otherwise a goal once picked could only be swapped, never
        // dropped, short of opening Omvision.
        OverlayButton {
          objectName: "noGoalButton"
          visible: overlay.engine.activeGoalSlug.length > 0
          label: "No goal"
          onActivated: {
            overlay.engine.chooseGoal("")
            overlay.goalPickerOpen = false
          }
        }
      }
    }
  }
}
