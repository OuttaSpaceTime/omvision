import QtQuick
import Quickshell
import Quickshell.Io

import "Cycle.js" as Cycle

// Ompom's pomodoro engine: Cycle.js's rules, with the clock, the state and
// the I/O they leave out. The state lives here as properties, which the
// overlay and the tests read; every event (a tick, a click, a write
// exiting, the active-goal file changing) runs through run(), which hands
// Cycle.js a plain copy of them with the time, writes back what changed,
// and carries out the effects it returns. Nothing here decides anything
// about the cycle, so nothing here needs testing beyond the wiring
// (tests/engine); the rules are tests/unit/tst_cycle.qml's.
//
// No window of its own: Service.qml, the plugin's entry point, puts
// Overlay.qml (which only reads this and calls its functions) in a
// layer-shell PanelWindow, and tests/engine puts the same overlay in a
// FloatingWindow, since offscreen `qs` has no layer shell.
Item {
  id: root

  // Set only by bin/ompom-demo, which loads this same file in its own qs
  // process, so the overlay can be seen and clicked through as it really is
  // without waiting out a 25/5 cycle and without touching the real engine
  // running inside omarchy-shell. What it changes: the timer lengths
  // (Cycle.demoDurations()), writes go nowhere (writeCommand()), its own IPC
  // target, and the overlay's Ctrl+Q. Reading the goal list stays live, so
  // the picker shows the real goals. A copied harness was the alternative,
  // and was rejected: it drifts from this file and then demos something that
  // no longer ships.
  property bool demo: false
  property int demoFocusSec: 5
  property int demoBreakSec: 5
  readonly property var durations: demo ? Cycle.demoDurations(demoFocusSec, demoBreakSec) : Cycle.DURATIONS

  // Added to the system clock: the engine's time is now(). Set by
  // tests/engine and bin/ompom-demo --clock, so a night can be tried at
  // noon; the live engine leaves it 0.
  property real clockOffsetMs: 0
  function now() { return new Date(Date.now() + root.clockOffsetMs) }

  // All note/state filesystem work (mkdir, read, append) is delegated to
  // notes-helper.py — a fixed interpreter/script pair, never a shell — which
  // holds validated, no-follow directory file descriptors for the whole
  // operation. That closes a gap this same choreography had here in QML:
  // doing it as several separate FileView/Process steps meant an
  // intermediate directory swapped for a symlink between two of those steps
  // could redirect a read, write, or append outside ~/Notes/Omvision or
  // ~/.local/state/omvision. See notes-helper.py's own docstring for the
  // rest.
  readonly property string pythonBin: "/usr/bin/python3"
  readonly property string notesHelperPath: decodeURIComponent(
    Qt.resolvedUrl("notes-helper.py").toString().replace(/^file:\/\//, ""))

  // ---- the state (Cycle.fresh()'s keys; see there for each) ----------------
  property string mode: "normal"
  property string phase: "focus"
  property bool paused: false
  property real endsAtMs: 0
  property int heldSec: 0
  property int extensionsUsed: 0
  property bool notesOpen: false
  property string doneText: ""
  property string leftText: ""
  property string elseText: ""
  property string activeGoalSlug: ""
  property string runGoalSlug: ""
  property string focusStartedIso: ""
  property int goalAttributionRemaining: -1
  property int runsInSet: 0
  property string setDay: ""
  property bool breakIsLong: false
  property int snoozesUsed: 0
  property string sleepSkippedNight: ""
  property string sleepNotesIso: ""
  property var sleepNotesSaved: Cycle.fresh().sleepNotesSaved
  property bool cycleLogged: false
  property bool notesSaveFailed: false
  property bool notesSavePending: false
  property int cycle: 0

  // list-goals' last answer, re-read at the start of every break.
  property var goalsList: []

  // The countdown at the last event: the seconds left, and as the screens
  // write them. Set by run(), which every tick goes through.
  property int remaining: 0
  property string countdownLabel: ""

  // ---- read off the state, for the overlay -----------------------------------
  readonly property var notes: Cycle.NOTES
  readonly property bool atNight: Cycle.NIGHT_PHASES.indexOf(phase) !== -1
  readonly property bool overlayVisible: Cycle.overlayVisible({ mode: mode, phase: phase })
  readonly property bool countdownRunning: Cycle.countdownRunning({ mode: mode, phase: phase, paused: paused })
  readonly property bool hasNotes: Cycle.hasNotes({ phase: phase })
  readonly property var pickableGoals: Cycle.pickableGoals(goalsList)
  // Whether Ctrl+G has anything to offer: a goal to pick, or an active one
  // for "No goal" to drop.
  readonly property bool canPickGoal: pickableGoals.length > 0 || activeGoalSlug.length > 0
  readonly property string activeGoalTitle: Cycle.goalTitle(goalsList, activeGoalSlug)
  readonly property string wakeLabel: Cycle.WAKE_LABEL
  readonly property int maxExtensions: Cycle.MAX_EXTENSIONS
  readonly property int maxSnoozes: Cycle.MAX_SNOOZES
  readonly property int maxNoteInputBytes: Cycle.MAX_NOTE_INPUT_BYTES
  readonly property int normalFocusSec: durations.focus.normal
  readonly property int longFocusSec: durations.focus.long

  // ---- running an event --------------------------------------------------------
  readonly property var stateKeys: Object.keys(Cycle.fresh())

  function state() {
    var s = {}
    for (var k of root.stateKeys) s[k] = root[k]
    return s
  }

  function context() {
    return {
      nowMs: root.now().getTime(),
      durations: root.durations,
      busy: { finishedLog: finishedRunLogProc.running, sleepSave: sleepNoteProc.running }
    }
  }

  // Calls Cycle[name](state, ctx, ...args), writes back the properties that
  // changed (only those, so a binding on one isn't woken by the others),
  // and carries out the effects.
  function run(name) {
    var s = root.state(), ctx = root.context()
    var fx = Cycle[name].apply(null, [s, ctx].concat(Array.prototype.slice.call(arguments, 1)))
    root.commit(s, ctx)
    root.perform(fx)
  }

  function commit(s, ctx) {
    for (var k of root.stateKeys) {
      var v = s[k]
      if (Array.isArray(v) ? JSON.stringify(v) !== JSON.stringify(root[k]) : v !== root[k]) root[k] = v
    }
    root.remaining = Cycle.remainingSec(s, ctx.nowMs)
    root.countdownLabel = Cycle.countdownLabel(s, ctx.nowMs)
  }

  function perform(fx) {
    for (var e of fx) {
      if (e.type === "log") root.startLog(e)
      else if (e.type === "listGoals") listGoalsProc.running = true
      else if (e.type === "writeActive") root.writeActiveGoal(e.slug)
      else if (e.type === "warn") console.warn(e.message)
    }
  }

  // ---- what the overlay, the IPC and the tests call ----------------------------
  function tick() { root.run("tick") }
  function togglePause() { root.run("togglePause"); return root.statusJson() }
  function cycleMode() { root.run("cycleMode"); return root.statusJson() }
  function skipSleep() { root.run("skipSleep"); return root.statusJson() }
  function addExtension() { root.run("addExtension") }
  function startBreak() { root.run("startBreak") }
  function extendBreak(minutes) { root.run("extendBreak", minutes) }
  function openNotes() { root.run("openNotes") }
  function closeNotes() { root.run("closeNotes") }
  function saveNote() { root.run("saveNote") }
  function skipUnsavedNotes() { root.run("skipUnsavedNotes") }
  function snooze() { root.run("snooze") }
  function startSleep() { root.run("startSleep") }
  function chooseGoal(slug) { root.run("chooseGoal", slug) }
  function resetRun() { root.run("resetRun") }
  // The notes page's only write to the engine. No rule to run: the text is
  // just kept, and the log reads it when the break ends.
  function setNote(field, text) { root[field] = text }

  function statusJson() { return JSON.stringify(Cycle.status(root.state(), root.now().getTime())) }
  function snapshotJson() { return JSON.stringify(Cycle.snapshot(root.state(), root.now().getTime())) }

  function restore(json) {
    var s = root.state(), ctx = root.context()
    var r = Cycle.restore(s, ctx, json)
    if (r.error !== "") return r.error
    root.commit(s, ctx)
    root.perform(r.fx)
    return root.statusJson()
  }

  // Once a second. The gap check is what Cycle.resumed() is for: QML's
  // Timer doesn't fire during a suspend, and doesn't catch up after one.
  // Measured on the system clock, not now(): a test or the demo moving the
  // engine's clock is not a suspend.
  property real lastTickWallMs: 0
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      var wall = Date.now()
      var gap = root.lastTickWallMs > 0 ? wall - root.lastTickWallMs - interval : 0
      root.lastTickWallMs = wall
      if (gap > Cycle.SUSPEND_GAP_MS) root.run("resumed", gap)
      root.tick()
    }
  }

  // The engine comes up in a fresh run, sized for its mode (the demo's
  // short one included) and stamped with its start, without which its log
  // entry would be refused (notes-helper.py parses "started").
  Component.onCompleted: root.run("startNextRun")

  // ---- the writes ----------------------------------------------------------------
  // Every notes-helper.py call that writes, and the one place the demo is
  // kept from writing: it gets a sink that reads its stdin and discards it,
  // so its Process still starts, takes the payload and exits 0 the way the
  // helper's does. Reading (list-goals) stays live and doesn't come here.
  function writeCommand(args) {
    return root.demo ? ["/bin/sh", "-c", "cat >/dev/null"] : [root.pythonBin, root.notesHelperPath].concat(args)
  }

  // A log effect: the goal's log, or the day file when it has no goal.
  // stdinEnabled must be re-armed before every run: Process.write() is a
  // no-op once it's been turned off, and onStarted turns it off right after
  // writing so the helper's stdin read() sees EOF. The demo goes through the
  // same Process, exit code and all, so the save path it shows is the real
  // one -- only the sink differs.
  function startLog(e) {
    var proc = { note: noteLogProc, finished: finishedRunLogProc, sleep: sleepNoteProc }[e.via]
    proc.payload = e.entry
    proc.cycle = e.cycle
    proc.saved = e.saved || []
    if (root.demo) console.log("ompom demo, not saved:", e.entry)
    proc.command = root.writeCommand(e.slug.length > 0 ? ["append-log", e.slug] : ["append-day"])
    proc.stdinEnabled = true
    proc.running = true
  }

  // One log write: the entry goes to the helper's stdin, which is then
  // closed so its read() sees EOF. When it exits, Cycle.<exited>() is told
  // the code and the cycle it was started in. See notes-helper.py's own
  // docstring for append-log/append-day: both are pure appends with no
  // read-modify-write, opened O_APPEND with no read of the file first, so
  // this is never racing a coaching session or Omvision rewriting the same
  // file. Both exit non-zero and write nothing on a malformed entry.
  component LogProcess: Process {
    id: logProc
    property string exited
    property string payload: ""
    property int cycle: -1
    property var saved: []
    command: []
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      var payload = logProc.payload
      logProc.payload = ""
      root.run(logProc.exited, exitCode, logProc.cycle, payload, logProc.saved)
    }
  }

  // The break's one write (Cycle.saveNote()).
  LogProcess { id: noteLogProc; exited: "noteLogExited" }
  // The one write a mode switch and bedtime make on their way out
  // (Cycle.logFinishedRunOnTheWayOut()). Its own process: by the time it
  // exits the next cycle has begun.
  LogProcess { id: finishedRunLogProc; exited: "finishedLogExited" }
  // The night's notes (Cycle.saveSleepNotes()).
  LogProcess { id: sleepNoteProc; exited: "sleepNoteExited" }

  // Best-effort, matching every other notes-helper call in this file: a
  // failed write here never blocks anything, it just means Omvision's idea
  // of "the active goal" lags behind until the next successful write. The
  // demo's goes nowhere (writeCommand()): the pointer is shared with
  // Omvision and the real engine.
  function writeActiveGoal(slug) {
    writeActiveProc.pendingSlug = slug
    writeActiveProc.stdinEnabled = true
    writeActiveProc.running = true
  }

  Process {
    id: writeActiveProc
    property string pendingSlug: ""
    command: root.writeCommand(["write-active"])
    onStarted: {
      writeActiveProc.write(writeActiveProc.pendingSlug)
      writeActiveProc.stdinEnabled = false
    }
  }

  // ---- the reads ---------------------------------------------------------------
  // Same FileView + watchChanges recipe Commons/Style.qml uses for
  // fontconfig/fonts.conf and the window-gaps toggle: reload() on
  // onFileChanged (text() is stale in that signal itself), then read fresh
  // content from text() once onLoaded fires. Read-only from here -- the
  // only write to this path from this file is writeActiveGoal(); an absent
  // file (no Omvision session has ever run) is just an empty slug, never an
  // error worth printing. liveChange tells Cycle.activeGoalRead() a change
  // from the first load.
  FileView {
    id: activeGoalFile
    property bool liveChange: false
    path: Quickshell.env("HOME") + "/.local/state/omvision/active-goal"
    watchChanges: true
    printErrors: false
    onFileChanged: { activeGoalFile.liveChange = true; reload() }
    onLoaded: {
      root.run("activeGoalRead", text(), activeGoalFile.liveChange)
      activeGoalFile.liveChange = false
    }
    onLoadFailed: {
      root.run("activeGoalRead", "", activeGoalFile.liveChange)
      activeGoalFile.liveChange = false
    }
  }

  // list-goals takes no stdin. Failure -- an old deployed helper without
  // this subcommand, no goal files yet, a permission error -- just means the
  // picker stays empty, never a crash; see notes-helper.py's own "skip what
  // can't parse" contract for list-goals.
  Process {
    id: listGoalsProc
    command: [root.pythonBin, root.notesHelperPath, "list-goals"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = []
        try { parsed = JSON.parse(text || "[]") } catch (e) { parsed = [] }
        root.goalsList = Array.isArray(parsed) ? parsed : []
      }
    }
    onStarted: listGoalsProc.stdinEnabled = false
    onExited: function(exitCode) {
      if (exitCode !== 0) root.goalsList = []
    }
  }

  IpcHandler {
    // Its own target in the demo, so a script aimed at "ompom" can never
    // be answered by the demo instead of the real engine.
    target: root.demo ? "ompom-demo" : "ompom"
    function status(): string { return root.statusJson() }
    function togglePause(): string { return root.togglePause() }
    function cycleMode(): string { return root.cycleMode() }
    // For bin/omvision-deploy only -- see Cycle.snapshot().
    function snapshot(): string { return root.snapshotJson() }
    function restore(json: string): string { return root.restore(json) }
    function skipSleep(): string { return root.skipSleep() }
  }
}
