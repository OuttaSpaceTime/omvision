import QtQuick
import QtQuick.Layouts

// The frame every dialog sits in: a true modal over the whole window. The
// three dialogs (New goal, Add event, Cancel goal) each carried their own
// copy of it, forty-odd lines apiece. A dialog puts its header and fields in
// as children, and its buttons in `actions`.
//
// - A FocusScope, so focus goes into the dialog when it opens (`opened` is
//   the dialog's moment to reset and focus its first field) and back to
//   wherever it was when it closes. Esc dismisses.
// - A clear full-window MouseArea under the card, never a scrim: nothing
//   dims the window behind a dialog (the user never wants a darkened
//   background; bin/check's noscrim step). Topmost under the pointer with
//   hoverEnabled, it absorbs every click and hover meant for what is
//   beneath. A stray click there dismisses an additive dialog; a
//   destructive one (Cancel goal) sets `dismissOnOutsideClick: false`, so
//   closing it always takes Back or Esc.
// - A card sized to its content, not a fixed height: an unsized Rectangle
//   once rendered as a zero-height box, and the dialog drew straight over
//   the screen with no card behind it.
// - Under the content, `error` in red when there is one, a hairline, and
//   the footer: `hint` in faint caption on the left, the actions on the
//   right.
FocusScope {
  id: frame

  property bool dismissOnOutsideClick: true
  property string error: ""
  property string hint: ""
  default property alias body: body.data
  property alias actions: actionRow.data
  signal opened()
  signal dismissed()

  property var previousFocusItem: null

  onVisibleChanged: {
    if (!visible) {
      if (frame.previousFocusItem) frame.previousFocusItem.forceActiveFocus()
      frame.previousFocusItem = null
      return
    }
    frame.previousFocusItem = frame.Window ? frame.Window.activeFocusItem : null
    frame.opened()
  }

  Keys.onEscapePressed: frame.dismissed()

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: if (frame.dismissOnOutsideClick) frame.dismissed()
  }

  Rectangle {
    anchors.centerIn: parent
    width: Math.min(Theme.dialogWidth, parent.width - Theme.space2xl * 2)
    height: layout.height + Theme.spaceXl * 2
    color: Theme.paper
    border.color: Theme.border
    border.width: Theme.dialogBorderWidth

    // Swallows clicks and hover, so the area beneath never sees them and a
    // click inside the card never dismisses it.
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    ColumnLayout {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Theme.spaceXl
      spacing: Theme.spaceLg

      ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: Theme.spaceLg
      }

      Text {
        Layout.fillWidth: true
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: frame.error
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.red
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm
        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: frame.hint
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.faint
        }
        RowLayout {
          id: actionRow
          spacing: Theme.spaceSm
        }
      }
    }
  }
}
