.pragma library

// Ompom's pomodoro cycle as plain functions: every rule of the timer, the
// break's notes and the night, and none of its I/O. Engine.qml is the
// adapter around it: it keeps the state in properties the overlay and the
// bar bind to, hands a copy of them to these functions with the time, and
// carries out what they ask for (a log write, a goal list, an active-goal
// write, a warning). So every rule here runs in qmltestrunner
// (tests/unit/tst_cycle.qml) with no Quickshell, no helper and no screen,
// and tests/engine only has to show the wiring works.
//
// A state is a plain object with fresh()'s keys. The functions that change
// it take (state, ctx, ...) and change the state in place, and return the
// effects to carry out, in order. ctx is { nowMs, durations, busy }: the
// engine's clock in milliseconds (the system clock plus Engine.clockOffsetMs,
// which tests and the demo move), the timer lengths (DURATIONS, or the
// demo's), and which of the engine's writes are still running
// ({ finishedLog, sleepSave }), which only the adapter knows.
//
// Effects: { type: "log", via: "note" | "finished" | "sleep", slug, entry,
// cycle, saved } is one notes-helper.py append (to the goal's log, or the
// day file for slug ""), stamped with the cycle it belongs to (see
// isStale()); { type: "listGoals" }; { type: "writeActive", slug };
// { type: "warn", message }.

// ---- constants ------------------------------------------------------------

// The break's notes: the state key each is typed into, the key
// notes-helper.py files it under (goal-files.md §4), and the heading the
// notes page gives it, in the order the log writes them. The heading lives
// here with the key rather than in Overlay.qml: the log keeps one line per
// question, so a question renamed or added is a change to both.
var NOTES = [
  { field: "doneText", key: "done", title: "What's done?" },
  { field: "leftText", key: "left", title: "What's left?" },
  { field: "elseText", key: "else", title: "What else?" }
]

var MODES = ["normal", "long", "off"]
var NIGHT_PHASES = ["bedtime", "snooze", "sleep"]
// focus | prompt | extend | break, or one of the night's. There is no
// screen before a run: the next focus run starts the moment its break ends
// (startNextRun()), on whatever goal is selected, and the engine comes up in
// "focus" so logging in never drops a blocking overlay on top of whatever
// you were doing. A "What's your focus?" screen before every run used to
// sit here; the break notes' "What's left?" already says what comes next.
var PHASES = ["focus", "prompt", "extend", "break"].concat(NIGHT_PHASES)

var DURATIONS = {
  focus: { normal: 25 * 60, long: 50 * 60 },
  break: { normal: 5 * 60, long: 10 * 60 },
  // The classic pomodoro set: every fourth break in Normal mode is a long
  // one. Long Focus already has a 10 minute break after every 50 minutes,
  // which is the same rest per hour, so it has no set of its own.
  setBreak: 15 * 60,
  extension: 60,
  snooze: 60
}

// bin/ompom-demo's: one length for every run and one for every break (the
// set's three times that), so a whole cycle passes in seconds.
function demoDurations(focusSec, breakSec) {
  return {
    focus: { normal: focusSec, long: focusSec },
    break: { normal: breakSec, long: breakSec },
    setBreak: breakSec * 3,
    extension: focusSec,
    snooze: DURATIONS.snooze
  }
}

var MAX_EXTENSIONS = 3
var RUNS_PER_SET = 4

// --- bedtime ---
// At 22:15 the engine stops whatever it was doing and puts up "Time to
// sleep" (phase "bedtime"); +1 minute takes the overlay down for a minute
// ("snooze"), three times at most. From 22:20 to 05:30 the night's screen
// ("sleep") is the only thing on the laptop: a countdown to 05:30 and the
// notes page, nothing else. It follows the clock rather than a countdown of
// its own (followTheClock(), every tick), so a login, a resume from suspend
// or a deploy at any hour of the night lands on the right screen, and a
// suspended night still ends at 05:30. It holds in every mode, "off" too:
// bedtime isn't a pomodoro, and switching the timer off is no way around it.
var BEDTIME_MINUTE = 22 * 60 + 15
var LIGHTS_OUT_MINUTE = 22 * 60 + 20
var WAKE_MINUTE = 5 * 60 + 30
var MAX_SNOOZES = 3

// notes-helper.py's MAX_NOTE_INPUT_BYTES: it reads no more of an entry
// than this, so a longer one would arrive cut off, as invalid JSON, and be
// refused on every retry. entryJson() shortens the notes to fit instead.
// tests/engine checks the two numbers agree.
var MAX_NOTE_INPUT_BYTES = 20000

// A hand-off older than this is refused; see restore().
var HANDOFF_MAX_AGE_MS = 5 * 60 * 1000

