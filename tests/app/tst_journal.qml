import QtQuick
import "../../Parser.js" as Parser

// Typing in the journal writes the day's file. The fixture has an entry for
// today (tests/fixtures/home/.../journal/TODAY.md, installed under today's
// date), and the journal always opens on today.
OmvisionTest {
  name: "journal"

  readonly property string today: "journal/" + Parser.dayKey(new Date()) + ".md"

  function openJournal() {
    app.currentScreen = "journal"
    tryCompare(journal, "bufferText", fixtureText(today), 5000)
  }

  function test_typing_writes_the_days_file() {
    openJournal()
    // The journal opens with the cursor at the end of the day's text.
    type("Then the charts.")
    expectFile(today, fixtureText(today) + "Then the charts.")
  }
}
