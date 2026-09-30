import QtQuick
import QtQuick.Controls

// One of the journal's two corner controls (`»` sidebar, `≡` days): a quiet
// square in the top-left corner. Faint, no border, no fill until hovered --
// present enough to find, not loud enough to read as content. The size is
// the app's small control height, the same as `+ task` and `copy`.
Rectangle {
  id: cb
  property string glyph: ""
  property string tip: ""
  signal activated()

  width: Theme.smallControlHeight
  height: Theme.smallControlHeight
  color: cbArea.containsMouse ? Theme.hoverFill : "transparent"

  Text {
    anchors.centerIn: parent
    text: cb.glyph
    font.family: Theme.fontFamily
    font.pixelSize: Theme.subtitleSize
    color: cbArea.containsMouse ? Theme.dim : Theme.faint
  }

  MouseArea {
    id: cbArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: cb.activated()
  }

  ToolTip.visible: cbArea.containsMouse
  ToolTip.delay: 400
  ToolTip.text: cb.tip
}
