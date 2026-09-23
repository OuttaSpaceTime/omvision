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
  readonly property string todayPath: daysDir + "/" + Parser.dayKey(new Date()) + ".md"

  property string currentScreen: "goals" // today | goals | coaching | journal | goalDetail
  property string openGoalSlug: ""

  // ---- collapsible sidebar -------------------------------------------------
  // Breakpoint picked off the widest screen (Goal detail: timeline + a 312px
  // rail). Below this, the two-column body starts crowding, so the sidebar
  // collapses on its own to give the content room; above it, it's back to an
  // ordinary in-flow 176px sidebar. A manual toggle always wins over the
  // automatic choice until the window crosses the breakpoint again — that's
  // `sidebarOverride`, reset to "no override" exactly when `sidebarWide` flips.
  readonly property int sidebarBreakpoint: 960
  readonly property bool sidebarWide: window.width >= sidebarBreakpoint
  property var sidebarOverride: null // null = follow automatic; true/false = manual pin

  function sidebarCollapsed() {
    return sidebarOverride !== null ? sidebarOverride : !sidebarWide
  }
  function toggleSidebar() {
    sidebarOverride = !sidebarCollapsed()
  }
  function closeNarrowOverlay() {
    if (!sidebarWide) sidebarOverride = true
  }
  onSidebarWideChanged: sidebarOverride = null // crossing the breakpoint clears the manual pin

  // slug -> { meta, logEntries }
  property var goalsData: ({})
  property var goalSlugs: []
  property var dayEntries: []

  function syncGoal(slug, meta, entries) {
    var d = {}
    for (var k in root.goalsData) d[k] = root.goalsData[k]
    d[slug] = { meta: meta, logEntries: entries || [] }
    root.goalsData = d
  }

  function applyGoalsList(text) {
    var lines = String(text || "").split("\n")
    var slugs = []
    for (var i = 0; i < lines.length; i++) {
      var p = lines[i].trim()
      if (p === "") continue
      var base = p.replace(/^.*\//, "")
      if (!base.match(/\.md$/)) continue
      var stem = base.replace(/\.md$/, "")
      if (stem.match(/\.log$/)) continue // "<slug>.log.md" — that's the log, not a goal file
      slugs.push(stem)
    }
    slugs.sort()

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

  function handleCloseGoal(slug) {
    root.queueGoalWrite(slug, function(raw) {
      var eol = Writer.detectEol(raw)
      var out = Writer.setStatus(Writer.splitLines(raw), "done")
      return out ? Writer.joinLines(out, eol) : null
    }, function(ok, message) {
      if (!ok) root.showWriteError("Couldn't close the goal" + (message ? " (" + message + ")" : "") + ".")
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
    root.newGoalDialogOpen = true
  }

  property bool newGoalDialogOpen: false
  property string newGoalError: ""

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

  // ---- journal files: goals/<slug>/journal/*.md ---------------------------
  // Same discovery/load idiom as the goal loaders above: poll a `find` for
  // the file list, then a per-file FileView loads and watches each one.
  // Journal screen (Journal.md, goal-files.md §1) only ever receives the
  // already-read result.
  property var journalFiles: []      // [{slug, path, dateIso}]
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
      var parts = p.split("/")
      var slug = parts.length >= 3 ? parts[parts.length - 3] : ""
      if (!slug) continue
      files.push({ slug: slug, path: p, dateIso: m[1] })
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
    command: ["/usr/bin/find", root.goalsDir, "-mindepth", "3", "-maxdepth", "3", "-type", "f", "-name", "*.md"]
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
    implicitWidth: 1440
    implicitHeight: 900
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

      Row {
        anchors.fill: parent
        spacing: 0

        Sidebar {
          id: inFlowSidebar
          height: parent.height
          // While narrow, the in-flow rail is always the collapsed rail —
          // an "expanded while narrow" choice renders as the overlay below,
          // it never pushes this layout (spec: overlay, don't push).
          collapsed: root.sidebarWide ? root.sidebarCollapsed() : true
          currentScreen: root.currentScreen === "goalDetail" ? "goals" : root.currentScreen
          onNavigate: function(screen) { root.currentScreen = screen }
          onToggle: root.toggleSidebar()
        }

        Item {
          width: parent.width - inFlowSidebar.width
          height: parent.height

          GoalsScreen {
          anchors.fill: parent
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
        }

        GoalDetailScreen {
          id: goalDetailScreen
          anchors.fill: parent
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
          onCloseGoal: root.handleCloseGoal(root.openGoalSlug)
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
          visible: root.currentScreen === "today"
          goalsData: root.goalsData
          dayEntries: root.dayEntries
        }

        CoachingScreen {
          id: coachingScreen
          anchors.fill: parent
          visible: root.currentScreen === "coaching"
          goalsData: root.goalsData
        }

        JournalScreen {
          anchors.fill: parent
          visible: root.currentScreen === "journal"
          journalFiles: root.journalFiles
          journalContents: root.journalContents
          goalsData: root.goalsData
        }
        }
      }

      // Click-outside catcher for the narrow-mode overlay: sits above the
      // content but below the overlay sidebar itself, so a click anywhere
      // in the content closes the overlay without also acting on whatever
      // is underneath it.
      MouseArea {
        anchors.left: overlaySidebar.right
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: overlaySidebar.visible
        enabled: overlaySidebar.visible
        onClicked: root.closeNarrowOverlay()
      }

      // Narrow-mode "expanded anyway" overlay: floats over the content,
      // anchored to the left edge, full height, opaque background (Sidebar's
      // own Rectangle fill already is), own right hairline. Never resizes
      // the in-flow layout — see `inFlowSidebar.collapsed` above.
      Sidebar {
        id: overlaySidebar
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        collapsed: false
        visible: !root.sidebarWide && !root.sidebarCollapsed()
        currentScreen: root.currentScreen === "goalDetail" ? "goals" : root.currentScreen
        onNavigate: function(screen) { root.currentScreen = screen; root.closeNarrowOverlay() }
        onToggle: root.closeNarrowOverlay()
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
        onDismissed: root.newGoalDialogOpen = false
        onSubmitted: function(fields) {
          root.newGoalError = ""
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
        anchors.topMargin: 14
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
