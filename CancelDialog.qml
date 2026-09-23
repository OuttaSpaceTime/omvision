import QtQuick
import QtQuick.Layouts

// "Cancel goal" flow (plan.md M3/O3, mockup Cancel.dc.html): a reason
// (one of three fixed choices, radio-style) and a free-text "what do you
// take from it" line. Confirming emits confirmed(reason, takeaway); the
// caller (GoalDetailScreen) re-reads <slug>.md and applies both the
// status change and the note in one write (Writer.appendCancelNote).
//
// The mockup's own footer copy ("moves to goals/archive/") describes a
// filesystem move that goal-files.md's fixed layout has no room for and
// that would break the existing status-filter UI in GoalsScreen -- this
// dialog follows the written task spec instead: front matter changes to
// "cancelled" in place, and the reason/takeaway are appended to the same
// file, exactly like every other cancelled goal already filed under
// GoalsScreen's "cancelled" tab.
//
// True modal: a FocusScope so focus can be pushed into the dialog on
// open and restored to wherever it was on close, and a scrim beneath the
// card that dims the content and blocks every click/hover meant for it.
// Unlike EventDialog, a click on the scrim does NOT dismiss -- this is
// the destructive action in the app, so closing it always takes an
// explicit Back/Cancel press (or Esc), never a stray click. The card is
// sized to its own content instead of a fixed height -- an unsized
// Rectangle here previously rendered as a zero-height box, which is why
// the dialog used to draw straight over the content with no visible card
// behind it.
FocusScope {
  id: root

  property string goalTitle: ""
  property int poms: 0
  property string errorMessage: ""
  signal confirmed(string reason, string takeaway)
  signal dismissed()

  readonly property var reasons: [
    "Not relevant any more",
    "Too big — I'll cut it differently",
    "Replaced by another goal"
  ]
  property int reasonIndex: 0
  property string takeawayText: ""
  property var previousFocusItem: null

  function confirm() { root.confirmed(root.reasons[root.reasonIndex], root.takeawayText) }

  onVisibleChanged: {
    if (!visible) {
      if (root.previousFocusItem) {
        root.previousFocusItem.forceActiveFocus()
        root.previousFocusItem = null
      }
      return
    }
    root.previousFocusItem = root.Window ? root.Window.activeFocusItem : null
    reasonIndex = 0
    takeawayText = ""
    takeawayInput.forceActiveFocus()
  }

  Keys.onEscapePressed: root.dismissed()
  // Only ever reaches here when the takeaway TextEdit does NOT have
  // active focus -- TextEdit accepts Return itself (to insert a
  // newline), so this never fires while the user is mid-sentence in the
  // one multi-line field. That's deliberate: a destructive confirm
  // should never be one accidental keystroke away while typing.
  Keys.onReturnPressed: root.confirm()

  // Scrim: dims the content behind and blocks every click/hover meant
  // for whatever is beneath it. No onClicked handler -- a stray click
  // here is swallowed, not treated as a dismissal, because ending a goal
  // is destructive and closing this dialog must always be an explicit
  // Back/Cancel press or Esc.
  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea { anchors.fill: parent; hoverEnabled: true }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(440, parent.width - 40)
    height: content.height + 36
    color: Theme.paper
    border.color: Theme.border
    border.width: 2

    // Swallow clicks/hover so the scrim beneath never sees them.
    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: {} }

    ColumnLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 18
      spacing: 14

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: "Cancel “" + root.goalTitle + "”?"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySize
          font.bold: true
          color: Theme.ink
        }
        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: root.poms + (root.poms === 1 ? " pom" : " poms") + " stay in the history. Status becomes “cancelled” — it drops out of Active and shows under its own filter."
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySmallSize
          color: Theme.dim
        }
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 7
        Text {
          text: "WHY"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.bold: true
          font.letterSpacing: 1.2
          color: Theme.dim
        }
        Repeater {
          model: root.reasons
          delegate: Item {
            id: reasonRow
            required property string modelData
            required property int index
            readonly property bool selected: root.reasonIndex === index
            Layout.fillWidth: true
            implicitHeight: 20

            RowLayout {
              anchors.fill: parent
              spacing: 9

              Rectangle {
                width: 13
                height: 13
                radius: 7
                border.color: Theme.border
                border.width: 1
                color: "transparent"
                Rectangle {
                  visible: reasonRow.selected
                  anchors.centerIn: parent
                  width: 7
                  height: 7
                  radius: 4
                  color: Theme.accentColor
                }
              }
              Text {
                Layout.fillWidth: true
                text: reasonRow.modelData
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: reasonRow.selected ? Theme.ink : Theme.dim
              }
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.reasonIndex = reasonRow.index
            }
          }
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 6
        Text {
          text: "WHAT DO YOU TAKE FROM IT?"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.bold: true
          font.letterSpacing: 1.2
          color: Theme.dim
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 56
          color: Theme.fill
          border.color: Theme.border
          border.width: 1

          Flickable {
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            contentHeight: Math.max(height, takeawayInput.contentHeight)
            TextEdit {
              id: takeawayInput
              width: parent.width
              wrapMode: TextEdit.Wrap
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              selectByMouse: true
              text: root.takeawayText
              onTextChanged: root.takeawayText = text
              Keys.onEscapePressed: root.dismissed()
            }
          }
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.errorMessage.length > 0
        wrapMode: Text.WordWrap
        text: root.errorMessage
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.red
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Item { Layout.fillWidth: true }
        Button {
          label: "Back"
          inert: false
          Layout.preferredWidth: implicitWidth
          Layout.preferredHeight: Theme.controlHeight
          onActivated: root.dismissed()
        }
        Rectangle {
          Layout.preferredWidth: endLabel.implicitWidth + 24
          Layout.preferredHeight: Theme.controlHeight
          color: "transparent"
          border.color: Theme.red
          border.width: Theme.borderWidth
          Text {
            id: endLabel
            anchors.centerIn: parent
            text: "End goal"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            font.bold: true
            color: Theme.red
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirm()
          }
        }
      }
    }
  }
}