// Ticks this far apart (beyond the second between them) are a suspend, or
// a shell that stopped for as long; see resumed().
var SUSPEND_GAP_MS = 5000

// ---- the state --------------------------------------------------------------

// A countdown is stored as when it ends, endsAtMs on the engine's clock,
// while it runs, and as heldSec, the seconds it has left, while it doesn't
// (paused, the timer off, bedtime at 0). remainingSec() reads whichever
// applies. An end time rather than a number ticked down every second: a
// hand-off then needs no correction for the seconds the restart took, a
// test or the demo moves time by moving the clock, and the night's
// countdown, which follows the clock anyway, is no exception.
function fresh() {
  return {
    mode: "normal",
    phase: "focus",
    paused: false,
    endsAtMs: 0,
    heldSec: 0,
    extensionsUsed: 0,
    notesOpen: false,
    doneText: "",
    leftText: "",
    elseText: "",
    // The selected goal (a slug, or "" for none), kept live from the
    // active-goal file by Engine.qml (activeGoalRead()).
    activeGoalSlug: "",
    // The goal the run that just finished was spent on, pinned when its
    // break starts. Picking a goal during the break is picking the *next*
    // run's goal, so the finished run's entry must not follow it into a log
    // it was never worked on.
    runGoalSlug: "",
    // Stamped by startNextRun(), read back in finishedRunEntry() -- with
    // finishedRunMinutes() and the notes, the whole log entry.
    focusStartedIso: "",
    // -1 is "no mid-run change": the goal active when the run started (or
    // no goal at all) gets the whole run's minutes. A non-negative value is
    // the seconds left at the moment the active goal last changed during
    // the focus run (activeGoalRead()), because only the remainder was ever
    // spent on whatever became active at that moment.
    goalAttributionRemaining: -1,
    // Finished Normal runs since the last long break, and the day they were
    // counted on: a new day starts a new set rather than finishing
    // yesterday's. A mode switch starts one too (resetRun()).
    runsInSet: 0,
    setDay: "",
    // Whether the break now running is the set's long one: fixed when the
    // break starts, so the label and a restart agree on it.
    breakIsLong: false,
    snoozesUsed: 0,
    // The night skipSleep() was used on (nightOf()), so the clock doesn't
    // put the overlay straight back up on the next tick. "" is none.
    sleepSkippedNight: "",
    // The night's notes as one entry, re-saved whole on every close that
    // changed them (saveSleepNotes()): the stamp its heading carries, fixed
    // at the night's first save, and the text as it was last written, so a
    // close that changed nothing appends nothing.
    sleepNotesIso: "",
    sleepNotesSaved: NOTES.map(function() { return "" }),
    // One entry per pomodoro, full stop: the log is append-only. Set the
    // moment this cycle's entry is on disk, cleared with the rest of the
    // cycle.
    cycleLogged: false,
    // Set when the break's one write comes back non-zero. The break then
    // stays up at 0:00, its text untouched, with "Try again" and "Skip" in
    // place of the extension buttons: the alternative, starting the next run
    // anyway, would hide a pomodoro that was never logged behind a closed
    // overlay. The night's page shows it too.
    notesSaveFailed: false,
    // From saveNote() until its write exits, so the tick that reaches 0:00
    // and a "Try again" click in the same instant can't both append the run.
    notesSavePending: false,
    // Counts clearCycle()s; see isStale().
    cycle: 0
  }
}

// ---- reading the state -----------------------------------------------------

function atNight(s) { return NIGHT_PHASES.indexOf(s.phase) !== -1 }

// extend deliberately behaves like focus here: no overlay, normal desktop
// use, just a ticking bar countdown you can't pause or escape via mode
// switch until it runs out and drops you back at the prompt overlay. break
// is the mirror case: overlay stays up, and togglePause/cycleMode both
// refuse to act, so there's no way to pause or mode-switch your way out of
// it early either. It only ends on its own, after whatever minutes you add
// to it.
function overlayVisible(s) {
  return (s.mode !== "off" && (s.phase === "prompt" || s.phase === "break"))
    || s.phase === "bedtime" || s.phase === "sleep"
}

// The snooze counts down in every mode, like the rest of the night; the
// night's other two phases follow the clock instead.
function countdownRunning(s) {
  return s.phase === "snooze" || (!atNight(s) && s.mode !== "off" && !s.paused)
}

// The phases with a notes page: a break, and the night.
function hasNotes(s) { return s.phase === "break" || s.phase === "sleep" }

function remainingSec(s, nowMs) {
  if (s.phase === "sleep") return secondsUntilWake(new Date(nowMs))
  if (countdownRunning(s)) return Math.max(0, Math.ceil((s.endsAtMs - nowMs) / 1000))
  return s.heldSec
}

function focusSec(s, durations) { return durations.focus[s.mode === "long" ? "long" : "normal"] }

