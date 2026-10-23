import QtQuick
import QtQuick.Layouts

// "New goal", and "Edit goal" when `editSlug` is set: title + one-line
// why, optionally an estimate in poms and a done_by date, and whether the
// goal can be focused on at the laptop. Submitting hands the raw fields up
// to omvision.qml as one payload -- this dialog never touches the filesystem
// itself, it only knows how to validate what the user typed (goal-files.md
// has nothing to say about *input* validation, only about the file shape
// once something is about to be written). Additive, so a stray click
// outside closes it (DialogFrame).
DialogFrame {
  id: root

  property string errorMessage: ""
  // Set both to edit an existing goal instead of creating one: `initial`
  // is that goal's parsed meta (Parser.parseGoalFile), used to pre-fill.
  property string editSlug: ""
  property var initial: null
  readonly property bool editing: editSlug !== ""

  signal submitted(var fields)

  property string titleText: ""
  property string whyText: ""
  property string estimateText: ""
  property string doneByText: ""
  // Ticked by default, a new goal's and every old goal's state: a goal
  // the picker should skip is the exception (goal-files.md §6).
  property bool focusable: true
  property string localError: ""

  error: root.localError || root.errorMessage
  hint: root.editing
    ? "Saves to goals/" + root.editSlug + ".md. The file name stays the same."
    : "Creates ~/Notes/Omvision/goals/<slug>.md with an empty Tasks list."

  onOpened: {
    var g = root.editing ? root.initial : null
    titleText = g ? g.title : ""
    whyText = g ? g.why : ""
    estimateText = g ? root.leadingNumber(g.raw.estimate) : ""
    doneByText = g && g.done_by ? g.done_by : ""
    focusable = g ? g.focusable !== false : true
    localError = ""
    titleField.focusInput()
  }

  // The leading digits of the raw front-matter value, not meta.estimate.
  // The two agree on every estimate the app writes or the coach does: a
  // whole number, with or without the coach's "# was 9" note (Parser now
  // strips it, so both give 6), and a missing one (both empty). They part
  // only on a hand-typed value Parser can't read as a number, such as
  // "estimate: 6 poms". meta.estimate has none there, so the field would
  // open empty, and saving the dialog to fix a typo in the title would then
  // delete the estimate line, since an empty field removes the key. Read
  // this way the field opens on 6 and the number survives.
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
    root.submitted({ title: t, why: root.whyText.trim(), estimate: estimate, doneBy: doneBy, focusable: root.focusable })
  }

  Keys.onReturnPressed: root.submit()
  Keys.onEnterPressed: root.submit()

  actions: [
    Button { label: "Cancel"; onActivated: root.dismissed() },
    Button { label: root.editing ? "Save" : "Create goal"; filled: true; onActivated: root.submit() }
  ]

  Text {
    text: root.editing ? "Edit goal" : "New goal"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    font.bold: true
    color: Theme.ink
  }

  Rectangle { Layout.fillWidth: true; Layout.preferredHeight: Theme.hairlineWidth; color: Theme.hairline }

  // The only required field; "*" marks it instead of a header caption.
  DialogField {
    id: titleField
    label: "Title *"
    text: root.titleText
    onEdited: function(text) { root.titleText = text }
    onAccepted: root.submit()
  }

  DialogField {
    label: "Why"
    text: root.whyText
    onEdited: function(text) { root.whyText = text }
    onAccepted: root.submit()
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Theme.spaceSm
    DialogField {
      fieldWidth: Theme.dialogShortFieldWidth
      label: "Estimate (poms)"
      text: root.estimateText
      onEdited: function(text) { root.estimateText = text }
      onAccepted: root.submit()
    }
    DialogField {
      label: "Done by (YYYY-MM-DD)"
      text: root.doneByText
      onEdited: function(text) { root.doneByText = text }
      onAccepted: root.submit()
    }
  }

  // ---- focusable ----------------------------------------------------
  // The same box as EventDialog's "count the time".
  CheckOption {
    objectName: "goalFocusableToggle"
    Layout.fillWidth: true
    checked: root.focusable
    label: "can be focused on at the laptop"
    onToggled: root.focusable = !root.focusable
  }
}
