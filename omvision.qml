import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import "Parser.js" as Parser
import "Writer.js" as Writer

// Omvision — goals/tasks viewer and, as of milestone 3, writer for the
// ompom-engine file contract. Standalone Quickshell config, launched with:
//   qs -p ~/Code/omvision/omvision.qml
// Writes go through two different paths, chosen per goal-files.md §2:
//   - <slug>.md (tasks, status, the cancel note) is read-modify-write:
//     Quickshell's own FileView.setText(), atomicWrites: true (temp file
//     + rename, same guarantee notes-helper.py's write_atomic() gives),
//     and always re-read (goalWriter.reload()) immediately before the
//     mutation is applied -- never from a copy taken when the screen
//     opened, per the contract's own rule for this file.
//   - <slug>.log.md and days/YYYY-MM-DD.md (events) are append-only:
//     a Process running `tee -a <path>` with the entry written to its
//     stdin. That's O_APPEND at the kernel level with no read step at
//     all, the same discipline notes-helper.py's append_entry() uses and
//     for the same reason (§2) -- a coaching session rewriting <slug>.md
//     concurrently must never be able to cost an event its entry. `tee`
//     is invoked directly (never through a shell), matching this
//     project's existing Process usage for `find`/`wl-copy`.
ShellRoot {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string goalsDir: home + "/Notes/Omvision/goals"
  readonly property string daysDir: home + "/Notes/Omvision/days"
  // The journal is not filed under a goal: one free-form file per calendar
  // day, flat, about whatever was on your mind that day. A reader (the coach
  // skill) takes the directory whole and decides for itself what is relevant.
  readonly property string journalDir: home + "/Notes/Omvision/journal"
  readonly property string todayPath: daysDir + "/" + Parser.dayKey(new Date()) + ".md"

  property string currentScreen: "goals" // today | goals | coaching | journal | goalDetail
  property string openGoalSlug: ""

  // ---- sidebar -------------------------------------------------------------
  // There is one sidebar and one state for it: the 64px icon rail (see
  // Sidebar.qml for what was removed and why). The only question left is
  // whether it is on screen at all, and only the Journal ever answers no:
  // writing mode hides it, and the journal's own faint control brings it
  // back for as long as you want it. Leaving the journal restores it, and
  // entering the journal hides it again however it was left -- writing
  // always starts with nothing down the side of the page.
  readonly property bool writingMode: currentScreen === "journal"
  property bool sidebarRevealed: false

  function sidebarHidden() {
    return writingMode && !sidebarRevealed
  }
  function toggleSidebar() {
    if (!writingMode) return // nothing to toggle: the rail is the only state
    sidebarRevealed = !sidebarRevealed
  }
  onWritingModeChanged: if (writingMode) sidebarRevealed = false

  // slug -> { meta, logEntries }
  property var goalsData: ({})
  property var goalSlugs: []
  // Logs with no goal file of their own -- see applyGoalsList().
  property var orphanLogSlugs: []
  property var orphanLogs: ({}) // slug -> entries
  property var dayEntries: []

  function syncGoal(slug, meta, entries) {
    var d = {}
    for (var k in root.goalsData) d[k] = root.goalsData[k]
    d[slug] = { meta: meta, logEntries: entries || [] }
    root.goalsData = d
  }

  function syncOrphanLog(slug, entries) {
    var d = {}
    for (var k in root.orphanLogs) d[k] = root.orphanLogs[k]
    d[slug] = entries || []
    root.orphanLogs = d
  }

  function applyGoalsList(text) {
    var lines = String(text || "").split("\n")
    var slugs = []
    var logStems = []
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].trim()
      if (p === "") continue
      var base = p.replace(/^.*\//, "")
      if (!base.match(/\.md$/)) continue
      var stem = base.replace(/\.md$/, "")
      if (stem.match(/\.log$/)) { // "<slug>.log.md" — the log, not the goal file
        logStems.push(stem.replace(/\.log$/, ""))
        continue
      }
      slugs.push(stem)
    }
    slugs.sort()

    // A log whose goal file is gone (renamed, deleted, or written by the
    // timer against a slug that never had one) still describes pomodoros
    // that really happened. The goal loaders below are driven by `slugs`,
    // so those entries used to be invisible everywhere in the app --
    // Today showed nothing for a run that is sitting right there on disk.
    // They get loaded separately and shown on Today under their slug.
    var have = {}
    for (var h = 0; h < slugs.length; h++) have[slugs[h]] = true
    var orphans = []
    for (var l = 0; l < logStems.length; l++) {
      if (!have[logStems[l]]) orphans.push(logStems[l])
    }
    orphans.sort()
    var orphansChanged = orphans.length !== root.orphanLogSlugs.length
    if (!orphansChanged) {
      for (var o = 0; o < orphans.length; o++) {
        if (orphans[o] !== root.orphanLogSlugs[o]) { orphansChanged = true; break }
      }
    }
    if (orphansChanged) {
      root.orphanLogSlugs = orphans
      var keep = {}
      for (var k = 0; k < orphans.length; k++) keep[orphans[k]] = true
      var prunedOrphans = {}
      for (var ko in root.orphanLogs) if (keep[ko]) prunedOrphans[ko] = root.orphanLogs[ko]
      root.orphanLogs = prunedOrphans
    }

    var changed = slugs.length !== root.goalSlugs.length
    if (!changed) {
      for (var j = 0; j < slugs.length; j++) {
        if (slugs[j] !== root.goalSlugs[j]) { changed = true; break }
      }
    }
    if (!changed) return

    root.goalSlugs = slugs

    // Drop stale entries for goals whose files disappeared.
    var set = {}
    for (var s = 0; s < slugs.length; s++) set[slugs[s]] = true
    var pruned = {}
    for (var k2 in root.goalsData) if (set[k2]) pruned[k2] = root.goalsData[k2]
    root.goalsData = pruned
  }

  readonly property var todaySummary: computeTodaySummary(goalsData, dayEntries)

  // ---- write path: <slug>.md (read-modify-write, re-read every time) -----
  // One shared FileView, one job at a time (writeQueue), so two writes
  // (e.g. ticking two tasks quickly) can never stomp each other's
  // pendingMutate/pendingDone -- each job gets its own fresh reload().
  property var writeQueue: []
  property bool writeBusy: false
  property string writeError: ""

  function showWriteError(message) {
    root.writeError = message
    writeErrorTimer.restart()
  }

  function queueGoalWrite(slug, mutateFn, onDone) {
    root.writeQueue.push({ slug: slug, mutate: mutateFn, onDone: onDone })
    root.pumpWriteQueue()
  }

  function pumpWriteQueue() {
    if (root.writeBusy || root.writeQueue.length === 0) return
    var job = root.writeQueue.shift()
    root.writeBusy = true
    goalWriter.pendingMutate = job.mutate
    goalWriter.pendingDone = function(ok, message) {
      root.writeBusy = false
      if (job.onDone) job.onDone(ok, message)
      root.pumpWriteQueue()
    }
    goalWriter.path = root.goalsDir + "/" + job.slug + ".md"
    goalWriter.reload()
  }

  function handleToggleTask(slug, index) {
    root.queueGoalWrite(slug, function(text) {
      var eol = Writer.detectEol(text)
      var out = Writer.toggleTask(Writer.splitLines(text), index)
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't update the task" + (message ? " (" + message + ")" : "") + ".")
    })
  }

  function handleAddTask(slug, text, resultFn) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var out = Writer.addTask(Writer.splitLines(raw), text)
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't add the task" + (message ? " (" + message + ")" : "") + ".")
      if (resultFn) resultFn(ok, message)
    })
  }

  function handleEditTask(slug, index, text, resultFn) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var out = Writer.editTask(Writer.splitLines(raw), index, text)
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't update the task" + (message ? " (" + message + ")" : "") + ".")
      if (resultFn) resultFn(ok, message)
    })
  }

  function handleCloseGoal(slug) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var out = Writer.setStatus(Writer.splitLines(raw), "done")
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't close the goal" + (message ? " (" + message + ")" : "") + ".")
    })
  }

  function handleReopenGoal(slug) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var out = Writer.setStatus(Writer.splitLines(raw), "active")
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't reopen the goal" + (message ? " (" + message + ")" : "") + ".")
    })
  }

  function handleCancelGoal(slug, reason, takeaway, resultFn) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var lines = Writer.setStatus(Writer.splitLines(raw), "cancelled")
      if (!lines) return null
      lines = Writer.appendCancelNote(lines, Writer.headingTimestamp(new Date()), reason, takeaway)
      return Writer.joinLines(lines, eol)
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't cancel the goal" + (message ? " (" + message + ")" : "") + ".")
      if (resultFn) resultFn(ok, message)
    })
  }

  // ---- write path: <slug>.log.md / days/YYYY-MM-DD.md (append-only) ------
  property var appendQueue: []
  property bool appendBusy: false

  function queueAppend(path, content, onDone) {
    root.appendQueue.push({ path: path, content: content, onDone: onDone })
    root.pumpAppendQueue()
  }

  function pumpAppendQueue() {
    if (root.appendBusy || root.appendQueue.length === 0) return
    var job = root.appendQueue.shift()
    root.appendBusy = true
    appendProc.pendingPayload = job.content
    appendProc.pendingDone = function(ok) {
      root.appendBusy = false
      if (job.onDone) job.onDone(ok)
      root.pumpAppendQueue()
    }
    appendProc.command = ["/usr/bin/tee", "-a", job.path]
    appendProc.stdinEnabled = true
    appendProc.running = true
  }

  function handleAddEvent(payload, resultFn) {
    var entryText = Writer.formatEventEntry(payload.whenDate, payload.minutes, payload.kind, payload.what, payload.countsToward)
    var slug = String(payload.slug || "")
    var path
    if (slug.length > 0 && /^[a-z0-9][a-z0-9-]*$/.test(slug)) {
      path = root.goalsDir + "/" + slug + ".log.md"
    } else {
      path = root.daysDir + "/" + Parser.dayKey(payload.whenDate) + ".md"
    }
    root.queueAppend(path, entryText, function(ok) {
      if (!ok) root.showWriteError("Couldn't log the event — nothing was saved. Copy your note before retrying.")
      if (resultFn) resultFn(ok)
    })
  }

  function openEventDialog(slug) {
    root.eventDialogDefaultSlug = slug
    root.eventDialogError = ""
    root.eventDialogOpen = true
  }

  property bool eventDialogOpen: false
  property string eventDialogDefaultSlug: ""
  property string eventDialogError: ""

  function openNewGoalDialog() {
    root.newGoalError = ""
    root.editGoalSlug = ""
    root.newGoalDialogOpen = true
  }

  // The New goal dialog doubles as Edit goal: same fields, pre-filled,
  // saved in place instead of creating a file.
  function openEditGoalDialog(slug) {
    if (!root.goalsData[slug] || !root.goalsData[slug].meta) return
    root.newGoalError = ""
    root.editGoalSlug = slug
    root.newGoalDialogOpen = true
  }

  function handleEditGoal(slug, fields, resultFn) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var out = Writer.updateGoalFields(Writer.splitLines(raw), fields)
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (resultFn) resultFn(ok, message)
    })
  }

  property bool newGoalDialogOpen: false
  property string newGoalError: ""
  property string editGoalSlug: ""

  // ---- write path: creating a new goal (<slug>.md), goal-files.md §3 -----
  // One goalCreateFile FileView, reused across the whole collision-probe
  // sequence: reload() against a candidate slug's path either succeeds
  // (something is already there -- read its title to decide "same goal,
  // no-op" vs. "someone else's goal, try <base>-2, <base>-3, ...") or
  // fails (the slug is free, write the new file there). Every candidate
  // is a fresh read right before any decision is made about it, same
  // "re-read immediately before mutating" discipline the rest of this
  // file's writers follow for <slug>.md.
  property var newGoalQueue: []
  property bool newGoalBusy: false
  property var newGoalJob: null
  property string newGoalBaseSlug: ""
  property string newGoalAttemptSlug: ""
  property int newGoalAttemptN: 1

  function queueNewGoal(fields, onDone) {
    root.newGoalQueue.push({ fields: fields, onDone: onDone })
    root.pumpNewGoalQueue()
  }

  function pumpNewGoalQueue() {
    if (root.newGoalBusy || root.newGoalQueue.length === 0) return
    var job = root.newGoalQueue.shift()
    root.newGoalBusy = true
    root.newGoalJob = job
    root.newGoalBaseSlug = Writer.deriveSlug(job.fields.title)
    root.newGoalAttemptSlug = root.newGoalBaseSlug
    root.newGoalAttemptN = 1
    root.tryCreateGoalSlug()
  }

  function tryCreateGoalSlug() {
    goalCreateFile.path = root.goalsDir + "/" + root.newGoalAttemptSlug + ".md"
    // Deferred through a zero-interval Timer rather than reload() called
    // straight from here: this function is itself often invoked from
    // inside goalCreateFile's own onSaved/onLoaded handlers (chained
    // collision-probe attempts, or the next queued job starting up), and
    // calling reload() synchronously from inside that same FileView's own
    // signal handler reliably stalled the chain in testing -- the same
    // class of dropped-completion-signal issue documented on setText()
    // below, just triggered by reload() instead.
    deferredCreateReload.start()
  }

  function finishNewGoal(ok, message, slug) {
    var job = root.newGoalJob
    root.newGoalJob = null
    root.newGoalBusy = false
    if (job && job.onDone) job.onDone(ok, message, slug)
    root.pumpNewGoalQueue()
  }

  function handleCreateGoal(fields, resultFn) {
    var title = String(fields.title || "").trim()
    if (title === "") { if (resultFn) resultFn(false, "Title is required.", ""); return }
    var clean = {
      title: title,
      why: String(fields.why || "").trim(),
      estimate: fields.estimate,
      doneBy: fields.doneBy
    }
    root.queueNewGoal(clean, function(ok, message, slug) {
      // Don't wait on the 2s directory poll -- a goal just created should
      // show up in the list right away.
      if (ok) listProc.running = true
      if (resultFn) resultFn(ok, message, slug)
    })
  }

  function computeTodaySummary(data, entries) {
    var now = new Date()
    var todayKey = Parser.dayKey(now)
    var poms = 0, minutes = 0
    function scan(list) {
      for (var i = 0; i < list.length; i++) {
        var e = list[i]
        if (Parser.dayKey(e.date) !== todayKey) continue
        if (e.type === "pomodoro") { poms++; minutes += e.minutes }
      }
    }
    for (var slug in data) scan(data[slug].logEntries || [])
    scan(entries || [])
    return { poms: poms, minutes: minutes }
  }

  // ---- directory listing: polled since Quickshell has no folder watcher --
  Process {
    id: listProc
    command: ["/usr/bin/find", root.goalsDir, "-maxdepth", "1", "-type", "f", "-name", "*.md"]
    stdout: StdioCollector {
      id: listCollector
      onStreamFinished: root.applyGoalsList(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: listProc.running = true
  }

  // ---- per-goal file loaders ----------------------------------------------
  Instantiator {
    id: orphanLogLoaders
    model: root.orphanLogSlugs
    delegate: QtObject {
      id: orphanLoader
      required property string modelData

      property FileView logFile: FileView {
        path: root.goalsDir + "/" + orphanLoader.modelData + ".log.md"
        watchChanges: true
        printErrors: false
        onLoaded: root.syncOrphanLog(orphanLoader.modelData, Parser.parseLogEntries(text(), new Date()))
        onLoadFailed: function(error) { root.syncOrphanLog(orphanLoader.modelData, []) }
        onFileChanged: reload()
      }
    }
  }

  Instantiator {
    id: goalLoaders
    model: root.goalSlugs
    delegate: QtObject {
      id: loader
      required property string modelData
      readonly property string slug: modelData
      property var meta: null
      property var entries: []

      property FileView mdFile: FileView {
        path: root.goalsDir + "/" + loader.slug + ".md"
        watchChanges: true
        printErrors: false
        onLoaded: {
          loader.meta = Parser.parseGoalFile(text())
          root.syncGoal(loader.slug, loader.meta, loader.entries)
        }
        onLoadFailed: function(error) {
          loader.meta = null
          root.syncGoal(loader.slug, null, loader.entries)
        }
        onFileChanged: reload()
      }

      property FileView logFile: FileView {
        path: root.goalsDir + "/" + loader.slug + ".log.md"
        watchChanges: true
        printErrors: false
        onLoaded: {
          loader.entries = Parser.parseLogEntries(text(), new Date())
          root.syncGoal(loader.slug, loader.meta, loader.entries)
        }
        onLoadFailed: function(error) {
          // No log yet is normal (§6): zero entries, not an error.
          loader.entries = []
          root.syncGoal(loader.slug, loader.meta, [])
        }
        onFileChanged: reload()
      }
    }
  }

  // ---- today's day file (poms/events run with no active goal) ------------
  FileView {
    id: dayFile
    path: root.todayPath
    watchChanges: true
    printErrors: false
    onLoaded: root.dayEntries = Parser.parseLogEntries(text(), new Date())
    onLoadFailed: function(error) { root.dayEntries = [] }
    onFileChanged: reload()
  }

  // ---- journal files: journal/YYYY-MM-DD.md -------------------------------
  // Same discovery/load idiom as the goal loaders above: poll a `find` for
  // the file list, then a per-file FileView loads and watches each one.
  // The Journal screen only ever receives the already-read result.
  property var journalFiles: []      // [{path, dateIso}]
  property var journalContents: ({}) // path -> raw text

  function applyJournalList(text) {
    var lines = String(text || "").split("\n")
    var files = []
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].trim()
      if (p === "") continue
      var base = p.replace(/^.*\//, "")
      var m = base.match(/^(\d{4}-\d{2}-\d{2})\.md$/)
      if (!m) continue
      files.push({ path: p, dateIso: m[1] })
    }
    files.sort(function(a, b) { return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0) })

    var changed = files.length !== root.journalFiles.length
    if (!changed) {
      for (var j = 0; j < files.length; j++) {
        if (files[j].path !== root.journalFiles[j].path) { changed = true; break }
      }
    }
    if (!changed) return

    root.journalFiles = files

    var set = {}
    for (var s = 0; s < files.length; s++) set[files[s].path] = true
    var pruned = {}
    for (var k in root.journalContents) if (set[k]) pruned[k] = root.journalContents[k]
    root.journalContents = pruned
  }

  function setJournalContent(path, text) {
    var d = {}
    for (var k in root.journalContents) d[k] = root.journalContents[k]
    d[path] = text
    root.journalContents = d
  }

  Process {
    id: journalListProc
    // Missing directory is not an error here: `find` writes to stderr, stdout
    // stays empty, and the screen shows today as the one (not-yet-created)
    // day -- which is exactly the state of a journal nobody has written in.
    command: ["/usr/bin/find", root.journalDir, "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "*.md"]
    stdout: StdioCollector {
      id: journalListCollector
      onStreamFinished: root.applyJournalList(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: journalListProc.running = true
  }

  Instantiator {
    id: journalLoaders
    model: root.journalFiles
    delegate: QtObject {
      id: jloader
      required property var modelData

      property FileView file: FileView {
        path: jloader.modelData.path
        watchChanges: true
        printErrors: false
        onLoaded: root.setJournalContent(jloader.modelData.path, text())
        onLoadFailed: function(error) { root.setJournalContent(jloader.modelData.path, "") }
        onFileChanged: reload()
      }
    }
  }

  // <slug>.md writer: reload() forces a fresh read every time
  // pumpWriteQueue() starts a job, so `text()` here is never the copy the
  // screen opened with. atomicWrites: true is the same temp-file+rename
  // guarantee write_atomic() gives on the Python side -- a crash or a
  // killed process mid-write can never leave a half-written <slug>.md.
  //
  // setText() is deferred to the next event-loop turn (deferredSetText,
  // a 0-interval Timer) rather than called straight from onLoaded:
  // calling it synchronously, in-handler, reliably got its completion
  // signal dropped on this Quickshell build (0.3.1) -- the write itself
  // still landed on disk either way, but onSaved/onSaveFailed never
  // fired, which stalled the write queue forever after the first job.
  // Verified both ways against the real filesystem before landing this.
  FileView {
    id: goalWriter
    property var pendingMutate: null
    property var pendingDone: null
    property string pendingText: ""
    printErrors: false
    watchChanges: false
    atomicWrites: true
    onLoaded: {
      var mutate = goalWriter.pendingMutate
      var done = goalWriter.pendingDone
      if (!mutate) return
      goalWriter.pendingMutate = null
      var newText
      try { newText = mutate(goalWriter.text()) } catch (e) { newText = null }
      if (newText === null || newText === undefined) {
        goalWriter.pendingDone = null
        if (done) done(false, "goal file changed unexpectedly")
        return
      }
      goalWriter.pendingText = newText
      deferredSetText.start()
    }
    onLoadFailed: function(error) {
      var done = goalWriter.pendingDone
      goalWriter.pendingMutate = null
      goalWriter.pendingDone = null
      if (done) done(false, "couldn't read the goal file")
    }
    onSaved: {
      var done = goalWriter.pendingDone
      goalWriter.pendingMutate = null
      goalWriter.pendingDone = null
      if (done) done(true, "")
    }
    onSaveFailed: function(error) {
      var done = goalWriter.pendingDone
      goalWriter.pendingMutate = null
      goalWriter.pendingDone = null
      if (done) done(false, "couldn't save the goal file")
    }
  }

  Timer {
    id: deferredSetText
    interval: 0
    onTriggered: goalWriter.setText(goalWriter.pendingText)
  }

  // New-goal creation prober/writer, goal-files.md §3. reload() against a
  // candidate <slug>.md either loads (occupied -- check its title) or
  // fails to load (free -- write the new file there). setText() is
  // deferred through a zero-interval Timer for the same reason
  // goalWriter's is: calling it synchronously from inside a FileView
  // signal handler on this Quickshell build reliably drops the
  // completion signal (onSaved never fires), which would stall this
  // dialog forever after the write actually landed on disk.
  FileView {
    id: goalCreateFile
    property string pendingText: ""
    property string pendingSlug: ""
    printErrors: false
    watchChanges: false
    atomicWrites: true
    onLoaded: {
      if (!root.newGoalJob) return
      var meta = Parser.parseGoalFile(text())
      var title = meta ? meta.title : null
      if (title !== null && title === root.newGoalJob.fields.title) {
        // Same title at this slug -- same goal. Creating it again is a
        // no-op, not an error (goal-files.md §3).
        root.finishNewGoal(true, "", root.newGoalAttemptSlug)
        return
      }
      // Slug is taken by a different goal (or an unparseable file):
      // try <base>-2, <base>-3, ... A generous but finite cap keeps this
      // from spinning forever if something truly pathological is going on.
      if (root.newGoalAttemptN > 500) {
        root.finishNewGoal(false, "couldn't find a free slug", "")
        return
      }
      root.newGoalAttemptN += 1
      root.newGoalAttemptSlug = root.newGoalBaseSlug + "-" + root.newGoalAttemptN
      root.tryCreateGoalSlug()
    }
    onLoadFailed: function(error) {
      if (!root.newGoalJob) return
      // Nothing at this slug -- free to create. Never overwrites: this
      // branch is only reached when the read above just failed.
      goalCreateFile.pendingText = Writer.buildNewGoalFile(root.newGoalJob.fields)
      goalCreateFile.pendingSlug = root.newGoalAttemptSlug
      deferredNewGoalSetText.start()
    }
    onSaved: root.finishNewGoal(true, "", goalCreateFile.pendingSlug)
    onSaveFailed: function(error) { root.finishNewGoal(false, "couldn't create the goal file", "") }
  }

  Timer {
    id: deferredNewGoalSetText
    interval: 0
    onTriggered: goalCreateFile.setText(goalCreateFile.pendingText)
  }

  Timer {
    id: deferredCreateReload
    interval: 0
    onTriggered: goalCreateFile.reload()
  }

  // <slug>.log.md / days/YYYY-MM-DD.md appender: `tee -a` opens O_APPEND
  // and never reads the target first (§2) -- this can run concurrently
  // with a coaching session rewriting the same goal's <slug>.md, or with
  // ompom's own notes-helper.py appending to the same log file, and
  // neither side can ever observe or clobber the other's already-written
  // bytes.
  Process {
    id: appendProc
    property string pendingPayload: ""
    property var pendingDone: null
    command: []
    onStarted: {
      appendProc.write(appendProc.pendingPayload)
      appendProc.stdinEnabled = false
    }
    onExited: function(exitCode) {
      var done = appendProc.pendingDone
      appendProc.pendingDone = null
      if (done) done(exitCode === 0)
    }
  }

  Timer {
    id: writeErrorTimer
    interval: 5000
    onTriggered: root.writeError = ""
  }

  FloatingWindow {
    id: window
    title: "Omvision"
    // bin/shot sets these to capture at other sizes; unset, they are 0.
    implicitWidth: parseInt(Quickshell.env("OMVISION_SHOT_WIDTH") || "0") || 1440
    implicitHeight: parseInt(Quickshell.env("OMVISION_SHOT_HEIGHT") || "0") || 900
    minimumSize: Qt.size(720, 560)
    color: Theme.paper

    Item {
      id: contentRoot
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_B && (event.modifiers & Qt.ControlModifier)) {
          root.toggleSidebar()
          event.accepted = true
        }
      }

      // Offscreen screenshots for bin/shot; inactive (nothing loaded) in a
      // normal launch. Behind everything, since it also paints the paper
      // the grab needs -- see ShotDriver.qml.
      Loader {
        anchors.fill: parent
        z: -1
        active: Quickshell.env("OMVISION_SHOT_DIR") !== null
                && Quickshell.env("OMVISION_SHOT_DIR") !== ""
        source: "ShotDriver.qml"
        onLoaded: {
          item.app = root
          item.journal = journalScreen
          item.goalDetail = goalDetailScreen
          item.target = contentRoot
        }
      }

      Row {
        anchors.fill: parent
        spacing: 0

        // Showing and hiding the sidebar animates the room it takes, not the
        // sidebar itself: this slot opens from 0 to the rail's width, the
        // rail (always its full 64px, so nothing inside it squeezes) slides
        // in along with it, and the content beside it narrows in step
        // instead of jumping sideways.
        Item {
          id: sidebarSlot
          height: parent.height
          width: root.sidebarHidden() ? 0 : inFlowSidebar.railWidth
          visible: width > 0
          clip: true

          Behavior on width {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
          }

          Sidebar {
            id: inFlowSidebar
            height: parent.height
            x: sidebarSlot.width - width
            currentScreen: root.currentScreen === "goalDetail" ? "goals" : root.currentScreen
            onNavigate: function(screen) { root.currentScreen = screen }
          }
        }

        // The screens. Each is told how far this area sits from the window's
        // left edge -- the rail's width, animated -- so it can centre its
        // text column on the window rather than on this area (Theme.pageX),
        // and the column stays put while the rail slides in or out.
        Item {
          width: parent.width - sidebarSlot.width
          height: parent.height

          GoalsScreen {
          anchors.fill: parent
          leftInset: sidebarSlot.width
          visible: root.currentScreen === "goals"
          goalsData: root.goalsData
          todaySummary: root.todaySummary
          selectedSlug: root.openGoalSlug
          onOpenGoal: function(slug) {
            root.openGoalSlug = slug
            root.currentScreen = "goalDetail"
          }
          onAddEventRequested: root.openEventDialog("")
          onNewGoalRequested: root.openNewGoalDialog()
          onEditGoalRequested: function(slug) { root.openEditGoalDialog(slug) }
        }

        GoalDetailScreen {
          id: goalDetailScreen
          anchors.fill: parent
          leftInset: sidebarSlot.width
          visible: root.currentScreen === "goalDetail"
          slug: root.openGoalSlug
          meta: root.goalsData[root.openGoalSlug] ? root.goalsData[root.openGoalSlug].meta : null
          logEntries: root.goalsData[root.openGoalSlug] ? root.goalsData[root.openGoalSlug].logEntries : []
          onBack: root.currentScreen = "goals"
          onToggleTask: function(index) { root.handleToggleTask(root.openGoalSlug, index) }
          onAddTask: function(text) {
            root.handleAddTask(root.openGoalSlug, text, function(ok, message) {
              goalDetailScreen.onAddTaskResult(ok, message)
            })
          }
          onEditTask: function(index, text) {
            root.handleEditTask(root.openGoalSlug, index, text, function(ok, message) {
              goalDetailScreen.onEditTaskResult(ok, message)
            })
          }
          onCloseGoal: root.handleCloseGoal(root.openGoalSlug)
          onReopenGoal: root.handleReopenGoal(root.openGoalSlug)
          onCancelGoal: function(reason, takeaway) {
            root.handleCancelGoal(root.openGoalSlug, reason, takeaway, function(ok, message) {
              goalDetailScreen.onCancelResult(ok, message)
            })
          }
          onAddEventRequested: root.openEventDialog(root.openGoalSlug)
          onCoachRequested: {
            coachingScreen.selectedSlug = root.openGoalSlug
            root.currentScreen = "coaching"
          }
        }

        TodayScreen {
          anchors.fill: parent
          leftInset: sidebarSlot.width
          visible: root.currentScreen === "today"
          goalsData: root.goalsData
          dayEntries: root.dayEntries
          orphanLogs: root.orphanLogs
        }

        CoachingScreen {
          id: coachingScreen
          anchors.fill: parent
          leftInset: sidebarSlot.width
          visible: root.currentScreen === "coaching"
          goalsData: root.goalsData
        }

        JournalScreen {
          id: journalScreen
          anchors.fill: parent
          leftInset: sidebarSlot.width
          visible: root.currentScreen === "journal"
          journalFiles: root.journalFiles
          journalContents: root.journalContents
          sidebarShown: !root.sidebarHidden()
          onToggleSidebar: root.toggleSidebar()
        }
        }
      }

      EventDialog {
        anchors.fill: parent
        visible: root.eventDialogOpen
        z: 900
        goalsData: root.goalsData
        defaultSlug: root.eventDialogDefaultSlug
        errorMessage: root.eventDialogError
        onDismissed: root.eventDialogOpen = false
        onSubmitted: function(payload) {
          root.eventDialogError = ""
          root.handleAddEvent(payload, function(ok) {
            if (ok) root.eventDialogOpen = false
            else root.eventDialogError = "Couldn't log the event. Your entry is still here — try again."
          })
        }
      }

      // Mounted at the window root, not nested inside GoalDetailScreen
      // (which only fills the content area to the right of the sidebar):
      // a modal has to sit above everything, including the floating
      // narrow-mode sidebar overlay below, so it lives at the same level
      // EventDialog does. Driven entirely by goalDetailScreen's own
      // cancelDialogOpen/cancelError state and cancelGoal signal --
      // `goalDetailScreen.cancelGoal(reason, takeaway)` emits that
      // screen's signal exactly as if it had fired internally, so the
      // existing onCancelGoal wiring above still owns the actual write.
      CancelDialog {
        anchors.fill: parent
        visible: goalDetailScreen.cancelDialogOpen
        z: 900
        goalTitle: goalDetailScreen.meta ? goalDetailScreen.meta.title : goalDetailScreen.slug
        poms: goalDetailScreen.poms
        errorMessage: goalDetailScreen.cancelError
        onConfirmed: function(reason, takeaway) {
          goalDetailScreen.cancelError = ""
          goalDetailScreen.cancelGoal(reason, takeaway)
        }
        onDismissed: {
          goalDetailScreen.cancelDialogOpen = false
          goalDetailScreen.cancelError = ""
        }
      }

      NewGoalDialog {
        anchors.fill: parent
        visible: root.newGoalDialogOpen
        z: 900
        errorMessage: root.newGoalError
        editSlug: root.editGoalSlug
        initial: root.editGoalSlug !== "" && root.goalsData[root.editGoalSlug]
          ? root.goalsData[root.editGoalSlug].meta : null
        onDismissed: root.newGoalDialogOpen = false
        onSubmitted: function(fields) {
          root.newGoalError = ""
          if (root.editGoalSlug !== "") {
            root.handleEditGoal(root.editGoalSlug, fields, function(ok, message) {
              if (ok) root.newGoalDialogOpen = false
              else root.newGoalError = "Couldn't save the goal" + (message ? " (" + message + ")" : "") + "."
            })
            return
          }
          root.handleCreateGoal(fields, function(ok, message, slug) {
            if (ok) root.newGoalDialogOpen = false
            else root.newGoalError = message || "Couldn't create the goal."
          })
        }
      }

      // A failed write is never silent (layout-rules-equivalent rule for
      // this milestone): every write path above funnels its failure
      // message through showWriteError(), which surfaces here for a few
      // seconds regardless of which screen is on screen when it happens.
      Rectangle {
        id: writeErrorBanner
        visible: root.writeError.length > 0
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.spaceMd
        width: Math.min(parent.width - 40, bannerText.implicitWidth + 28)
        height: bannerText.implicitHeight + 16
        color: Theme.paper
        border.color: Theme.red
        border.width: Theme.borderWidth
        z: 1000

        Text {
          id: bannerText
          anchors.centerIn: parent
          text: root.writeError
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySmallSize
          color: Theme.red
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.writeError = ""
        }
      }
    }
  }
}
