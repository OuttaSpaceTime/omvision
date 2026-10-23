import QtQuick
import QtQuick.Layouts

// A dialog's one-line text field: its label above a filled, bordered input
// a control high. The New goal and Add event dialogs had seven copies of
// it, each twenty lines.
//
// It doesn't write `text` itself, which would break the dialog's binding
// to it (and with it the reset each time the dialog opens): it says what
// was typed (`edited`, for typing only, not for the dialog's own resets),
// and the dialog changes its own state, the way CheckOption does. Return and
// Enter are `accepted`, the dialog's submit.
//
// It fills its row unless given a `fieldWidth`, for a short value (`How
// long`, `Estimate`) held at that width beside a field that fills.
ColumnLayout {
  id: field

  property string label: ""
  property string text: ""
  property int fieldWidth: 0
  // The input's objectName, for the tests' click() (docs/testing.md).
  property alias inputName: input.objectName
  signal edited(string text)
  signal accepted()

  Layout.fillWidth: field.fieldWidth === 0
  Layout.preferredWidth: field.fieldWidth > 0 ? field.fieldWidth : -1  // check: allow-px -1 is Layout's "no preferred width"

  function focusInput() { input.forceActiveFocus() }

  spacing: Theme.spaceXs

  CaptionLabel { text: field.label }

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Theme.controlHeight
    color: Theme.fill
    border.color: Theme.border
    border.width: Theme.borderWidth

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Theme.spaceSm
      anchors.rightMargin: Theme.spaceSm
      verticalAlignment: TextInput.AlignVCenter
      clip: true
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
      color: Theme.ink
      selectByMouse: true
      text: field.text
      onTextEdited: field.edited(text)
      Keys.onReturnPressed: field.accepted()
      Keys.onEnterPressed: field.accepted()
    }
  }
}
