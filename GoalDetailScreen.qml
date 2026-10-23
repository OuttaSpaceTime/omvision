pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// Spec §Screen: Goal detail.
Item {
  id: root

  // How far this screen's left edge sits from the window's; see Theme.pageX.
  property int leftInset: 0

  required property App app

  // The open goal. Every change to it goes through app.notes, which re-reads
  // <slug>.md immediately before applying it (goal-files.md's "re-read right
  // before writing, never from a copy taken when the screen was opened"
  // rule), which this screen has no way to honour on its own since it only
  // ever sees what the store last loaded.
  readonly property string slug: root.app.nav.goalSlug
  readonly property var goal: root.app.notes.goalsData[root.slug] || null
  readonly property var meta: root.goal ? root.goal.meta : null
  readonly property var logEntries: root.goal ? root.goal.logEntries : []

  function startEditTask(index, text) {
    root.editTaskText = text
    root.editTaskOriginal = text
    root.editTaskError = ""
    root.editingTaskIndex = index
  }
  // Saving an emptied task deletes it (Writer.editTask). Unchanged text
  // just closes the field: clicking away from a task you only looked at
  // shouldn't rewrite the goal file.
  function commitEditTask(index) {
    var text = root.editTaskText.trim()
    if (text === root.editTaskOriginal.trim()) { root.cancelEditTask(); return }
    root.editTaskError = ""
    root.savingTaskIndex = index
    // Only closes the field if it is still the one that was saved: a click
    // on another task's pencil saves this edit and opens that one before
    // the write lands, and the result must not close the new field. A
    // failure then has no field to show in, so it goes to the banner
    // (returning false). Likewise only a save still marked as saving
    // clears the mark: one that lands while a later save is under way
    // would otherwise let the click-away catcher commit that later edit a
    // second time.
    root.app.notes.editTask(root.slug, index, text, function(ok, why) {
      if (root.savingTaskIndex === index) root.savingTaskIndex = -1
      if (root.editingTaskIndex !== index) return false
      if (ok) { root.editingTaskIndex = -1; root.editTaskText = "" }
      else root.editTaskError = why
    })
  }
  function cancelEditTask() {
    root.editingTaskIndex = -1
    root.editTaskText = ""
    root.editTaskError = ""
  }

  function commitAddTask() {
    var text = root.addTaskText.trim()
    if (text === "") { root.addingTask = false; return } // empty input is a no-op
    root.addTaskError = ""
    // Kept in the field on a failed write, not cleared optimistically.
    root.app.notes.addTask(root.slug, text, function(ok, why) {
      if (ok) root.cancelAddTask()
      else root.addTaskError = why
    })
  }
  function cancelAddTask() {
    root.addingTask = false
    root.addTaskText = ""
    root.addTaskError = ""
    addTaskInput.text = ""
  }

  property bool addingTask: false
  property string addTaskText: ""
  property string addTaskError: ""
  property int editingTaskIndex: -1
  property string editTaskText: ""
  property string editTaskOriginal: ""
  property string editTaskError: ""
  // The task whose edit is being written, -1 when none is in flight.
  property int savingTaskIndex: -1
  // The open edit field, for the click-away catcher's hit test.
  property Item taskEditField: null

  // Leaving the screen (the sidebar, or the back link) with a task open
  // saves it too, the same as clicking anywhere else on this screen.
  onVisibleChanged: if (!visible && root.editingTaskIndex >= 0 && root.savingTaskIndex < 0)
    root.commitEditTask(root.editingTaskIndex)
  // A field left open by a failed save belongs to that goal's task list,
  // not to the same row of the next goal opened.
  onSlugChanged: root.cancelEditTask()

  readonly property int poms: Parser.pomodoroCount(logEntries)
  readonly property var tasks: meta ? meta.tasks : []
  readonly property int tasksDone: Parser.doneTaskCount(tasks)

  // The screen is put together from GoalHeader, GoalFigures, Timeline,
  // TaskRow and GoalEndActions. None of them keeps state or writes: the
  // state above stays here, where ShotDriver, the tests and the click-away
  // catcher below reach it, and the parts report what the user did through
  // their signals.
  ColumnLayout {
    // The journal's column, on the journal's line (Theme.pageX).
    x: Theme.pageX(root.width, root.leftInset)
    y: Theme.panelPadding
    width: Theme.pageWidth(root.width)
    height: root.height - Theme.panelPadding * 2
    spacing: Theme.sectionGap

    GoalHeader {
      Layout.fillWidth: true
      title: root.meta ? root.meta.title : root.slug
      editable: !!root.meta
      backLabel: root.app.nav.goalBack === "journal" ? "← Journal" : "← Goals"
      running: !!root.meta && root.meta.status === "active"
      onBack: root.app.nav.back()
      onEditGoalRequested: root.app.openDialog("goal", root.slug)
      onAddEventRequested: root.app.openDialog("event", root.slug)
      onCoachRequested: root.app.nav.coach(root.slug)
    }

    GoalFigures {
      Layout.fillWidth: true
      poms: root.poms
      minutes: Parser.investedMinutes(root.logEntries)
      estimate: root.meta ? root.meta.estimate : undefined
      tasksDone: root.tasksDone
      taskCount: root.tasks.length
    }

    // A progress rule used to fill by `poms / estimate`. Dropped: once
    // `estimate:` is read correctly as poms remaining (goal-files.md),
    // that fraction has no honest meaning -- it would need a recorded
    // starting estimate this contract doesn't keep, and a bar that
    // silently reinterprets "poms done" as "poms done out of whatever
    // estimate happens to be right now" would just lie in a different way
    // than the subtraction bug it replaced. Nothing here plots progress
    // until there's a real denominator for it.

    // ---- body: timeline + right rail --------------------------------------
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      Timeline {
        Layout.fillWidth: true
        Layout.fillHeight: true
        logEntries: root.logEntries
      }

      // hairline between timeline and right rail
      Rectangle {
        Layout.preferredWidth: Theme.hairlineWidth
        Layout.fillHeight: true
        color: Theme.hairline
      }

      // Right rail. A share of the column rather than a fixed 312px: at full
      // measure that share is the same ~310px, but at the window's minimum
      // a fixed rail left the timeline -- the screen's actual content --
      // about fifteen characters a line. Task names elide instead. Never
      // narrower than its two rows of controls, though, which can't elide
      // and would otherwise draw past the window edge (layout-rules §7).
      //
      // Off the page column's width, not this layout's: a layout reading
      // its own width to size its children feeds back into itself. And off
      // those two rows' implicit widths rather than the whole rail's, whose
      // wrapped hint text reports its unwrapped, full-sentence width.
      Item {
        Layout.preferredWidth: Math.max(Math.round(Theme.pageWidth(root.width) * 3 / 8),
                                        Math.ceil(Math.max(tasksHeader.implicitWidth, endActions.closeRowWidth))
                                        + Theme.spaceLg * 2)
        Layout.fillHeight: true

        ColumnLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.leftMargin: Theme.spaceLg
          anchors.rightMargin: Theme.spaceLg
          anchors.bottomMargin: Theme.spaceLg
          spacing: Theme.spaceSm

          RowLayout {
            id: tasksHeader
            Layout.fillWidth: true
            spacing: Theme.spaceSm
            CaptionLabel { text: "Tasks" }
            Text {
              text: root.tasksDone + " of " + root.tasks.length + " done"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              color: Theme.faint
            }
            Item { Layout.fillWidth: true }
            Button {
              objectName: "addTaskButton"
              label: "+ task"
              visible: !root.addingTask
              Layout.preferredHeight: Theme.smallControlHeight
              Layout.alignment: Qt.AlignVCenter
              onActivated: { root.addTaskError = ""; root.addingTask = true }
            }
          }

          // Minimal inline input, not a dialog: Enter commits to "## Tasks",
          // Escape cancels. Stays open with whatever was typed if the write
          // fails, so a rejected add is never silently lost (layout-rules
          // §9: this is a small secondary control, not a modal).
          Column {
            Layout.fillWidth: true
            visible: root.addingTask
            spacing: Theme.spaceXs

            Rectangle {
              width: parent.width
              height: Theme.smallControlHeight
              color: "transparent"
              border.color: Theme.border
              border.width: Theme.borderWidth

              TextInput {
                id: addTaskInput
                objectName: "addTaskField"
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceXs
                anchors.rightMargin: Theme.spaceXs
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.ink
                selectByMouse: true

                onVisibleChanged: if (visible) { text = root.addTaskText; forceActiveFocus() }
                onTextChanged: root.addTaskText = text
                Keys.onReturnPressed: root.commitAddTask()
                Keys.onEnterPressed: root.commitAddTask()
                Keys.onEscapePressed: root.cancelAddTask()
              }
            }

            Text {
              visible: root.addTaskError.length > 0
              width: parent.width
              wrapMode: Text.WordWrap
              lineHeight: Theme.proseLineHeight
              text: root.addTaskError
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              color: Theme.red
            }
          }

          Column {
            Layout.fillWidth: true
            Repeater {
              model: root.tasks
              delegate: TaskRow {
                required property var modelData
                required property int index
                width: parent.width
                task: modelData
                taskIndex: index
                editing: root.editingTaskIndex === index
                editText: root.editTaskText
                editError: root.editTaskError
                onToggleRequested: root.app.notes.toggleTask(root.slug, index)
                onEditRequested: root.startEditTask(index, modelData.text)
                onEditTextEdited: function(text) { root.editTaskText = text }
                onCommitRequested: root.commitEditTask(index)
                onCancelRequested: root.cancelEditTask()
                onEditFieldShown: function(field) { root.taskEditField = field }
              }
            }

            Text {
              visible: root.tasks.length === 0
              text: "No tasks yet."
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.faint
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.tasks.length === 0
            wrapMode: Text.WordWrap
            lineHeight: Theme.proseLineHeight
            text: "Tasks belong to the goal, not to a pomodoro. A finished pom never ticks one off — you do, or the coach does."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            color: Theme.faint
          }

          Item { Layout.preferredHeight: Theme.spaceSm }

          // "NEXT SESSION" (the claude /ompom-coach command + copy button)
          // used to live here too. Removed: CoachingScreen already carries
          // that hand-off with its own working copy button, and the same
          // control in two places is two things to keep in step instead
          // of one.

          Item { Layout.fillHeight: true }

          GoalEndActions {
            id: endActions
            Layout.fillWidth: true
            meta: root.meta
            onCloseGoal: root.app.notes.closeGoal(root.slug)
            onReopenGoal: root.app.notes.reopenGoal(root.slug)
            onCancelRequested: root.app.openDialog("cancel", root.slug)
          }
        }
      }
    }
  }

  // Click away to save. While a task is open, a press anywhere on this
  // screen outside its field saves it (Enter's commitEditTask), and the
  // press then carries on to whatever is under it: ticking another task or
  // opening its pencil takes one click, not two. A press in the field
  // itself is passed straight through, so the caret and selection work.
  //
  // One exception: saving an emptied task deletes it, and every task below
  // it moves up an index. Queued behind that delete, a tick or an edit on a
  // lower row would hit the task after the one clicked, so that press is
  // swallowed and only saves.
  //
  // A MouseArea on top that declines the press, not activeFocus: the other
  // rows, the rail and the timeline don't take focus, so clicking them
  // never takes it from the field, and the window losing focus (switching
  // workspace mid-edit) would have saved and closed it.
  MouseArea {
    id: clickAway
    anchors.fill: parent
    enabled: root.editingTaskIndex >= 0 && root.savingTaskIndex < 0
    onPressed: function(mouse) {
      var field = root.taskEditField
      if (field && field.visible
          && field.contains(field.mapFromItem(clickAway, mouse.x, mouse.y))) {
        mouse.accepted = false
        return
      }
      var deleting = root.editTaskText.trim() === ""
      root.commitEditTask(root.editingTaskIndex)
      mouse.accepted = deleting
    }
  }
}
