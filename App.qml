import QtQuick

// The app, as the screens and dialogs see it: its data (notes), where it is
// (nav) and which dialog is open. Each screen and dialog declares
// `required property App app` and calls these directly, so a misspelled
// member fails `bin/check lint` instead of failing at run time. Small
// widgets (TaskRow, DayList, Sidebar, ...) get only what they show, and
// report clicks by signal.
QtObject {
  id: app

  readonly property NotesStore notes: NotesStore {}
  readonly property Navigator nav: Navigator {
    blocked: app.dialog !== ""
  }

  // ---- dialogs -------------------------------------------------------------
  // At most one is open, so one value says which: "" | "event" | "goal" |
  // "cancel". `dialogSlug` is the goal it was opened for: the event's goal,
  // the goal to edit ("" for a new one), the goal to cancel. Each dialog
  // keeps its own error line, and closes itself once its save has landed.
  property string dialog: ""
  property string dialogSlug: ""
  // Counts openings. A dialog takes it when it saves, and on the save's
  // result asks isOpen() whether it is still that opening: by then the user
  // may have closed it and opened another -- the same dialog for another
  // goal, even -- which must not be closed or given the error.
  property int dialogSerial: 0

  // A goal whose file doesn't parse has nothing to edit; the dialog would
  // open blank.
  function openDialog(name, slug) {
    if (name === "goal" && slug && !(app.notes.goalsData[slug] && app.notes.goalsData[slug].meta)) return
    app.dialogSlug = slug || ""
    app.dialogSerial++
    app.dialog = name
  }

  function isOpen(serial) { return app.dialog !== "" && app.dialogSerial === serial }

  function closeDialog() { app.dialog = "" }
}
