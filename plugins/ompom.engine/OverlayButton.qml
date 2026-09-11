import QtQuick
import qs.Commons

Rectangle {
  id: root
  property string label: ""
  property bool primary: false
  signal activated()

  implicitWidth: btnLabel.implicitWidth + Style.space(36)
  implicitHeight: Style.space(44)
  radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(8)
  color: root.primary ? Color.accent : Color.popups.background
  border.color: root.primary ? Color.accent : Color.popups.border
  border.width: Style.space(1)

  Text {
    id: btnLabel
    anchors.centerIn: parent
    text: root.label
    color: root.primary ? Color.background : Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
