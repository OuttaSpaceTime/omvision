pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "Writer.js" as Writer
import "Util.js" as Util

// "Add event": logs time that wasn't run through the timer -- training, a
// meeting, reading, deep work, or anything else. Submitting hands the
// validated fields to NotesStore.addEvent() as one payload; the store is
// the one that knows how to turn it into a §4 entry and append it
// (append-only, no read-back -- this dialog itself never touches the
// filesystem). Additive, so a stray click outside closes it (DialogFrame).
DialogFrame {
  id: root

  required property App app
  visible: root.app.dialog === "event"
  onDismissed: root.app.closeDialog()

  readonly property var kinds: ["training", "meeting", "reading", "deep work", "other"]
  property int kindIndex: 0
  property string whatText: ""
  property string whenText: ""
  property string lenText: ""
  property string selectedSlug: ""
  property bool countsToward: false
  property string localError: ""

  error: root.localError
  hint: "Lands on the timeline as an event."

  onOpened: {
    kindIndex = 0
    whatText = ""
    whenText = "today " + Writer.clockTime(new Date())
    lenText = ""
    selectedSlug = root.app.dialogSlug
    countsToward = false
    localError = ""
    whatField.focusInput()
  }

  function submit() {
    var when = Writer.parseWhen(root.whenText, new Date())
    var minutes = Writer.parseDurationInput(root.lenText)
    if (when === null) { root.localError = "\"When\" isn't a time I understand — try \"today 14:30\" or \"09:00\"."; return }
    if (!(minutes > 0)) { root.localError = "\"How long\" needs a duration — try \"25\", \"25m\" or \"1h30\"."; return }
    root.localError = ""
    var opening = root.app.dialogSerial
    root.app.notes.addEvent({
      kind: root.kinds[root.kindIndex],
      what: root.whatText,
      whenDate: when,
      minutes: minutes,
      slug: root.selectedSlug,
      countsToward: root.countsToward
    }, function(ok) {
      if (!root.app.isOpen(opening)) return
      if (ok) root.app.closeDialog()
      else root.localError = "Couldn't log the event. Your entry is still here — try again."
    })
  }

  actions: [
    Button { label: "Cancel"; onActivated: root.dismissed() },
    Button { label: "Add"; filled: true; onActivated: root.submit() }
  ]

  RowLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceSm
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
      color: Theme.dim
    }
  }

  Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }

  // ---- type chips -----------------------------------------------------
  Flow {
    Layout.fillWidth: true
    spacing: Theme.spaceXs
    Repeater {
      model: root.kinds
      delegate: BoxChip {
        id: kindChip
        required property string modelData
        required property int index
        label: modelData
        selected: root.kindIndex === index
        onClicked: root.kindIndex = kindChip.index
      }
    }
  }

  DialogField {
    id: whatField
    inputName: "eventWhatField"
    label: "What"
    text: root.whatText
    onEdited: function(text) { root.whatText = text }
    onAccepted: root.submit()
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceSm
    DialogField {
      label: "When"
      text: root.whenText
      onEdited: function(text) { root.whenText = text }
      onAccepted: root.submit()
    }
    DialogField {
      fieldWidth: Theme.dialogShortFieldWidth
      inputName: "eventLengthField"
      label: "How long"
      text: root.lenText
      onEdited: function(text) { root.lenText = text }
      onAccepted: root.submit()
    }
  }

  // ---- goal -------------------------------------------------------------
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceXs
    CaptionLabel { text: "Goal" }
    Flow {
      Layout.fillWidth: true
      spacing: Theme.spaceXs

      BoxChip {
        label: "no goal · shows on the day only"
        selected: root.selectedSlug === ""
        onClicked: root.selectedSlug = ""
      }

      Repeater {
        model: Util.goalsByTitle(root.app.notes.goalsData)
        delegate: BoxChip {
          id: goalChip
          required property var modelData
          label: modelData.meta.title
          selected: root.selectedSlug === modelData.slug
          onClicked: root.selectedSlug = goalChip.modelData.slug
        }
      }
    }
  }

  CheckOption {
    Layout.fillWidth: true
    checked: root.countsToward
    label: "count the time towards the goal"
    onToggled: root.countsToward = !root.countsToward
  }
}
