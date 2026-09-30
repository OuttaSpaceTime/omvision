import QtQuick
import QtQuick.Layouts

// One task on the goal detail's rail: a hairline above it (but on the
// first), then the row -- checkbox, text, `≈N` estimate, the pencil -- and,
// while its edit is open, the inline edit field in place of the text, with
// the save error under the row.
//
// It owns no state and writes nothing. The screen (GoalDetailScreen) keeps
// which task is open and what its field says, passes that in, and does
// what the signals ask; it also hit-tests the open field for its
// click-away catcher, which is why the row hands the field over when it
// shows (editFieldShown).
Column {
  id: root

  // The task, as Parser.parseTasks returns it: { done, text, estimate }.
  property var task: ({})
  // Its index in the goal's task list: what the objectNames carry, and
  // whether the rule above the row is drawn.
  property int taskIndex: 0
  // Whether this task's edit field is open, what the field starts with, and
  // the error its last save left, if any.
  property bool editing: false
  property string editText: ""
  property string editError: ""

  signal toggleRequested()
  signal editRequested()
  // The field's text, as the user types it.
  signal editTextEdited(string text)
  signal commitRequested()
  signal cancelRequested()
  signal editFieldShown(Item field)

  // Full row width, same edges the row content below sits
  // inside -- every rule starts and ends at the same two
  // points now that the checkbox is no longer bled outside
  // this width (layout-rules §2, §3: one left edge, fills
  // bleed only where the scroller itself is the wide thing,
  // which this rail is not).
  Rectangle {
    width: parent.width
    height: Theme.hairlineWidth
    color: Theme.hairline
    visible: root.taskIndex > 0
  }

  // The checkbox is the row's leading element and owns the
  // rail's left edge -- the same edge the TASKS heading
  // sits at -- with the label inset a consistent gap to its
  // right. Row height floors at the control-height token but
  // grows for a task long enough to wrap (no more eliding --
  // the row still centres the checkbox and estimate against
  // whatever height that takes). The hit target covers the
  // whole row, not just the checkbox, so ticking a task is
  // easy; the toggle MouseArea sits *behind* the RowLayout
  // (declared first) so the edit control and the inline edit
  // field, both on top, get first claim on their own clicks
  // and everything else falls through to the toggle.
  Item {
    id: taskRow
    objectName: "taskRow:" + root.taskIndex
    width: parent.width
    implicitHeight: taskRowLayout.implicitHeight + pad * 2
    height: implicitHeight

    readonly property bool editing: root.editing
    // One line of task text. The side items (checkbox,
    // estimate, pencil) sit in boxes this tall, top-aligned,
    // so on a wrapped task they line up with the first line
    // rather than floating mid-block. `pad` keeps a one-line
    // row at the control height, and a wrapped one off its
    // hairlines.
    readonly property int lineH: Math.ceil(taskFont.height)
    readonly property int pad: Math.max(Theme.spaceXs, Math.floor((Theme.controlHeight - lineH) / 2))

    FontMetrics {
      id: taskFont
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
    }

    // Passive, so it stays hovered while the pointer is over
    // the pencil's own MouseArea too.
    HoverHandler { id: taskRowHover }

    MouseArea {
      anchors.fill: parent
      enabled: !taskRow.editing
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleRequested()
    }

    RowLayout {
      id: taskRowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: taskRow.pad
      spacing: Theme.spaceSm

      Item {
        Layout.preferredWidth: Theme.checkboxSize
        Layout.preferredHeight: taskRow.lineH
        Layout.alignment: Qt.AlignTop

        Rectangle {
          anchors.centerIn: parent
          width: Theme.checkboxSize
          height: Theme.checkboxSize
          border.color: Theme.border
          border.width: Theme.borderWidth
          color: "transparent"

          Text {
            visible: root.task.done
            anchors.centerIn: parent
            text: "✓"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.checkMarkSize
            color: Theme.accentColor
          }
        }
      }

      Text {
        visible: !taskRow.editing
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        wrapMode: Text.WordWrap
        text: root.task.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        font.strikeout: root.task.done
        color: root.task.done ? Theme.faint : Theme.ink
      }

      // Inline edit field, same minimal-input pattern as
      // "+ task" (Enter commits, Escape cancels) rather than
      // a dialog -- editing one task's wording is a small
      // secondary action, not one that deserves a modal.
      // A TextEdit so a long task wraps while being edited
      // exactly as it does when shown; Enter is taken by the
      // key handlers, so it never inserts a newline.
      TextEdit {
        id: taskEditInput
        objectName: "taskEditField:" + root.taskIndex
        visible: taskRow.editing
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        wrapMode: TextEdit.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.ink
        selectionColor: Theme.accentFill
        selectedTextColor: Theme.ink
        selectByMouse: true

        // Cursor at the end, nothing selected: an edit is
        // usually a tweak, and a select-all would make the
        // first keystroke wipe the whole task.
        onVisibleChanged: if (visible) {
          text = root.editText
          cursorPosition = length
          forceActiveFocus()
          root.editFieldShown(taskEditInput)
        }
        onTextChanged: if (visible) root.editTextEdited(text)
        Keys.onReturnPressed: root.commitRequested()
        Keys.onEnterPressed: root.commitRequested()
        Keys.onEscapePressed: root.cancelRequested()

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.bottom
          height: Theme.hairlineWidth
          color: Theme.accentColor
        }
      }

      Item {
        visible: root.task.estimate !== undefined && !taskRow.editing
        Layout.preferredWidth: taskEstimate.implicitWidth
        Layout.preferredHeight: taskRow.lineH
        Layout.alignment: Qt.AlignTop

        Text {
          id: taskEstimate
          anchors.verticalCenter: parent.verticalCenter
          text: root.task.estimate !== undefined ? ("≈" + root.task.estimate) : ""
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySmallSize
          color: Theme.dim
        }
      }

      // A pencil, shown only while the pointer is over the
      // row. Faded with opacity rather than toggled with
      // `visible`, so its slot is always reserved: hovering
      // must never re-wrap the task text or grow the row.
      // Centred on the whole row, unlike the checkbox: it
      // belongs to the row, not to the first line of text.
      Item {
        Layout.preferredWidth: taskPencil.implicitWidth
        Layout.fillHeight: true
        opacity: taskRowHover.hovered && !taskRow.editing ? 1 : 0
        enabled: opacity > 0

        PencilIcon {
          id: taskPencil
          objectName: "taskEdit:" + root.taskIndex
          small: true
          anchors.centerIn: parent
          onClicked: root.editRequested()
        }
      }
    }
  }

  Text {
    visible: taskRow.editing && root.editError.length > 0
    width: parent.width
    wrapMode: Text.WordWrap
    text: root.editError
    font.family: Theme.fontFamily
    font.pixelSize: Theme.captionSize
    color: Theme.red
  }
}
