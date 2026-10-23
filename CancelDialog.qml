pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// "Cancel goal": a reason (one of three fixed choices, radio-style) and a
// free-text "what do you take from it" line. Confirming emits
// confirmed(reason, takeaway); omvision.qml, which mounts this dialog over
// the whole window for GoalDetailScreen, re-reads <slug>.md and applies both
// the status change and the note in one write (Writer.appendCancelNote).
//
// The approved mockup's footer copy ("moves to goals/archive/") described a
// filesystem move that goal-files.md's fixed layout has no room for and
// that would break the existing status-filter UI in GoalsScreen -- this
// dialog follows the written task spec instead: front matter changes to
// "cancelled" in place, and the reason/takeaway are appended to the same
// file, exactly like every other cancelled goal already filed under
// GoalsScreen's "cancelled" tab.
//
// The destructive dialog in the app, so a stray click outside never
// closes it: that takes Back or Esc (DialogFrame).
DialogFrame {
  id: root

  property string goalTitle: ""
  property int poms: 0
  property string errorMessage: ""
  signal confirmed(string reason, string takeaway)

  readonly property var reasons: [
    "Not relevant any more",
    "Too big — I'll cut it differently",
    "Replaced by another goal"
  ]
  property int reasonIndex: 0
  property string takeawayText: ""

  dismissOnOutsideClick: false
  error: root.errorMessage

  function confirm() { root.confirmed(root.reasons[root.reasonIndex], root.takeawayText) }

  onOpened: {
    reasonIndex = 0
    takeawayText = ""
    takeawayInput.forceActiveFocus()
  }

  // Only ever reaches here when the takeaway TextEdit does NOT have
  // active focus -- TextEdit accepts Return itself (to insert a
  // newline), so this never fires while the user is mid-sentence in the
  // one multi-line field. That's deliberate: a destructive confirm
  // should never be one accidental keystroke away while typing.
  Keys.onReturnPressed: root.confirm()

  actions: [
    Button { label: "Back"; onActivated: root.dismissed() },
    Button { label: "End goal"; danger: true; onActivated: root.confirm() }
  ]

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceXs
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
      text: Parser.pomsLabel(root.poms) + " stay in the history. Status becomes “cancelled” — it drops out of Active and shows under its own filter."
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.dim
    }
  }

  Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceSm
    CaptionLabel { text: "Why" }
    Repeater {
      model: root.reasons
      delegate: Item {
        id: reasonRow
        required property string modelData
        required property int index
        readonly property bool selected: root.reasonIndex === index
        Layout.fillWidth: true
        implicitHeight: Theme.smallControlHeight

        RowLayout {
          anchors.fill: parent
          spacing: Theme.spaceSm

          OptionMark {
            round: true
            checked: reasonRow.selected
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
    spacing: Theme.spaceXs
    CaptionLabel { text: "What do you take from it?" }
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: Theme.dialogTextAreaHeight
      color: Theme.fill
      border.color: Theme.border
      border.width: Theme.borderWidth

      Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spaceSm
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
}
