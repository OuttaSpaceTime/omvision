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
//   entries       -- JournalScreen.entries: [{path, dateLabel, preview}],
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
    anchors.leftMargin: Theme.rowPadding
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
        // Rows only while the list is on screen. `entries` is a fresh array
        // after every save, and the Repeater rebuilds every row for it --
        // each a wrapped few lines to lay out -- whether or not anyone can
        // see them.
        model: dayList.visible ? dayList.entries : []
        delegate: Rectangle {
          id: dayRow
          required property var modelData
          required property int index

          readonly property bool isSelected: dayList.selectedPath === modelData.path
          readonly property bool isEmpty: modelData.preview === ""
          property bool hovered: false

          // As tall as its text: a day with a line or two of preview
          // shouldn't sit in the box a three-line one needs.
          width: daysColumn.width
          height: dayText.height + Theme.rowGap * 2
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

          // Inset by a list row's padding, not the page's: this panel
          // doesn't bleed (docs/layout-rules.md §3).
          Column {
            id: dayText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.rowPadding
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
            // The font's own leading, not proseLineHeight as a coaching
            // summary has: at 1.4 the list held fewer days, and the leading
            // under the last line left each row's bottom gap wider than its
            // top. This is scanned, not read.
            Text {
              width: parent.width
              text: dayRow.isEmpty ? "empty" : dayRow.modelData.preview
              wrapMode: Text.Wrap
              maximumLineCount: Theme.journalPreviewLines
              elide: Text.ElideRight
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: dayRow.isEmpty ? Theme.faint : Theme.dim
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
