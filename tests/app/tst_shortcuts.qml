import QtQuick

// The screen shortcuts: Ctrl+T/G/J and Ctrl+1-4, handled in omvision.qml's
// window-level Keys handler. What can go wrong is the key never getting
// there: the journal's editor or a task field taking it first, or the
// keyboard left on a screen that was just hidden, so the next press goes
// nowhere. So each test presses keys from where the focus really is.
OmvisionTest {
  name: "shortcuts"

  function test_letters_from_the_goals_screen() {
    key(Qt.Key_T, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "today")
    key(Qt.Key_G, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "goals")
    key(Qt.Key_J, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "journal")
  }

  function test_numbers_follow_the_rail() {
    key(Qt.Key_1, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "today")
    key(Qt.Key_3, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "coaching")
    key(Qt.Key_4, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "journal")
    key(Qt.Key_2, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "goals")
  }

  // The editor has the keyboard on the journal. The shortcut has to get
  // past it without typing anything into the day, and a second shortcut
  // from the screen it lands on has to work too.
  function test_out_of_the_journal_editor_and_back() {
    key(Qt.Key_J, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "journal")
    var page = item("journalEditor")
    tryVerify(function() { return page.activeFocus }, 3000, "the page has the keyboard")
    var before = journal.bufferText
    key(Qt.Key_T, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "today")
    compare(journal.bufferText, before, "the shortcut typed nothing into the day")
    key(Qt.Key_J, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "journal")
    tryVerify(function() { return page.activeFocus }, 3000, "back on the journal, the page has the keyboard again")
  }

  // Regression: hiding the journal left its editor holding the keyboard, so
  // leaving it by the rail (which only sets the screen) and typing wrote
  // into the hidden day, and saved it.
  function test_typing_after_leaving_the_journal_stays_out_of_it() {
    key(Qt.Key_J, Qt.ControlModifier)
    var page = item("journalEditor")
    tryVerify(function() { return page.activeFocus }, 3000, "the page has the keyboard")
    var before = journal.bufferText
    app.currentScreen = "today" // what the rail's Today does
    type("q")
    compare(journal.bufferText, before, "the keystroke stayed out of the hidden day")
    key(Qt.Key_G, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "goals")
  }

  function test_out_of_a_task_field() {
    openGoal("write-the-report")
    click("addTaskButton")
    var field = item("addTaskField")
    tryVerify(function() { return field.activeFocus }, 3000, "the field has the keyboard")
    key(Qt.Key_J, Qt.ControlModifier)
    tryCompare(app, "currentScreen", "journal")
  }

  // A dialog belongs to the screen it was opened over.
  function test_not_while_a_dialog_is_open() {
    app.openNewGoalDialog()
    tryCompare(app, "newGoalDialogOpen", true)
    key(Qt.Key_J, Qt.ControlModifier)
    wait(200)
    compare(app.currentScreen, "goals", "the screen stayed put under the dialog")
    app.newGoalDialogOpen = false
  }
}