function breakSec(s, durations, isSetBreak) {
  return isSetBreak ? durations.setBreak : durations.break[s.mode === "long" ? "long" : "normal"]
}

// A finished run's minutes: the whole focus time (or, after a mid-run goal
// change, only what was left of it -- see goalAttributionRemaining) plus
// every +1 minute taken at the prompt.
function finishedRunMinutes(s, durations) {
  var base = s.goalAttributionRemaining >= 0 ? s.goalAttributionRemaining : focusSec(s, durations)
  return Math.round(base / 60) + s.extensionsUsed
}

function noteTexts(s) { return NOTES.map(function(n) { return s[n.field] }) }

// What the break's picker offers: the open goals that can be worked on at
// the laptop, out of list-goals' list. `focusable: no` (goal-files.md §6)
// marks the rest -- training, sleep, a habit -- which still log events from
// Omvision but are no run's goal. A helper deployed before the key existed
// sends no `focusable` at all, so only an explicit false drops a goal. Done
// and cancelled goals are finished work, not a next run's; any other
// status, a missing one included (§6: it reads as active), stays.
function pickableGoals(goals) {
  return (goals || []).filter(function(g) {
    return g && g.focusable !== false && g.status !== "done" && g.status !== "cancelled"
  })
}

// From the whole list, not pickableGoals(): an active goal closed or marked
// unfocusable since it was picked still has a title.
function goalTitle(goals, slug) {
  if (!slug) return ""
  for (var i = 0; i < (goals || []).length; i++) {
    var g = goals[i]
    if (g && g.slug === slug) return String(g.title || g.slug)
  }
  return ""
}

// ---- time and its labels ----------------------------------------------------

function pad2(n) { return (n < 10 ? "0" : "") + n }

// mm:ss, or h:mm:ss from an hour up.
function fmt(totalSeconds) {
  var s = Math.max(0, totalSeconds)
  var h = Math.floor(s / 3600)
  return (h > 0 ? h + ":" : "") + pad2(Math.floor(s / 60) % 60) + ":" + pad2(s % 60)
}

// The countdown as the screens show it. The night's is h:mm, in minutes
// rounded up so it reads 0:00 at 05:30 and not a minute before: it runs for
// seven hours, the seconds were noise on a screen meant to be left alone,
// and they made the whole layer surface redraw every second all night.
function countdownLabel(s, nowMs) {
  var sec = remainingSec(s, nowMs)
  if (s.phase !== "sleep") return fmt(sec)
  var minutes = Math.ceil(sec / 60)
  return Math.floor(minutes / 60) + ":" + pad2(minutes % 60)
}

// What the bar shows beside its icon. Here rather than in the bar, which
// only displays it, so a phase added here never needs a bar change. The
// night outranks "off": it holds in every mode. Only the snooze is ever seen
// on the bar; the night's other two phases cover it. Only the break is
// labelled: an extension ("extend") is focus time, and the prompt is the
// moment between the two.
function barLabel(s, nowMs) {
  if (s.phase === "snooze") return "sleep in " + countdownLabel(s, nowMs)
  if (s.phase === "bedtime" || s.phase === "sleep") return "sleep"
  if (s.mode === "off") return ""
  if (s.phase === "break") return "break " + countdownLabel(s, nowMs)
  return countdownLabel(s, nowMs)
}

// The engine's `status` IPC reply, which the bar polls once a second.
function status(s, nowMs) {
  var sec = remainingSec(s, nowMs)
  return {
    mode: s.mode,
    phase: s.phase,
    remaining: sec,
    remainingLabel: countdownLabel(s, nowMs),
    label: barLabel(s, nowMs),
    paused: s.paused,
    extensionsUsed: s.extensionsUsed,
    maxExtensions: MAX_EXTENSIONS,
    breakIsLong: s.breakIsLong,
    overlay: overlayVisible(s)
  }
}

var WAKE_LABEL = pad2(Math.floor(WAKE_MINUTE / 60)) + ":" + pad2(WAKE_MINUTE % 60)

// Local time, no offset suffix -- what notes-helper.py's format_timestamp()
// expects from datetime.fromisoformat() and, more importantly, what it then
// renders with a local strftime(): a UTC timestamp here would print the
// wrong wall-clock hour in the log.
function isoOf(d) {
  return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate())
    + "T" + pad2(d.getHours()) + ":" + pad2(d.getMinutes()) + ":" + pad2(d.getSeconds())
}

