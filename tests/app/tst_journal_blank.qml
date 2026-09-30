import QtQuick
import "../../Parser.js" as Parser

// Known bug, pinned: a journal opened before its files have loaded stays
// blank over a non-empty day, and typing into that blank page then saves
// over the day's file.
//
// Opening the journal sets its buffer to "" (nothing loaded yet), and that
// edit of the editor's text restarts the 800ms write debounce. The day's
// text arrives within it, and syncBufferFromDisk(), which is what should
// put it in the buffer, returns early while the debounce is running -- and
// it also runs on journalContents' change, before `entries` has been
// recomputed. Nothing calls it again, so the page stays blank, and the next
// keystroke's write replaces the day's text with just that keystroke.
//
// A file of its own, with no reset between tests: the journal has to be
// opened the moment the app starts, before any file is read, and only a
// fresh app is in that state.
OmvisionTest {
  name: "journal_blank"
  resetBeforeEachTest: false

  readonly property string today: "journal/" + Parser.dayKey(new Date()) + ".md"
  property bool openedBeforeLoad: false

  function started() {
    // The journal's file list and files load later, on the event loop.
    openedBeforeLoad = app.journalContents[notesPath(today)] === undefined
    app.currentScreen = "journal"
  }

  function test_journal_opened_before_load_shows_the_day() {
    if (!openedBeforeLoad) skip("the day's file had loaded before the journal opened; the race did not happen")
    var text = fixtureText(today)
    verify(text !== null && text.length > 0, "the fixture has an entry for today")
    // Let the load land and the debounce run out.
    tryVerify(function() { return app.journalContents[notesPath(today)] === text }, 8000,
              "the app loaded today's file")
    wait(1500)

    expectFailContinue("", "BUG: journal opened before load stays blank over a non-empty day")
    compare(journal.bufferText, text, "the page shows the day's text")

    // Click into the page, the way you would start writing on it, and type.
    var page = click("journalEditor")
    tryVerify(function() { return page.activeFocus }, 3000, "the page has the keyboard")
    key(Qt.Key_End, Qt.ControlModifier)
    type("x")
    compare(journal.bufferText.slice(-1), "x", "the keystroke reached the page")
    wait(2000) // the debounce, then the write
    expectFailContinue("", "BUG: typing into the blank page saves over the day's file")
    compare(readFile(today), text + "x", "the day's text survives a keystroke")
  }
}
