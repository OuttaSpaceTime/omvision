import QtQuick
import QtQuick.Layouts

// The foot of the goal detail's rail: how the goal ends, or how it ended.
// While it is open, `Close goal · done` and a red `Cancel`; on a done goal,
// `Reopen goal`; on a cancelled one, the reason and takeaway it was
// cancelled with. Each block sits under a hairline. It writes nothing: the
// signals go to GoalDetailScreen, which re-reads the file and writes it.
ColumnLayout {
  id: root

  // The goal's parsed meta (Parser.parseGoalFile), or null before its file
  // has been read.
  property var meta: null
  readonly property bool isOpen: !!meta && meta.status !== "done" && meta.status !== "cancelled"
  readonly property bool isDone: !!meta && meta.status === "done"
  readonly property bool hasCancelNote: !!meta && meta.status === "cancelled" && !!meta.cancelled
  // The close row's natural width, whether or not it is showing: the rail
  // is never made narrower than this row, which can't elide.
  readonly property real closeRowWidth: closeRow.implicitWidth

  signal closeGoal()
  signal reopenGoal()
  signal cancelRequested()

  // Out of the rail's layout altogether when there is nothing to show, so
  // it adds no spacing there either.
  visible: isOpen || isDone || hasCancelNote
  spacing: 0

  // Close / cancel. Only offered while the goal is still open --
  // a done or cancelled goal has nothing left to close or cancel.
  ColumnLayout {
    Layout.fillWidth: true
    visible: root.isOpen
    spacing: Theme.spaceSm

    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }

    RowLayout {
      id: closeRow
      Layout.fillWidth: true
      spacing: Theme.spaceSm
      Button {
        objectName: "closeGoalButton"
        label: "Close goal · done"
        inert: false
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: Theme.controlHeight
        onActivated: root.closeGoal()
      }
      Item { Layout.fillWidth: true }
      Text {
        objectName: "cancelGoalButton"
        text: "Cancel"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySmallSize
        color: Theme.red
        MouseArea {
          anchors.fill: parent
          anchors.margins: -Theme.linkHitSlop
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelRequested()
        }
      }
    }
  }

  // A done goal can be taken back up: closing one by mistake, or
  // finding there is more to do, shouldn't mean editing the file by
  // hand. Cancelled goals aren't offered this -- their "## Cancelled"
  // note would stay in the file and a second cancel would append
  // another beside it.
  ColumnLayout {
    Layout.fillWidth: true
    visible: root.isDone
    spacing: Theme.spaceSm

    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }

    Button {
      objectName: "reopenGoalButton"
      label: "Reopen goal"
      inert: false
      Layout.preferredWidth: implicitWidth
      Layout.preferredHeight: Theme.controlHeight
      onActivated: root.reopenGoal()
    }
  }

  // A cancelled goal keeps its reason/takeaway on screen -- it's
  // the one place this otherwise-invisible "## Cancelled" section
  // (Writer.appendCancelNote) is ever shown back to the user.
  ColumnLayout {
    Layout.fillWidth: true
    visible: root.hasCancelNote
    spacing: Theme.spaceXs
    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }
    Text {
      text: "Cancelled"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      font.bold: true
      color: Theme.red
    }
    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      visible: root.hasCancelNote && root.meta.cancelled.reason.length > 0
      text: root.hasCancelNote ? root.meta.cancelled.reason : ""
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.ink
    }
    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      visible: root.hasCancelNote && root.meta.cancelled.takeaway.length > 0
      text: root.hasCancelNote ? root.meta.cancelled.takeaway : ""
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.dim
    }
  }
}
