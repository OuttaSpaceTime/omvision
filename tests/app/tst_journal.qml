import QtQuick

// Typing in the journal writes the day's file. The fixture has an entry for
// today (tests/fixtures/home/.../journal/TODAY.md, installed under today's
// date), and the journal always opens on today.
OmvisionTest {
  name: "journal"

  function test_typing_writes_the_days_file() {
    openJournal()
    // The open day and its cursor carry over from the last test (a click
    // into the text leaves it on the first line), so go to the end first.
    key(Qt.Key_End, Qt.ControlModifier)
    type("Then the charts.")
    expectFile(today, fixtureText(today) + "Then the charts.")
  }

  // Deleting a day's whole text deletes its file, and typing again
  // afterwards writes the day afresh.
  function test_emptying_a_day_deletes_its_file() {
    openJournal()
    key(Qt.Key_A, Qt.ControlModifier)
    key(Qt.Key_Delete)
    compare(journal.bufferText, "", "the page is empty")
    expectFile(today, null, undefined, "the emptied day's file is gone")
    type("Again.")
    expectFile(today, "Again.")
  }

  // An emptied day drops out of the day list (today keeps its row whatever
  // is on disk, so this is a past day).
  function test_an_emptied_past_day_leaves_the_day_list() {
    var path = addDays({ 3: "An old day.\n" })[3]
    app.currentScreen = "journal"
    journal.openDay(path)
    tryCompare(journal, "bufferText", "An old day.\n", 5000)
    key(Qt.Key_A, Qt.ControlModifier)
    key(Qt.Key_Backspace)
    expectFile(path, null, undefined, "the emptied day's file is gone")
    tryVerify(function() { return journal.findEntry(path) === null }, 8000,
              "the day left the day list")
  }

  // A click into the words is starting to write, as a click on the paper
  // around them is: the sidebar brought out with `»` goes away. It used to
  // stay, because the editor takes its own clicks and only the margins
  // reached the paper's MouseArea.
  function test_a_click_into_the_text_hides_the_sidebar() {
    openJournal()
    app.toggleSidebar() // what `»` does
    tryVerify(function() { return journal.sidebarShown }, 3000, "the sidebar is out")
    var page = item("journalEditor")
    settle(page)
    // On the first line's words, not the paper beside them.
    mouseClick(page, page.width / 8, page.cursorRectangle.height / 2)
    tryVerify(function() { return !journal.sidebarShown }, 3000, "the click put the sidebar away")
    expectFileUnchanged(today, 1500)
  }
}