function minuteOfDay(d) { return d.getHours() * 60 + d.getMinutes() }
// From `from` in the evening until the wake-up, across midnight.
function nightFrom(minute, from) { return minute >= from || minute < WAKE_MINUTE }
// The evening a night began on: 02:00 on the 17th is the night of the 16th.
function nightOf(d) {
  var n = new Date(d.getTime())
  if (minuteOfDay(d) < WAKE_MINUTE) n.setDate(n.getDate() - 1)
  return isoOf(n).slice(0, 10)
}
function secondsUntilWake(d) {
  var w = new Date(d.getTime())
  w.setHours(Math.floor(WAKE_MINUTE / 60), WAKE_MINUTE % 60, 0, 0)
  if (w.getTime() <= d.getTime()) w.setDate(w.getDate() + 1)
  return Math.round((w.getTime() - d.getTime()) / 1000)
}

// ---- the log entry ---------------------------------------------------------

// The entry for the run that just finished, with whatever notes are typed.
function finishedRunEntry(s, durations) {
  return entryJson(s.focusStartedIso, finishedRunMinutes(s, durations), noteTexts(s))
}

// Any entry carrying the notes (`texts`, in NOTES' order), as notes-helper.py
// reads it: a finished run's, or the night's (0 minutes, see
// saveSleepNotes()).
//
// An entry over the helper's limit has its longest note cut short, with "…"
// to say so, until it fits: the helper would otherwise read it cut off
// mid-JSON and refuse it, every retry alike, and the run would only get past
// "Not saved" by being skipped. Only a paste could get there.
function entryJson(started, minutes, texts) {
  var entry = { started: started, minutes: minutes }
  var keys = NOTES.map(function(n) { return n.key })
  keys.forEach(function(k, i) { entry[k] = texts[i] })
  var json = JSON.stringify(entry)
  for (var over = utf8Bytes(json) - MAX_NOTE_INPUT_BYTES; over > 0; over = utf8Bytes(json) - MAX_NOTE_INPUT_BYTES) {
    var key = keys.reduce(function(a, b) { return entry[a].length >= entry[b].length ? a : b })
    // Every character costs at least a byte, and "…" adds three back.
    var kept = entry[key].slice(0, Math.max(0, entry[key].length - over - 3))
    // Never half an emoji: a lone surrogate can't be encoded as UTF-8, and
    // the helper would refuse the entry over it.
    if (/[\uD800-\uDBFF]$/.test(kept)) kept = kept.slice(0, -1)
    entry[key] = kept + "…"
    json = JSON.stringify(entry)
  }
  return json
}

function utf8Bytes(text) {
  var n = 0
  for (var i = 0; i < text.length; i++) {
    var c = text.charCodeAt(i)
    if (c < 0x80) n += 1
    else if (c < 0x800) n += 2
    else if (c >= 0xD800 && c < 0xDC00) { n += 4; i++ }
    else n += 3
  }
  return n
}

// ---- changing the state ----------------------------------------------------

function setCountdown(s, sec, nowMs) {
  s.heldSec = sec
  s.endsAtMs = nowMs + sec * 1000
}

// A log write stamped with an older cycle exits into a cycle that isn't its
// own -- a bedtime, a 05:30 or a restore moved on while it ran -- so it
// leaves this one's state alone. Testing the phase instead would miss a
// write that outlives its break and finds a later one.
function isStale(s, cycle) { return cycle !== s.cycle }

function log(fx, s, via, slug, entry, saved) {
  fx.push({ type: "log", via: via, slug: slug, entry: entry, cycle: s.cycle, saved: saved })
}

function warn(fx, message) { fx.push({ type: "warn", message: message }) }

// Everything one cycle collects, gone: by startNextRun(), and by goToBed(),
// whose night starts with an empty notes page.
function clearCycle(s) {
  s.cycle += 1
  s.extensionsUsed = 0
  s.notesOpen = false
  s.notesSaveFailed = false
  s.cycleLogged = false
  NOTES.forEach(function(n) { s[n.field] = "" })
  s.sleepNotesIso = ""
  s.sleepNotesSaved = NOTES.map(function() { return "" })
}

// A fresh focus run on the selected goal, with this cycle's notes and
// extensions cleared: at the end of a break whose run is logged (or
// skipped), at startup, and from resetRun(). Only this and goToBed() clear a
// cycle's notes, so they last through every close and reopen of the notes
// page in the break they belong to.
function startNextRun(s, ctx) {
  clearCycle(s)
  s.phase = "focus"
  setCountdown(s, focusSec(s, ctx.durations), ctx.nowMs)
  s.focusStartedIso = isoOf(new Date(ctx.nowMs))
  s.breakIsLong = false
  s.goalAttributionRemaining = -1
  return []
}

// Back to the start of a fresh run, the long-break set included: what a
// mode switch, a restore and 05:30 begin from.
function resetRun(s, ctx) {
  s.paused = false
  s.runsInSet = 0
  s.setDay = ""
  return startNextRun(s, ctx)
}

