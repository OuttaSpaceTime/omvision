import QtQuick
import QtQuick.Layouts

// "New goal" (the last inert control in a fresh install, plan.md O2):
// title + one-line why, optionally an estimate in poms and a done_by
// date. Submitting hands the raw fields up to omvision.qml as one
// payload -- this dialog never touches the filesystem itself, it only
// knows how to validate what the user typed (goal-files.md has nothing
// to say about *input* validation, only about the file shape once
// something is about to be written).
//
// True modal, same construct as EventDialog/CancelDialog: a FocusScope
// so focus can be pushed in on open and popped back out on close, a
// scrim Rectangle + full-window MouseArea beneath the card that blocks
// every click/hover from reaching the content behind and dismisses on a
// stray click (this dialog is not destructive, unlike Cancel), and a
// card sized to its own content rather than a fixed height.
FocusScope {
  id: root

  property string errorMessage: ""
  // Set both to edit an existing goal instead of creating one: `initial`
  // is that goal's parsed meta (Parser.parseGoalFile), used to pre-fill.
  property string editSlug: ""
  property var initial: null
  readonly property bool editing: editSlug !== ""

  signal submitted(var fields)
  signal dismissed()

  property string titleText: ""
  property string whyText: ""
  property string estimateText: ""
  property string doneByText: ""
  property string localError: ""
  property var previousFocusItem: null

  onVisibleChanged: {
    if (!visible) {
      if (root.previousFocusItem) {
        root.previousFocusItem.forceActiveFocus()
        root.previousFocusItem = null
      }
      return
    }
    root.previousFocusItem = root.Window ? root.Window.activeFocusItem : null
    var g = root.editing ? root.initial : null
    titleText = g ? g.title : ""
    whyText = g ? g.why : ""
    estimateText = g ? root.leadingNumber(g.raw.estimate) : ""
    doneByText = g && g.done_by ? g.done_by : ""
    localError = ""
    titleInput.forceActiveFocus()
  }

  // The raw front-matter value, not meta.estimate: the coach writes
  // "estimate: 6   # was 9", which meta.estimate reads as not-a-number.
  function leadingNumber(raw) {
    var m = String(raw || "").match(/^\s*(\d+)/)
    return m ? m[1] : ""
  }

  function submit() {
    var t = root.titleText.trim()
    if (t === "") { root.localError = "Title is required."; return }

    var estimate = undefined
    var estimateStr = root.estimateText.trim()
    if (estimateStr !== "") {
      if (!/^\d+$/.test(estimateStr)) { root.localError = "Estimate needs a whole number of poms."; return }
      estimate = Number(estimateStr)
    }

    var doneBy = undefined
    var doneByStr = root.doneByText.trim()
    if (doneByStr !== "") {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(doneByStr)) { root.localError = "Done by needs a date like 2026-10-01."; return }
      doneBy = doneByStr
    }

    root.localError = ""
    root.submitted({ title: t, why: root.whyText.trim(), estimate: estimate, doneBy: doneBy })
  }

  Keys.onEscapePressed: root.dismissed()
  Keys.onReturnPressed: root.submit()
  Keys.onEnterPressed: root.submit()

  // Scrim: dims the content behind and, being the topmost item under the
  // pointer with hoverEnabled, absorbs every click and hover meant for
  // whatever is beneath it. A plain click here dismisses -- this dialog
  // is additive, not destructive, so a stray click closing it is fine
  // (contrast CancelDialog, which deliberately does not do this).
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
    width: Math.min(Theme.dialogWidth, parent.width - Theme.space2xl * 2)
    height: content.height + Theme.spaceXl * 2
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
      anchors.margins: Theme.spaceXl
      spacing: Theme.spaceLg

      Text {
        text: root.editing ? "Edit goal" : "New goal"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        font.bold: true
        color: Theme.ink
      }

      Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

      // ---- title --------------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceXs
        Text {
          // The only required field; "*" marks it instead of a header caption.
          text: "Title *"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.bold: true
          color: Theme.dim
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Theme.controlHeight
          color: Theme.fill
          border.color: Theme.border
          border.width: 1
          TextInput {
            id: titleInput
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceSm
            anchors.rightMargin: Theme.spaceSm
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.ink
            selectByMouse: true
            text: root.titleText
            onTextChanged: root.titleText = text
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
          }
        }
      }

      // ---- why ------------------------------------------------------------
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceXs
        Text {
          text: "Why"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          font.bold: true
          color: Theme.dim
        }
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: Theme.controlHeight
          color: Theme.fill
          border.color: Theme.border
          border.width: 1
          TextInput {
            id: whyInput
            anchors.fill: parent
            anchors.leftMargin: Theme.spaceSm
            anchors.rightMargin: Theme.spaceSm
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.ink
            selectByMouse: true
            text: root.whyText
            onTextChanged: root.whyText = text
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
          }
        }
      }

      // ---- estimate / done by ---------------------------------------------
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceSm
        ColumnLayout {
          // Fixed, explicitly: its field's fillWidth would otherwise make
          // this whole column fill too, and it squeezed its neighbour.
          Layout.preferredWidth: 120
          Layout.fillWidth: false
          spacing: Theme.spaceXs
          Text {
            text: "Estimate (poms)"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
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
              anchors.leftMargin: Theme.spaceSm
              anchors.rightMargin: Theme.spaceSm
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              selectByMouse: true
              text: root.estimateText
              onTextChanged: root.estimateText = text
              Keys.onReturnPressed: root.submit()
              Keys.onEnterPressed: root.submit()
            }
          }
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: Theme.spaceXs
          Text {
            text: "Done by (YYYY-MM-DD)"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
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
              anchors.leftMargin: Theme.spaceSm
              anchors.rightMargin: Theme.spaceSm
              verticalAlignment: TextInput.AlignVCenter
              clip: true
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              selectByMouse: true
              text: root.doneByText
              onTextChanged: root.doneByText = text
              Keys.onReturnPressed: root.submit()
              Keys.onEnterPressed: root.submit()
            }
          }
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
        spacing: Theme.spaceSm
        Text {
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          text: root.editing
            ? "Saves to goals/" + root.editSlug + ".md. The file name stays the same."
            : "Creates ~/Notes/Omvision/goals/<slug>.md with an empty Tasks list."
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
          label: root.editing ? "Save" : "Create goal"
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
