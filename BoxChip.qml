import QtQuick

// One of a set of boxed choices, as the Add event dialog's kinds and goals
// are: a small control's height, a hairline box, and the chosen one filled
// and outlined in the accent. Sized to its label.
//
// Like CheckOption, it doesn't choose itself: it says it was clicked, and
// the dialog changes what is selected.
Rectangle {
  id: chip

  property string label: ""
  property bool selected: false
  signal clicked()

  implicitHeight: Theme.smallControlHeight
  implicitWidth: chipLabel.implicitWidth + Theme.spaceLg
  color: chip.selected ? Theme.accentFill : "transparent"
  border.color: chip.selected ? Theme.accentColor : Theme.hairline
  border.width: Theme.borderWidth

  Text {
    id: chipLabel
    anchors.centerIn: parent
    text: chip.label
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySmallSize
    color: chip.selected ? Theme.accentColor : Theme.dim
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}
