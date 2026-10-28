import QtQuick

// A run, its prompt and its break, through the overlay: the buttons, the
// goal picker, and the entry the break's end has the real helper write.
EngineTest {
  name: "break"

  function test_comes_up_in_a_stamped_run_with_the_overlay_down() {
    compare(engine.phase, "focus")
    verify(!engine.overlayVisible)
    verify(engine.focusStartedIso.length > 0, "stamped, or the helper would refuse its entry")
  }

  function test_a_mode_switch_at_the_prompt_logs_the_run() {
    runOut()
    var before = entries(dayLog()).length
    engine.cycleMode()
    compare(engine.mode, "long")
    compare(engine.phase, "focus", "a fresh run, no overlay")
    compare(engine.remaining, engine.longFocusSec)
    tryVerify(function() { return entries(dayLog()).length === before + 1 }, 4000,
              "the run switched away from at the prompt is logged")
  }

  function test_the_breaks_countdown_and_its_extensions() {
    toBreak()
    verify(near(engine.remaining, 300), "a 5 minute break: " + engine.remaining)
    verify(!engine.breakIsLong)
    click("extendBreakButton:2")
    verify(near(engine.remaining, 420), "+2 min lengthens it: " + engine.remaining)
  }

  function test_the_goal_picker_offers_the_open_focusable_goals() {
    toBreak()
    tryVerify(function() { return engine.goalsList.length === 3 }, 4000, "the goal list")
    key(Qt.Key_G, Qt.ControlModifier)
    verify(overlay.goalPickerOpen, "Ctrl+G opens the picker")
    item("pickGoal:write-the-report")
    verify(!shows("pickGoal:train-legs"), "and leaves out the `focusable: no` one")
    verify(!shows("pickGoal:old-milestone"), "and the done one")
    key(Qt.Key_Escape)
    verify(!overlay.goalPickerOpen, "Escape closes it")
    compare(engine.phase, "break")
    key(Qt.Key_G, Qt.ControlModifier)
    click("pickGoal:write-the-report")
    verify(!overlay.goalPickerOpen)
    compare(engine.activeGoalSlug, "write-the-report")
    compare(engine.runGoalSlug, "", "the finished run keeps the goal it ran on (none)")
    expectFile(activeGoalPath, "write-the-report\n", 4000, "the pick is written to active-goal")
  }

  function test_the_breaks_end_logs_its_run_with_its_notes() {
    var started = engine.focusStartedIso
    toBreak()
    click("takeNotesButton")
    tryVerify(function() { return section("done").edit.activeFocus }, 4000, "the caret in Done")
    type("- one\ntwo")
    key(Qt.Key_Escape)
    var before = entries(dayLog()).length
    endBreak()
    verify(!engine.overlayVisible)
    compare(engine.doneText, "", "the next run starts with an empty page")
    verify(near(engine.remaining, engine.normalFocusSec))
    tryVerify(function() { return entries(dayLog()).length === before + 1 }, 4000, "the run is logged")
    var logged = entries(dayLog())[before]
    compare(logged.done, "- one\n- two", "Parser.js reads the notes back as written")
    compare(logged.id, started, "under the run's own id")
    compare(logged.minutes, 25)
  }

  function test_a_run_on_a_goal_is_logged_to_its_log() {
    toBreak()
    tryVerify(function() { return engine.canPickGoal }, 4000, "the goal list")
    key(Qt.Key_G, Qt.ControlModifier)
    click("pickGoal:write-the-report")
    var before = entries(goalLog).length
    endBreak()
    toBreak()
    endBreak()
    tryVerify(function() { return entries(goalLog).length === before + 1 }, 4000,
              "the run after the pick goes to the goal's log, the one before it didn't")
  }

  function test_every_fourth_break_is_long() {
    for (let n = 1; n <= 3; n++) {
      toBreak()
      verify(!engine.breakIsLong, "break " + n + " is short")
      endBreak()
    }
    toBreak()
    verify(engine.breakIsLong && near(engine.remaining, 900), "the 4th is 15 minutes: " + engine.remaining)
    item("extendBreakButton:1")
  }

  function test_a_refused_write_holds_the_break_until_skipped() {
    toBreak()
    engine.runGoalSlug = "../not-a-slug"
    runOut()
    tryVerify(function() { return engine.notesSaveFailed }, 4000, "the helper refuses the entry")
    compare(engine.phase, "break", "the break holds at 0:00")
    verify(engine.overlayVisible)
    item("notesNotSaved")
    item("tryAgainButton")
    verify(!shows("extendBreakButton:1"), "Try again instead of extensions")
    click("skipButton")
    compare(engine.phase, "focus", "Skip starts the next run")
    verify(!engine.notesSaveFailed)
  }

  // Cycle.js cuts a note too long for the helper to fit (tst_cycle.qml); the
  // limit it cuts to has to be the helper's.
  function test_the_engines_note_limit_is_the_helpers() {
    var m = (readFile(engine.notesHelperPath) || "").match(/^MAX_NOTE_INPUT_BYTES = ([\d_]+)/m)
    verify(m !== null, "notes-helper.py states its limit")
    compare(Number(m[1].replace(/_/g, "")), engine.maxNoteInputBytes)
  }

  // A break handed over by a deploy comes up with its notes on screen, and
  // reads the goal list it started with in another process.
  function test_a_restored_break_shows_its_notes() {
    var brk = Object.assign(JSON.parse(engine.snapshotJson()), {
      phase: "break", endsAtMs: engine.now().getTime() + 100000, heldSec: 100, extensionsUsed: 1,
      focusStartedIso: "2026-10-13T10:00:00", notesOpen: true, doneText: "d" })
    var r = engine.restore(JSON.stringify(brk))
    compare(r.indexOf("error"), -1, r)
    tryVerify(function() { return engine.goalsList.length > 0 }, 4000, "the goal list")
    compare(engine.phase, "break")
    verify(engine.overlayVisible)
    tryCompare(section("done").edit, "text", "d")
    verify(near(engine.remaining, 100))
    var bad = engine.restore("{}")
    compare(bad.indexOf("error"), 0, "a bad snapshot is refused")
    compare(engine.doneText, "d", "and changes nothing")
  }
}