function cycleMode(s, ctx) {
  if (s.phase === "extend" || s.phase === "break" || atNight(s)) return []
  // A finished pomodoro is logged before the reset below throws its cycle
  // away. Switching mode at the +1 minute / Start break prompt used to drop
  // a run that had fully happened, just because no break was taken to log
  // it.
  var fx = logFinishedRunOnTheWayOut(s, ctx)
  s.mode = MODES[(MODES.indexOf(s.mode) + 1) % MODES.length]
  // A mode switch never raises the overlay (it only comes up when a run
  // ends), so clicking through the modes on the bar just restarts the run in
  // each one, and the last one clicked is the one that runs.
  return fx.concat(resetRun(s, ctx))
}

// Pausing holds the seconds left; resuming sets a new end that far ahead.
function togglePause(s, ctx) {
  if (s.mode === "off" || s.phase !== "focus") return []
  if (!s.paused) s.heldSec = remainingSec(s, ctx.nowMs)
  s.paused = !s.paused
  if (!s.paused) setCountdown(s, s.heldSec, ctx.nowMs)
  return []
}

// Once a second, from the engine's Timer.
function tick(s, ctx) {
  var fx = followTheClock(s, ctx)
  if (!countdownRunning(s) || remainingSec(s, ctx.nowMs) > 0) return fx
  if (s.phase === "focus" || s.phase === "extend") {
    s.phase = "prompt"
    setCountdown(s, 0, ctx.nowMs)
  } else if (s.phase === "snooze") {
    s.phase = "bedtime"
    setCountdown(s, 0, ctx.nowMs)
  } else if (s.phase === "break") {
    // The break's end is when its run is logged, whether or not a note was
    // ever written: started/minutes are real information either way. The
    // next run starts once the write lands (noteLogExited()); until then,
    // and after a refusal, the break holds at 0:00.
    if (s.notesSavePending || s.notesSaveFailed) return fx
    fx = fx.concat(s.cycleLogged ? startNextRun(s, ctx) : saveNote(s, ctx))
  }
  return fx
}

// The engine's ticks came gapMs further apart than they should have: the
// laptop was suspended, or the shell stopped. A running countdown didn't
// run meanwhile, so its end moves on by the gap: a focus run is time at the
// laptop, and a suspended one hasn't happened yet. That is what the engine
// always did, back when it counted seconds down one tick at a time, and
// it's kept on purpose rather than by accident now. The night isn't a
// countdown and follows the clock regardless.
function resumed(s, ctx, gapMs) {
  if (countdownRunning(s) && s.phase !== "sleep") s.endsAtMs += gapMs
  return []
}

function addExtension(s, ctx) {
  if (s.phase !== "prompt" || s.extensionsUsed >= MAX_EXTENSIONS) return []
  s.extensionsUsed += 1
  s.phase = "extend"
  setCountdown(s, ctx.durations.extension, ctx.nowMs)
  return []
}

function startBreak(s, ctx) {
  if (s.phase !== "prompt") return []
  if (s.mode === "normal") {
    var today = isoOf(new Date(ctx.nowMs)).slice(0, 10)
    if (s.setDay !== today) {
      s.setDay = today
      s.runsInSet = 0
    }
    s.runsInSet += 1
  }
  s.breakIsLong = s.runsInSet >= RUNS_PER_SET
  if (s.breakIsLong) s.runsInSet = 0
  s.phase = "break"
  setCountdown(s, breakSec(s, ctx.durations, s.breakIsLong), ctx.nowMs)
  s.runGoalSlug = s.activeGoalSlug
  // The break opens on its ticking countdown, never on the notes view:
  // opening the notes straight away turned every break into a writing
  // prompt and hid the one thing a break is for, time away. The goal list
  // is read again here, where the picker is, rather than cached across a
  // session, so a goal created, renamed or closed in Omvision between
  // pomodoros shows up on the very next break.
  return [{ type: "listGoals" }]
}

// The break's +1/+2/+3 min buttons. No cap, unlike the focus run's
// extensions: those are the run eating into the rest, these are more rest.
// After a refused save they're hidden (see notesSaveFailed), so a break is
// never stretched just to postpone a failure.
function extendBreak(s, ctx, minutes) {
  if (s.phase !== "break" || s.notesSavePending || s.notesSaveFailed) return []
  setCountdown(s, remainingSec(s, ctx.nowMs) + minutes * 60, ctx.nowMs)
  return []
}

// Shows the notes page with whatever this break has already put in it: only
// the next run's start clears it. The night has the same page.
function openNotes(s, ctx) {
  if (hasNotes(s)) s.notesOpen = true
  return []
}

// Back to the countdown. In a break it never saves: the run is logged once,
// when the break ends, with the notes as they stand then, so the page can be
// opened and left as often as the break allows. The night is the other way
// round, see saveSleepNotes().
function closeNotes(s, ctx) {
  s.notesOpen = false
  return s.phase === "sleep" ? saveSleepNotes(s, ctx) : []
}

