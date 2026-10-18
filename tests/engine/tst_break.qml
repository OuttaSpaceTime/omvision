import QtQuick
import QtTest
import Quickshell

import "../../Parser.js" as Parser

// The ompom engine's run/break cycle, through its overlay: real clicks and
// keys, real helper writes into the throwaway HOME tests/engine/run.sh made,
// read back with the app's own Parser.js. Time moves by setting `remaining`
// to 0 and calling the engine's tick(), the function its one-second Timer
// calls.
//
// One long sequence rather than separate tests: each step starts from the
// state the one before left, as a real cycle does. Lines go to stdout as
// `[engine-test] ok|FAIL <what>`, then `DONE <n> failed`.
TestCase {
  id: t
  // Started below, once the window's contents exist: Qt's own scheduler
  // needs qmltestrunner, which can't load Quickshell's modules.
  when: false

  property var engine
  property var overlayWindow
  property var overlay
  property int failures: 0
  readonly property string home: Quickshell.env("HOME")

  Component.onCompleted: Qt.callLater(run)

  function run() {
    try { steps() } catch (e) { failures++; say("FAIL " + e + "\n" + e.stack) }
    say("DONE " + failures + " failed")
    Qt.quit()
  }

  // ---- helpers ----------------------------------------------------------------
  function say(s) { console.log("[engine-test] " + s) }
  function check(cond, what) {
    if (cond) say("ok   " + what)
    else { failures++; say("FAIL " + what); shot("fail-" + failures) }
  }
  function waitFor(fn, what) {
    for (var ms = 0; ms < 4000; ms += 50) { if (fn()) return; wait(50) }
    check(false, "timed out waiting for " + what)
  }
  function find(node, pred) {
    if (!node) return null
    if (pred(node)) return node
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = find(kids[i], pred)
      if (hit) return hit
    }
    return null
  }
  function shown(item) {
    for (var p = item; p; p = p.parent) if (!p.visible) return false
    return true
  }
  function button(label) {
    return find(overlay, function(n) { return n.label === label && shown(n) })
  }
  // Settled first: a button whose row has just changed (a line shown above
  // it, a neighbour hidden) is still at its old position until its
  // positioners have run, and a click there lands on whatever used to be.
  // OmvisionTest.settle()'s way, by watching it stop moving, rather than
  // waitForRendering(): with nothing to redraw that waits for the engine's
  // next tick, and on a screen no tick changes, its whole 5s timeout.
  function clickButton(label) {
    var b = button(label)
    check(!!b, "\"" + label + "\" is on screen")
    if (!b) return
    settle(b)
    mouseClick(b, b.width / 2, b.height / 2)
    wait(50)
  }
  function settle(item) {
    var last = null
    for (var t = 0; t < 2000; t += 25) {
      var p = item.mapToItem(overlay, 0, 0)
      var here = p.x + "," + p.y + "," + item.width + "," + item.height
      if (here === last) return
      last = here
      wait(25)
    }
  }
  function section(title) {
    return find(overlay, function(n) { return n.title === title })
  }
  function type(text) {
    for (var i = 0; i < text.length; i++) {
      var c = text.charAt(i)
      if (c === "\n") keyClick(Qt.Key_Return)
      else keyClick(c)
    }
  }
  // Only for a failed check: the overlay as it stood, kept with the run.
  function shot(name) {
    wait(100)
    grabImage(overlay).save(Quickshell.env("ENGINE_TEST_SHOTS") + "/" + name + ".png")
  }
  function readFile(path) {
    var x = new XMLHttpRequest()
    x.open("GET", "file://" + path, false)
    try { x.send() } catch (e) { return "" }
    return x.responseText || ""
  }
  function allEntries(path) { return Parser.parseLogEntries(readFile(path), new Date()) }
  function entries(path) { return allEntries(path).filter(function(e) { return e.type === "pomodoro" }) }
  // The day file for the engine's clock, which night() moves.
  function engineDayLog() { return home + "/Notes/Omvision/days/" + Parser.dayKey(engine.now()) + ".md" }
  function near(value, want) { return value <= want && value >= want - 5 }

  readonly property string goalLog: home + "/Notes/Omvision/goals/write-the-report.log.md"
  readonly property string dayLog: home + "/Notes/Omvision/days/" + Parser.dayKey(new Date()) + ".md"

  // Every run the test finishes gets a start minute of its own: the runs
  // here take milliseconds, and Parser.js reads two entries under one
  // `### <time> · <N>m` heading as one pomodoro saved twice.
  property int runsEnded: 0
  function runOut() {
    if (engine.phase === "focus") {
      runsEnded++
      engine.focusStartedIso = Parser.dayKey(new Date()) + "T09:" + (runsEnded < 10 ? "0" : "") + runsEnded + ":00"
    }
    engine.remaining = 0
    engine.tick()
  }
  function toBreak() {
    runOut()
    check(engine.phase === "prompt", "the run ends on the prompt")
    clickButton("Start break")
    check(engine.phase === "break", "Start break starts the break")
  }
  function endBreak() {
    runOut()
    waitFor(function() { return engine.phase === "focus" }, "the next run")
  }

  // ---- the cycle ----------------------------------------------------------------
  function steps() {
    check(engine.phase === "focus" && !engine.overlayVisible && engine.focusStartedIso.length > 0,
          "comes up in a stamped focus run, overlay down")

    // A mode switch at the prompt logs the finished run on its way out.
    runOut()
    var dayBefore = entries(dayLog).length
    engine.cycleMode()
    check(engine.mode === "long" && engine.phase === "focus" && engine.remaining === engine.longFocusSec,
          "a mode switch starts a fresh run, no overlay")
    waitFor(function() { return entries(dayLog).length === dayBefore + 1 }, "the run switched away from at the prompt to be logged")
    engine.cycleMode(); engine.cycleMode()
    check(engine.mode === "normal", "back to Normal")

    // The break: countdown, extensions, goal picker.
    toBreak()
    check(near(engine.remaining, 300) && !engine.breakIsLong, "a 5 minute break: " + engine.remaining)
    clickButton("+2 min")
    check(near(engine.remaining, 420), "+2 min lengthens it: " + engine.remaining)
    waitFor(function() { return engine.goalsList.length > 0 }, "the goal list")
    keyClick(Qt.Key_G, Qt.ControlModifier)
    check(overlay.goalPickerOpen, "Ctrl+G opens the goal picker")
    check(engine.goalsList.length === 3 && !!button("Write the report"), "it offers the open, focusable goal")
    check(!button("Train legs"), "and leaves out the `focusable: no` one")
    check(!button("Old milestone"), "and the done one")
    keyClick(Qt.Key_Escape)
    check(!overlay.goalPickerOpen && engine.phase === "break", "Escape closes it")
    keyClick(Qt.Key_G, Qt.ControlModifier)
    clickButton("Write the report")
    check(!overlay.goalPickerOpen && engine.activeGoalSlug === "write-the-report", "a goal is picked")
    check(engine.runGoalSlug === "", "the finished run keeps the goal it ran on (none)")
    waitFor(function() { return readFile(home + "/.local/state/omvision/active-goal").trim() === "write-the-report" },
            "the pick to be written to active-goal")

    // The notes: lists continue, the first letter moves nothing, Ctrl+G
    // belongs to the countdown.
    clickButton("Take notes")
    check(engine.notesOpen, "Take notes opens the notes")
    var done = section("What's done?"), els = section("What else?")
    waitFor(function() { return done.edit.activeFocus }, "the caret in What's done?")
    var nextY = section("What's left?").y
    keyClick("-")
    wait(50)
    check(section("What's left?").y === nextY,
          "typing into an empty section doesn't push the next one down: " + nextY + " -> " + section("What's left?").y)
    type(" one\n")
    check(engine.doneText === "- one\n- ", "Return continues a list: " + JSON.stringify(engine.doneText))
    type("two")
    keyClick(Qt.Key_G, Qt.ControlModifier)
    check(!overlay.goalPickerOpen && engine.notesOpen, "Ctrl+G does nothing on the notes page")

    // Return on the last section's last line scrolls the page with it.
    var flick = find(overlay, function(n) { return n.contentY !== undefined && n.clip === true })
    mouseClick(els.edit, 10, 5)
    for (var i = 0; i < 20; i++) type("line " + i + "\n")
    wait(50)
    var caret = els.edit.mapToItem(flick, els.edit.cursorRectangle)
    check(flick.contentY > 0 && caret.y >= 0 && caret.y + caret.height + flick.bottomRoom <= flick.height + 1,
          "the caret stays on screen, clear of the bottom edge: y " + caret.y + " of " + flick.height)
    flick.contentY = 0

    // Headings fold.
    var heading = find(done, function(n) { return n.readOnly === true })
    check(heading.text === "# What's done?", "the heading is a markdown heading")
    mouseClick(heading, Math.min(heading.width / 2, 40), heading.height / 2)
    check(!done.open && !done.edit.visible, "clicking a heading folds its section")
    mouseClick(heading, Math.min(heading.width / 2, 40), heading.height / 2)
    check(done.open && done.edit.activeFocus, "clicking it again unfolds it, caret inside")

    // The arrows run through the page as through one markdown file,
    // stopping on the headings and skipping folded text.
    var left = section("What's left?")
    done.edit.cursorPosition = 3
    keyClick(Qt.Key_Up)
    check(done.heading.activeFocus, "Up off a section's first line lands on its heading")
    // Qt paints no caret on a read-only field, so the heading draws its own.
    var caretItem = find(done.heading, function(n) { return n.lit !== undefined })
    check(caretItem && caretItem.visible && caretItem.height > 0, "the heading shows a caret")
    keyClick(Qt.Key_Up)
    check(done.heading.activeFocus, "Up on the first heading stays there")
    keyClick(Qt.Key_Down)
    check(done.edit.activeFocus && done.edit.cursorPosition === 3,
          "Down from the heading goes back, same column: " + done.edit.cursorPosition)
    keyClick(Qt.Key_Down); keyClick(Qt.Key_Down)
    check(left.heading.activeFocus, "Down off a section's last line lands on the next heading")
    keyClick(Qt.Key_Down); keyClick(Qt.Key_Down)
    check(els.heading.activeFocus, "and on through an empty section")
    keyClick(Qt.Key_Up)
    check(left.edit.activeFocus, "Up goes back into it")
    keyClick(Qt.Key_Up)
    keyClick("x")
    check(left.heading.activeFocus && left.heading.text === "# What's left?" && engine.leftText === "",
          "typing on a heading changes nothing")
    keyClick(Qt.Key_Return)
    check(!left.open && left.heading.activeFocus, "Return on a heading folds it, caret stays")
    keyClick(Qt.Key_Down)
    check(els.heading.activeFocus, "Down skips folded text")
    keyClick(Qt.Key_Up); keyClick(Qt.Key_Return)
    check(left.open && left.heading.activeFocus, "Return unfolds it again, caret still on the heading")
    left.heading.cursorPosition = 0
    keyClick(Qt.Key_Left)
    check(done.edit.activeFocus && done.edit.cursorPosition === done.edit.length,
          "Left at a line's start goes to the end of the line before")
    keyClick(Qt.Key_Right)
    check(left.heading.activeFocus && left.heading.cursorPosition === 0,
          "Right at the end goes to the start of the next")
    keyClick(Qt.Key_Left)
    done.edit.cursorPosition = 0
    keyClick(Qt.Key_Up, Qt.ShiftModifier)
    check(done.edit.activeFocus, "Shift+Up stays in the field")
    var doneHeading = done.heading
    mouseClick(doneHeading, Math.min(doneHeading.width / 2, 40), doneHeading.height / 2)
    check(!done.open && doneHeading.activeFocus, "folding from inside the text leaves the caret on the heading")
    mouseClick(doneHeading, Math.min(doneHeading.width / 2, 40), doneHeading.height / 2)
    check(done.open && done.edit.activeFocus, "a click unfolds it into the text, even from the heading")

    // Leaving the notes keeps them, and writes nothing.
    var goalBefore = entries(goalLog).length
    keyClick(Qt.Key_Escape)
    check(!engine.notesOpen && engine.phase === "break", "Escape goes back to the countdown")
    clickButton("Take notes")
    check(done.edit.text === "- one\n- two", "the notes are still there")
    keyClick(Qt.Key_Escape)

    // The break's end logs the run (to the day file: it ran on no goal),
    // its multi-line notes intact through the file, and starts the next
    // run on the new goal.
    dayBefore = entries(dayLog).length
    endBreak()
    check(!engine.overlayVisible && done.edit.text === "" && engine.remaining === engine.normalFocusSec,
          "the next run starts, notes cleared")
    waitFor(function() { return entries(dayLog).length === dayBefore + 1 }, "the run to be logged")
    var logged = entries(dayLog)[dayBefore]
    check(logged.done === "- one\n- two" && logged.left === "" && logged.other.indexOf("line 0\nline 1\n") === 0,
          "Parser.js reads the notes back as written: " + JSON.stringify(logged))
    check(entries(goalLog).length === goalBefore, "nothing in the goal's log yet")

    // Every fourth Normal break is long. The prompt-time mode switch above
    // started the set over, so this is the second of the set.
    toBreak(); check(!engine.breakIsLong, "2nd break short"); endBreak()
    toBreak(); check(!engine.breakIsLong, "3rd break short"); endBreak()
    toBreak()
    check(engine.breakIsLong && near(engine.remaining, 900) && button("+1 min") && overlay.visible,
          "the 4th break is 15 minutes: " + engine.remaining)
    check(entries(goalLog).length === goalBefore + 2, "runs on the goal are logged to it")

    // A note too long for the helper is cut to fit, not refused, and never
    // through the middle of an emoji (a lone surrogate the helper can't
    // encode). Straight through entryJson(): typed into the page, each of
    // these texts would cost the hidden notes page a relayout of its own.
    var helperMax = Number((readFile(engine.notesHelperPath).match(/^MAX_NOTE_INPUT_BYTES = ([\d_]+)/m) || ["", "0"])[1].replace(/_/g, ""))
    check(helperMax === engine.maxNoteInputBytes,
          "the engine's limit is notes-helper.py's: " + engine.maxNoteInputBytes + " vs " + helperMax)
    var big = engine.entryJson("2026-10-13T10:00:00", 25, ["", "", new Array(30001).join("ä")])
    check(engine.utf8Bytes(big) <= engine.maxNoteInputBytes && JSON.parse(big)["else"].slice(-1) === "…",
          "an oversized note is shortened to the helper's limit")
    for (var cut = 0; cut < 4; cut++) {
      var kept = JSON.parse(engine.entryJson("2026-10-13T10:00:00", 25,
                                             ["", "", new Array(cut + 1).join("a") + new Array(6001).join("😀")]))["else"]
      if (/[\uD800-\uDBFF]…$/.test(kept)) { check(false, "a cut emoji at offset " + cut); break }
    }

    // A refused write holds the break; Skip moves on.
    engine.runGoalSlug = "../not-a-slug"
    runOut()
    waitFor(function() { return engine.notesSaveFailed }, "the helper to refuse the entry")
    check(engine.phase === "break" && engine.overlayVisible && !button("+1 min") && button("Try again"),
          "the break holds at 0:00, Try again instead of extensions")
    clickButton("Skip")
    check(engine.phase === "focus" && !engine.notesSaveFailed && !engine.breakIsLong,
          "Skip starts the next run: " + engine.statusJson())

    // Hand-offs across a deploy. `focusText` is a key an older engine
    // sent, and stands for any this one doesn't know.
    var brk = Object.assign(JSON.parse(engine.snapshotJson()), { phase: "break", remaining: 100, extensionsUsed: 1,
      focusStartedIso: "2026-10-13T10:00:00", notesOpen: true, doneText: "d", runGoalSlug: engine.activeGoalSlug,
      focusText: "x" })
    engine.goalsList = []
    var r = engine.restore(JSON.stringify(brk))
    waitFor(function() { return engine.goalsList.length > 0 }, "a break restored from another process to list the goals")
    check(engine.phase === "break" && engine.notesOpen && done.edit.text === "d" && engine.extensionsUsed === 1,
          "a break restores with its notes on screen, a key it doesn't know ignored: " + r)
    engine.restore(JSON.stringify(Object.assign(JSON.parse(engine.snapshotJson()), { runsInSet: 3, breakIsLong: true })))
    check(engine.runsInSet === 3 && engine.breakIsLong && engine.doneText === "d", "this engine's own snapshot round-trips")
    var partial = JSON.parse(engine.snapshotJson())
    delete partial.sleepNotesIso
    r = engine.restore(JSON.stringify(partial))
    check(r === "error: bad sleepNotesIso" && engine.phase === "break" && engine.doneText === "d",
          "a snapshot missing a field is refused, and changes nothing: " + r)
    check(engine.restore("{}").indexOf("error") === 0 && engine.phase === "break", "a bad snapshot changes nothing")

    night()
  }

  // Sets the engine's clock to hh:mm on today plus `days`, and ticks.
  function clockAt(days, hh, mm) {
    var d = new Date()
    d.setDate(d.getDate() + days)
    d.setHours(hh, mm, 0, 0)
    engine.clockOffsetMs = d.getTime() - Date.now()
    engine.tick()
  }

  // ---- the night ------------------------------------------------------------------
  function night() {
    // 22:15 ends the break restored above, logging it with its note.
    var goalBefore = entries(goalLog).length
    clockAt(0, 22, 16)
    check(engine.phase === "bedtime" && engine.overlayVisible && engine.doneText === "",
          "22:15 puts up Time to sleep, notes cleared: " + engine.statusJson())
    waitFor(function() { return entries(goalLog).length === goalBefore + 1 }, "the cut-short break to be logged")
    check(entries(goalLog)[goalBefore].done === "d", "with its notes")
    engine.cycleMode()
    check(engine.phase === "bedtime" && engine.mode === "normal", "the mode can't be switched out of it")

    // Three snoozes of a minute each.
    for (var n = 3; n > 0; n--) {
      clickButton("+1 minute (" + n + " left)")
      check(engine.phase === "snooze" && !engine.overlayVisible && near(engine.remaining, 60),
            "a snooze takes the overlay down for a minute")
      engine.remaining = 0
      engine.tick()
      check(engine.phase === "bedtime" && engine.overlayVisible, "and it comes back")
    }
    check(!button("+1 minute (0 left)") && button("Good night"), "three is all")

    // 22:20: the night, whatever is up. Notes are its only button.
    check(!button("Take notes"), "no notes before the night starts")
    engine.snoozesUsed = 0
    engine.snooze()
    clockAt(0, 22, 21)
    check(engine.phase === "sleep" && engine.overlayVisible && near(engine.remaining, 7 * 3600 + 9 * 60),
          "22:20 starts the night even mid-snooze, counting down to 05:30: " + engine.fmt(engine.remaining))
    check(button("Take notes") && !button("+1 min") && !button("+1 minute (3 left)") && !button("Good night"),
          "the night offers only notes")
    keyClick(Qt.Key_G, Qt.ControlModifier)
    check(!overlay.goalPickerOpen, "and no goal picker")

    // Each close of the page saves it to the day file, 0 minutes long, and
    // the page keeps its text for the next open.
    var nightLog = engineDayLog()
    var nightBefore = allEntries(nightLog).length
    clickButton("Take notes")
    check(engine.notesOpen, "Take notes opens the night's notes")
    waitFor(function() { return section("What's done?").edit.activeFocus }, "the caret in What's done?")
    type("lights out")
    keyClick(Qt.Key_Escape)
    check(!engine.notesOpen && engine.phase === "sleep", "Escape goes back to the night")
    waitFor(function() { return allEntries(nightLog).length === nightBefore + 1 }, "the night's notes to be saved")
    var saved = allEntries(nightLog)[nightBefore]
    check(saved.minutes === 0 && saved.done === "lights out" && Parser.pomodoroCount([saved]) === 0,
          "saved as 0 minutes of notes, not a pomodoro: " + JSON.stringify(saved))
    waitFor(function() { return engine.sleepNotesSaved[0] === "lights out" }, "the save to come back")
    check(engine.doneText === "lights out", "the page keeps its text once saved")

    // Reopened, it shows what was written; more written is saved whole
    // under the same heading, and read back as the one entry.
    function nightHeadings() { return (readFile(nightLog).match(/ · 0m$/mg) || []).length }
    var headingsBefore = nightHeadings()
    clickButton("Take notes")
    waitFor(function() { return section("What's done?").edit.activeFocus }, "the caret back in What's done?")
    check(section("What's done?").edit.text === "lights out", "a reopened page shows the night's notes")
    keyClick(Qt.Key_End, Qt.ControlModifier)
    type("\nand a book")
    keyClick(Qt.Key_Escape)
    waitFor(function() { return nightHeadings() === headingsBefore + 1 }, "the page to be saved again")
    var night = allEntries(nightLog)
    check(night.length === nightBefore + 1 && night[nightBefore].done === "lights out\nand a book"
          && night[nightBefore].heading === saved.heading,
          "re-saved whole under the night's heading, read as one entry: " + JSON.stringify(night.slice(nightBefore)))
    waitFor(function() { return engine.sleepNotesSaved[0] === "lights out\nand a book" }, "the second save to come back")
    clickButton("Take notes")
    keyClick(Qt.Key_Escape)
    wait(300)
    check(nightHeadings() === headingsBefore + 1, "a close that changed nothing appends nothing")

    // Logging in during the night lands on it, past "Time to sleep".
    engine.skipSleep()
    check(engine.phase === "focus" && !engine.overlayVisible, "skipSleep ends the night")
    engine.tick()
    check(engine.phase === "focus", "and it stays ended for the night")
    engine.sleepSkippedNight = ""
    clockAt(1, 1, 0)
    check(engine.phase === "sleep", "a fresh engine after 22:20 goes straight to the night: " + engine.phase)
    var snap = engine.snapshotJson()
    engine.restore(snap)
    check(engine.phase === "sleep" && engine.overlayVisible, "the night survives a deploy")

    // 05:30: notes still open are saved, and the day starts.
    clickButton("Take notes")
    type("x")
    var morningLog = engineDayLog()
    var morningBefore = allEntries(morningLog).length
    clockAt(1, 5, 31)
    check(engine.phase === "focus" && !engine.overlayVisible && !engine.notesOpen && near(engine.remaining, engine.normalFocusSec),
          "05:30 starts a fresh run: " + engine.statusJson())
    waitFor(function() { return allEntries(morningLog).length === morningBefore + 1 },
            "notes left open at 05:30 to be saved")

    // Bedtime is a hard limit, not a pomodoro: a timer switched off or
    // paused is no way around it.
    engine.cycleMode(); engine.cycleMode()
    check(engine.mode === "off" && !engine.countdownRunning, "the timer is off")
    clockAt(1, 22, 16)
    check(engine.phase === "bedtime" && engine.overlayVisible, "22:15 puts up Time to sleep with the timer off")
    clockAt(1, 22, 21)
    check(engine.phase === "sleep" && engine.overlayVisible, "and the night follows: " + engine.statusJson())
    clockAt(2, 5, 31)
    engine.cycleMode()
    engine.togglePause()
    check(engine.mode === "normal" && engine.paused && engine.phase === "focus", "a run is paused")
    clockAt(2, 22, 21)
    check(engine.phase === "sleep" && engine.overlayVisible && !engine.paused,
          "a paused run is no way around the night either: " + engine.statusJson())

    // The page fills the screen before it scrolls: it used to keep a third
    // of its height free under the caret, and scrolled the headings away
    // from the eleventh line on.
    clickButton("Take notes")
    waitFor(function() { return section("What's done?").edit.activeFocus }, "the caret in What's done?")
    var flick = find(overlay, function(n) { return n.bottomRoom !== undefined })
    for (var i = 1; i <= 14; i++) type("line " + i + "\n")
    waitForRendering(overlay)
    check(flick.contentY === 0, "fourteen lines don't scroll the page: contentY " + flick.contentY)
    for (i = 15; i <= 24; i++) type("line " + i + "\n")
    waitForRendering(overlay)
    var caret = section("What's done?").edit
    var bottom = caret.mapToItem(flick, caret.cursorRectangle).y + caret.cursorRectangle.height
    check(flick.contentY > 0 && bottom <= flick.height, "past the bottom it scrolls, the caret in view: " + bottom)
  }
}
