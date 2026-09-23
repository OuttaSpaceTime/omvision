import QtQuick
import QtQuick.Layouts

// "New entry — pick a goal" (Journal M?/O5 write path). Journal mixes every
// goal's entries into one list, so a bare "+ entry" click is ambiguous about
// which goal's journal/ directory the new file belongs to. Same overlay-card
// idiom as CancelDialog.qml / EventDialog.qml: centered card, backdrop click
// and Escape both dismiss without creating anything.
Item {
  id: root

  property var goalOptions: [] // [{slug, title}]
  property string defaultSlug: ""

  signal chosen(string slug)
  signal dismissed()

  property string selectedSlug: ""

  onVisibleChanged: if (visible) { selectedSlug = root.defaultSlug; root.forceActiveFocus() }

  function moveSelection(delta) {
    if (root.goalOptions.length === 0) return
    var idx = -1
    for (var i = 0; i < root.goalOptions.length; i++) {
      if (root.goalOptions[i].slug === root.selectedSlug) { idx = i; break }
    }
    idx = (idx + delta + root.goalOptions.length) % root.goalOptions.length
    root.selectedSlug = root.goalOptions[idx].slug
  }

  Keys.onEscapePressed: root.dismissed()
  Keys.onReturnPressed: if (root.selectedSlug !== "") root.chosen(root.selectedSlug)
  Keys.onEnterPressed: if (root.selectedSlug !== "") root.chosen(root.selectedSlug)
  Keys.onRightPressed: root.moveSelection(1)
  Keys.onLeftPressed: root.moveSelection(-1)
  Keys.onDownPressed: root.moveSelection(1)
  Keys.onUpPressed: root.moveSelection(-1)

  MouseArea {
    anchors.fill: parent
    onClicked: root.dismissed()
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(420, parent.width - 40)
    // No anchor gives a plain Rectangle its height from a child's content --
    // unlike CancelDialog.qml/EventDialog.qml's fixed-content cards, this one's
    // Flow of goal chips can wrap to a different number of rows, so height is
    // bound to the content's own implicit size (right column below) rather
    // than a guessed constant; that's what keeps centerIn actually centered.
    height: cardContent.implicitHeight + 36
    color: Theme.paper
    border.color: Theme.border
    border.width: 2

    MouseArea { anchors.fill: parent; onClicked: {} }

    ColumnLayout {
      id: cardContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 18
      spacing: 12

      Text {
        text: "New entry — which goal?"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        font.bold: true
        color: Theme.ink
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
          model: root.goalOptions
          delegate: Rectangle {
            required property var modelData
            readonly property bool selected: root.selectedSlug === modelData.slug
            height: 22
            width: goalLabel.implicitWidth + 16
            color: selected ? Theme.accentFill : "transparent"
            border.color: selected ? Theme.accentColor : Theme.hairline
            border.width: 1
            Text {
              id: goalLabel
              anchors.centerIn: parent
              text: parent.modelData.title
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: parent.selected ? Theme.accentColor : Theme.dim
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectedSlug = parent.modelData.slug
            }
          }
        }
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: "Creates today's entry for that goal."
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.faint
        }
        Button {
          label: "Cancel"
          inert: false
          Layout.preferredWidth: implicitWidth
          Layout.preferredHeight: Theme.controlHeight
          onActivated: root.dismissed()
        }
        Button {
          label: "Create"
          filled: true
          inert: root.selectedSlug === ""
          Layout.preferredWidth: implicitWidth
          Layout.preferredHeight: Theme.controlHeight
          onActivated: if (root.selectedSlug !== "") root.chosen(root.selectedSlug)
        }
      }
    }
  }
}
