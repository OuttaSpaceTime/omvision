import QtQuick

// 28px, 1px-border control used for the header actions. `inert: true`
// (the default — every button in M2 except the timeline "copy" control is
// inert per spec) suppresses the click signal entirely: present and styled,
// does nothing.
Rectangle {
  id: root

  property string label: ""
  property bool filled: false
  property bool inert: true
  signal activated()

  implicitHeight: Theme.controlHeight
  implicitWidth: labelText.implicitWidth + 24
  color: filled ? Theme.accentColor : (hovered ? Theme.hoverFill : "transparent")
  border.color: filled ? Theme.accentColor : Theme.border
  border.width: Theme.borderWidth
  radius: Theme.radius

  property bool hovered: false

  Text {
    id: labelText
    anchors.centerIn: parent
    text: root.label
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    color: root.filled ? root.paperOnAccent() : Theme.ink
  }

  function paperOnAccent() { return Theme.paper }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered = true
    onExited: root.hovered = false
    onClicked: { if (!root.inert) root.activated() }
  }
}
