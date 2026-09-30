import QtQuick

// The journal's list of days: an overlay that slides in from the left edge
// of the journal's area. Collapsed by default and an overlay when open, never
// an in-flow pane: the text column must not shift when you glance at the
// list of days. Same shape the app sidebar takes in writing mode, on the same
// edge -- so opening one closes the other (JournalScreen's corner controls).
//
// It only shows and reports: which day is open, and which one was clicked.
// Opening a day, and closing the list when that happens, is the screen's job.
//
// API:
//   open          -- slid in (true) or out
//   entries       -- JournalScreen.entries: [{path, dateLabel, firstLine}],
//                    newest first
//   selectedPath  -- the open day, marked with the accent bar
//   dayClicked(path)
Rectangle {
  id: dayList

  property bool open: false
  property var entries: []
  property string selectedPath: ""
  signal dayClicked(string path)

  width: Theme.journalDayListWidth
  x: dayList.open ? 0 : -width
  visible: x > -width
  color: Theme.paper
  clip: true

  Behavior on x {
    NumberAnimation { duration: Theme.slideDuration; easing.type: Theme.slideEasing }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Theme.hairlineWidth
    color: Theme.hairline
  }

  Text {
    id: dayListHeading
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.leftMargin: Theme.panelPadding
    anchors.topMargin: Theme.spaceLg
    text: "Days"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.captionSize
    color: Theme.faint
  }

  Flickable {
    id: dayFlick
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: dayListHeading.bottom
    anchors.bottom: parent.bottom
    anchors.topMargin: Theme.spaceMd
    anchors.rightMargin: Theme.spaceXxs
    contentHeight: daysColumn.height
    clip: true

    Column {
      id: daysColumn
      width: dayFlick.width

      Repeater {
        model: dayList.entries
        delegate: Rectangle {
          id: dayRow
          required property var modelData
          required property int index

          readonly property bool isSelected: dayList.selectedPath === modelData.path
          property bool hovered: false

          width: daysColumn.width
          height: Theme.journalDayRowHeight
          color: (isSelected || hovered) ? Theme.fill : "transparent"

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Theme.hairlineWidth
            color: Theme.hairline
            visible: dayRow.index > 0
          }

          Rectangle {
            visible: dayRow.isSelected
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Theme.selectionBarWidth
            color: Theme.accentColor
          }

          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.panelPadding
            anchors.rightMargin: Theme.spaceMd
            spacing: Theme.spaceXxs

            Text {
              width: parent.width
              text: dayRow.modelData.dateLabel
              elide: Text.ElideRight
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              font.bold: true
              color: Theme.ink
            }
            Text {
              width: parent.width
              text: dayRow.modelData.firstLine === "" ? "empty" : dayRow.modelData.firstLine
              elide: Text.ElideRight
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: dayRow.modelData.firstLine === "" ? Theme.faint : Theme.dim
            }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: dayRow.hovered = true
            onExited: dayRow.hovered = false
            onClicked: dayList.dayClicked(dayRow.modelData.path)
          }
        }
      }
    }
  }
}
