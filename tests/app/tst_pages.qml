import QtQuick

// The journal's page turns: `‹`/`›` in its header, Alt+←/→ and Ctrl+PgUp/PgDn.
// One page per day with an entry, never past today, and each turned page
// opens at its top. The fixture has only today's entry, so each test writes
// the older days it needs (the reset before the next test deletes them) and
// waits for the journal to list them.
OmvisionTest {
  name: "pages"

  // Long enough to scroll well past one screen.
  readonly property string longDay: {
    var t = "# A long day\n"
    for (var i = 1; i <= 60; i++) t += "\nParagraph " + i + ", and a line or two more of what happened.\n"
    return t
  }

  // A disabled control can't be click()ed (it waits for it to be enabled),
  // so this clicks it the way a user would anyway.
  function clickDisabled(name) {
    var it = item(name)
    verify(!it.enabled, name + " is disabled")
    mouseClick(it, it.width / 2, it.height / 2)
  }

  function test_pages_go_back_and_stop_at_both_ends() {
    // A day file dated ahead of today (a hand edit, a wrong clock) is in
    // the day list, but it is not a page `›` turns to.
    var days = addDays({ 3: "# Three days ago\n", 1: "# Yesterday\n", "-2": "# Ahead of time\n" })
    openJournal()
    tryVerify(function() { return item("prevDayButton").enabled }, 3000, "there is a page before today")
    verify(!item("nextDayButton").enabled, "there is no page after today, even with a later file")

    click("prevDayButton")
    tryCompare(journal, "selectedPath", days[1])
    tryCompare(journal, "bufferText", "# Yesterday\n")
    // Two days ago has no entry, so no page: the next one back is three.
    click("prevDayButton")
    tryCompare(journal, "selectedPath", days[3])
    tryVerify(function() { return !item("prevDayButton").enabled }, 3000, "the oldest page has nothing before it")
    clickDisabled("prevDayButton")
    compare(journal.selectedPath, days[3], "back from the oldest page goes nowhere")

    click("nextDayButton")
    tryCompare(journal, "selectedPath", days[1])
    click("nextDayButton")
    tryCompare(journal, "selectedPath", journal.todayPath)
    tryCompare(journal, "bufferText", fixtureText(today))
    tryVerify(function() { return !item("nextDayButton").enabled }, 3000, "today is the last page")
    clickDisabled("nextDayButton")
    compare(journal.selectedPath, journal.todayPath, "forward from today goes nowhere")
    compare(item("journalEditor").cursorPosition, 0, "and the click didn't fall through to the text")

    // Turning pages reads; it writes nothing.
    compare(readFile(today), fixtureText(today), "today's file is untouched")
    compare(readFile(days[1]), "# Yesterday\n", "yesterday's file is untouched")
  }

  function test_a_turned_page_starts_at_its_top() {
    var days = addDays({ 1: longDay, 2: "# Two days ago\n" })
    openJournal()
    var canvas = item("journalCanvas")
    var page = item("journalEditor")

    click("prevDayButton")
    tryCompare(journal, "selectedPath", days[1])
    tryCompare(canvas, "contentY", 0)
    compare(page.cursorPosition, 0, "the cursor is on the page's first character")

    // Read down to the end of the day, then turn away and back.
    key(Qt.Key_End, Qt.ControlModifier)
    tryVerify(function() { return canvas.contentY > 0 }, 3000, "the long day scrolled down")
    click("prevDayButton")
    tryCompare(journal, "selectedPath", days[2])
    tryCompare(canvas, "contentY", 0)
    click("nextDayButton")
    tryCompare(journal, "selectedPath", days[1])
    // Not scrolled back down to where the last visit left off, once the
    // page has finished arriving.
    tryCompare(page, "opacity", 1)
    compare(canvas.contentY, 0, "the page is back at its top")
    compare(page.cursorPosition, 0, "and so is the cursor")
  }

  function test_ctrl_page_keys_turn_pages() {
    var days = addDays({ 1: "# Yesterday\n" })
    openJournal()
    var page = item("journalEditor")
    tryVerify(function() { return page.activeFocus }, 3000, "the page has the keyboard")
    key(Qt.Key_PageUp, Qt.ControlModifier)
    tryCompare(journal, "selectedPath", days[1])
    tryCompare(journal, "bufferText", "# Yesterday\n")
    key(Qt.Key_PageDown, Qt.ControlModifier)
    tryCompare(journal, "selectedPath", journal.todayPath)
    tryCompare(journal, "bufferText", fixtureText(today))
  }

  function test_alt_arrows_turn_pages() {
    var days = addDays({ 1: "# Yesterday\n" })
    openJournal()
    var page = item("journalEditor")
    tryVerify(function() { return page.activeFocus }, 3000, "the page has the keyboard")
    key(Qt.Key_Left, Qt.AltModifier)
    tryCompare(journal, "selectedPath", days[1])
    tryCompare(journal, "bufferText", "# Yesterday\n")
    compare(page.cursorPosition, 0, "the turned page starts at its top")
    key(Qt.Key_Right, Qt.AltModifier)
    tryCompare(journal, "selectedPath", journal.todayPath)
    tryCompare(journal, "bufferText", fixtureText(today))
    // On the last page Alt+→ is a no-op, and it moves nothing in the text.
    key(Qt.Key_Right, Qt.AltModifier)
    compare(journal.selectedPath, journal.todayPath, "forward from today goes nowhere")
    compare(journal.bufferText, fixtureText(today), "and typed nothing")
  }
}
