import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Ompom pomodoro engine. Always running (keepLoaded), owns the timer state
// machine, and renders its own fullscreen blocking overlay directly (the same
// PanelWindow + WlrLayershell technique the lock screen and idle screensaver
// use) rather than being a separate summoned plugin. That keeps the block and
// the notes flow inside a single Wayland layer surface, so there's never a
// second layer-shell surface fighting it for exclusive keyboard focus.
// The block/notes buttons are OverlayButton.qml, a sibling file in this same
// plugin directory — QML resolves same-directory PascalCase files as types
// automatically, no import needed.
Item {
  id: root

  // Injected by omarchy-shell for first/third-party services. Unused here —
  // Ompom needs no host lookups — but declaring it matches the documented
  // service entry-point contract.
  property var shell: null

  // Set only by bin/ompom-demo, which loads this same file in its own qs
  // process, so the overlay can be seen and clicked through as it really is
  // without waiting out a 25/5 cycle and without touching the real engine
  // running inside omarchy-shell. Everything the demo changes is gated on
  // this one flag: short timers (below), no disk writes (break notes are
  // printed instead of appended, the active goal is never written), its own
  // IPC target, starting on the intent screen, and Ctrl+Q to quit. Reading
  // the goal list stays live, so the picker shows the real goals. A copied
  // harness was the alternative, and was rejected: it drifts from this file
  // and then demos something that no longer ships.
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

  // Belt-and-suspenders: the helper enforces this same ceiling itself
  // (it's the actual trust boundary), but trimming here too means an
  // oversized entry is never even written to the subprocess's stdin. See
  // saveNote() for the one place this is applied now — to the serialized
  // JSON log entry, not free text — and why a truncated (and therefore
  // invalid) JSON payload is an acceptable outcome for that rare case.
  readonly property int maxNoteInputChars: 20000

  // The overlay's writing surfaces use omvision's journal type exactly:
  // Theme.writingPointSize there, in points for the same reason (the
  // highlighter's character formats are point-sized, and mixing pixel and
  // point sizes on one run of text gives Qt two systems to reconcile).
  readonly property real writingPointSize: 15

  readonly property int normalFocusSec: 25 * 60
  readonly property int normalBreakSec: 5 * 60
  readonly property int longFocusSec: 50 * 60
  readonly property int longBreakSec: 10 * 60
  readonly property int extensionSec: demo ? demoFocusSec : 60
  readonly property int maxExtensions: 3

  readonly property int focusSecFor: demo ? demoFocusSec : (mode === "long" ? longFocusSec : normalFocusSec)
  readonly property int breakSecFor: demo ? demoBreakSec : (mode === "long" ? longBreakSec : normalBreakSec)

  // normal | long | off
  property string mode: "normal"
  // intent | focus | prompt | extend | break -- intent runs before every
  // focus cycle EXCEPT the very first one after the shell (re)starts: the
  // engine comes up already in "focus" so logging in never drops a
  // blocking "what's your focus?" overlay on top of whatever you were
  // doing. See tick()'s break branch for where intent is entered from
  // then on, Component.onCompleted for the one thing the cold-start run
  // still needs stamped (its "started" time, since startFocus() never
  // runs for it), and resetRun()/cycleMode() for why intent is the one
  // phase whose typed text a mode switch must not destroy.
  property string phase: "focus"
  property bool paused: false
  property int remaining: normalFocusSec
  property int extensionsUsed: 0
  property bool notesOpen: false

  // --- intent phase state ---
  // The goal the intent screen is currently pointed at (a slug, or "" for
  // none), and the full goal list it was chosen from -- both refreshed from
  // disk every time intent is (re)entered (see refreshGoalData()), never
  // cached across a whole session, so a goal created or renamed in Omvision
  // between pomodoros shows up on the very next one.
  property string activeGoalSlug: ""
  property var goalsList: []
  readonly property string activeGoalTitle: root.goalTitleForSlug(root.activeGoalSlug)
  // Ctrl+G (see focusEdit's Keys.onPressed) toggles this; a no-op with no
  // goal files at all — see toggleGoalPicker().
  property bool goalPickerOpen: false
  // Stamped in startFocus() when intent hands off to a real focus run, read
  // back in saveNote() when that run's break notes are logged -- together
  // with focusSecFor/extensionsUsed and whatever's typed into
  // focusEdit/doneEdit/leftEdit at that point, this is the whole log entry.
  property string focusStartedIso: ""
  // -1 is "no mid-run change": the goal active when the run started (or no
  // goal at all) gets the whole run's minutes. A non-negative value is
  // `remaining` as it stood the moment activeGoalFile last changed WHILE
  // phase was "focus" -- see onActiveGoalFileText() -- because only the
  // remainder was ever spent on whatever became active at that moment.
  // Reset to -1 at the start of every real run (startFocus()); the
  // cold-start run (see phase's own comment) never touches it, so it
  // correctly stays -1 there too.
  property int goalAttributionRemaining: -1

  // --- break notes state ---
  // Two collapsible sections, both open by default so neither prompt is
  // ever hidden by surprise -- collapsing is purely a decluttering option
  // once one side is finished. Reset to open at the start of every new
  // break (clearNotes()), so a section collapsed during one break doesn't
  // stay collapsed for the next.
  property bool doneSectionOpen: true
  property bool leftSectionOpen: true
  // "What else?" -- the open question, last, after the two that ask for an
  // account of the run. Whatever the break actually put in your head goes
  // here; done/left are the structured part above it.
  property bool elseSectionOpen: true
  // Transiently holds the JSON entry between kicking off noteLogProc and it
  // reading it from stdin in onStarted. Rebuilt on every saveNote() call,
  // first attempt or retry -- see pendingLogStarted/pendingLogMinutes for
  // the two pieces of it that are NOT rebuilt every time.
  property string pendingLogPayload: ""
  // Pinned once per note-taking cycle, at the first saveNote() call for
  // it, and left untouched by every retry after that (a non-zero exit
  // never re-pins them -- see saveNote()). started/minutes identify WHICH
  // run this entry is for; noteLogProc.command (the append-log <slug> vs
  // append-day choice) is pinned the same way, right alongside them, for
  // the same reason: by the time a refusal can happen on tick()'s
  // auto-save path, phase has already moved to "intent" and
  // activeGoalSlug/extensionsUsed/goalAttributionRemaining/focusStartedIso
  // are free to describe the *next* run. done/left/focus are deliberately
  // NOT pinned -- doneEdit/leftEdit/focusEdit stay live and rebuilt every
  // time specifically so a note that failed to save because it was too
  // long can actually be trimmed and retried, instead of the retry just
  // resending the same oversized text forever. Cleared alongside the rest
  // of a cycle's state in clearNotes().
  property string pendingLogStarted: ""
  property int pendingLogMinutes: 0
  // Set when the one write in saveNote() below comes back non-zero: the
  // notes view stays open, the typed text is never touched, and a quiet
  // Color.urgent line says so — see the floating header in the notes view.
  // Also what tells a subsequent saveNote() call not to re-pin
  // pendingLogStarted/pendingLogMinutes/noteLogProc.command -- see its own
  // comment.
  property bool notesSaveFailed: false
  // True from the moment saveNote() kicks off noteLogProc until it exits.
  // Makes saveNote() itself safe to call twice in quick succession -- see
  // its own guard and tick()'s break branch, which can otherwise both try
  // to save the exact same entry within the same instant (← pressed just
  // as the break timer hits zero).
  property bool notesSavePending: false
  // Set by tick()'s break branch when the timer, not the user, is the one
  // ending the note-taking cycle. Tells noteLogProc.onExited to do the
  // deferred cycle-end wipe (clear the editors, reset extensionsUsed and
  // goalAttributionRemaining for the next run) once the write actually
  // lands -- never for an ordinary manual ← save, which never touches any
  // of that. See tick()'s break branch and onExited for the two halves.
  property bool notesSaveIsCycleEnd: false
  // One entry per pomodoro, full stop. The log is append-only, so every
  // saveNote() that reaches notes-helper.py appends -- and nothing used to
  // stop a second one: pressing ← again, or reopening "Take notes" during
  // the same break and pressing ← there, wrote the same run to the log a
  // second, third, fourth time under the same `### <time> · <N>m` heading.
  // Set the moment this cycle's entry is known to be on disk, cleared with
  // the rest of the cycle in clearNotes(). While it is set, saving is a
  // no-op that just closes the view: later edits to done/left/else are
  // dropped rather than duplicating the run, which is the right trade --
  // the session happening once is a fact, the note is a note.
  property bool cycleLogged: false

  // intent is a distinct pre-focus screen: overlay up, no countdown of its
  // own (tick() returns early for it below), and no togglePause lockout to
  // add (togglePause already refuses anything but "focus" — see its own
  // comment). extend deliberately behaves like focus here: no overlay,
  // normal desktop use, just a ticking bar countdown you can't pause or
  // escape via mode switch until it runs out and drops you back at the
  // prompt overlay. break is the mirror case: overlay stays up, and
  // togglePause/cycleMode both refuse to act, so there's no way to pause or
  // mode-switch your way out of it early either — it only ends on its own.
  //
  // A running modeSettleTimer holds the overlay back after a mode switch:
  // see its own comment.
  readonly property bool overlayVisible: mode !== "off" && !modeSettleTimer.running
    && (phase === "intent" || phase === "prompt" || phase === "break")

  // Right-clicking through the modes on the bar used to raise the intent
  // screen on every click, so passing through Long Focus on the way to Off
  // flashed a blocking overlay you then had to get out of. A mode now only
  // counts as chosen once it has stayed put this long; every click restarts
  // the wait. The run itself is still reset on each click, only the overlay
  // waits -- deferring the reset too would leave a focus countdown running
  // on the bar in a mode you've already left. Long enough for a few
  // deliberate clicks at the bar's pace, short enough that stopping on a
  // mode still feels immediate.
  Timer {
    id: modeSettleTimer
    interval: 1500
  }

  // Whether tick() counts remaining down. Intent time is not focus time:
  // nothing decrements while you're composing your intent, however long
  // that takes -- remaining is primed for the focus run to come in
  // startFocus(), not here. restore() asks the same question to take the
  // restart's seconds off a countdown.
  readonly property bool countdownRunning: mode !== "off" && !paused && phase !== "intent"

  function fmt(totalSeconds) {
    var s = Math.max(0, totalSeconds)
    var m = Math.floor(s / 60)
    var r = s % 60
    return (m < 10 ? "0" : "") + m + ":" + (r < 10 ? "0" : "") + r
  }

  // During intent, remaining is whatever the last run left behind (it is
  // only primed on the way out, in startFocus()), so status reports the
  // length of the run about to start instead: while clicking through the
  // modes the bar shows 25:00, 50:00, rather than a stale number.
  function statusJson() {
    var shown = root.phase === "intent" ? root.focusSecFor : root.remaining
    return JSON.stringify({
      mode: root.mode,
      phase: root.phase,
      remaining: shown,
      remainingLabel: root.fmt(shown),
      paused: root.paused,
      extensionsUsed: root.extensionsUsed,
      maxExtensions: root.maxExtensions,
      overlay: root.overlayVisible
    })
  }

  // --- hand-off across a shell restart ---
  // The manifest's keepLoaded keeps this engine alive through plugin
  // hot-reloads, which is what lets the bar widget be redeployed without
  // touching the timer. The price is that a new Service.qml only loads on
  // a whole-shell restart, which would start every deploy on a fresh 25
  // minutes. bin/ompom-deploy bridges that: snapshot() before the restart,
  // restore() into the new engine after it. PersistentProperties was the
  // obvious alternative and doesn't apply: it carries state across a
  // Quickshell reload, but a restart is a new process, and even a plugin
  // reload destroys and recreates this object rather than reloading it.
  //
  // Only the cycle is carried, never an in-flight save: a note write in
  // progress at snapshot time either landed (the log has it) or didn't
  // (it was never going to be retried by a new process anyway).
  readonly property int handoffMaxAgeMs: 5 * 60 * 1000

  // The typed text that belongs to a cycle, by snapshot field.
  function cycleTextEdits() {
    return { focusText: focusEdit, doneText: doneEdit, leftText: leftEdit, elseText: elseEdit }
  }

  function snapshotJson() {
    var s = {
      takenAtMs: Date.now(),
      mode: root.mode,
      phase: root.phase,
      paused: root.paused,
      remaining: root.remaining,
      extensionsUsed: root.extensionsUsed,
      focusStartedIso: root.focusStartedIso,
      goalAttributionRemaining: root.goalAttributionRemaining,
      cycleLogged: root.cycleLogged,
      notesOpen: root.notesOpen
    }
    var edits = root.cycleTextEdits()
    for (var field in edits) s[field] = String(edits[field].text || "")
    return JSON.stringify(s)
  }

  // Takes exactly what snapshotJson() gives, every field required. Every
  // field is checked before anything is assigned, so a bad hand-off leaves
  // the fresh engine exactly as it started rather than half-restored.
  function restore(json) {
    var s
    try { s = JSON.parse(String(json || "")) } catch (e) { return "error: not JSON" }
    if (!Util.isPlainObject(s)) return "error: not an object"
    function int(v, lo, hi) { return Number.isInteger(v) && v >= lo && v <= hi }
    var age = Date.now() - s.takenAtMs
    if (!(age >= 0 && age <= root.handoffMaxAgeMs))
      return "error: snapshot missing takenAtMs or older than " + (root.handoffMaxAgeMs / 60000) + " minutes"
    if (["normal", "long", "off"].indexOf(s.mode) === -1) return "error: bad mode"
    if (["intent", "focus", "prompt", "extend", "break"].indexOf(s.phase) === -1) return "error: bad phase"
    if (!int(s.remaining, 0, 4 * 3600)) return "error: bad remaining"
    if (!int(s.extensionsUsed, 0, root.maxExtensions)) return "error: bad extensionsUsed"
    if (!int(s.goalAttributionRemaining, -1, 4 * 3600)) return "error: bad goalAttributionRemaining"
    if (typeof s.focusStartedIso !== "string"
        || !/^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)?$/.test(s.focusStartedIso)) return "error: bad focusStartedIso"
    for (var b of ["paused", "cycleLogged", "notesOpen"])
      if (typeof s[b] !== "boolean") return "error: bad " + b
    var edits = root.cycleTextEdits()
    for (var t in edits)
      if (typeof s[t] !== "string") return "error: bad " + t

    // From the baseline every new cycle starts from, then the snapshot on
    // top of it.
    modeSettleTimer.stop()
    root.resetRun()
    root.mode = s.mode
    root.phase = s.phase
    root.paused = s.paused
    root.extensionsUsed = s.extensionsUsed
    root.goalAttributionRemaining = s.goalAttributionRemaining
    root.focusStartedIso = s.focusStartedIso
    root.cycleLogged = s.cycleLogged
    root.notesOpen = s.notesOpen
    for (var field in edits) edits[field].text = s[field].slice(0, root.maxNoteInputChars)
    // The countdown kept running in the old process until the restart,
    // so the time since the snapshot is taken off it. A countdown that
    // runs out this way is left at 0 for the next tick() to move on from,
    // exactly as if it had run out here.
    root.remaining = root.countdownRunning ? Math.max(0, s.remaining - Math.round(age / 1000)) : s.remaining
    return root.statusJson()
  }

  // Single owner of "a note-taking cycle just ended" cleanup, called from
  // every path that can end one: an explicit mode switch (resetRun), a new
  // break starting (startBreak), a break timing out on its own with
  // nothing to save (tick(), when the cycle was already logged), and --
  // once the write actually lands -- a break that timed out before its
  // pomodoro was saved (noteLogProc.onExited's deferred cycle-end wipe;
  // see tick()'s break branch for why that one specifically can't call
  // this directly).
  // Without this, notesOpen could survive into the next prompt and the
  // block view would open straight into the notes screen instead of the
  // normal +1-minute/Start-break buttons. Deliberately break-notes-only:
  // it never touches focusEdit's text — see resetRun() for why a mode
  // switch specifically must not route the typed focus line through here,
  // and tick()'s break branch / noteLogProc.onExited for where that line
  // does get cleared, at the start of a genuinely new cycle.
  function clearNotes() {
    root.notesOpen = false
    root.notesSaveFailed = false
    root.doneSectionOpen = true
    root.leftSectionOpen = true
    root.elseSectionOpen = true
    doneEdit.text = ""
    leftEdit.text = ""
    elseEdit.text = ""
    // No cycle's entry is pending or retryable once this runs -- see
    // pendingLogStarted's own comment for why these must not leak into
    // whatever saveNote() pins next.
    root.pendingLogStarted = ""
    root.pendingLogMinutes = 0
    root.cycleLogged = false
  }

  function resetRun() {
    root.paused = false
    root.extensionsUsed = 0
    root.phase = "intent"
    // Deliberately not touching remaining here: intent has no countdown of
    // its own (tick() returns early for it below), and remaining is only
    // ever primed for the next focus run on the way OUT of intent, in
    // startFocus() — never on the way in.
    root.clearNotes()
    root.goalPickerOpen = false
    root.goalAttributionRemaining = -1
    root.refreshGoalData()
  }

  function cycleMode() {
    if (root.phase === "extend" || root.phase === "break") return root.statusJson()
    // A finished pomodoro is logged before the reset below throws its cycle
    // away. Switching mode at the +1 minute / Start break prompt -- or off
    // the notes view after its save was refused -- used to drop a run that
    // had fully happened, just because no break was taken to log it.
    var loggedOnTheWayOut = root.logFinishedRunOnTheWayOut()
    if (root.mode === "normal") root.mode = "long"
    else if (root.mode === "long") root.mode = "off"
    else root.mode = "normal"
    // resetRun() lands back in "intent", not "focus" — and, per its own
    // comment, leaves focusEdit's text alone, so switching modes mid-way
    // through naming your focus doesn't cost you what you'd already typed.
    // The exception is a line that was just logged with its finished run:
    // it described that run, not the next one.
    root.resetRun()
    if (loggedOnTheWayOut) focusEdit.text = ""
    modeSettleTimer.restart()
    return root.statusJson()
  }

  // A finished run's minutes: the whole focus time (or, after a mid-run goal
  // change, only what was left of it -- see goalAttributionRemaining) plus
  // every +1 minute taken at the prompt.
  function finishedRunMinutes() {
    var minutesBase = root.goalAttributionRemaining >= 0 ? root.goalAttributionRemaining : root.focusSecFor
    return Math.round(minutesBase / 60) + root.extensionsUsed
  }

  // Where a finished run is written: the active goal's log, or the day file
  // when no goal was chosen. The demo reads the entry and discards it.
  function logCommandForActiveGoal() {
    return root.demo
      ? ["/bin/sh", "-c", "cat >/dev/null"]
      : root.activeGoalSlug.length > 0
        ? [root.pythonBin, root.notesHelperPath, "append-log", root.activeGoalSlug]
        : [root.pythonBin, root.notesHelperPath, "append-day"]
  }

  // Called by cycleMode() just before its reset. Logs the cycle's pomodoro
  // if it finished and nothing has written it yet, and says whether it did:
  //   - "prompt": focus ran out and no break was taken, so there are no
  //     notes -- the entry carries the focus line and blank done/left/else,
  //     like a break that timed out untouched.
  //   - a refused save still on screen (notesSaveFailed): the entry
  //     saveNote() pinned, with whatever notes are typed now.
  // Not a partial run switched off mid-focus: that isn't a pomodoro.
  //
  // Through its own process rather than saveNote(): the write finishes
  // after resetRun() has already begun the next cycle, and saveNote()'s
  // exit handler would mark *that* cycle logged or failed. There is nowhere
  // left to show a refusal once the overlay is gone, so one is only warned.
  function logFinishedRunOnTheWayOut() {
    var entry, command
    if (root.phase === "prompt" && !root.cycleLogged) {
      command = root.logCommandForActiveGoal()
      entry = { started: root.focusStartedIso, minutes: root.finishedRunMinutes(),
                focus: String(focusEdit.text || ""), done: "", left: "", "else": "" }
    } else if (root.notesSaveFailed && !root.cycleLogged && !root.notesSavePending
               && root.pendingLogStarted.length > 0) {
      command = noteLogProc.command
      entry = { started: root.pendingLogStarted, minutes: root.pendingLogMinutes,
                focus: String(focusEdit.text || ""), done: String(doneEdit.text || ""),
                left: String(leftEdit.text || ""), "else": String(elseEdit.text || "") }
    } else {
      return false
    }
    if (finishedRunLogProc.running) {
      console.warn("ompom: previous run still being logged, this one was not:", JSON.stringify(entry))
      return false
    }
    var payload = JSON.stringify(entry)
    if (root.demo) console.log("ompom demo, not saved:", payload)
    finishedRunLogProc.payload = payload.slice(0, root.maxNoteInputChars)
    finishedRunLogProc.command = command
    finishedRunLogProc.stdinEnabled = true
    finishedRunLogProc.running = true
    return true
  }

  // Needs no change for intent: the guard below already refuses anything
  // but "focus", and intent is a distinct phase from "focus" — pausing
  // while composing your intent was never a possibility before this phase
  // existed either, since there's no timer running yet to pause.
  function togglePause() {
    if (root.mode === "off" || root.phase !== "focus") return root.statusJson()
    root.paused = !root.paused
    return root.statusJson()
  }

  function tick() {
    if (!root.countdownRunning) return
    if (root.remaining > 0) {
      root.remaining -= 1
      return
    }
    if (root.phase === "focus") {
      root.phase = "prompt"
    } else if (root.phase === "extend") {
      root.phase = "prompt"
    } else if (root.phase === "break") {
      // A break that runs out before its pomodoro was saved via ← or
      // Escape still logs it rather than discarding it -- started/minutes/
      // focus are real information regardless of whether done/left were
      // ever filled in (see saveNote()'s own comment). That includes a
      // break whose notes were never opened at all, now that the break
      // starts on its countdown (see startBreak()). Asking "was the notes
      // view open?" instead, as this once did, would drop exactly those
      // runs from the log.
      //
      // Saving this here IS starting an async write, though, and the whole
      // point of the "refused write keeps what's on screen" guarantee is
      // that nothing gets wiped before the result is known. So when a save
      // is actually started, the wipe below (extensionsUsed,
      // goalAttributionRemaining, doneEdit/leftEdit/focusEdit,
      // notesOpen) is deferred to noteLogProc.onExited instead of
      // happening here -- on success there, and never on a refusal, where
      // the notes view stays or comes up (over this new "intent" phase
      // underneath -- see focusEdit's own focus binding for why that
      // doesn't fight it for keyboard focus) with "Not saved -- try
      // again" up, and ← still works there to retry -- saveNote() keeps
      // resending this same run's pinned started/minutes/goal (see
      // pendingLogStarted's own comment for why those can't be rebuilt
      // from state that, by the time a refusal can happen, already
      // belongs to this new phase) while still rebuilding the text fresh
      // each time, so a too-long note can actually be trimmed and retried.
      var savingThisCycle = !root.cycleLogged
      if (savingThisCycle) {
        root.notesSaveIsCycleEnd = true
        root.saveNote()
      }
      root.phase = "intent"
      root.goalPickerOpen = false
      root.refreshGoalData()
      if (!savingThisCycle) {
        root.extensionsUsed = 0
        root.goalAttributionRemaining = -1
        focusEdit.text = ""
        root.clearNotes()
      }
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
    root.phase = "break"
    root.remaining = root.breakSecFor
    // Take Notes is only reachable during "break" (see the block view), so
    // this is the start of a new note-taking cycle: clear whatever's left
    // from a previous break. See clearNotes() for the other paths that
    // also need this (an explicit mode switch, or a break timing out
    // while notes were still open).
    root.clearNotes()
    // The break opens on its ticking countdown, never on the notes view.
    // It used to open the notes straight away, which turned every break
    // into a writing prompt and hid the one thing a break is for: time
    // away, counting down. Writing is one "Take notes" click away. The
    // pomodoro is logged whether or not you ever write -- see tick()'s
    // break branch.
  }

  function openNotes() {
    // Deliberately doesn't touch doneEdit/leftEdit text: reopening Take
    // Notes during the same break should show whatever was last written
    // (saveNote() no longer clears it either) -- see clearNotes() for
    // where it does get cleared, at the start of the next cycle. Caret
    // always starts in "What's done?", never "What's left?".
    root.notesOpen = true
    root.notesSaveFailed = false
    root.doneSectionOpen = true
    Qt.callLater(function() { doneEdit.forceActiveFocus() })
  }

  // The one and only write for a completed pomodoro's break notes: the
  // active goal's log if one was chosen in intent (append-log), or the day
  // file if not (append-day) — notes-helper.py no longer has a separate
  // daily-notes file or a free-text mode, so this always writes an entry
  // once called, even one with blank done/left: started/minutes/focus are
  // still real information about a pomodoro that happened.
  //
  // On a non-zero exit (a malformed entry the helper refused, a bad slug,
  // or — mid-deploy — append-log/append-day not existing yet on an old
  // helper) the write never happened, so this must not act like it did:
  // doneEdit/leftEdit/focusEdit are never touched here regardless of
  // outcome, and it's noteLogProc.onExited, not this function, that
  // decides whether notesOpen (and, for tick()'s auto-save, the rest of
  // the cycle-end wipe) actually happens. See notesSaveFailed for the
  // quiet on-screen sign of a refusal.
  //
  // Every call rebuilds pendingLogPayload from whatever doneEdit/leftEdit/
  // focusEdit currently hold -- deliberately, so a note that failed to
  // save because it was over maxNoteInputChars can actually be trimmed
  // and retried, rather than a retry just resending the same oversized,
  // still-invalid payload forever. started/minutes/noteLogProc.command
  // are the one part NOT rebuilt every time -- see pendingLogStarted's own
  // comment for why a retry still has to identify the same finished run
  // even though its text is free to keep changing.
  function saveNote() {
    // Re-entrant-safe: a break can time out (tick()'s auto-save) in the
    // same instant the user pressed ← themselves a moment earlier, and
    // this makes the second call a no-op instead of a duplicate log entry.
    // See notesSavePending's own comment.
    if (root.notesSavePending) return

    // Already on disk for this cycle: close up rather than append a
    // duplicate of a pomodoro that has already been logged.
    if (root.cycleLogged) {
      root.notesSaveFailed = false
      root.notesOpen = false
      return
    }

    if (!root.notesSaveFailed) {
      // First attempt at this cycle's entry: pin its identity now, before
      // extensionsUsed/goalAttributionRemaining/focusStartedIso/
      // activeGoalSlug get a chance to move on to the next cycle. A retry
      // (notesSaveFailed already true) skips this and keeps whatever was
      // pinned here the first time.
      root.pendingLogStarted = root.focusStartedIso
      root.pendingLogMinutes = root.finishedRunMinutes()
      // The demo goes through the same Process, exit code and all, so the
      // save path it shows is the real one -- only the sink differs: a
      // shell that reads the entry and discards it instead of the helper.
      noteLogProc.command = root.logCommandForActiveGoal()
    }

    var done = String(doneEdit.text || "")
    var left = String(leftEdit.text || "")
    // Quoted: `else` is a reserved word, and an unquoted key would be a
    // syntax error in some engines even where QML's own tolerates it.
    var payload = JSON.stringify({
      started: root.pendingLogStarted,
      minutes: root.pendingLogMinutes,
      focus: String(focusEdit.text || ""),
      done: done,
      left: left,
      "else": String(elseEdit.text || "")
    })
    // Truncating valid JSON produces invalid JSON -- deliberately fine
    // here: this ceiling only exists to stop an absurd paste from ever
    // reaching the subprocess's stdin at all, and the helper rejecting a
    // truncated payload is exactly the non-zero-exit path above, which by
    // design never loses what's on screen -- and, since the payload is
    // rebuilt from live text on every call, trimming it below the ceiling
    // and pressing ← again actually produces a shorter, valid payload
    // next time instead of repeating the same refusal forever.
    if (payload.length > root.maxNoteInputChars) payload = payload.slice(0, root.maxNoteInputChars)

    root.pendingLogPayload = payload
    if (root.demo) console.log("ompom demo, not saved:", payload)
    root.notesSaveFailed = false
    root.notesSavePending = true
    // stdinEnabled must be re-armed before every run: Process.write() is a
    // no-op once it's been turned off, and it's turned off below right
    // after writing so the helper's stdin read() sees EOF.
    noteLogProc.stdinEnabled = true
    noteLogProc.running = true
  }

  // Local-time, no offset suffix -- matches what notes-helper.py's
  // format_timestamp() expects from datetime.fromisoformat() and, more
  // importantly, what it then renders with a local strftime(): a UTC
  // timestamp here would print the wrong wall-clock hour in the log.
  function isoNow() {
    var d = new Date()
    function pad(n) { return (n < 10 ? "0" : "") + n }
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
      "T" + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":" + pad(d.getSeconds())
  }

  // See notes-helper.py's own docstring for append-log/append-day: both are
  // pure appends with no read-modify-write, opened O_APPEND with no read of
  // the file first, so this is never racing a coaching session or Omvision
  // rewriting the same file. Both exit non-zero and write nothing on a
  // malformed entry -- see saveNote() above for how a non-zero exit here is
  // handled (the typed text is never lost, and never treated as saved).
  Process {
    id: noteLogProc
    command: []
    onStarted: {
      noteLogProc.write(root.pendingLogPayload)
      noteLogProc.stdinEnabled = false
    }
    onExited: function(exitCode) {
      root.notesSavePending = false
      if (exitCode === 0) {
        root.pendingLogPayload = ""
        // This cycle's pomodoro is now in the log. Nothing may write it
        // again -- see cycleLogged.
        root.cycleLogged = true
        if (root.notesSaveIsCycleEnd) {
          // The deferred half of tick()'s break-timeout auto-save: see
          // its own comment there for why this can't just run
          // synchronously in tick(), and why doing it here instead is
          // what lets a refusal (below) keep everything exactly as it
          // was instead of having already wiped it.
          root.notesSaveIsCycleEnd = false
          root.extensionsUsed = 0
          root.goalAttributionRemaining = -1
          root.clearNotes()
          // Guarded rather than assumed: in practice the still-open
          // notes view blocks the intent screen underneath (see
          // focusEdit's focus binding) so phase can't have moved past
          // "intent" again before this fires, but if that ever changes,
          // a focus line already being typed for a newer cycle must
          // never be the one that gets cleared here.
          if (root.phase === "intent") focusEdit.text = ""
        } else {
          root.notesOpen = false
        }
      } else {
        // pendingLogStarted/pendingLogMinutes/noteLogProc.command are
        // deliberately left exactly as they are -- see saveNote()'s
        // pinning branch, which only sets them once per cycle and skips
        // it entirely while notesSaveFailed is already true.
        root.notesSaveFailed = true
        // A break that ran out with its notes never opened still gets its
        // refusal on screen, where ← can retry it. Left closed, the run
        // would sit unsaved behind the intent screen with no sign of it.
        root.notesOpen = true
      }
    }
  }

  // The one write cycleMode() makes on its way out -- see
  // logFinishedRunOnTheWayOut(). Fire and forget: by the time it exits the
  // next cycle has begun, so it touches none of the cycle state noteLogProc
  // does.
  Process {
    id: finishedRunLogProc
    property string payload: ""
    command: []
    onStarted: {
      finishedRunLogProc.write(finishedRunLogProc.payload)
      finishedRunLogProc.stdinEnabled = false
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("ompom: finished run not logged (helper exit " + exitCode + "):", finishedRunLogProc.payload)
      finishedRunLogProc.payload = ""
    }
  }

  // Continues a "- ", "* ", or "1. " list line onto the next line,
  // auto-incrementing numbered markers, for either break-notes TextEdit
  // (doneEdit and leftEdit both use this -- focusEdit deliberately doesn't,
  // see its own Keys.onPressed comment). Pressing Return on an
  // already-empty list line ends the list instead of piling up empty
  // markers.
  function continueList(edit, event) {
    event.accepted = true
    var pos = edit.cursorPosition
    var text = edit.text
    var lineStart = text.lastIndexOf("\n", pos - 1) + 1
    var lineEnd = text.indexOf("\n", lineStart)
    if (lineEnd === -1) lineEnd = text.length
    var line = text.substring(lineStart, lineEnd)

    var bullet = line.match(/^(\s*)([-*])\s+(.*)$/)
    var numbered = line.match(/^(\s*)(\d+)\.\s+(.*)$/)
    var marker = bullet || numbered

    if (marker && marker[3].trim().length === 0) {
      edit.remove(lineStart, lineEnd)
      edit.insert(lineStart, "\n")
      edit.cursorPosition = lineStart + 1
      return
    }

    var continuation = "\n"
    if (bullet) {
      continuation += bullet[1] + bullet[2] + " "
    } else if (numbered) {
      continuation += numbered[1] + (parseInt(numbered[2], 10) + 1) + ". "
    }
    edit.insert(pos, continuation)
    edit.cursorPosition = pos + continuation.length
  }

  // Ends the intent screen and hands off to a real focus run. The one
  // function both the header's ← button and Escape call (the same "one
  // button, one key, same action" pattern the break notes view uses for
  // saveNote()) — see intentEscape() for the one thing Escape does
  // differently first (closing an open goal picker instead of leaving).
  // "No note" here means exactly that: unlike saveNote(), this never
  // writes a note/log entry. The typed focus line stays in focusEdit,
  // carried forward in memory until saveNote() reads it when this run's
  // break notes are eventually logged. The only disk write here is
  // remembering which goal was chosen, via write-active.
  function startFocus() {
    root.goalPickerOpen = false
    root.phase = "focus"
    root.remaining = root.focusSecFor
    root.focusStartedIso = root.isoNow()
    // Fresh run, no mid-run goal change yet -- see its own comment.
    root.goalAttributionRemaining = -1
    root.writeActiveGoal()
  }

  function intentEscape() {
    if (root.goalPickerOpen) {
      root.goalPickerOpen = false
      return
    }
    root.startFocus()
  }

  // Best-effort, matching every other notes-helper call in this file: a
  // stale or missing write here never blocks the overlay from moving on to
  // focus, it just means Omvision's idea of "the active goal" lags behind
  // until the next successful write.
  function writeActiveGoal() {
    // The active-goal pointer is shared with Omvision and the real engine;
    // a demo picking a goal must not change what either of them sees.
    if (root.demo) return
    writeActiveProc.pendingSlug = root.activeGoalSlug
    writeActiveProc.stdinEnabled = true
    writeActiveProc.running = true
  }

  // Re-reads the goal list every time intent is (re)entered -- called from
  // resetRun() and tick()'s break branch, the two places phase becomes
  // "intent" -- rather than caching it across a whole session, so a goal
  // created, renamed, or closed in Omvision between pomodoros shows up on
  // the very next intent screen. activeGoalSlug doesn't need this: it's
  // kept continuously live by activeGoalFile below, not polled -- this
  // just forces one extra read on top of that, belt-and-suspenders for the
  // moment intent opens.
  function refreshGoalData() {
    activeGoalFile.reload()
    listGoalsProc.running = true
  }

  // The active-goal pointer (~/.local/state/omvision/active-goal) can
  // change out from under ompom two different ways: our own writeActiveGoal()
  // when intent hands off to focus, and -- the new case -- Omvision writing
  // it while a focus run is already ticking, to pick up or drop a goal
  // mid-run. isLiveChange distinguishes a genuine change (activeGoalFile's
  // onFileChanged fired) from the file's very first load, which matters
  // for exactly one run: the cold-start one (see phase's own comment).
  // That run is already "focus" by the time this first load lands, but it
  // never went through intent, so whatever's sitting on disk from a
  // previous session must not be silently inherited as if it had been
  // active the whole time -- only a change that happens live, after the
  // engine is already up, ever gets attributed.
  function onActiveGoalFileText(rawSlug, isLiveChange) {
    var slug = String(rawSlug || "").trim()
    if (!isLiveChange && root.phase === "focus") return

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

  // A no-op with no goal files at all -- see goalsList/refreshGoalData()
  // above; there's nothing to pick from and no picker worth opening.
  function toggleGoalPicker() {
    if (root.goalsList.length === 0) return
    root.goalPickerOpen = !root.goalPickerOpen
  }

  function chooseGoal(slug) {
    root.activeGoalSlug = String(slug || "")
    root.goalPickerOpen = false
  }

  Component.onCompleted: {
    // A demo starts where a cycle starts, on the intent screen, rather than
    // in the cold-start focus run the real engine uses to stay out of the
    // way at login.
    if (root.demo) {
      root.resetRun()
      return
    }
    root.refreshGoalData()
    // The cold-start run (phase already "focus" by default -- see its own
    // comment) skips intent entirely, so startFocus() never stamps this.
    // Without it, that run's eventual log entry would carry an empty
    // "started" and notes-helper.py would reject the whole thing (it
    // parses this with datetime.fromisoformat()).
    if (root.phase === "focus" && root.focusStartedIso.length === 0) {
      root.focusStartedIso = root.isoNow()
    }
  }

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

  // list-goals takes no stdin and is re-run every time intent is
  // (re)entered (see refreshGoalData()). Failure -- an old deployed helper
  // without this subcommand, no goal files yet, a permission error -- just
  // means the picker stays empty, never a crash; see notes-helper.py's own
  // "skip what can't parse" contract for list-goals.
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
    command: [root.pythonBin, root.notesHelperPath, "write-active"]
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
    // For bin/ompom-deploy only -- see snapshotJson().
    function snapshot(): string { return root.snapshotJson() }
    function restore(json: string): string { return root.restore(json) }
  }

  PanelWindow {
    id: overlay
    visible: root.overlayVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "ompom-overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    // The writing surfaces (intent, and each notes section) are set to one
    // measure and centred in it, rather than run edge to edge across a
    // 1440px screen -- a line that long is unreadable, and it was the one
    // thing that made this screen look nothing like the journal in Omvision
    // or like omawrite. Measured in characters off the live font, so a
    // change of font size or scale moves the column with it.
    readonly property int writingColumns: 70
    readonly property real writingWidth: writingMetrics.advanceWidth("0") * writingColumns

    FontMetrics {
      id: writingMetrics
      font.family: Style.font.family
      font.pointSize: root.writingPointSize
    }

    Rectangle {
      anchors.fill: parent
      color: Color.background
    }

    // Quickshell only reserves pointer input over areas that actually have a
    // MouseArea (or similar), so without this, clicks over the plain
    // background Rectangle above fall through to whatever window is
    // underneath — the overlay looks blocking but the desktop keeps working
    // right through it. This absorbs every click that doesn't land on one of
    // the buttons below (those still win, since they're declared later and
    // stack on top).
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
      hoverEnabled: true
    }

    // Demo only: the overlay takes exclusive keyboard focus and covers the
    // screen, so the demo needs an exit that works from every screen,
    // including the intent screen, which otherwise waits for you forever.
    // Application-wide so it works whichever field has focus. The label
    // says it is a demo, so it is never mistaken for a real break.
    Shortcut {
      sequences: ["Ctrl+Q"]
      context: Qt.ApplicationShortcut
      enabled: root.demo
      onActivated: if (root.demo) Qt.quit()
    }

    Text {
      visible: root.demo
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(24)
      z: 10
      text: "DEMO  ·  Ctrl+Q quits"
      color: Util.alpha(Color.popups.text, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.letterSpacing: 2
    }

    // --- block view: prompt / extend / break ---
    // Three tiers, and they have to read as three: a quiet uppercase label
    // for which mode you are in, the state you are in at heading weight, and
    // the countdown as the one large thing on the screen. Before this they
    // were 13 / 24 / 28px in a flat 20px stack, which put the mode label and
    // the countdown within one step of each other and left the screen
    // looking like a list of three sentences.
    Column {
      anchors.centerIn: parent
      // intent has its own screen below, not this one, even though it
      // shares overlayVisible with prompt/break.
      visible: !root.notesOpen && root.phase !== "intent"
      spacing: Style.space(14)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: (root.mode === "long" ? "Long Focus" : "Normal").toUpperCase()
        color: Color.muted
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.letterSpacing: 2
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.phase === "break" ? "Break" : "Focus complete"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.display
        font.bold: true
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.phase === "break"
        text: root.fmt(root.remaining)
        color: Color.accent
        font.family: Style.font.family
        // The hero of this screen, and sized like it: no token goes big
        // enough, so it is derived from the largest one rather than typed
        // in as a pixel count that a font-scale change would leave behind.
        font.pixelSize: Math.round(Style.font.displayLarge * 2.2)
      }

      // The buttons are a separate decision from the reading above them, so
      // they get their own gap rather than the stack's rhythm.
      Item {
        width: 1
        height: Style.space(18)
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(16)

        OverlayButton {
          visible: root.phase === "prompt" && root.extensionsUsed < root.maxExtensions
          label: "+1 minute (" + (root.maxExtensions - root.extensionsUsed) + " left)"
          onActivated: root.addExtension()
        }

        OverlayButton {
          visible: root.phase === "prompt"
          primary: true
          label: "Start break"
          onActivated: root.startBreak()
        }

        OverlayButton {
          // Only once the break has actually started -- the prompt/extend
          // screen is a "focus just ended, what now" decision point, not a
          // writing moment.
          visible: root.phase === "break"
          label: "Take notes"
          onActivated: root.openNotes()
        }
      }
    }

    // --- intent view: "what's your focus?", before every fresh focus run ---
    // Same 120px-inset, floating-opaque-header idiom as the notes view
    // below, just addressed by phase === "intent" instead of notesOpen.
    Item {
      id: intentPage
      anchors.fill: parent
      anchors.margins: Style.space(120)
      visible: root.phase === "intent"

      readonly property real headerHeight: intentHeaderColumn.implicitHeight + Style.space(32)

      Flickable {
        id: intentFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, focusEdit.y + focusEdit.paintedHeight)

        // Same recipe as the notes view's ensureCursorVisible(): called on
        // every cursor move so Return at the bottom scrolls like a normal
        // editor instead of typing off the bottom of the screen.
        function ensureCursorVisible() {
          var top = focusEdit.y + focusEdit.cursorRectangle.y
          var bottom = top + focusEdit.cursorRectangle.height
          if (top < intentFlick.contentY) {
            intentFlick.contentY = top
          } else if (bottom > intentFlick.contentY + intentFlick.height) {
            intentFlick.contentY = bottom - intentFlick.height
          }
        }

        // Plain text, same reasoning as the notes view below. Deliberately
        // no list-continuation on Return here (unlike doneEdit/leftEdit):
        // this is a single line naming what you're about to do, not a
        // running list, and "g" is exactly the kind of character it would
        // contain -- see the Ctrl+G handler below for why the goal-picker
        // shortcut needs a modifier instead of a bare key.
        TextEdit {
          id: focusEdit
          x: Math.round((intentFlick.width - width) / 2)
          y: intentPage.headerHeight
          width: Math.min(overlay.writingWidth, intentFlick.width)
          wrapMode: TextEdit.Wrap
          textFormat: TextEdit.PlainText
          color: Color.popups.text
          font.family: Style.font.family
          font.pointSize: root.writingPointSize
          selectionColor: Util.alpha(Color.accent, 0.12)
          selectedTextColor: Color.popups.text
          persistentSelection: true
          selectByMouse: true
          // Excludes root.notesOpen: a refused deferred save (see
          // tick()'s break branch and noteLogProc.onExited) leaves the
          // notes view open on top of this screen, already in "intent",
          // until it's retried successfully -- without this exclusion
          // this would compete with doneEdit/leftEdit for active focus
          // the whole time that view is still up.
          focus: root.phase === "intent" && !root.notesOpen
          onCursorRectangleChanged: intentFlick.ensureCursorVisible()
          Keys.onEscapePressed: root.intentEscape()

          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_G && (event.modifiers & Qt.ControlModifier)) {
              event.accepted = true
              root.toggleGoalPicker()
            }
          }
        }

        // Omvision's journal styling, the same as the break notes get, so
        // both writing surfaces read like the journal. A Loader for the same
        // reason as theirs (see NoteHighlighterHost.qml): a missing native
        // module costs this field its styling, not the engine its load.
        Loader {
          id: focusHighlighterLoader
          source: "NoteHighlighterHost.qml"
          onLoaded: {
            item.basePointSize = root.writingPointSize
            item.document = focusEdit.textDocument
          }
        }
      }


      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: intentPage.headerHeight
        color: Color.background
        z: 2

        Column {
          id: intentHeaderColumn
          anchors.left: parent.left
          anchors.leftMargin: Math.max(0, Math.round((parent.width - focusEdit.width) / 2))
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Row {
            spacing: Style.space(16)

            OverlayButton {
              label: "←"
              onActivated: root.startFocus()
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "What's your focus?"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true
            }
          }

          // The quiet line: absent with no goal files at all (goalsList
          // empty), otherwise always shown so the Ctrl+G hint is
          // discoverable even before a goal's ever been picked.
          Text {
            visible: root.goalsList.length > 0
            text: (root.activeGoalTitle.length > 0 ? "Goal: " + root.activeGoalTitle : "No goal set")
              + "  ·  Ctrl+G to change"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }
        }
      }

      // Opaque backdrop for the picker below, same reasoning as the
      // floating header: fully occludes the typed focus line rather than
      // showing through it. focusEdit itself is left alone (still visible,
      // still focused) underneath so Escape/Ctrl+G keep working through it
      // whether the picker is open or not.
      Rectangle {
        anchors.fill: parent
        visible: root.goalPickerOpen
        color: Color.background
        z: 3
      }

      // Goal picker: the existing block-view idiom (centered column,
      // subtitle mode label, display heading, a row of OverlayButtons) —
      // see the block view above for the pattern this mirrors.
      Column {
        anchors.centerIn: parent
        visible: root.goalPickerOpen
        z: 4
        spacing: Style.space(20)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: (root.mode === "long" ? "Long Focus" : "Normal").toUpperCase()
          color: Color.muted
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 2
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Pick a goal"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.display
          font.bold: true
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(16)

          Repeater {
            model: root.goalsList
            OverlayButton {
              label: (modelData && modelData.title) ? modelData.title : (modelData ? modelData.slug : "")
              onActivated: root.chooseGoal(modelData.slug)
            }
          }
        }
      }
    }

    // --- notes view: break, two collapsible sections ---
    // Plain text, deliberately: QML's TextEdit has no supported way to apply
    // rich formatting to text as it's being typed without either a C++
    // QSyntaxHighlighter (unavailable to a QML-only Quickshell plugin) or
    // round-tripping through TextEdit's own Markdown (de)serializer, which
    // in practice escapes literal "#"/"**" characters and grows the buffer
    // on every keystroke instead of ever converting anything (verified by
    // hand). So no live rendering here -- just calm, minimal plain text,
    // with Return smart enough to continue a bullet/numbered list, in each
    // of the two sections below.
    Item {
      id: notesPage
      anchors.fill: parent
      anchors.margins: Style.space(120)
      // The header sits close to the top edge so the writing below it gets
      // the vertical space; only the sides and bottom keep the wide margin.
      anchors.topMargin: Style.space(32)
      visible: root.notesOpen

      readonly property real headerHeight: notesHeaderColumn.implicitHeight + Style.space(16)

      // Esc from the page itself, not only from inside a section: with every
      // section collapsed no TextEdit can hold focus, and the page does.
      // A TextEdit's own Esc handler accepts the key, so this never runs
      // twice for one press.
      Keys.onEscapePressed: root.saveNote()

      // Collapsing the section the caret is in hides its TextEdit, and a
      // hidden item drops keyboard focus -- verified: afterwards nothing on
      // the page had it, so typing and Esc both went nowhere. Hand focus to
      // the first section still open, or to the page when none is.
      function toggleSection(section, edit) {
        var hadFocus = edit.activeFocus
        root[section + "SectionOpen"] = !root[section + "SectionOpen"]
        // Reopening while the page holds focus (everything was collapsed):
        // put the caret back where the writing is.
        if (edit.visible && notesPage.activeFocus) { edit.forceActiveFocus(); return }
        if (!hadFocus || edit.visible) return
        var edits = [doneEdit, leftEdit, elseEdit]
        for (var i = 0; i < edits.length; i++) {
          if (edits[i].visible) { edits[i].forceActiveFocus(); return }
        }
        notesPage.forceActiveFocus()
      }

      Flickable {
        id: noteFlick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, notesColumn.y + notesColumn.implicitHeight)

        // Standard Qt recipe for keeping the caret visible in a TextEdit
        // wrapped in a Flickable (TextEdit has no built-in auto-scroll):
        // called on every cursor move, including the one Return itself
        // causes, so pressing Enter at the bottom scrolls down like any
        // normal editor instead of typing off the bottom of the screen.
        // Shared by both sections' TextEdits, parameterized on which one
        // fired, since they're both positioned within the same Column.
        function ensureCursorVisible(edit) {
          var top = edit.y + edit.cursorRectangle.y
          var bottom = top + edit.cursorRectangle.height
          if (top < noteFlick.contentY) {
            noteFlick.contentY = top
          } else if (bottom > noteFlick.contentY + noteFlick.height) {
            noteFlick.contentY = bottom - noteFlick.height
          }
        }

        Column {
          id: notesColumn
          // Centred on the measure, not filling the page -- see
          // overlay.writingWidth.
          x: Math.round((noteFlick.width - width) / 2)
          // A clear gap under the header so the caption label reads as a
          // label, not as the first line of the writing.
          y: notesPage.headerHeight + Style.space(32)
          width: Math.min(overlay.writingWidth, noteFlick.width)
          spacing: Style.space(32)

          // "What's done?" -- caret starts here, see openNotes().
          Column {
            width: notesColumn.width
            spacing: Style.space(8)

            Text {
              width: notesColumn.width
              text: (root.doneSectionOpen ? "▾ " : "▸ ") + "What's done?"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: notesPage.toggleSection("done", doneEdit)
              }
            }

            TextEdit {
              id: doneEdit
              visible: root.doneSectionOpen
              width: notesColumn.width
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              // The journal's writing size, not UI chrome's: this is the
              // one thing on screen you're meant to be focused on.
              font.pointSize: root.writingPointSize
              selectionColor: Util.alpha(Color.accent, 0.12)
              selectedTextColor: Color.popups.text
              persistentSelection: true
              selectByMouse: true
              focus: root.notesOpen && root.doneSectionOpen
              onCursorRectangleChanged: noteFlick.ensureCursorVisible(doneEdit)
              Keys.onEscapePressed: root.saveNote()
              Keys.onReturnPressed: function(event) { root.continueList(doneEdit, event) }
            }
          }

          // "What's left?"
          Column {
            width: notesColumn.width
            spacing: Style.space(8)

            Text {
              width: notesColumn.width
              text: (root.leftSectionOpen ? "▾ " : "▸ ") + "What's left?"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: notesPage.toggleSection("left", leftEdit)
              }
            }

            TextEdit {
              id: leftEdit
              visible: root.leftSectionOpen
              width: notesColumn.width
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              font.pointSize: root.writingPointSize
              selectionColor: Util.alpha(Color.accent, 0.12)
              selectedTextColor: Color.popups.text
              persistentSelection: true
              selectByMouse: true
              onCursorRectangleChanged: noteFlick.ensureCursorVisible(leftEdit)
              Keys.onEscapePressed: root.saveNote()
              Keys.onReturnPressed: function(event) { root.continueList(leftEdit, event) }
            }
          }

          // "What else?" -- last on the page, after the structured account
          // of the run, for whatever else the break brought up. The caret
          // still starts in "What's done?", see openNotes().
          Column {
            width: notesColumn.width
            spacing: Style.space(8)

            Text {
              width: notesColumn.width
              text: (root.elseSectionOpen ? "▾ " : "▸ ") + "What else?"
              color: Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              font.bold: true

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: notesPage.toggleSection("else", elseEdit)
              }
            }

            TextEdit {
              id: elseEdit
              visible: root.elseSectionOpen
              width: notesColumn.width
              wrapMode: TextEdit.Wrap
              textFormat: TextEdit.PlainText
              color: Color.popups.text
              font.family: Style.font.family
              font.pointSize: root.writingPointSize
              selectionColor: Util.alpha(Color.accent, 0.12)
              selectedTextColor: Color.popups.text
              persistentSelection: true
              selectByMouse: true
              onCursorRectangleChanged: noteFlick.ensureCursorVisible(elseEdit)
              Keys.onEscapePressed: root.saveNote()
              Keys.onReturnPressed: function(event) { root.continueList(elseEdit, event) }
            }
          }
        }

        // See NoteHighlighterHost.qml for why this is a Loader rather than
        // a plain import here: it keeps a missing native module from taking
        // down the whole engine. One per section -- each is its own
        // highlighter bound to its own TextEdit's document.
        Loader {
          id: doneHighlighterLoader
          source: "NoteHighlighterHost.qml"
          onLoaded: {
            item.basePointSize = root.writingPointSize
            item.document = doneEdit.textDocument
          }
        }

        Loader {
          id: leftHighlighterLoader
          source: "NoteHighlighterHost.qml"
          onLoaded: {
            item.basePointSize = root.writingPointSize
            item.document = leftEdit.textDocument
          }
        }

        Loader {
          id: elseHighlighterLoader
          source: "NoteHighlighterHost.qml"
          onLoaded: {
            item.basePointSize = root.writingPointSize
            item.document = elseEdit.textDocument
          }
        }
      }

      // Floats over the scrollable text instead of reserving its own
      // permanent row, so scrolled-past lines disappear behind it like a
      // normal editor's sticky header. Opaque (matching the overlay's own
      // background) rather than translucent so scrolled text doesn't show
      // through illegibly.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: notesPage.headerHeight
        color: Color.background
        z: 2

        Column {
          id: notesHeaderColumn
          anchors.left: parent.left
          // Starts at the writing column's own left edge rather than the
          // page's, so the header reads as belonging to the text under it.
          anchors.leftMargin: Math.max(0, Math.round((parent.width - notesColumn.width) / 2))
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          // Kept light -- small, regular weight, slim button -- so the header
          // reads as chrome and the section headings below stay the focus.
          Row {
            id: notesHeaderRow
            spacing: Style.space(12)

            OverlayButton {
              // Icon-only, deliberately minimal: a label would compete with
              // the heading text right next to it for attention.
              label: "←"
              implicitHeight: Style.space(22)
              implicitWidth: Style.space(28)
              // Always attempts a save rather than offering a separate
              // discard -- but see saveNote()/noteLogProc: unlike before,
              // that attempt can now fail, and a failure keeps this view
              // open with the text intact instead of discarding anything.
              onActivated: root.saveNote()
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              // A caption, same tier as the block view's mode label, but at
              // partial text alpha rather than Color.muted, which on light
              // themes is too close to the background to read.
              text: "BREAK NOTES"
              color: Util.alpha(Color.popups.text, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.letterSpacing: 2
            }
          }

          // The one on-screen sign that the last save attempt was refused
          // -- quiet by design (no dialog), Color.urgent so it still reads
          // as a warning. See noteLogProc.onExited for where this is set.
          Text {
            visible: root.notesSaveFailed
            text: "Not saved — try again"
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
          }
        }
      }
    }
  }
}
