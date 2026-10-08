import QtQuick
import qs.Commons

// Mirrors Omvision's Button.qml so the overlay and the app read as one tool:
// square corners, a 1px border at 40% foreground, transparent until hovered
// (8% foreground), 28px tall with 12px of padding each side. `primary` is
// Omvision's `filled`: accent fill and border, background-coloured label.
Rectangle {
  id: root
  property string label: ""
  property bool primary: false
  property bool hovered: false
  signal activated()

  implicitWidth: btnLabel.implicitWidth + Style.space(24)
  implicitHeight: Style.space(28)
  radius: 0
  color: root.primary ? Color.accent
       : (root.hovered ? Util.alpha(Color.popups.text, 0.08) : "transparent")
  border.color: root.primary ? Color.accent : Util.alpha(Color.popups.text, 0.40)
  border.width: Style.space(1)

  Text {
    id: btnLabel
    anchors.centerIn: parent
    text: root.label
    color: root.primary ? Color.background : Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hovered = true
    onExited: root.hovered = false
    onClicked: root.activated()
  }
}
