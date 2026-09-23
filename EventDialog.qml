import QtQuick
import QtQuick.Layouts

import "Writer.js" as Writer

// "Add event" (plan.md M3/O4, mockup Event.dc.html): logs time that
// wasn't run through the timer -- training, a meeting, reading, deep
// work, or anything else. Submitting hands the raw, still-unvalidated
// fields up to omvision.qml as one payload; omvision.qml is the one that
// knows how to turn it into a §4 entry and append it (append-only, no
// read-back -- this dialog itself never touches the filesystem).
//
// True modal: a FocusScope so focus can be pushed into the dialog on
// open and restored to wherever it was on close, a scrim beneath the
// card that dims the content, blocks every click/hover meant for it,
// and dismisses on a stray click (this dialog is not destructive,
// unlike CancelDialog), and a card sized to its own content instead of
// a fixed height -- an unsized Rectangle here previously rendered as a
// zero-height box, which is why the dialog used to draw straight over
// the content with no visible card behind it.
FocusScope {
  id: root

  property var goalsData: ({})
  property string defaultSlug: ""
  property string errorMessage: ""

  signal submitted(var payload)
  signal dismissed()

  readonly property var kinds: ["training", "meeting", "reading", "deep work", "other"]
  property int kindIndex: 0
  property string whatText: ""
  property string whenText: ""
  property string lenText: ""
  property string selectedSlug: ""
  property bool countsToward: false
  property string localError: ""
  property var previousFocusItem: null

  function pad2(n) { return (n < 10 ? "0" : "") + n }

  onVisibleChanged: {
    if (!visible) {
      if (root.previousFocusItem) {
        root.previousFocusItem.forceActiveFocus()
        root.previousFocusItem = null
      }
      return
    }
    root.previousFocusItem = root.Window ? root.Window.activeFocusItem : null
    kindIndex = 0
    whatText = ""
    var now = new Date()
    whenText = "today " + pad2(now.getHours()) + ":" + pad2(now.getMinutes())
    lenText = ""
    selectedSlug = root.defaultSlug
    countsToward = false
    localError = ""
    whatInput.forceActiveFocus()
  }

  function goalList() {
    var out = []
    for (var slug in root.goalsData) {
      var g = root.goalsData[slug]
      if (g && g.meta) out.push({ slug: slug, title: g.meta.title })
    }
    out.sort(function(a, b) { return a.title < b.title ? -1 : (a.title > b.title ? 1 : 0) })
    return out
  }

  function tryWhen() { return Writer.parseWhen(root.whenText, new Date()) }
  function tryMinutes() { return Writer.parseDurationInput(root.lenText) }

  function submit() {
    var when = root.tryWhen()
    var minutes = root.tryMinutes()
    if (when === null) { root.localError = "\"When\" isn't a time I understand — try \"today 14:30\" or \"09:00\"."; return }
    if (!(minutes > 0)) { root.localError = "\"How long\" needs a duration — try \"25\", \"25m\" or \"1h30\"."; return }
    root.localError = ""
    root.submitted({
      kind: root.kinds[root.kindIndex],
      what: root.whatText,
      whenDate: when,
      minutes: minutes,
      slug: root.selectedSlug,
      countsToward: root.countsToward
    })
  }

  Keys.onEscapePressed: root.dismissed()

  // Scrim: dims the content behind and, being the topmost item under the
  // pointer with hoverEnabled, absorbs every click and hover meant for
  // whatever is beneath it. A plain click here dismisses the dialog --
  // it is additive, not destructive (contrast CancelDialog).
  Rectangle {
    id: scrim
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.45)
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.dismissed()
    }
  }

  Rectangle {
    id: card
    anchors.centerIn: parent
    width: Math.min(520, parent.width - 40)
    height: content.height + 36
    color: Theme.paper
    border.color: Theme.border
    border.width: 2

    // Swallow clicks/hover so the scrim beneath never sees them, and a
    // click inside the card never dismisses it.
    MouseArea { anchors.fill: parent; hoverEnabled: true; onClicked: {} }

    ColumnLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 18
      spacing: 12

      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Text {
          text: "Add event"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySize
          font.bold: true
          color: Theme.ink
        }
        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: "time that wasn't a pomodoro"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.capitalization: Font.AllUppercase
          font.letterSpacing: 1.2
          color: Theme.dim
        }
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      // ---- type chips -----------------------------------------------------
      Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
          model: root.kinds
          delegate: Rectangle {
            required property string modelData
            required property int index
            readonly property bool selected: root.kindIndex === index
            height: 22
            width: chipLabel.implicitWidth + 16
            color: selected ? Theme.accentFill : "transparent"
            border.color: selected ? Theme.accentColor : Theme.hairline
            border.width: 1
            Text {
              id: chipLabel
              anchors.centerIn: parent
              text: parent.modelData
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: parent.selected ? Theme.accentColor : Theme.dim
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.kindIndex = index
            }
          }
        }
      }

      // ---- what -------------------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        Text {
          text: "WHAT"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.bold: true
          font.letterSpacing: 1.2
          color: Theme.dim
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Theme.controlHeight
          color: Theme.fill
          border.color: Theme.border
          border.width: 1
          TextInput {
            id: whatInput
            anchors.fill: parent
            anchors.leftMargin: 9
            anchors.rightMargin: 9
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.ink
            selectByMouse: true
            text: root.whatText
            onTextChanged: root.whatText = text
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
          }
        }
      }

      // ---- when / how long ----------------------------------------------
      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 5
          Text {
            text: "WHEN"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.letterSpacing: 1.2
            color: Theme.dim
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlHeight
            color: Theme.fill
            border.color: Theme.border
            border.width: 1
            TextInput {
              anchors.fill: parent
              anchors.leftMargin: 9
              anchors.rightMargin: 9
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              selectByMouse: true
              text: root.whenText
              onTextChanged: root.whenText = text
              Keys.onReturnPressed: root.submit()
              Keys.onEnterPressed: root.submit()
            }
          }
        }
        ColumnLayout {
          Layout.preferredWidth: 120
          spacing: 5
          Text {
            text: "HOW LONG"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.letterSpacing: 1.2
            color: Theme.dim
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.controlHeight
            color: Theme.fill
            border.color: Theme.border
            border.width: 1
            TextInput {
              anchors.fill: parent
              anchors.leftMargin: 9
              anchors.rightMargin: 9
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              selectByMouse: true
              text: root.lenText
              onTextChanged: root.lenText = text
              Keys.onReturnPressed: root.submit()
              Keys.onEnterPressed: root.submit()
            }
          }
        }
      }

      // ---- goal -------------------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 5
        Text {
          text: "GOAL"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.bold: true
          font.letterSpacing: 1.2
          color: Theme.dim
        }
        Flow {
          Layout.fillWidth: true
          spacing: 6

          Rectangle {
            readonly property bool selected: root.selectedSlug === ""
            height: 22
            width: noGoalLabel.implicitWidth + 16
            color: selected ? Theme.accentFill : "transparent"
            border.color: selected ? Theme.accentColor : Theme.hairline
            border.width: 1
            Text {
              id: noGoalLabel
              anchors.centerIn: parent
              text: "no goal · shows on the day only"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: parent.selected ? Theme.accentColor : Theme.dim
            }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedSlug = "" }
          }

          Repeater {
            model: root.goalList()
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
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedSlug = parent.modelData.slug }
            }
          }
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 20
        RowLayout {
          anchors.fill: parent
          spacing: 9
          Rectangle {
            width: 13
            height: 13
            border.color: Theme.border
            border.width: 1
            color: "transparent"
            Rectangle {
              visible: root.countsToward
              anchors.centerIn: parent
              width: 7
              height: 7
              color: Theme.accentColor
            }
          }
          Text {
            Layout.fillWidth: true
            text: "count the time towards the goal"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySmallSize
            color: Theme.dim
          }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.countsToward = !root.countsToward
        }
      }

      Text {
        Layout.fillWidth: true
        visible: root.localError.length > 0 || root.errorMessage.length > 0
        wrapMode: Text.WordWrap
        text: root.localError.length > 0 ? root.localError : root.errorMessage
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.red
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10
        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: "Lands on the timeline as an event."
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
          label: "Add"
          filled: true
          inert: false
          Layout.preferredWidth: implicitWidth
          Layout.preferredHeight: Theme.controlHeight
          onActivated: root.submit()
        }
      }
    }
  }
}
