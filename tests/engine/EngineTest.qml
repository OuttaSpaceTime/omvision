import QtQuick

import "../lib"
import "../../Parser.js" as Parser
import "../../plugins/ompom.engine/Cycle.js" as Cycle

// The base type of every engine test (tests/engine/tst_*.qml): a QsTestCase
// (tests/lib/QsTestCase.qml) loaded beside the real ompom engine and its
// overlay by tests/engine/run.sh, with the real notes-helper.py writing into
// the throwaway HOME. The rules are tests/unit/tst_cycle.qml's; these are
// for the wiring: clicks and keys on the overlay, and the bytes the helper
// writes, read back with the app's own Parser.js.
//
// Time moves by moving the engine's clock (clockOffsetMs) and calling its
// tick(), the function its one-second Timer calls. Before every test the
// fixture is put back (tests/fixtures/home, and tests/fixtures/engine's two
// goals the picker must leave out), and the engine is back on a fresh run
// at noon today, with no goal and nothing open.
//
// What a test file gets, besides QsTestCase's helpers:
//   engine, overlay               set by run.sh
//   clockAt(days, hh, mm)         the engine's clock to hh:mm, `days` from
//                                 today, and a tick
//   advance(sec), runOut()        time moves on, by `sec` or to the end of
//                                 the countdown, and a tick
//   toBreak(), endBreak()         the run to its prompt and "Start break";
//                                 the break to its end and the next run
//   section(key)                  the notes page's "done", "left" or "else"
//   entries(rel), allEntries(rel) a log's pomodoros, or all its entries
//   dayLog()                      the day file for the engine's clock
//   goalLog                       write-the-report's log
QsTestCase {
  id: base

  property var engine: null
  property var overlay: null

  readonly property string goalLog: "goals/write-the-report.log.md"
  readonly property string activeGoalPath: home + "/.local/state/omvision/active-goal"

  function dayLog() { return "days/" + Parser.dayKey(engine.now()) + ".md" }
  function allEntries(rel) { return Parser.parseLogEntries(readFile(rel) || "", new Date()) }
  function entries(rel) { return allEntries(rel).filter(function(e) { return e.type === "pomodoro" }) }

  function section(key) { return item("noteSection:" + key) }

  function clockAt(days, hh, mm) {
    var d = new Date()
    d.setDate(d.getDate() + days)
    d.setHours(hh, mm, 0, 0)
    engine.clockOffsetMs = d.getTime() - Date.now()
    engine.tick()
  }

  // Each run so starts at a time of its own, as real ones do, and its log
  // entry has an id of its own.
  function advance(sec) {
    engine.clockOffsetMs += sec * 1000
    engine.tick()
  }
  function runOut() { advance(engine.remaining) }

  function toBreak() {
    runOut()
    compare(engine.phase, "prompt", "the run ends on the prompt")
    click("startBreakButton")
    compare(engine.phase, "break", "Start break starts the break")
  }

  function endBreak() {
    runOut()
    tryCompare(engine, "phase", "focus", 4000, "the next run")
  }

  // A seconds count that can be a moment short of `want`, as the clock
  // never stops.
  function near(value, want) { return value <= want && value >= want - 5 }

  function resetFixture() {
    resetHome()
    // A break's write from the test before lands before anything else.
    tryVerify(function() { return !engine.notesSavePending }, 4000, "the last test's write")
    var noon = new Date()
    noon.setHours(12, 0, 0, 0)
    engine.clockOffsetMs = noon.getTime() - Date.now()
    // A fresh engine's state, then a fresh run from noon on it.
    compare(engine.restore(JSON.stringify(Cycle.snapshot(Cycle.fresh(), engine.now().getTime()))).indexOf("error"), -1,
            "the engine took the fresh state")
    engine.resetRun()
    if (engine.activeGoalSlug !== "") {
      engine.chooseGoal("")
      expectFile(activeGoalPath, "\n", 4000, "no goal")
    }
    engine.goalsList = []
    overlay.goalPickerOpen = false
  }
}