// The one write for a completed pomodoro: the run's goal log, or the day
// file when it had no goal, always with an entry, even one with blank notes.
// On a non-zero exit (a malformed entry the helper refused, a bad slug, or
// -- mid-deploy -- an old helper) the write never happened, so nothing acts
// like it did: the text is never touched here, and noteLogExited() decides
// between starting the next run and holding the break with "Not saved" up.
function saveNote(s, ctx) {
  if (s.notesSavePending || s.cycleLogged) return []
  s.notesSaveFailed = false
  s.notesSavePending = true
  var fx = []
  log(fx, s, "note", s.runGoalSlug, finishedRunEntry(s, ctx.durations))
  return fx
}

function noteLogExited(s, ctx, code, cycle, payload) {
  s.notesSavePending = false
  var fx = []
  if (isStale(s, cycle)) {
    if (code !== 0) warn(fx, "ompom: break notes not logged (helper exit " + code + "): " + payload)
    return fx
  }
  if (code !== 0) {
    s.notesSaveFailed = true
    return fx
  }
  s.cycleLogged = true
  return startNextRun(s, ctx)
}

// "Skip" after a refused save: the run goes unlogged rather than holding the
// screen forever (an old helper mid-deploy refuses every time). The entry
// goes to the shell's log, so it isn't lost without a trace.
function skipUnsavedNotes(s, ctx) {
  if (!s.notesSaveFailed) return []
  var fx = []
  warn(fx, "ompom: break notes not logged, skipped after a refused save: " + finishedRunEntry(s, ctx.durations))
  return fx.concat(startNextRun(s, ctx))
}

// Called by cycleMode() just before its reset: a run that reached the prompt
// is a pomodoro that happened, so it's logged with blank notes, like a break
// that ran out untouched. Not a partial run switched off mid-focus: that
// isn't a pomodoro. Bedtime (goToBed()) calls it too, and can also land in a
// break: that run is logged with its notes as they stand, since the break
// will never reach its end. A break whose own write is in flight is left to
// it, and one refused already only goes to the shell's log, as Skip would.
//
// Through a write of its own ("finished") rather than saveNote()'s: it
// finishes after the reset has already begun the next cycle, and there is
// nowhere left to show a refusal once the overlay is gone, so one is only
// warned (finishedLogExited()).
function logFinishedRunOnTheWayOut(s, ctx) {
  var fx = []
  var slug
  if (s.phase === "prompt") slug = s.activeGoalSlug
  else if (s.phase === "break" && !s.cycleLogged && !s.notesSavePending) slug = s.runGoalSlug
  else return fx
  var entry = finishedRunEntry(s, ctx.durations)
  if (s.notesSaveFailed) warn(fx, "ompom: break notes not logged, refused before the cycle was dropped: " + entry)
  else if (ctx.busy.finishedLog) warn(fx, "ompom: previous run still being logged, this one was not: " + entry)
  else log(fx, s, "finished", slug, entry)
  return fx
}

function finishedLogExited(s, ctx, code, cycle, payload) {
  var fx = []
  if (code !== 0) warn(fx, "ompom: finished run not logged (helper exit " + code + "): " + payload)
  return fx
}

// ---- the night ---------------------------------------------------------------

// Every tick, before anything else: puts the engine where the clock says it
// belongs. Into bed from any phase at 22:15, straight into the night from
// 22:20 on (whatever snooze or prompt was up), and back to a fresh run at
// 05:30.
function followTheClock(s, ctx) {
  var d = new Date(ctx.nowMs)
  var minute = minuteOfDay(d)
  if (!nightFrom(minute, BEDTIME_MINUTE) || s.sleepSkippedNight === nightOf(d))
    return atNight(s) ? wake(s, ctx) : []
  var fx = atNight(s) ? [] : goToBed(s, ctx)
  if (nightFrom(minute, LIGHTS_OUT_MINUTE)) fx = fx.concat(startSleep(s, ctx))
  return fx
}

// Whatever was running ends here. A finished run (at the prompt or in its
// break) is logged first; a focus run cut off part-way isn't, as with a mode
// switch, since it isn't a pomodoro.
function goToBed(s, ctx) {
  var fx = logFinishedRunOnTheWayOut(s, ctx)
  clearCycle(s)
  s.paused = false
  s.snoozesUsed = 0
  s.phase = "bedtime"
  setCountdown(s, 0, ctx.nowMs)
  return fx
}

