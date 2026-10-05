import QtQuick
import QtQuick.Controls

// One of the journal's header controls (`»` sidebar and `≡` days at the
// left, `‹`/`›` page turns at the right): a quiet square. Faint, no border,
// no fill until hovered -- present enough to find, not loud enough to read
// as content. The size is the app's small control height, the same as
// `+ task` and `copy`.
//
// Disabled (`enabled: false`) is a page turn with no page to turn to: the
// glyph drops to `markup`, the 2:1 colour the journal's own markdown markers
// recede in, and the control stops answering. A click on it lands on the
// header, which takes it (see JournalScreen's stickyHeader).
Rectangle {
  id: cb
  property string glyph: ""
  property string tip: ""
  signal activated()
  // Under the pointer and able to answer it.
  readonly property bool hot: cb.enabled && cbArea.containsMouse

  width: Theme.smallControlHeight
  height: Theme.smallControlHeight
  color: cb.hot ? Theme.hoverFill : "transparent"

  Text {
    anchors.centerIn: parent
    text: cb.glyph
    font.family: Theme.fontFamily
    font.pixelSize: Theme.subtitleSize
    color: !cb.enabled ? Theme.markup : (cb.hot ? Theme.dim : Theme.faint)
  }

  MouseArea {
    id: cbArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: cb.activated()
  }

  ToolTip.visible: cb.hot
  ToolTip.delay: 400
  ToolTip.text: cb.tip
}
