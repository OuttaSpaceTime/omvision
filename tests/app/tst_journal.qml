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