// "+1 minute" on "Time to sleep": the overlay goes for a minute, and comes
// back. Never past 22:20, where followTheClock() starts the night.
function snooze(s, ctx) {
  if (s.phase !== "bedtime" || s.snoozesUsed >= MAX_SNOOZES) return []
  s.snoozesUsed += 1
  s.phase = "snooze"
  setCountdown(s, ctx.durations.snooze, ctx.nowMs)
  return []
}

// "Good night", or 22:20.
function startSleep(s, ctx) {
  if (s.phase === "bedtime" || s.phase === "snooze") s.phase = "sleep"
  return []
}

// 05:30: any notes still unsaved are written, and the day starts on a fresh
// run and a fresh set.
function wake(s, ctx) {
  var fx = s.phase === "sleep" ? saveSleepNotes(s, ctx) : []
  return fx.concat(resetRun(s, ctx))
}

// The way out of a night, for when the laptop is really needed: an IPC call
// only (`omarchy-shell ompom skipSleep`, from a TTY if need be), so nothing
// on the overlay offers it. It lasts the rest of this night; the next one
// starts at 22:15 as usual.
function skipSleep(s, ctx) {
  s.sleepSkippedNight = nightOf(new Date(ctx.nowMs))
  return followTheClock(s, ctx)
}

// The night's notes go to the day file each time the page is closed (and at
// 05:30), and stay on the page: it's one page for the whole night, as a
// break's is for the break. Not saved once at the night's end, as a break
// does: a laptop switched off overnight would take them with it. So each
// close that changed them appends the whole text again, under the one
// heading the night's first save stamped, and Parser.js shows only the last
// copy (goal-files.md §4). An entry of 0 minutes: notes with no run behind
// them, never counted as a pomodoro.
//
// Clearing the page after each save was the first version: every reopen
// showed an empty page, and what had been written looked lost. Appending
// only what was added since was the other way, and was rejected: an edit in
// the middle of the text has no "added since".
function saveSleepNotes(s, ctx) {
  var text = noteTexts(s)
  if (text.every(function(t) { return t.trim() === "" })) return []
  if (text.every(function(t, i) { return t === s.sleepNotesSaved[i] })) return []
  // A save still running takes this text with the next close, or at 05:30.
  if (ctx.busy.sleepSave) return []
  if (s.sleepNotesIso === "") s.sleepNotesIso = isoOf(new Date(ctx.nowMs))
  s.notesSaveFailed = false
  var fx = []
  log(fx, s, "sleep", "", entryJson(s.sleepNotesIso, 0, text), text)
  return fx
}

// Records the text the write carried as saved, which is what the next close
// compares against. A refusal says so and records nothing, so the next close
// tries again. After 05:30 nothing is left to show it on, so it's only
// warned.
function sleepNoteExited(s, ctx, code, cycle, payload, saved) {
  var fx = []
  if (isStale(s, cycle)) {
    if (code !== 0) warn(fx, "ompom: night notes not logged (helper exit " + code + "): " + payload)
  } else if (code !== 0) {
    s.notesSaveFailed = true
  } else {
    s.sleepNotesSaved = saved
  }
  return fx
}

// ---- the goal ------------------------------------------------------------------

// The active-goal pointer (~/.local/state/omvision/active-goal) can change
// out from under the engine two ways: its own chooseGoal() when a goal is
// picked in the break, and Omvision writing it, which can happen while a
// focus run is already ticking. isLive tells a genuine change from the
// file's first load, which is not a change of goal mid-run: the run the
// engine starts with simply runs on the goal that was selected last.
function activeGoalRead(s, ctx, rawSlug, isLive) {
  var slug = String(rawSlug || "").trim()
  if (isLive && s.phase === "focus" && slug !== s.activeGoalSlug) {
    // Only the remainder counts: the minutes before this moment were spent
    // on whatever was active before (or on nothing), never on the newly
    // active goal. Clearing (slug === "") goes back to the full run rather
    // than a partial one, which is what a day-file entry gets too.
    s.goalAttributionRemaining = slug.length > 0 ? remainingSec(s, ctx.nowMs) : -1
  }
  s.activeGoalSlug = slug
  return []
}

// The next run's goal: written straight away, so Omvision and the bar show
// it during the break rather than only once the run starts.
function chooseGoal(s, ctx, slug) {
  s.activeGoalSlug = String(slug || "")
  return [{ type: "writeActive", slug: s.activeGoalSlug }]
}

// ---- hand-off across a shell restart ---------------------------------------
// A new engine only loads on a whole-shell restart, which would start every
// deploy on a fresh 25 minutes. bin/omvision-deploy bridges that: snapshot()
// before the restart, restore() into the new engine after it. Only the cycle
// is carried, never an in-flight save: a note write in progress at snapshot
// time either landed (the log has it) or didn't (the break ends again in the
// new engine, which retries it).

