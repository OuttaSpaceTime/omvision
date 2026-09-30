import QtQuick

// The journal's `@` goal list (see JournalScreen's "`@` goal tags" section
// for what it is for and how it opens and closes).
//
// Hangs under the `@` it belongs to, left edge on the `@`, like any editor's
// completion list; flips above the line when there is no room below, and is
// pulled back inside its parent at the right. The screen puts it over the
// canvas rather than in it, so the canvas's clip cannot cut it off, and below
// the day list, which closes it anyway.
//
// It only draws and reports. Which rows match, which one is highlighted, and
// what accepting one writes are the screen's: this moves the highlight on
// hover (`highlight`) and asks for a row to be accepted on a click (`accept`).
//
// API:
//   textEdit, scroller -- the journal's TextEdit and the Flickable it
//                      scrolls in: the `@`'s position is read from the one and moved
//                      by the other's scroll
//   mentionStart    -- index of the `@` in the editor's text, -1 while the
//                      list is closed (the screen still decides `visible`).
//                      Open-ness is read from it rather than passed on its
//                      own: two separately bound properties update one at a
//                      time, and anchorRect saw `open` before the index and
//                      asked the editor for position -1.
//   matches         -- the goals to list, [{slug, title, status}]
//   currentIndex    -- the highlighted row
//   query           -- what follows the `@`, for the "no match" line
//   goalCount       -- how many goals exist at all, for "No goals yet"
//   bottomInset     -- how much of the parent's bottom edge is taken (the
//                      word count's patch), which the list must not cover
//   highlight(index), accept(index)
Rectangle {
  id: mentionPopup

  property Item textEdit: null
  property Item scroller: null
  property int mentionStart: -1
  property var matches: []
  property int currentIndex: 0
  property string query: ""
  property int goalCount: 0
  property real bottomInset: 0
  signal highlight(int index)
  signal accept(int index)

  readonly property int rowHeight: Theme.bodySize + Theme.spaceSm * 2 + Theme.spaceXxs
  readonly property int maxRows: 6
  // Rebinds on scroll and on reflow (cursorRectangle moves with both the
  // text and the width), which positionToRectangle() alone would not.
  readonly property rect anchorRect: {
    var e = mentionPopup.textEdit, s = mentionPopup.scroller
    if (!e || !s) return Qt.rect(0, 0, 0, 0)
    var dep = e.cursorRectangle
    var r = mentionPopup.mentionStart >= 0 ? e.positionToRectangle(mentionPopup.mentionStart) : Qt.rect(0, 0, 0, 0)
    return Qt.rect(e.x + r.x - s.contentX, e.y + r.y - s.contentY, r.width, r.height)
  }
  readonly property bool fitsBelow: anchorRect.y + anchorRect.height + Theme.spaceXs + height
                                    <= parent.height - mentionPopup.bottomInset

  width: Math.min(Math.round(Theme.pageMeasure / 2), parent.width - Theme.spaceLg * 2)
  height: (mentionPopup.matches.length > 0
           ? Math.min(mentionPopup.matches.length, maxRows) * rowHeight
           : emptyText.implicitHeight + Theme.spaceSm * 2) + Theme.borderWidth * 2
  // The rows' text starts on the `@` itself.
  x: Math.max(Theme.spaceLg, Math.min(anchorRect.x - Theme.spaceMd - Theme.borderWidth,
                                      parent.width - width - Theme.spaceLg))
  y: fitsBelow ? anchorRect.y + anchorRect.height + Theme.spaceXs
               : anchorRect.y - height - Theme.spaceXs
  color: Theme.paper
  border.color: Theme.border
  border.width: Theme.borderWidth

  Text {
    id: emptyText
    visible: mentionPopup.matches.length === 0
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Theme.spaceMd
    anchors.rightMargin: Theme.spaceMd
    elide: Text.ElideRight
    text: mentionPopup.goalCount === 0 ? "No goals yet" : "No goal matches “" + mentionPopup.query + "”"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.captionSize
    color: Theme.faint
  }

  ListView {
    id: mentionList
    anchors.fill: parent
    anchors.margins: Theme.borderWidth
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    model: mentionPopup.matches
    currentIndex: mentionPopup.currentIndex
    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

    delegate: Rectangle {
      id: mentionRow
      required property var modelData
      required property int index
      readonly property bool current: index === mentionPopup.currentIndex

      width: mentionList.width
      height: mentionPopup.rowHeight
      color: current ? Theme.hoverFill : "transparent"

      Rectangle {
        visible: mentionRow.current
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Theme.selectionBarWidth
        color: Theme.accentColor
      }

      // One line: the title, and a closed goal's status on the right. The
      // `@slug` used to sit under the title, but the tag is drawn as the
      // title anyway, so the slug only added noise to the list.
      Text {
        id: mentionTitle
        anchors.left: parent.left
        anchors.right: statusText.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.spaceMd
        anchors.rightMargin: statusText.text === "" ? 0 : Theme.spaceSm
        text: mentionRow.modelData.title
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: mentionRow.modelData.status === "active" ? Theme.ink : Theme.dim
      }
      Text {
        id: statusText
        anchors.right: parent.right
        anchors.baseline: mentionTitle.baseline
        anchors.rightMargin: Theme.spaceMd
        text: mentionRow.modelData.status === "active" ? "" : mentionRow.modelData.status
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.faint
      }

      // Hover moves the highlight rather than drawing a second one, the
      // way a menu does. It never takes focus, so the cursor stays in the
      // text and typing goes on filtering.
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: mentionPopup.highlight(mentionRow.index)
        onClicked: mentionPopup.accept(mentionRow.index)
      }
    }
  }
}
