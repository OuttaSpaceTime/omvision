import QtQuick

// The edit affordance, wherever it appears: Font Awesome's pencil (U+F040,
// from the Nerd Font the sidebar's icons come from), at its own diagonal.
// Turned upright it read as strange, so it stays as drawn.
//
// A square button of its own, drawn the way Button.qml is (1px border at
// 40% foreground, 8% fill under the pointer, ink label) and as tall as one,
// so it reads as something to click. A bare dim glyph didn't: on a Goals row
// the whole row already shows a hand cursor for "open goal", so the cursor
// said nothing about the pencil. Callers reserve its full width, so
// showing it on hover shifts nothing.
//
// `small` is the task rows' size: the smallControlHeight of the `+ task`
// button above them. At full size it towered over a one-line task, nearly
// as tall as the row between its rules.
Rectangle {
  id: root

  signal clicked()
  property bool small: false

  implicitWidth: root.small ? Theme.smallControlHeight : Theme.controlHeight
  implicitHeight: implicitWidth
  color: area.containsMouse ? Theme.hoverFill : "transparent"
  border.color: Theme.border
  border.width: Theme.borderWidth
  radius: Theme.radius

  Text {
    anchors.centerIn: parent
    text: ""
    font.family: Theme.fontFamily
    font.pixelSize: root.small ? Theme.captionSize : Theme.subtitleSize
    color: Theme.ink
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
