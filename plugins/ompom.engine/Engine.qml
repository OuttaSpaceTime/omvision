import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Ompom's pomodoro cycle: the timer state machine, the break's notes, and
// every write they lead to. No window of its own: Service.qml, the plugin's
// entry point, puts Overlay.qml (which only reads this and calls its
// functions) in a layer-shell PanelWindow, and tests/engine puts the same
// overlay in a FloatingWindow, since offscreen `qs` has no layer shell. The
// split is what lets the tests run the shipped files rather than a patched
// copy of one big Service.qml.
Item {
  id: root

  // Set only by bin/ompom-demo, which loads this same file in its own qs
  // process, so the overlay can be seen and clicked through as it really is
  // without waiting out a 25/5 cycle and without touching the real engine
  // running inside omarchy-shell. Everything the demo changes is gated on
  // this one flag: short timers (below), no disk writes (break notes are
  // printed instead of appended, the active goal is never written), its own
  // IPC target, and Ctrl+Q to quit. Reading the goal list stays live, so the
  // picker shows the real goals. A copied harness was the alternative, and
  // was rejected: it drifts from this file and then demos something that no
  // longer ships.
  property bool demo: false
  property int demoFocusSec: 5
  property int demoBreakSec: 5

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

  // notes-helper.py's MAX_NOTE_INPUT_BYTES: it reads no more of an entry
  // than this, so a longer one would arrive cut off, as invalid JSON, and be
  // refused on every retry. finishedRunEntry() shortens the notes to fit
  // instead.
  readonly property int maxNoteInputBytes: 20000

  readonly property int normalFocusSec: 25 * 60
  readonly property int normalBreakSec: 5 * 60
  readonly property int longFocusSec: 50 * 60
  readonly property int longBreakSec: 10 * 60
  // The classic pomodoro set: every fourth break in Normal mode is a long
  // one. Long Focus already has a 10 minute break after every 50 minutes,
  // which is the same rest per hour, so it has no set of its own.
  readonly property int setBreakSec: 15 * 60
  readonly property int runsPerSet: 4
  readonly property int extensionSec: demo ? demoFocusSec : 60
  readonly property int maxExtensions: 3

  readonly property int focusSecFor: demo ? demoFocusSec : (mode === "long" ? longFocusSec : normalFocusSec)

  function breakSecFor(isSetBreak) {
    if (root.demo) return isSetBreak ? root.demoBreakSec * 3 : root.demoBreakSec
    if (isSetBreak) return root.setBreakSec
    return root.mode === "long" ? root.longBreakSec : root.normalBreakSec
  }

  // --- bedtime ---
  // At 22:15 the engine stops whatever it was doing and puts up "Time to
  // sleep" (phase "bedtime"); +1 minute takes the overlay down for a minute
  // ("snooze"), three times at most. From 22:20 to 05:30 the night's screen
  // ("sleep") is the only thing on the laptop: a countdown to 05:30 and the
  // notes page, nothing else. It follows the clock rather than a countdown
  // of its own (followTheClock(), every tick), so a login, a resume from
  // suspend or a deploy at any hour of the night lands on the right screen,
  // and a suspended night still ends at 05:30. It holds in every mode,
  // "off" too: bedtime isn't a pomodoro, and switching the timer off is no
  // way around it.
  readonly property int bedtimeMinute: 22 * 60 + 15
  readonly property int lightsOutMinute: 22 * 60 + 20
  readonly property int wakeMinute: 5 * 60 + 30
  readonly property int snoozeSec: 60
  readonly property int maxSnoozes: 3
  readonly property var nightPhases: ["bedtime", "snooze", "sleep"]
  readonly property bool atNight: nightPhases.indexOf(phase) !== -1
  property int snoozesUsed: 0
  // The night's notes as one entry, re-saved whole on every close that
  // changed them (saveSleepNotes()): the stamp its heading carries, fixed at
  // the night's first save, and the text as it was last written, so a close
  // that changed nothing appends nothing. Both are cycle state: a deploy in
  // the night that lost the stamp would start a second heading.
  property string sleepNotesIso: ""
  property var sleepNotesSaved: ["", "", ""]
  // The night skipSleep() was used on (nightOf()), so the clock doesn't put
  // the overlay straight back up on the next tick. "" is none.
  property string sleepSkippedNight: ""
  // Added to the system clock. Set by tests/engine and bin/ompom-demo
  // --clock, so a night can be tried at noon; the live engine leaves it 0.
  property real clockOffsetMs: 0

  // normal | long | off
  property string mode: "normal"
  // focus | prompt | extend | break, or one of nightPhases above. There is no screen before a run: the
  // next focus run starts the moment its break ends (startNextRun()), on
  // whatever goal is selected, and the engine comes up in "focus" so logging
  // in never drops a blocking overlay on top of whatever you were doing.
  // A "What's your focus?" screen before every run used to sit here; the
  // break notes' "What's left?" already says what comes next, so it was a
  // second writing prompt for the same thing.
  property string phase: "focus"
  property bool paused: false
  property int remaining: normalFocusSec
  property int extensionsUsed: 0
  property bool notesOpen: false
  // The break's three notes sections, as typed. Here rather than in the
  // overlay's fields, so the log entry, the snapshot and a restore all read
  // and write plain strings.
  property string doneText: ""
  property string leftText: ""
  property string elseText: ""
  // The one list of them: the property each is typed into, the key
  // notes-helper.py files it under (goal-files.md §4), and the heading the
  // notes page gives it, in the order the log writes them. The heading
  // lives here with the key rather than in Overlay.qml: the log keeps one
  // line per question, so a question renamed or added is a change to both.
  readonly property var notes: [
    { field: "doneText", key: "done", title: "What's done?" },
    { field: "leftText", key: "left", title: "What's left?" },
    { field: "elseText", key: "else", title: "What else?" }
  ]
  function noteTexts() { return root.notes.map(function(n) { return root[n.field] }) }
  // The notes page's only write to the engine.
  function setNote(field, text) { root[field] = text }

  // --- goal ---
  // The selected goal (a slug, or "" for none), kept live from the
  // active-goal file (see activeGoalFile), and the goal list the break's
  // picker offers, re-read at the start of every break (refreshGoalData()).
  property string activeGoalSlug: ""
  property var goalsList: []
  // What the picker offers: the open goals that can be worked on at the
  // laptop. `focusable: no` (goal-files.md §6) marks the rest -- training,
  // sleep, a habit -- which still log events from Omvision but are no run's
  // goal. A helper deployed before the key existed sends no `focusable` at
  // all, so only an explicit false drops a goal. Done and cancelled goals
  // are finished work, not a next run's; any other status, a missing one
  // included (§6: it reads as active), stays. goalsList itself stays whole:
  // an active goal closed or marked unfocusable since it was picked still
  // has a title.
  readonly property var pickableGoals: root.goalsList.filter(function(g) {
    return g && g.focusable !== false && g.status !== "done" && g.status !== "cancelled"
  })
  // Whether Ctrl+G has anything to offer: a goal to pick, or an active one
  // for "No goal" to drop.
  readonly property bool canPickGoal: root.pickableGoals.length > 0 || root.activeGoalSlug.length > 0
  readonly property string activeGoalTitle: root.goalTitleForSlug(root.activeGoalSlug)
  // The goal the run that just finished was spent on, pinned when its
  // break starts. Picking a goal during the break is picking the *next*
  // run's goal, so the finished run's entry must not follow it into a log
  // it was never worked on.
  property string runGoalSlug: ""
  // Stamped in startNextRun(), read back in finishedRunEntry() -- together
  // with finishedRunMinutes() and the three notes, the whole log entry.
  property string focusStartedIso: ""
  // -1 is "no mid-run change": the goal active when the run started (or no
  // goal at all) gets the whole run's minutes. A non-negative value is
  // `remaining` as it stood the moment activeGoalFile last changed WHILE
  // phase was "focus" -- see onActiveGoalFileText() -- because only the
  // remainder was ever spent on whatever became active at that moment.
  // Reset to -1 at the start of every run (startNextRun()).
  property int goalAttributionRemaining: -1

  // --- the long break ---
  // Finished Normal runs since the last long break, and the day they were
  // counted on: a new day starts a new set rather than finishing
  // yesterday's. A mode switch starts one too (resetRun()).
  property int runsInSet: 0
  property string setDay: ""
  // Whether the break now running is the set's long one: fixed when the
  // break starts, so the label and a restart agree on it.
  property bool breakIsLong: false

  // --- the break's log write ---
  // Set when the break's one write comes back non-zero. The break then
  // stays up at 0:00, its text untouched, with "Try again" and "Skip" in
  // place of the extension buttons: the alternative, starting the next run
  // anyway, would hide a pomodoro that was never logged behind a closed
  // overlay.
  property bool notesSaveFailed: false
  // True from the moment saveNote() kicks off noteLogProc until it exits,
  // so the tick that reaches 0:00 and a "Try again" click in the same
  // instant can't both append the same run.
  property bool notesSavePending: false
  // One entry per pomodoro, full stop: the log is append-only. Set the
  // moment this cycle's entry is on disk, cleared with the rest of the
  // cycle in startNextRun(). Within one process the next run starts in the
  // same handler that sets it; it matters for a snapshot taken from an
  // older engine, which saved on leaving the notes view, so a break
  // restored from one doesn't log its run a second time when it ends.
  property bool cycleLogged: false

  // extend deliberately behaves like focus here: no overlay, normal desktop
  // use, just a ticking bar countdown you can't pause or escape via mode
  // switch until it runs out and drops you back at the prompt overlay.
  // break is the mirror case: overlay stays up, and togglePause/cycleMode
  // both refuse to act, so there's no way to pause or mode-switch your way
  // out of it early either. It only ends on its own, after whatever
  // minutes you add to it.
  readonly property bool overlayVisible: (mode !== "off" && (phase === "prompt" || phase === "break"))
    || phase === "bedtime" || phase === "sleep"

  // The snooze counts down in every mode, like the rest of the night; the
  // night's other two phases follow the clock instead (followTheClock()).
  readonly property bool countdownRunning: phase === "snooze" || (!atNight && mode !== "off" && !paused)

  // The phases with a notes page: a break, and the night.
  readonly property bool hasNotes: phase === "break" || phase === "sleep"

  readonly property string wakeLabel: pad2(Math.floor(wakeMinute / 60)) + ":" + pad2(wakeMinute % 60)

  function pad2(n) { return (n < 10 ? "0" : "") + n }

  // mm:ss, or h:mm:ss from an hour up: the night's countdown runs to seven
  // hours, and "429:59" doesn't read as a time.
  function fmt(totalSeconds) {
    var s = Math.max(0, totalSeconds)
    var h = Math.floor(s / 3600)
    return (h > 0 ? h + ":" : "") + root.pad2(Math.floor(s / 60) % 60) + ":" + root.pad2(s % 60)
  }

  function statusJson() {
    return JSON.stringify({
      mode: root.mode,
      phase: root.phase,
      remaining: root.remaining,
      remainingLabel: root.fmt(root.remaining),
      paused: root.paused,
      extensionsUsed: root.extensionsUsed,
      maxExtensions: root.maxExtensions,
      breakIsLong: root.breakIsLong,
      overlay: root.overlayVisible
    })
  }

  // --- hand-off across a shell restart ---
  // The manifest's keepLoaded keeps this engine alive through plugin
  // hot-reloads, which is what lets the bar widget be redeployed without
  // touching the timer. The price is that a new engine (Service.qml and
  // the files it uses) only loads on a whole-shell restart, which would start every deploy on a fresh 25
  // minutes. bin/omvision-deploy bridges that: snapshot() before the restart,
  // restore() into the new engine after it. PersistentProperties was the
  // obvious alternative and doesn't apply: it carries state across a
  // Quickshell reload, but a restart is a new process, and even a plugin
  // reload destroys and recreates this object rather than reloading it.
  //
  // Only the cycle is carried, never an in-flight save: a note write in
  // progress at snapshot time either landed (the log has it) or didn't
  // (the break ends again in the new engine, which retries it).
  readonly property int handoffMaxAgeMs: 5 * 60 * 1000

  // Every property the hand-off carries, each with the check restore()
  // puts it through: a new piece of cycle state is one row here, and
  // snapshotJson() and restore() both follow the list. A snapshot is at
  // most handoffMaxAgeMs old and only ever comes from the engine deployed
  // just before, so a row this engine adds takes `optional: true` for the
  // one deploy that hands off from an engine without it (restore() then
  // keeps the fresh run's value), and loses it after: rows don't stay
  // optional for good, as the old engine's did. Keys a snapshot has and
  // this list doesn't (an older engine's `focusText`) are ignored.
  readonly property var cycleFields: [
    { name: "mode", ok: root.isOneOf(["normal", "long", "off"]) },
    { name: "phase", ok: root.isOneOf(["focus", "prompt", "extend", "break"].concat(root.nightPhases)) },
    { name: "paused", ok: root.isBool },
    { name: "remaining", ok: root.isInt(0, 4 * 3600) },
    { name: "extensionsUsed", ok: root.isInt(0, root.maxExtensions) },
    { name: "focusStartedIso", ok: root.isStamp },
    { name: "goalAttributionRemaining", ok: root.isInt(-1, 4 * 3600) },
    { name: "cycleLogged", ok: root.isBool },
    { name: "notesOpen", ok: root.isBool },
    { name: "runGoalSlug", ok: root.isString },
    { name: "runsInSet", ok: root.isInt(0, root.runsPerSet - 1) },
    { name: "setDay", ok: root.isDay },
    { name: "breakIsLong", ok: root.isBool },
    { name: "snoozesUsed", ok: root.isInt(0, root.maxSnoozes) },
    { name: "sleepSkippedNight", ok: root.isDay },
    { name: "sleepNotesIso", ok: root.isStamp },
    { name: "sleepNotesSaved", ok: function(v) {
      return Array.isArray(v) && v.length === root.notes.length && v.every(root.isString) } }
  ].concat(root.notes.map(function(n) { return { name: n.field, ok: root.isString } }))

  function isBool(v) { return typeof v === "boolean" }
  function isString(v) { return typeof v === "string" }
  function isInt(lo, hi) { return function(v) { return Number.isInteger(v) && v >= lo && v <= hi } }
  function isOneOf(values) { return function(v) { return values.indexOf(v) !== -1 } }
  // "" or a date, and "" or isoOf()'s stamp: both are unset as "".
  function isDay(v) { return typeof v === "string" && /^(\d{4}-\d\d-\d\d)?$/.test(v) }
  function isStamp(v) { return typeof v === "string" && /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)?$/.test(v) }

  function snapshotJson() {
    var s = { takenAtMs: Date.now() }
    for (var f of root.cycleFields) s[f.name] = root[f.name]
    return JSON.stringify(s)
  }

  // Takes what snapshotJson() gives. Every field is checked before anything
  // is assigned, so a bad hand-off leaves the fresh engine exactly as it
  // started rather than half-restored.
  function restore(json) {
    var s
    try { s = JSON.parse(String(json || "")) } catch (e) { return "error: not JSON" }
    if (!Util.isPlainObject(s)) return "error: not an object"
    var age = Date.now() - s.takenAtMs
    if (!(age >= 0 && age <= root.handoffMaxAgeMs))
      return "error: snapshot missing takenAtMs or older than " + (root.handoffMaxAgeMs / 60000) + " minutes"
    for (var f of root.cycleFields)
      if (!(f.optional && s[f.name] === undefined) && !f.ok(s[f.name])) return "error: bad " + f.name

    // From the baseline every new cycle starts from, then the snapshot on
    // top of it. The mode goes first: the fresh run resetRun() starts is
    // sized by it.
    root.mode = s.mode
    root.resetRun()
    for (f of root.cycleFields) if (s[f.name] !== undefined) root[f.name] = s[f.name]
    // The countdown kept running in the old process until the restart,
    // so the time since the snapshot is taken off it. A countdown that
    // runs out this way is left at 0 for the next tick() to move on from,
    // exactly as if it had run out here.
    root.remaining = root.countdownRunning ? Math.max(0, s.remaining - Math.round(age / 1000)) : s.remaining
    // The picker's list is otherwise only read when a break starts, and this
    // one started in another process.
    if (root.phase === "break") root.refreshGoalData()
    return root.statusJson()
  }

  // Back to the start of a fresh run, the long-break set included: what a
  // mode switch and a restore begin from.
  function resetRun() {
    root.paused = false
    root.runsInSet = 0
    root.setDay = ""
    root.startNextRun()
  }

  function cycleMode() {
    if (root.phase === "extend" || root.phase === "break" || root.atNight) return root.statusJson()
    // A finished pomodoro is logged before the reset below throws its cycle
    // away. Switching mode at the +1 minute / Start break prompt used to
    // drop a run that had fully happened, just because no break was taken
    // to log it.
    root.logFinishedRunOnTheWayOut()
    if (root.mode === "normal") root.mode = "long"
    else if (root.mode === "long") root.mode = "off"
    else root.mode = "normal"
    // A mode switch never raises the overlay (it only comes up when a run
    // ends), so clicking through the modes on the bar just restarts the
    // run in each one, and the last one clicked is the one that runs.
    root.resetRun()
    return root.statusJson()
  }

  // A finished run's minutes: the whole focus time (or, after a mid-run goal
  // change, only what was left of it -- see goalAttributionRemaining) plus
  // every +1 minute taken at the prompt.
  function finishedRunMinutes() {
    var minutesBase = root.goalAttributionRemaining >= 0 ? root.goalAttributionRemaining : root.focusSecFor
    return Math.round(minutesBase / 60) + root.extensionsUsed
  }

  // Every notes-helper.py call that writes, and the one place the demo is
  // kept from writing: it gets a sink that reads its stdin and discards it,
  // so its Process still starts, takes the payload and exits 0 the way the
  // helper's does. Reading (list-goals) stays live and doesn't come here.
  function writeCommand(args) {
    return root.demo ? ["/bin/sh", "-c", "cat >/dev/null"] : [root.pythonBin, root.notesHelperPath].concat(args)
  }

  // Where a finished run is written: the goal's log, or the day file when
  // no goal was selected.
  function logCommandFor(slug) {
    return root.writeCommand(slug.length > 0 ? ["append-log", slug] : ["append-day"])
  }

  // The entry for the run that just finished, with whatever notes are typed.
  function finishedRunEntry() {
    return root.entryJson(root.focusStartedIso, root.finishedRunMinutes(), root.noteTexts())
  }

  // Any entry carrying the notes (`texts`, in root.notes' order), as
  // notes-helper.py reads it: a finished run's, or the night's (0 minutes,
  // see saveSleepNotes()). The texts are passed in rather than read here,
  // so the trimming below can be tried on any text without typing it into
  // the notes page.
  //
  // An entry over the helper's limit has its longest note cut short, with
  // "…" to say so, until it fits: the helper would otherwise read it cut off
  // mid-JSON and refuse it, every retry alike, and the run would only get
  // past "Not saved" by being skipped. Only a paste could get there.
  function entryJson(started, minutes, texts) {
    var entry = { started: started, minutes: minutes }
    var keys = root.notes.map(function(n) { return n.key })
    keys.forEach(function(k, i) { entry[k] = texts[i] })
    var json = JSON.stringify(entry)
    for (var over = root.utf8Bytes(json) - root.maxNoteInputBytes; over > 0;
         over = root.utf8Bytes(json) - root.maxNoteInputBytes) {
      var key = keys.reduce(function(a, b) { return entry[a].length >= entry[b].length ? a : b })
      // Every character costs at least a byte, and "…" adds three back.
      var kept = entry[key].slice(0, Math.max(0, entry[key].length - over - 3))
      // Never half an emoji: a lone surrogate can't be encoded as UTF-8,
      // and the helper would refuse the entry over it.
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

  // Starts one of the log writes, stamped with the cycle it belongs to (see
  // `cycle`). stdinEnabled must be re-armed before every run: Process.write() is a
  // no-op once it's been turned off, and onStarted turns it off right after
  // writing so the helper's stdin read() sees EOF. The demo goes through the
  // same Process, exit code and all, so the save path it shows is the real
  // one -- only the sink differs.
  function startLog(proc, slug, entry) {
    proc.payload = entry
    proc.cycle = root.cycle
    if (root.demo) console.log("ompom demo, not saved:", proc.payload)
    proc.command = root.logCommandFor(slug)
    proc.stdinEnabled = true
    proc.running = true
  }

  // Called by cycleMode() just before its reset: a run that reached the
  // prompt is a pomodoro that happened, so it's logged with blank notes,
  // like a break that ran out untouched. Not a partial run switched off
  // mid-focus: that isn't a pomodoro. Bedtime (goToBed()) calls it too, and
  // can also land in a break: that run is logged with its notes as they
  // stand, since the break will never reach its end. A break whose own write
  // is in flight is left to it, and one refused already only goes to the
  // shell's log, as Skip would.
  //
  // Through its own process rather than saveNote(): the write finishes
  // after resetRun() has already begun the next cycle, and saveNote()'s
  // exit handler would act on *that* cycle. There is nowhere left to show a
  // refusal once the overlay is gone, so one is only warned.
  function logFinishedRunOnTheWayOut() {
    var slug
    if (root.phase === "prompt") slug = root.activeGoalSlug
    else if (root.phase === "break" && !root.cycleLogged && !root.notesSavePending) slug = root.runGoalSlug
    else return
    if (root.notesSaveFailed) {
      console.warn("ompom: break notes not logged, refused before the cycle was dropped:", root.finishedRunEntry())
      return
    }
    if (finishedRunLogProc.running) {
      console.warn("ompom: previous run still being logged, this one was not:", root.finishedRunEntry())
      return
    }
    root.startLog(finishedRunLogProc, slug, root.finishedRunEntry())
  }

  function togglePause() {
    if (root.mode === "off" || root.phase !== "focus") return root.statusJson()
    root.paused = !root.paused
    return root.statusJson()
  }

  function tick() {
    root.followTheClock()
    if (!root.countdownRunning) return
    if (root.remaining > 0) {
      root.remaining -= 1
      return
    }
    if (root.phase === "focus" || root.phase === "extend") {
      root.phase = "prompt"
    } else if (root.phase === "snooze") {
      root.phase = "bedtime"
    } else if (root.phase === "break") {
      // The break's end is when its run is logged, whether or not a note
      // was ever written: started/minutes are real information either way.
      // The next run starts once the write lands (noteLogProc.onExited);
      // until then, and after a refusal, the break holds at 0:00.
      if (root.notesSavePending || root.notesSaveFailed) return
      if (root.cycleLogged) root.startNextRun()
      else root.saveNote()
    }
  }

  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: root.tick()
  }

  function addExtension() {
    if (root.phase !== "prompt") return
    if (root.extensionsUsed >= root.maxExtensions) return
    root.extensionsUsed += 1
    root.phase = "extend"
    root.remaining = root.extensionSec
  }

  function startBreak() {
    if (root.phase !== "prompt") return
    if (root.mode === "normal") {
      var today = root.isoNow().slice(0, 10)
      if (root.setDay !== today) {
        root.setDay = today
        root.runsInSet = 0
      }
      root.runsInSet += 1
    }
    root.breakIsLong = root.runsInSet >= root.runsPerSet
    if (root.breakIsLong) root.runsInSet = 0
    root.phase = "break"
    root.remaining = root.breakSecFor(root.breakIsLong)
    root.runGoalSlug = root.activeGoalSlug
    root.refreshGoalData()
    // The break opens on its ticking countdown, never on the notes view:
    // opening the notes straight away turned every break into a writing
    // prompt and hid the one thing a break is for, time away. Writing is
    // one "Take notes" click away.
  }

  // The break's +1/+2/+3 min buttons. No cap, unlike the focus run's
  // extensions: those are the run eating into the rest, these are more
  // rest. After a refused save they're hidden (see notesSaveFailed), so a
  // break is never stretched just to postpone a failure.
  function extendBreak(minutes) {
    if (root.phase !== "break" || root.notesSavePending || root.notesSaveFailed) return
    root.remaining += minutes * 60
  }

  // Shows the notes page with whatever this break has already put in it:
  // only the next run's start clears it (startNextRun()). The night has the
  // same page.
  function openNotes() {
    if (!root.hasNotes) return
    root.notesOpen = true
  }

  // Back to the countdown. In a break it never saves: the run is logged
  // once, when the break ends, with the notes as they stand then, so the
  // page can be opened and left as often as the break allows. The night is
  // the other way round, see saveSleepNotes().
  function closeNotes() {
    root.notesOpen = false
    if (root.phase === "sleep") root.saveSleepNotes()
  }

  // The one write for a completed pomodoro: the run's goal log (append-log),
  // or the day file when it had no goal (append-day), always with an entry,
  // even one with blank notes. On a non-zero exit (a malformed entry the
  // helper refused, a bad slug, or -- mid-deploy -- an old helper) the
  // write never happened, so nothing acts like it did: the text is never
  // touched here, and noteLogProc.onExited decides between starting the
  // next run and holding the break with "Not saved" up.
  function saveNote() {
    if (root.notesSavePending || root.cycleLogged) return
    root.notesSaveFailed = false
    root.notesSavePending = true
    root.startLog(noteLogProc, root.runGoalSlug, root.finishedRunEntry())
  }

  // "Skip" after a refused save: the run goes unlogged rather than holding
  // the screen forever (an old helper mid-deploy refuses every time). The
  // entry goes to the shell's log, so it isn't lost without a trace.
  function skipUnsavedNotes() {
    if (!root.notesSaveFailed) return
    console.warn("ompom: break notes not logged, skipped after a refused save:", root.finishedRunEntry())
    root.startNextRun()
  }

  // --- the night ---
  function now() { return new Date(Date.now() + root.clockOffsetMs) }
  function minuteOfDay(d) { return d.getHours() * 60 + d.getMinutes() }
  // From `from` in the evening until the wake-up, across midnight.
  function nightFrom(minute, from) { return minute >= from || minute < root.wakeMinute }
  // The evening a night began on: 02:00 on the 17th is the night of the 16th.
  function nightOf(d) {
    var n = new Date(d.getTime())
    if (root.minuteOfDay(d) < root.wakeMinute) n.setDate(n.getDate() - 1)
    return root.isoOf(n).slice(0, 10)
  }
  function secondsUntilWake(d) {
    var w = new Date(d.getTime())
    w.setHours(Math.floor(root.wakeMinute / 60), root.wakeMinute % 60, 0, 0)
    if (w.getTime() <= d.getTime()) w.setDate(w.getDate() + 1)
    return Math.round((w.getTime() - d.getTime()) / 1000)
  }

  // Every tick, before anything else: puts the engine where the clock says
  // it belongs. Into bed from any phase at 22:15, straight into the night
  // from 22:20 on (whatever snooze or prompt was up), and back to a fresh
  // run at 05:30.
  function followTheClock() {
    var d = root.now()
    var minute = root.minuteOfDay(d)
    if (!root.nightFrom(minute, root.bedtimeMinute) || root.sleepSkippedNight === root.nightOf(d)) {
      if (root.atNight) root.wake()
      return
    }
    if (!root.atNight) root.goToBed()
    if (root.nightFrom(minute, root.lightsOutMinute)) root.startSleep()
    if (root.phase === "sleep") root.remaining = root.secondsUntilWake(d)
  }

  // Whatever was running ends here. A finished run (at the prompt or in its
  // break) is logged first; a focus run cut off part-way isn't, as with a
  // mode switch, since it isn't a pomodoro.
  function goToBed() {
    root.logFinishedRunOnTheWayOut()
    root.clearCycle()
    root.paused = false
    root.snoozesUsed = 0
    root.phase = "bedtime"
    root.remaining = 0
  }

  // "+1 minute" on "Time to sleep": the overlay goes for a minute, and comes
  // back. Never past 22:20, where followTheClock() starts the night.
  function snooze() {
    if (root.phase !== "bedtime" || root.snoozesUsed >= root.maxSnoozes) return
    root.snoozesUsed += 1
    root.phase = "snooze"
    root.remaining = root.snoozeSec
  }

  // "Good night", or 22:20.
  function startSleep() {
    if (root.phase !== "bedtime" && root.phase !== "snooze") return
    root.phase = "sleep"
    root.remaining = root.secondsUntilWake(root.now())
  }

  // 05:30: any notes still unsaved are written, and the day starts on a
  // fresh run and a fresh set.
  function wake() {
    if (root.phase === "sleep") root.saveSleepNotes()
    root.resetRun()
  }

  // The way out of a night, for when the laptop is really needed: an IPC
  // call only (`omarchy-shell ompom skipSleep`, from a TTY if need be), so
  // nothing on the overlay offers it. It lasts the rest of this night; the
  // next one starts at 22:15 as usual.
  function skipSleep() {
    root.sleepSkippedNight = root.nightOf(root.now())
    root.followTheClock()
    return root.statusJson()
  }

  // The night's notes go to the day file each time the page is closed (and
  // at 05:30), and stay on the page: it's one page for the whole night, as a
  // break's is for the break. Not saved once at the night's end, as a break
  // does: a laptop switched off overnight would take them with it. So each
  // close that changed them appends the whole text again, under the one
  // heading the night's first save stamped, and Parser.js shows only the
  // last copy (goal-files.md §4). An entry of 0 minutes: notes with no run
  // behind them, never counted as a pomodoro.
  //
  // Clearing the page after each save was the first version: every reopen
  // showed an empty page, and what had been written looked lost. Appending
  // only what was added since was the other way, and was rejected: an edit
  // in the middle of the text has no "added since".
  function saveSleepNotes() {
    var text = root.noteTexts()
    if (text.every(function(t) { return t.trim() === "" })) return
    if (text.every(function(t, i) { return t === root.sleepNotesSaved[i] })) return
    // A save still running takes this text with the next close, or at 05:30.
    if (sleepNoteProc.running) return
    if (root.sleepNotesIso === "") root.sleepNotesIso = root.isoNow()
    root.notesSaveFailed = false
    sleepNoteProc.saved = text
    root.startLog(sleepNoteProc, "", root.entryJson(root.sleepNotesIso, 0, text))
  }

  // Local-time, no offset suffix -- matches what notes-helper.py's
  // format_timestamp() expects from datetime.fromisoformat() and, more
  // importantly, what it then renders with a local strftime(): a UTC
  // timestamp here would print the wrong wall-clock hour in the log.
  function isoNow() {
    return root.isoOf(root.now())
  }

  function isoOf(d) {
    var pad = root.pad2
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
      "T" + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
  }

  // One log write: the entry goes to the helper's stdin, which is then
  // closed so its read() sees EOF. startLog() fills in the rest.
  component LogProcess: Process {
    property string payload: ""
    // The cycle startLog() started it in; see isStale().
    property int cycle: -1
    command: []
    onStarted: {
      write(payload)
      stdinEnabled = false
    }
  }

  // See notes-helper.py's own docstring for append-log/append-day: both are
  // pure appends with no read-modify-write, opened O_APPEND with no read of
  // the file first, so this is never racing a coaching session or Omvision
  // rewriting the same file. Both exit non-zero and write nothing on a
  // malformed entry.
  LogProcess {
    id: noteLogProc
    onExited: function(exitCode) {
      root.notesSavePending = false
      var payload = noteLogProc.payload
      noteLogProc.payload = ""
      if (root.isStale(noteLogProc)) {
        if (exitCode !== 0) console.warn("ompom: break notes not logged (helper exit " + exitCode + "):", payload)
        return
      }
      if (exitCode === 0) {
        root.cycleLogged = true
        root.startNextRun()
      } else {
        root.notesSaveFailed = true
      }
    }
  }

  // The one write cycleMode() and goToBed() make on their way out -- see
  // logFinishedRunOnTheWayOut(). Fire and forget: by the time it exits the
  // next cycle has begun, so it touches none of the cycle state noteLogProc
  // does.
  LogProcess {
    id: finishedRunLogProc
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("ompom: finished run not logged (helper exit " + exitCode + "):", finishedRunLogProc.payload)
      finishedRunLogProc.payload = ""
    }
  }


  // saveSleepNotes()'s write. Records the text it carried as saved, which
  // is what the next close compares against. A refusal says so and records
  // nothing, so the next close tries again. After 05:30 nothing is left to
  // show it on, so it's only warned.
  LogProcess {
    id: sleepNoteProc
    property var saved: []
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        if (!root.isStale(sleepNoteProc)) root.notesSaveFailed = true
        else console.warn("ompom: night notes not logged (helper exit " + exitCode + "):", sleepNoteProc.payload)
      } else if (!root.isStale(sleepNoteProc)) {
        root.sleepNotesSaved = sleepNoteProc.saved
      }
      sleepNoteProc.payload = ""
    }
  }

  // A fresh focus run on the selected goal, with this cycle's notes and
  // extensions cleared: at the end of a break whose run is logged (or
  // skipped), at startup, and from resetRun(). Only this and goToBed()
  // clear a cycle's notes, so they last through every close and reopen of
  // the notes page in the break they belong to.
  function startNextRun() {
    root.clearCycle()
    root.phase = "focus"
    root.remaining = root.focusSecFor
    root.focusStartedIso = root.isoNow()
    root.breakIsLong = false
    // Fresh run, no mid-run goal change yet -- see its own comment.
    root.goalAttributionRemaining = -1
  }

  // Counts clearCycle()s. A log write stamped with an older one exits into a
  // cycle that isn't its own -- a bedtime, a 05:30 or a restore moved on
  // while it ran -- so it leaves this one's state alone. Testing the phase
  // instead would miss a write that outlives its break and finds a later one.
  property int cycle: 0
  function isStale(proc) { return proc.cycle !== root.cycle }

  // Everything one cycle collects, gone: by startNextRun(), and by
  // goToBed(), whose night starts with an empty notes page.
  function clearCycle() {
    root.cycle += 1
    root.extensionsUsed = 0
    root.notesOpen = false
    root.notesSaveFailed = false
    root.cycleLogged = false
    for (var n of root.notes) root[n.field] = ""
    root.sleepNotesIso = ""
    root.sleepNotesSaved = root.notes.map(function() { return "" })
  }

  // Best-effort, matching every other notes-helper call in this file: a
  // failed write here never blocks anything, it just means Omvision's idea
  // of "the active goal" lags behind until the next successful write. The
  // demo's goes nowhere (writeCommand()): the pointer is shared with
  // Omvision and the real engine.
  function writeActiveGoal() {
    writeActiveProc.pendingSlug = root.activeGoalSlug
    writeActiveProc.stdinEnabled = true
    writeActiveProc.running = true
  }

  // Re-reads the goal list at the start of every break, where the picker
  // is, rather than caching it across a whole session, so a goal created,
  // renamed, or closed in Omvision between pomodoros shows up on the very
  // next break. activeGoalSlug doesn't need this: it's kept live by
  // activeGoalFile below.
  function refreshGoalData() {
    listGoalsProc.running = true
  }

  // The active-goal pointer (~/.local/state/omvision/active-goal) can
  // change out from under ompom two ways: our own writeActiveGoal() when a
  // goal is picked in the break, and Omvision writing it, which can happen
  // while a focus run is already ticking. isLiveChange tells a genuine
  // change (activeGoalFile's onFileChanged fired) from the file's first
  // load, which is not a change of goal mid-run: the run the engine starts
  // with simply runs on the goal that was selected last.
  function onActiveGoalFileText(rawSlug, isLiveChange) {
    var slug = String(rawSlug || "").trim()
    if (isLiveChange && root.phase === "focus" && slug !== root.activeGoalSlug) {
      // Only the remainder counts: the minutes before this moment were
      // spent on whatever was active before (or on nothing), never on the
      // newly active goal. Clearing (slug === "") resets to the full run
      // length rather than a partial one -- see goalAttributionRemaining's
      // own comment for why that's the right default for append-day too.
      root.goalAttributionRemaining = slug.length > 0 ? root.remaining : -1
    }
    root.activeGoalSlug = slug
  }

  function goalTitleForSlug(slug) {
    if (!slug) return ""
    for (var i = 0; i < root.goalsList.length; i++) {
      var g = root.goalsList[i]
      if (g && g.slug === slug) return String(g.title || g.slug)
    }
    return ""
  }

  // The next run's goal: written straight away, so Omvision and the bar
  // show it during the break rather than only once the run starts.
  function chooseGoal(slug) {
    root.activeGoalSlug = String(slug || "")
    root.writeActiveGoal()
  }

  // The engine comes up in a fresh run, sized for its mode (the demo's
  // short one included) and stamped with its start, without which its log
  // entry would be refused (notes-helper.py parses "started").
  Component.onCompleted: root.startNextRun()

  // Same FileView + watchChanges recipe Commons/Style.qml uses for
  // fontconfig/fonts.conf and the window-gaps toggle: reload() on
  // onFileChanged (text() is stale in that signal itself), then read
  // fresh content from text() once onLoaded fires. Read-only from here --
  // the only write to this path from this file is writeActiveGoal(); an
  // absent file (no Omvision session has ever run) is just an empty slug,
  // never an error worth printing.
  FileView {
    id: activeGoalFile
    property bool liveChange: false
    path: Quickshell.env("HOME") + "/.local/state/omvision/active-goal"
    watchChanges: true
    printErrors: false
    onFileChanged: { activeGoalFile.liveChange = true; reload() }
    onLoaded: {
      root.onActiveGoalFileText(text(), activeGoalFile.liveChange)
      activeGoalFile.liveChange = false
    }
    onLoadFailed: {
      root.onActiveGoalFileText("", activeGoalFile.liveChange)
      activeGoalFile.liveChange = false
    }
  }

  // list-goals takes no stdin and is re-run at the start of every break
  // (see refreshGoalData()). Failure -- an old deployed helper without this
  // subcommand, no goal files yet, a permission error -- just means the
  // picker stays empty, never a crash; see notes-helper.py's own "skip what
  // can't parse" contract for list-goals.
  Process {
    id: listGoalsProc
    command: [root.pythonBin, root.notesHelperPath, "list-goals"]
    stdout: StdioCollector {
      id: listGoalsStdout
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

  Process {
    id: writeActiveProc
    property string pendingSlug: ""
    command: root.writeCommand(["write-active"])
    onStarted: {
      writeActiveProc.write(writeActiveProc.pendingSlug)
      writeActiveProc.stdinEnabled = false
    }
  }

  IpcHandler {
    // Its own target in the demo, so a script aimed at "ompom" can never
    // be answered by the demo instead of the real engine.
    target: root.demo ? "ompom-demo" : "ompom"
    function status(): string { return root.statusJson() }
    function togglePause(): string { return root.togglePause() }
    function cycleMode(): string { return root.cycleMode() }
    // For bin/omvision-deploy only -- see snapshotJson().
    function snapshot(): string { return root.snapshotJson() }
    function restore(json: string): string { return root.restore(json) }
    function skipSleep(): string { return root.skipSleep() }
  }
}
