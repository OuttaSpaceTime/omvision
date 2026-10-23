import QtQuick

// One of a row of text-only choices: the Goals screen's status filters and
// the Coaching screen's goal and method. The chosen one is in the accent and
// underlined, the rest dim. Its clicks reach chipHitSlop past the text, so
// the gaps in a row of short words still land on one. Body size unless the
// row sets its own (the Goals filters are captions).
//
// Like CheckOption, it doesn't choose itself: it says it was clicked, and
// the screen changes what is selected.
Text {
  id: chip

  property string label: ""
  property bool selected: false
  signal clicked()

  text: chip.label
  font.family: Theme.fontFamily
  font.pixelSize: Theme.bodySize
  color: chip.selected ? Theme.accentColor : Theme.dim
  font.underline: chip.selected

  MouseArea {
    anchors.fill: parent
    anchors.margins: -Theme.chipHitSlop
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}
