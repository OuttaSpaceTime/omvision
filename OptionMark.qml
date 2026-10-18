import QtQuick

// The mark in front of a dialog option, with the accent dot inside when it's
// on: a square box for a yes/no option (CheckOption.qml), a ring with
// `round` for one of a set (CancelDialog's reasons). One drawing, so the
// dialogs' options can't drift apart in size or weight.
Rectangle {
  id: mark

  property bool checked: false
  property bool round: false

  implicitWidth: Theme.optionMarkSize
  implicitHeight: Theme.optionMarkSize
  // A ring: a radius of half the width. Qt caps a radius at half the
  // shorter side, so this is what a larger number would draw too.
  radius: round ? width / 2 : 0
  border.color: Theme.border
  border.width: Theme.borderWidth
  color: "transparent"

  Rectangle {
    visible: mark.checked
    anchors.centerIn: parent
    width: Theme.optionDotSize
    height: Theme.optionDotSize
    radius: mark.round ? width / 2 : 0
    color: Theme.accentColor
  }
}
