import QtQuick
import QtQuick.Layouts

// A dialog's yes/no option: the box, its label in the dialogs' small dim
// type, and the whole row as the click target. It doesn't flip `checked`
// itself, which would break the caller's binding to it: it says it was
// clicked, and the dialog changes its own state.
Item {
  id: option

  property bool checked: false
  property string label: ""
  signal toggled()

  implicitHeight: Theme.smallControlHeight

  RowLayout {
    anchors.fill: parent
    spacing: Theme.spaceSm

    OptionMark { checked: option.checked }

    Text {
      Layout.fillWidth: true
      elide: Text.ElideRight
      text: option.label
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.dim
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: option.toggled()
  }
}
