import QtQuick

import "../../Parser.js" as Parser

// Bedtime and the night, on the engine's clock: "Time to sleep" at 22:15,
// the snoozes, the night's screen from 22:20, its notes, and 05:30.
EngineTest {
  name: "night"

  function test_bedtime_ends_a_break_and_logs_it() {
    toBreak()
    engine.setNote("doneText", "d")
    var before = entries(dayLog()).length
    clockAt(0, 22, 16)
    compare(engine.phase, "bedtime", "22:15 puts up Time to sleep")
    verify(engine.overlayVisible)
    compare(engine.doneText, "", "on an empty page")
    tryVerify(function() { return entries(dayLog()).length === before + 1 }, 4000, "the cut-short break is logged")
    compare(entries(dayLog())[before].done, "d", "with its notes")
    engine.cycleMode()
    compare(engine.phase, "bedtime", "the mode can't be switched out of it")
  }

  function test_three_snoozes_of_a_minute() {
    clockAt(0, 22, 16)
    for (var n = 3; n > 0; n--) {
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
    clockAt(0, 22, 16)
    click("snoozeButton")
    clockAt(0, 22, 21)
    compare(engine.phase, "sleep", "even mid-snooze")
    verify(engine.overlayVisible)
    verify(near(engine.remaining, 7 * 3600 + 9 * 60), "counting down to 05:30")
    compare(engine.countdownLabel, "7:09", "in hours and minutes")
    item("takeNotesButton")
    verify(!shows("extendBreakButton:1") && !shows("snoozeButton") && !shows("goodNightButton"))
    key(Qt.Key_G, Qt.ControlModifier)
    verify(!overlay.goalPickerOpen, "and no goal picker")
  }

  // Each close of the page saves it to the day file, 0 minutes long, under
  // the night's one heading and id, and the page keeps its text.
  function test_the_nights_notes_are_saved_on_each_close() {
    clockAt(0, 22, 21)
    var log = dayLog()
    click("takeNotesButton")
    tryVerify(function() { return section("done").edit.activeFocus }, 4000, "the caret in What's done?")
    type("lights out")
    key(Qt.Key_Escape)
    compare(engine.phase, "sleep")
    tryVerify(function() { return allEntries(log).length === 1 }, 4000, "the night's notes are saved")
    var saved = allEntries(log)[0]
    compare(saved.minutes, 0)
    compare(saved.done, "lights out")
    compare(Parser.pomodoroCount([saved]), 0, "notes, not a pomodoro")
    tryCompare(engine, "sleepNotesSaved", ["lights out", "", ""])
    compare(engine.doneText, "lights out", "the page keeps its text")

    click("takeNotesButton")
    tryVerify(function() { return section("done").edit.activeFocus }, 4000, "the caret back")
    compare(section("done").edit.text, "lights out", "a reopened page shows the night's notes")
    key(Qt.Key_End, Qt.ControlModifier)
    type("\nand a book")
    key(Qt.Key_Escape)
    tryVerify(function() { return (readFile(log).match(/ · 0m$/mg) || []).length === 2 }, 4000, "saved again")
    var night = allEntries(log)
    compare(night.length, 1, "read as the one entry")
    compare(night[0].done, "lights out\nand a book")
    compare(night[0].id, saved.id, "under the same id")
    tryCompare(engine, "sleepNotesSaved", ["lights out\nand a book", "", ""])
    click("takeNotesButton")
    key(Qt.Key_Escape)
    wait(300)
    compare((readFile(log).match(/ · 0m$/mg) || []).length, 2, "a close that changed nothing appends nothing")
  }

  function test_skip_sleep_lasts_the_night() {
    clockAt(0, 22, 21)
    engine.skipSleep()
    compare(engine.phase, "focus")
    verify(!engine.overlayVisible)
    engine.tick()
    compare(engine.phase, "focus", "and stays ended")
  }

  function test_the_night_survives_a_deploy_at_any_hour() {
    clockAt(1, 1, 0)
    compare(engine.phase, "sleep", "a fresh engine after 22:20 goes straight to the night")
    engine.setNote("doneText", "late")
    var r = engine.restore(engine.snapshotJson())
    compare(r.indexOf("error"), -1, r)
    compare(engine.phase, "sleep")
    compare(engine.doneText, "late")
  }

  function test_05_30_saves_the_page_and_starts_the_day() {
    clockAt(1, 1, 0)
    click("takeNotesButton")
    tryVerify(function() { return section("done").edit.activeFocus }, 4000, "the caret in What's done?")
    type("x")
    var log = dayLog()
    clockAt(1, 5, 31)
    compare(engine.phase, "focus", "05:30 starts a fresh run")
    verify(!engine.overlayVisible && !engine.notesOpen)
    verify(near(engine.remaining, engine.normalFocusSec))
    tryVerify(function() { return allEntries(log).length === 1 }, 4000, "notes left open at 05:30 are saved")
  }

  // Bedtime is a hard limit, not a pomodoro: a timer switched off or paused
  // is no way around it.
  function test_the_timer_off_or_paused_is_no_way_around_it() {
    engine.cycleMode(); engine.cycleMode()
    compare(engine.mode, "off")
    verify(!engine.countdownRunning)
    clockAt(0, 22, 16)
    compare(engine.phase, "bedtime")
    verify(engine.overlayVisible)
    clockAt(0, 22, 21)
    compare(engine.phase, "sleep")
    clockAt(1, 5, 31)
    engine.cycleMode()
    engine.togglePause()
    verify(engine.mode === "normal" && engine.paused)
    clockAt(1, 22, 21)
    compare(engine.phase, "sleep")
    verify(!engine.paused)
  }
}
