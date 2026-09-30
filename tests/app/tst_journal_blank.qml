import QtQuick
import "../../Parser.js" as Parser

// Regression test: a journal opened before its files have loaded used to
// stay blank over a non-empty day, and typing into that blank page then
// saved over the day's file.
//
// Opening the journal set its buffer to "" (nothing loaded yet), and that
// edit restarted the 800ms write debounce. The day's text arrived within
// it, and syncBufferFromDisk() returned early while the debounce ran -- and
// it also ran before `entries` had been recomputed. Nothing called it
// again. JournalStore now never writes a day before its text on disk is
// known, and the page adopts that text when it arrives.
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

    compare(journal.bufferText, text, "the page shows the day's text")

    // Click into the page, the way you would start writing on it, and type.
    var page = click("journalEditor")
    tryVerify(function() { return page.activeFocus }, 3000, "the page has the keyboard")
    key(Qt.Key_End, Qt.ControlModifier)
    type("x")
    compare(journal.bufferText.slice(-1), "x", "the keystroke reached the page")
    wait(2000) // the debounce, then the write
    compare(readFile(today), text + "x", "the day's text survives a keystroke")
  }
}
