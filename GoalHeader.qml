import QtQuick
import QtQuick.Layouts

// The goal detail's header: the title with its edit pencil, the `Add
// event` and `Coach this goal` buttons, and under them a band holding the
// back link and the `running` chip.
//
// The title and the buttons own the first row and never move. The back
// link and the "running" chip can't always fit alongside a long title
// and two buttons, so they get a row of their own, banded by hairlines
// the way GoalsScreen's filter row is -- degrading by design instead of
// clipping off the right edge (layout-rules §1, §7).
ColumnLayout {
  id: root

  property string title: ""
  // Whether the pencil is offered: only once the goal's file has been read.
  property bool editable: false
  // The back link's text: `← Goals`, or `← Journal` (see GoalDetailScreen).
  property string backLabel: "← Goals"
  // The goal is the one being worked on (status: active).
  property bool running: false

  signal back()
  signal editGoalRequested()
  signal addEventRequested()
  signal coachRequested()

  spacing: 0

  RowLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceMd

    // The title and its edit pencil (the Goals rows' pencil, same
    // dialog). The group is sized to the title, capped by maximumWidth so
    // a long title still elides, rather than filling the row: the pencil
    // belongs right after the words, not over by the buttons. The hover
    // covers title and pencil together, so crossing the gap between them
    // doesn't flicker it off.
    RowLayout {
      id: titleGroup
      Layout.fillWidth: true
      Layout.maximumWidth: implicitWidth
      spacing: Theme.spaceSm

      HoverHandler { id: titleHover }

      Text {
        Layout.fillWidth: true
        text: root.title
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headingSize
        font.bold: true
        color: Theme.ink
      }

      // Faded with opacity, not toggled with `visible`, so its slot is
      // always reserved and hovering never re-elides the title.
      PencilIcon {
        objectName: "editGoalButton"
        opacity: titleHover.hovered && root.editable ? 1 : 0
        enabled: opacity > 0
        onClicked: root.editGoalRequested()
      }
    }

    Item { Layout.fillWidth: true }

    Button { objectName: "addEventButton"; label: "Add event"; inert: false; onActivated: root.addEventRequested() }
    Button { objectName: "coachButton"; label: "Coach this goal"; filled: true; inert: false; onActivated: root.coachRequested() }
  }

  Item { Layout.preferredHeight: Theme.spaceLg; Layout.fillWidth: true }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: subHeaderRow.implicitHeight + Theme.spaceXl
    color: "transparent"

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: Theme.hairlineWidth
      color: Theme.hairline
    }

    RowLayout {
      id: subHeaderRow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spaceMd

      // A real control, not a bare Text + MouseArea: sized
      // deterministically (a full control's height as its hit target)
      // so the click always lands, with a hover fill so it reads as a
      // control rather than as receding dim text.
      Rectangle {
        id: backControl
        objectName: "backControl"
        // Its label sits on the column's left edge and the hover fill
        // spills into the margin, not the other way round (layout-rules
        // §2, §3).
        Layout.leftMargin: -Math.round((implicitWidth - backText.implicitWidth) / 2)
        implicitWidth: backText.implicitWidth + Theme.spaceMd
        implicitHeight: Theme.controlHeight
        color: backArea.containsMouse ? Theme.hoverFill : "transparent"

        Text {
          id: backText
          anchors.centerIn: parent
          text: root.backLabel
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.dim
        }

        MouseArea {
          id: backArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.back()
        }
      }

      Text {
        visible: root.running
        text: "running"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        font.bold: true
        color: Theme.accentColor
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Theme.hairlineWidth
      color: Theme.hairline
    }
  }
}