function isBool(v) { return typeof v === "boolean" }
function isString(v) { return typeof v === "string" }
function isInt(lo, hi) { return function(v) { return Number.isInteger(v) && v >= lo && v <= hi } }
function isOneOf(values) { return function(v) { return values.indexOf(v) !== -1 } }
function isTime(v) { return typeof v === "number" && isFinite(v) && v >= 0 }
// "" or a date, and "" or isoOf()'s stamp: both are unset as "".
function isDay(v) { return typeof v === "string" && /^(\d{4}-\d\d-\d\d)?$/.test(v) }
function isStamp(v) { return typeof v === "string" && /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)?$/.test(v) }

// Every key the hand-off carries, each with the check restore() puts it
// through: a new piece of cycle state is one row here. A snapshot is at most
// HANDOFF_MAX_AGE_MS old and only ever comes from the engine deployed just
// before, so a row this engine adds takes `optional: true` for the one
// deploy that hands off from an engine without it (restore() then keeps the
// fresh run's value), and loses it after: rows don't stay optional for
// good. Keys a snapshot has and this list doesn't (an older engine's
// `focusText`) are ignored. Not carried: the goal (the new engine reads the
// active-goal file itself), the write in flight, and the cycle count.
var FIELDS = [
  { name: "mode", ok: isOneOf(MODES) },
  { name: "phase", ok: isOneOf(PHASES) },
  { name: "paused", ok: isBool },
  { name: "endsAtMs", ok: isTime, optional: true },
  { name: "heldSec", ok: isInt(0, 24 * 3600), optional: true },
  { name: "extensionsUsed", ok: isInt(0, MAX_EXTENSIONS) },
  { name: "focusStartedIso", ok: isStamp },
  { name: "goalAttributionRemaining", ok: isInt(-1, 4 * 3600) },
  { name: "cycleLogged", ok: isBool },
  { name: "notesOpen", ok: isBool },
  { name: "runGoalSlug", ok: isString },
  { name: "runsInSet", ok: isInt(0, RUNS_PER_SET - 1) },
  { name: "setDay", ok: isDay },
  { name: "breakIsLong", ok: isBool },
  { name: "snoozesUsed", ok: isInt(0, MAX_SNOOZES) },
  { name: "sleepSkippedNight", ok: isDay },
  { name: "sleepNotesIso", ok: isStamp },
  { name: "sleepNotesSaved", ok: function(v) { return Array.isArray(v) && v.length === NOTES.length && v.every(isString) } }
].concat(NOTES.map(function(n) { return { name: n.field, ok: isString } }))

function snapshot(s, nowMs) {
  var out = { takenAtMs: nowMs }
  FIELDS.forEach(function(f) { out[f.name] = s[f.name] })
  return out
}

// Takes what snapshot() gives, as JSON. Returns "" and has changed `s`, or
// returns what's wrong and has left `s` exactly as it was: every field is
// checked before anything is assigned, so a bad hand-off never leaves the
// fresh engine half-restored.
function restore(s, ctx, json) {
  var snap
  try { snap = JSON.parse(String(json || "")) } catch (e) { return { error: "error: not JSON", fx: [] } }
  if (snap === null || typeof snap !== "object" || Array.isArray(snap)) return { error: "error: not an object", fx: [] }
  var age = ctx.nowMs - snap.takenAtMs
  if (!(age >= 0 && age <= HANDOFF_MAX_AGE_MS))
    return { error: "error: snapshot missing takenAtMs or older than " + (HANDOFF_MAX_AGE_MS / 60000) + " minutes", fx: [] }
  for (var i = 0; i < FIELDS.length; i++) {
    var f = FIELDS[i]
    if (!(f.optional && snap[f.name] === undefined) && !f.ok(snap[f.name])) return { error: "error: bad " + f.name, fx: [] }
  }
  // The engine before end times (e81a789) sends the seconds left as
  // `remaining`, counted at takenAtMs, and neither end key. Only the deploy
  // that replaces it gets here; the commit after it drops this and makes
  // both keys required.
  if (snap.endsAtMs === undefined || snap.heldSec === undefined) {
    if (!isInt(0, 24 * 3600)(snap.remaining)) return { error: "error: bad remaining", fx: [] }
    snap.heldSec = snap.remaining
    snap.endsAtMs = snap.takenAtMs + snap.remaining * 1000
  }

  // From the baseline every new cycle starts from, then the snapshot on top
  // of it. The mode goes first: the fresh run resetRun() starts is sized by
  // it.
  s.mode = snap.mode
  var fx = resetRun(s, ctx)
  FIELDS.forEach(function(f) { if (snap[f.name] !== undefined) s[f.name] = snap[f.name] })
  // The picker's list is otherwise only read when a break starts, and this
  // one started in another process.
  if (s.phase === "break") fx.push({ type: "listGoals" })
  return { error: "", fx: fx }
}
