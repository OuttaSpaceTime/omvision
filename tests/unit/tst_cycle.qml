import QtQuick
import QtTest

import "../../plugins/ompom.engine/Cycle.js" as Cycle

// The ompom engine's rules (Cycle.js), with no engine around them: a state,
// a clock that only moves when a test moves it, and the effects each event
// asks for. tests/engine runs the real engine and overlay on top of these,
// for the wiring: clicks, keys, and what the helper really writes.
TestCase {
  name: "Cycle"

  // Noon on a Friday, local time.
  readonly property real noon: new Date(2026, 9, 16, 12, 0, 0).getTime()
  function at(h, m, dayOffset) { return new Date(2026, 9, 16 + (dayOffset || 0), h, m, 0).getTime() }

  function ctx(nowMs, busy) {
    return { nowMs: nowMs, durations: Cycle.DURATIONS, busy: busy || { finishedLog: false, sleepSave: false } }
  }

  // A fresh engine at `nowMs`, as Engine.qml starts one.
  function started(nowMs) {
    var s = Cycle.fresh()
    Cycle.startNextRun(s, ctx(nowMs))
    return s
  }

  // Ticks at `nowMs` and returns the effects.
  function tickAt(s, nowMs, busy) { return Cycle.tick(s, ctx(nowMs, busy)) }

  // A run started at `t` taken to its prompt, then into its break; returns
  // the time the break started.
  function toBreak(s, t) {
    var end = t + Cycle.focusSec(s, Cycle.DURATIONS) * 1000
    tickAt(s, end)
    compare(s.phase, "prompt")
    Cycle.startBreak(s, ctx(end))
    compare(s.phase, "break")
    return end
  }

  function logs(fx) { return fx.filter(function(e) { return e.type === "log" }) }

  // ---- the run ------------------------------------------------------------------
  function test_a_fresh_run_counts_down_by_the_clock() {
    var s = started(noon)
    compare(s.phase, "focus")
    compare(s.focusStartedIso, "2026-10-16T12:00:00")
    compare(Cycle.remainingSec(s, noon), 25 * 60)
    compare(Cycle.remainingSec(s, noon + 1000), 25 * 60 - 1)
    compare(Cycle.remainingSec(s, noon + 1500), 25 * 60 - 1, "a part second still counts as one left")
    compare(tickAt(s, noon + 24 * 60 * 1000), [])
    compare(s.phase, "focus", "not over a minute early")
  }

  function test_the_end_of_a_run_is_the_prompt_and_extensions_are_capped() {
    var s = started(noon)
    var t = noon + 25 * 60 * 1000
    tickAt(s, t)
    compare(s.phase, "prompt")
    compare(Cycle.overlayVisible(s), true)
    for (var i = 1; i <= Cycle.MAX_EXTENSIONS; i++) {
      Cycle.addExtension(s, ctx(t))
      compare(s.phase, "extend")
      compare(Cycle.remainingSec(s, t), 60)
      t += 60 * 1000
      tickAt(s, t)
      compare(s.phase, "prompt", "extension " + i + " ends on the prompt")
    }
    Cycle.addExtension(s, ctx(t))
    compare(s.phase, "prompt", "a fourth is refused")
    compare(Cycle.finishedRunMinutes(s, Cycle.DURATIONS), 28)
  }

  function test_pausing_holds_the_time_left() {
    var s = started(noon)
    Cycle.togglePause(s, ctx(noon + 60 * 1000))
    compare(s.paused, true)
    compare(Cycle.remainingSec(s, noon + 3600 * 1000), 24 * 60, "an hour paused takes nothing off")
    tickAt(s, noon + 3600 * 1000)
    compare(s.phase, "focus")
    Cycle.togglePause(s, ctx(noon + 3600 * 1000))
    compare(s.paused, false)
    compare(Cycle.remainingSec(s, noon + 3660 * 1000), 23 * 60, "and it runs on from where it was")
  }

  function test_a_suspend_moves_the_end_on() {
    var s = started(noon)
    var gap = 40 * 60 * 1000
    Cycle.resumed(s, ctx(noon + gap), gap)
    tickAt(s, noon + gap)
    compare(s.phase, "focus", "a run the laptop slept through hasn't happened")
    compare(Cycle.remainingSec(s, noon + gap), 25 * 60)
  }

  function test_the_timer_off_holds_still_and_modes_cycle() {
    var s = started(noon)
    Cycle.cycleMode(s, ctx(noon))
    compare(s.mode, "long")
    compare(Cycle.remainingSec(s, noon), 50 * 60)
    Cycle.cycleMode(s, ctx(noon))
    compare(s.mode, "off")
    compare(Cycle.countdownRunning(s), false)
    compare(Cycle.remainingSec(s, noon + 3600 * 1000), 25 * 60)
    tickAt(s, noon + 3600 * 1000)
    compare(s.phase, "focus")
    compare(Cycle.overlayVisible(s), false)
    Cycle.cycleMode(s, ctx(noon + 3600 * 1000))
    compare(s.mode, "normal")
    compare(Cycle.remainingSec(s, noon + 3600 * 1000), 25 * 60, "back on, a fresh run from now")
  }

  function test_a_mode_switch_logs_a_finished_run_on_the_way_out() {
    var s = started(noon)
    s.activeGoalSlug = "write-the-report"
    tickAt(s, noon + 25 * 60 * 1000)
    var fx = Cycle.cycleMode(s, ctx(noon + 25 * 60 * 1000))
    compare(logs(fx).length, 1)
    compare(logs(fx)[0].via, "finished")
    compare(logs(fx)[0].slug, "write-the-report")
    compare(JSON.parse(logs(fx)[0].entry), { started: "2026-10-16T12:00:00", minutes: 25, done: "", left: "", "else": "" })
    compare(s.phase, "focus")

    var busy = started(noon)
    tickAt(busy, noon + 25 * 60 * 1000)
    fx = Cycle.cycleMode(busy, ctx(noon + 25 * 60 * 1000, { finishedLog: true, sleepSave: false }))
    compare(logs(fx).length, 0, "a write still running isn't doubled up")
    compare(fx[0].type, "warn", "but warned about")
  }

  function test_a_mode_switch_mid_run_or_in_a_break_does_nothing_or_logs_nothing() {
    var s = started(noon)
    compare(logs(Cycle.cycleMode(s, ctx(noon + 60 * 1000))), [], "a run cut short isn't a pomodoro")
    Cycle.cycleMode(s, ctx(noon)); Cycle.cycleMode(s, ctx(noon))
    toBreak(s, noon)
    Cycle.cycleMode(s, ctx(noon + 26 * 60 * 1000))
    compare(s.phase, "break", "no mode switch out of a break")
    compare(s.mode, "normal")
  }

  // ---- the break -----------------------------------------------------------------
  function test_every_fourth_normal_break_is_long() {
    var s = started(noon), t = noon
    for (var n = 1; n <= 4; n++) {
      t = toBreak(s, t)
      compare(s.breakIsLong, n === 4, "break " + n)
      compare(Cycle.remainingSec(s, t), n === 4 ? 15 * 60 : 5 * 60)
      Cycle.startNextRun(s, ctx(t))
    }
    compare(s.runsInSet, 0, "the set starts again")
  }

  function test_a_new_day_starts_a_new_set() {
    var s = started(noon)
    toBreak(s, noon); Cycle.startNextRun(s, ctx(noon))
    toBreak(s, noon); Cycle.startNextRun(s, ctx(noon))
    compare(s.runsInSet, 2)
    var tomorrow = at(9, 0, 1)
    Cycle.startNextRun(s, ctx(tomorrow))
    toBreak(s, tomorrow)
    compare(s.runsInSet, 1)
    compare(s.setDay, "2026-10-17")
  }

  function test_long_focus_has_long_breaks_and_no_set() {
    var s = started(noon)
    Cycle.cycleMode(s, ctx(noon))
    var t = toBreak(s, noon)
    compare(Cycle.remainingSec(s, t), 10 * 60)
    compare(s.runsInSet, 0)
  }

  function test_the_break_end_logs_its_run_then_starts_the_next() {
    var s = started(noon)
    s.activeGoalSlug = "write-the-report"
    var t = toBreak(s, noon)
    compare(s.runGoalSlug, "write-the-report", "pinned when the break starts")
    Cycle.chooseGoal(s, ctx(t), "other-goal")
    compare(s.runGoalSlug, "write-the-report", "a goal picked in the break is the next run's")
    s.doneText = "- one\n- two"
    Cycle.extendBreak(s, ctx(t), 2)
    compare(Cycle.remainingSec(s, t), 7 * 60)
    var end = t + 7 * 60 * 1000
    var fx = tickAt(s, end)
    compare(logs(fx).length, 1)
    compare(logs(fx)[0].via, "note")
    compare(logs(fx)[0].slug, "write-the-report")
    compare(JSON.parse(logs(fx)[0].entry).done, "- one\n- two")
    compare(s.notesSavePending, true)
    compare(logs(tickAt(s, end + 1000)), [], "nothing more while it runs")
    Cycle.noteLogExited(s, ctx(end + 1000), 0, logs(fx)[0].cycle, "")
    compare(s.phase, "focus")
    compare(s.doneText, "", "the next run starts with an empty page")
    compare(s.activeGoalSlug, "other-goal")
  }

  function test_a_refused_write_holds_the_break_until_skipped() {
    var s = started(noon)
    var t = toBreak(s, noon) + 5 * 60 * 1000
    var fx = tickAt(s, t)
    Cycle.noteLogExited(s, ctx(t), 2, logs(fx)[0].cycle, "")
    compare(s.notesSaveFailed, true)
    compare(s.phase, "break")
    tickAt(s, t + 60 * 1000)
    compare(s.phase, "break", "it holds at 0:00")
    Cycle.extendBreak(s, ctx(t), 1)
    compare(Cycle.remainingSec(s, t), 0, "and isn't stretched to put the failure off")
    fx = Cycle.saveNote(s, ctx(t))
    compare(logs(fx).length, 1, "Try again writes again")
    Cycle.noteLogExited(s, ctx(t), 2, logs(fx)[0].cycle, "")
    fx = Cycle.skipUnsavedNotes(s, ctx(t))
    compare(fx[0].type, "warn", "Skip leaves the entry in the shell's log")
    compare(s.phase, "focus")
  }

  function test_a_write_from_an_older_cycle_changes_nothing() {
    var s = started(noon)
    var fx = tickAt(s, toBreak(s, noon) + 5 * 60 * 1000)
    var stale = logs(fx)[0].cycle
    Cycle.resetRun(s, ctx(noon + 3600 * 1000))
    fx = Cycle.noteLogExited(s, ctx(noon + 3600 * 1000), 2, stale, "{}")
    compare(s.notesSaveFailed, false)
    compare(fx[0].type, "warn")
  }

  function test_a_goal_changed_mid_run_gets_only_the_rest_of_it() {
    var s = started(noon)
    Cycle.activeGoalRead(s, ctx(noon), "first", false)
    compare(s.goalAttributionRemaining, -1, "the file's first read isn't a change")
    Cycle.activeGoalRead(s, ctx(noon + 10 * 60 * 1000), "second", true)
    compare(s.goalAttributionRemaining, 15 * 60)
    compare(Cycle.finishedRunMinutes(s, Cycle.DURATIONS), 15)
    Cycle.activeGoalRead(s, ctx(noon + 12 * 60 * 1000), "", true)
    compare(s.goalAttributionRemaining, -1, "no goal goes back to the whole run, for the day file")
  }

  function test_notes_open_only_where_there_is_a_page() {
    var s = started(noon)
    Cycle.openNotes(s, ctx(noon))
    compare(s.notesOpen, false)
    toBreak(s, noon)
    Cycle.openNotes(s, ctx(noon))
    compare(s.notesOpen, true)
    compare(Cycle.closeNotes(s, ctx(noon)), [], "closing a break's page writes nothing")
    compare(s.notesOpen, false)
  }

  // ---- the night -----------------------------------------------------------------
  function test_bedtime_ends_whatever_runs() {
    var s = started(at(22, 0))
    s.doneText = "x"
    var fx = tickAt(s, at(22, 15))
    compare(s.phase, "bedtime")
    compare(logs(fx), [], "a run cut short isn't logged")
    compare(s.doneText, "")
    compare(Cycle.overlayVisible(s), true)

    var p = started(at(21, 49))
    p.activeGoalSlug = "g"
    tickAt(p, at(22, 15) - 1000)
    compare(p.phase, "prompt")
    fx = tickAt(p, at(22, 15))
    compare(logs(fx).length, 1, "a finished run at its prompt is logged first")
    compare(logs(fx)[0].slug, "g")

    var b = started(at(21, 40))
    toBreak(b, at(21, 40))
    b.leftText = "tomorrow"
    fx = tickAt(b, at(22, 16))
    compare(JSON.parse(logs(fx)[0].entry).left, "tomorrow", "and a break's with its notes")
  }

  function test_snoozes_then_the_night() {
    var s = started(at(22, 0))
    tickAt(s, at(22, 15))
    for (var n = 0; n < Cycle.MAX_SNOOZES; n++) {
      Cycle.snooze(s, ctx(at(22, 15)))
      compare(s.phase, "snooze")
      compare(Cycle.overlayVisible(s), false)
      compare(Cycle.barLabel(s, at(22, 15) + 18 * 1000), "sleep in 00:42")
      tickAt(s, at(22, 16))
      compare(s.phase, "bedtime")
    }
    Cycle.snooze(s, ctx(at(22, 16)))
    compare(s.phase, "bedtime", "three is all")
    s.snoozesUsed = 0
    Cycle.snooze(s, ctx(at(22, 19)))
    tickAt(s, at(22, 20))
    compare(s.phase, "sleep", "22:20 starts the night even mid-snooze")
    compare(Cycle.remainingSec(s, at(22, 20)), 7 * 3600 + 10 * 60)
    compare(Cycle.countdownLabel(s, at(22, 20)), "7:10")
    compare(Cycle.countdownLabel(s, at(22, 20) + 1000), "7:10", "minutes rounded up")
    compare(Cycle.countdownLabel(s, at(5, 29, 1) + 30 * 1000), "0:01")
    compare(Cycle.barLabel(s, at(22, 20)), "sleep")
    compare(Cycle.cycleMode(s, ctx(at(22, 30))), [])
    compare(s.phase, "sleep", "no mode switch out of it")
  }

  function test_the_night_holds_with_the_timer_off_or_paused() {
    var s = started(noon)
    Cycle.cycleMode(s, ctx(noon)); Cycle.cycleMode(s, ctx(noon))
    compare(s.mode, "off")
    tickAt(s, at(22, 21))
    compare(s.phase, "sleep")
    var p = started(noon)
    Cycle.togglePause(p, ctx(noon))
    tickAt(p, at(22, 21))
    compare(p.phase, "sleep")
    compare(p.paused, false)
  }

  function test_the_night_notes_are_saved_whole_on_each_close_that_changed_them() {
    var s = started(at(22, 0))
    tickAt(s, at(22, 21))
    Cycle.openNotes(s, ctx(at(22, 30)))
    s.doneText = "lights out"
    var fx = Cycle.closeNotes(s, ctx(at(22, 31)))
    compare(logs(fx).length, 1)
    compare(logs(fx)[0].slug, "", "the day file")
    compare(JSON.parse(logs(fx)[0].entry), { started: "2026-10-16T22:31:00", minutes: 0, done: "lights out", left: "", "else": "" })
    Cycle.sleepNoteExited(s, ctx(at(22, 31)), 0, logs(fx)[0].cycle, "", logs(fx)[0].saved)
    compare(s.sleepNotesSaved, ["lights out", "", ""])
    compare(s.doneText, "lights out", "the page keeps its text")
    compare(Cycle.closeNotes(s, ctx(at(22, 40))), [], "a close that changed nothing appends nothing")
    s.doneText = "lights out\nand a book"
    fx = Cycle.closeNotes(s, ctx(at(23, 0)))
    compare(JSON.parse(logs(fx)[0].entry).started, "2026-10-16T22:31:00", "under the night's one stamp")
    compare(logs(Cycle.closeNotes(s, ctx(at(23, 1), { finishedLog: false, sleepSave: true }))), [],
            "a save still running takes the text with the next close")
    Cycle.sleepNoteExited(s, ctx(at(23, 1)), 1, logs(fx)[0].cycle, "", logs(fx)[0].saved)
    compare(s.notesSaveFailed, true)
  }

  function test_05_30_saves_the_page_and_starts_the_day() {
    var s = started(at(22, 0))
    tickAt(s, at(22, 21))
    s.elseText = "dream"
    var fx = tickAt(s, at(5, 31, 1))
    compare(logs(fx).length, 1)
    compare(s.phase, "focus")
    compare(s.elseText, "")
    compare(Cycle.remainingSec(s, at(5, 31, 1)), 25 * 60)
    compare(Cycle.overlayVisible(s), false)
  }

  function test_skip_sleep_lasts_the_night() {
    var s = started(at(22, 0))
    tickAt(s, at(23, 0))
    compare(s.phase, "sleep")
    Cycle.skipSleep(s, ctx(at(23, 0)))
    compare(s.phase, "focus")
    tickAt(s, at(2, 0, 1))
    compare(Cycle.atNight(s), false, "the rest of this night")
    tickAt(s, at(22, 21, 1))
    compare(s.phase, "sleep", "and the next one as usual")
  }

  function test_after_lights_out_a_fresh_engine_goes_straight_to_the_night() {
    var s = started(at(1, 0, 1))
    tickAt(s, at(1, 0, 1))
    compare(s.phase, "sleep")
  }

  // ---- labels ----------------------------------------------------------------------
  function test_labels() {
    compare(Cycle.fmt(0), "00:00")
    compare(Cycle.fmt(299), "04:59")
    compare(Cycle.fmt(3 * 3600 + 61), "3:01:01")
    var s = started(noon)
    compare(Cycle.barLabel(s, noon + 1000), "24:59")
    toBreak(s, noon)
    compare(Cycle.barLabel(s, noon + 26 * 60 * 1000), "break 04:00")
    var off = started(noon)
    Cycle.cycleMode(off, ctx(noon)); Cycle.cycleMode(off, ctx(noon))
    compare(Cycle.barLabel(off, noon), "")
    compare(Cycle.status(s, noon + 26 * 60 * 1000).label, "break 04:00")
  }

  function test_the_picker_offers_open_focusable_goals() {
    var goals = [
      { slug: "a", title: "A", status: "active", focusable: true },
      { slug: "b", title: "B", status: "active", focusable: false },
      { slug: "c", title: "C", status: "done", focusable: true },
      { slug: "d", title: "D", status: null },
      { slug: "e", title: "E", status: "cancelled" }
    ]
    compare(Cycle.pickableGoals(goals).map(function(g) { return g.slug }), ["a", "d"])
    compare(Cycle.goalTitle(goals, "b"), "B", "a goal left out still has its title")
    compare(Cycle.goalTitle(goals, "zz"), "")
  }

  // ---- the log entry -----------------------------------------------------------------
  function test_an_oversized_note_is_cut_to_the_helpers_limit() {
    var big = Cycle.entryJson("2026-10-13T10:00:00", 25, ["", "", new Array(30001).join("ä")])
    verify(Cycle.utf8Bytes(big) <= Cycle.MAX_NOTE_INPUT_BYTES)
    compare(JSON.parse(big)["else"].slice(-1), "…")
    for (var cut = 0; cut < 4; cut++) {
      var kept = JSON.parse(Cycle.entryJson("2026-10-13T10:00:00", 25,
                                            ["", "", new Array(cut + 1).join("a") + new Array(6001).join("😀")]))["else"]
      verify(!/[\uD800-\uDBFF]…$/.test(kept), "never through an emoji, at offset " + cut)
    }
  }

  // ---- the hand-off ------------------------------------------------------------------
  function test_a_snapshot_round_trips_and_the_time_runs_on() {
    var s = started(noon)
    toBreak(s, noon)
    s.doneText = "d"
    s.runsInSet = 3
    var json = JSON.stringify(Cycle.snapshot(s, noon + 26 * 60 * 1000))
    var t = started(noon + 26 * 60 * 1000 + 3000)
    var r = Cycle.restore(t, ctx(noon + 26 * 60 * 1000 + 3000), json)
    compare(r.error, "")
    compare(t.phase, "break")
    compare(t.doneText, "d")
    compare(t.runsInSet, 3)
    compare(Cycle.remainingSec(t, noon + 26 * 60 * 1000 + 3000), 4 * 60 - 3, "the restart's seconds are gone, with no correction")
    compare(r.fx, [{ type: "listGoals" }], "a break restored reads the goal list")
    verify(t.cycle > 1, "a write from before the hand-off is stale")
  }

  function test_a_bad_snapshot_changes_nothing() {
    var s = started(noon)
    var before = JSON.stringify(s)
    var snap = Cycle.snapshot(started(noon), noon)
    delete snap.sleepNotesIso
    compare(Cycle.restore(s, ctx(noon), JSON.stringify(snap)).error, "error: bad sleepNotesIso")
    compare(Cycle.restore(s, ctx(noon), "{}").error.indexOf("error"), 0)
    compare(Cycle.restore(s, ctx(noon), "nope").error, "error: not JSON")
    verify(Cycle.restore(s, ctx(noon + 6 * 60 * 1000), JSON.stringify(Cycle.snapshot(s, noon))).error.indexOf("older than") !== -1)
    compare(JSON.stringify(s), before)
  }

  function test_a_key_it_doesnt_know_is_ignored() {
    var snap = Cycle.snapshot(started(noon), noon)
    snap.focusText = "from an older engine"
    var s = started(noon)
    compare(Cycle.restore(s, ctx(noon), JSON.stringify(snap)).error, "")
  }

  // The bug a 4-hour cap on the countdown had: the night's runs to seven,
  // so a deploy before about 01:30 was refused, and the night's notes and
  // stamp went with it.
  function test_a_night_hands_off_at_any_hour() {
    var s = started(at(22, 0))
    tickAt(s, at(22, 21))
    s.doneText = "late"
    s.sleepNotesIso = "2026-10-16T22:30:00"
    var t = started(at(22, 25))
    compare(Cycle.restore(t, ctx(at(22, 25)), JSON.stringify(Cycle.snapshot(s, at(22, 25)))).error, "")
    compare(t.phase, "sleep")
    compare(t.doneText, "late")
    compare(t.sleepNotesIso, "2026-10-16T22:30:00")
  }
}
