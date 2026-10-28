import QtQuick

import "../../Parser.js" as Parser

// Bedtime and the night, on the engine's clock: "Time to sleep" at 21:45,
// the snoozes, the night's screen from 21:50, its journal page, and 05:30.
EngineTest {
  name: "night"

  function test_bedtime_ends_a_break_and_logs_it() {
    toBreak()
    engine.setNote("doneText", "d")
    var before = entries(dayLog()).length
    clockAt(0, 21, 46)
    compare(engine.phase, "bedtime", "21:45 puts up Time to sleep")
    verify(engine.overlayVisible)
    compare(engine.doneText, "", "on an empty page")
    tryVerify(function() { return entries(dayLog()).length === before + 1 }, 4000, "the cut-short break is logged")
    compare(entries(dayLog())[before].done, "d", "with its notes")
    engine.cycleMode()
    compare(engine.phase, "bedtime", "the mode can't be switched out of it")
  }

  function test_three_snoozes_of_a_minute() {
    clockAt(0, 21, 46)
    for (let n = 3; n > 0; n--) {
      compare(item("snoozeButton").label, "+1 minute (" + n + " left)")
      click("snoozeButton")
      compare(engine.phase, "snooze")
      verify(!engine.overlayVisible, "the overlay goes for a minute")
      verify(near(engine.remaining, 60))
      runOut()
      compare(engine.phase, "bedtime", "and comes back")
    }
    verify(!shows("snoozeButton"), "three is all")
    item("goodNightButton")
    verify(!shows("takeNotesButton"), "no notes before the night")
  }

  function test_22_20_starts_the_night_with_only_its_notes() {
    clockAt(0, 21, 46)
    click("snoozeButton")
    clockAt(0, 21, 51)
    compare(engine.phase, "sleep", "even mid-snooze")
    verify(engine.overlayVisible)
    verify(near(engine.remaining, 7 * 3600 + 39 * 60), "counting down to 05:30")
    verify(/^7:3[89]:\d\d$/.test(engine.countdownLabel), "in hours, minutes and seconds: " + engine.countdownLabel)
    item("takeNotesButton")
    verify(!shows("extendBreakButton:1") && !shows("snoozeButton") && !shows("goodNightButton"))
    key(Qt.Key_G, Qt.ControlModifier)
    verify(!overlay.goalPickerOpen, "and no goal picker")
  }

  function journalFile() { return "journal/" + Parser.dayKey(engine.now()) + ".md" }
  function editor() { return item("journalEditor") }

  // Take notes opens the day's journal on its text, with the caret at the
  // end, and what's typed is saved into the file itself -- the day file
  // gets nothing. A save Omvision made meanwhile isn't written over.
  function test_the_nights_page_is_the_days_journal() {
    clockAt(0, 21, 51)
    writeFile(journalFile(), "morning\n")
    var log = dayLog()
    click("takeNotesButton")
    tryVerify(function() { return editor().activeFocus && editor().text === "morning\n" }, 4000, "today's journal, focused")
    compare(editor().cursorPosition, editor().length, "the caret at the end")
    verify(!shows("noteSection:done"), "no questions")
    type("lights out")
    expectFile(journalFile(), "morning\nlights out", 4000, "saved as it's typed")
    compare(allEntries(log).length, 0, "nothing in the day file")

    key(Qt.Key_Escape)
    writeFile(journalFile(), "morning\nlights out\nfrom omvision")
    click("takeNotesButton")
    tryCompare(editor(), "text", "morning\nlights out\nfrom omvision", 4000, "a reopened page reads the file again")
    type(" too")
    writeFile(journalFile(), "changed in omvision")
    expectFile(journalFile(), "changed in omvision too", 4000,
               "a save made meanwhile is kept, with the page's typing after it")
    tryCompare(editor(), "text", "changed in omvision too", 4000, "the page shows it")
    compare(editor().cursorPosition, editor().length, "and writing goes on at the end")
  }

  // Qt drops a byte-order mark the helper would otherwise count as text, so
  // every save would look like the file had changed under it.
  function test_a_journal_with_a_byte_order_mark_still_saves() {
    clockAt(0, 21, 51)
    writeFile(journalFile(), "\ufeffmorning")
    click("takeNotesButton")
    tryCompare(editor(), "text", "morning", 4000)
    key(Qt.Key_End, Qt.ControlModifier)
    type(".")
    expectFile(journalFile(), "morning.", 4000)
    verify(!engine.journalFailed)
  }

  function test_skip_sleep_lasts_the_night() {
    clockAt(0, 21, 51)
    engine.skipSleep()
    compare(engine.phase, "focus")
    verify(!engine.overlayVisible)
    engine.tick()
    compare(engine.phase, "focus", "and stays ended")
  }

  function test_the_night_survives_a_deploy_at_any_hour() {
    clockAt(1, 1, 0)
    compare(engine.phase, "sleep", "a fresh engine after 21:50 goes straight to the night")
    writeFile(journalFile(), "late")
    click("takeNotesButton")
    tryCompare(editor(), "text", "late", 4000)
    var r = engine.restore(engine.snapshotJson())
    compare(r.indexOf("error"), -1, r)
    compare(engine.phase, "sleep")
    tryVerify(function() { return engine.journalLoaded && editor().text === "late" }, 4000, "the open page is read again")
  }

  function test_05_30_saves_the_page_and_starts_the_day() {
    clockAt(1, 1, 0)
    click("takeNotesButton")
    tryVerify(function() { return editor().activeFocus && engine.journalLoaded }, 4000, "the page, read")
    var file = journalFile()
    type("x")
    clockAt(1, 5, 31)
    compare(engine.phase, "focus", "05:30 starts a fresh run")
    verify(!engine.overlayVisible && !engine.notesOpen)
    verify(near(engine.remaining, engine.normalFocusSec))
    expectFile(file, function(t) { return /x$/.test(t) }, 4000, "typing left at 05:30 is saved")
  }

  // Bedtime is a hard limit, not a pomodoro: a timer switched off or paused
  // is no way around it.
  function test_the_timer_off_or_paused_is_no_way_around_it() {
    engine.cycleMode(); engine.cycleMode()
    compare(engine.mode, "off")
    verify(!engine.countdownRunning)
    clockAt(0, 21, 46)
    compare(engine.phase, "bedtime")
    verify(engine.overlayVisible)
    clockAt(0, 21, 51)
    compare(engine.phase, "sleep")
    clockAt(1, 5, 31)
    engine.cycleMode()
    engine.togglePause()
    verify(engine.mode === "normal" && engine.paused)
    clockAt(1, 21, 51)
    compare(engine.phase, "sleep")
    verify(!engine.paused)
  }
}
