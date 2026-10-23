import QtQuick

// A controlHeight-tall, 1px-border control used for the header and dialog
// actions, its label padded half a spaceXl each side. `filled` is the
// screen's one primary action, in the accent; `danger` an action that
// destroys something (Cancel goal's `End goal`), outlined and labelled in red.
Rectangle {
  id: root

  property string label: ""
  property bool filled: false
  property bool danger: false
  signal activated()

  readonly property bool hovered: area.containsMouse

  implicitHeight: Theme.controlHeight
  implicitWidth: labelText.implicitWidth + Theme.spaceXl
  color: filled ? Theme.accentColor : (hovered ? Theme.hoverFill : "transparent")
  border.color: filled ? Theme.accentColor : (danger ? Theme.red : Theme.border)
  border.width: Theme.borderWidth
  radius: Theme.radius

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    font.bold: root.danger
    color: root.filled ? Theme.paper : (root.danger ? Theme.red : Theme.ink)
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
