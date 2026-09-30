import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io

import "Parser.js" as Parser
import "Writer.js" as Writer
import "Util.js" as Util

// Omvision -- goals, tasks, a daily journal and coaching, over the ompom
// engine's file contract (~/Code/ompom-engine/docs/goal-files.md). A
// standalone Quickshell config, launched with bin/omvision rather than
// `qs -p` by hand: the launcher puts the journal's compiled markdown
// highlighter on the import path (see bin/omvision for why it has to).
//
// This file owns the app's data. It lists and loads every goal, log, day and
// journal file and hands the screens results that are already parsed, and it
// makes every write except the journal's, which JournalScreen does itself.
// Writes take one of two paths, chosen per goal-files.md §2:
//   - <slug>.md (tasks, status, the cancel note, a new goal) is
//     read-modify-write, through goalFiles (SerialFileWriter.qml): one job at
//     a time, the file always re-read immediately before the change is
//     applied -- never from a copy taken when the screen opened, per the
//     contract's own rule for this file -- and written atomically (temp file
//     + rename, the same guarantee notes-helper.py's write_atomic() gives).
//   - <slug>.log.md and days/YYYY-MM-DD.md (events) are append-only, through
//     appender (Appender.qml): `tee -a`, O_APPEND with no read step at all,
//     the discipline notes-helper.py's append_entry() follows for the same
//     reason -- a coaching session rewriting <slug>.md concurrently must
//     never be able to cost an event its entry.
// Where the files live is Paths.qml's business.
ShellRoot {
  id: root

  // Evaluated once, at startup, like before Paths existed: the day file the
  // Today screen reads does not roll over at midnight.
  readonly property string todayPath: Paths.dayFile(Parser.dayKey(new Date()))

  property string currentScreen: "goals" // today | goals | coaching | journal | goalDetail
  property string openGoalSlug: ""
  // The screen a goal's back link returns to: the Goals list, or the
  // journal when the goal was opened from an `@` tag there, so reading up
  // on a goal mid-sentence puts you back in the sentence.
  property string goalBackScreen: "goals"

  function openGoal(slug, from) {
    root.openGoalSlug = slug
    root.goalBackScreen = from
    root.currentScreen = "goalDetail"
  }

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

  // Each of these state objects is replaced whole, never edited in place:
  // see Util.js for why.
  function syncGoal(slug, meta, entries) {
    root.goalsData = Util.withKey(root.goalsData, slug, { meta: meta, logEntries: entries || [] })
  }

  function syncOrphanLog(slug, entries) {
    root.orphanLogs = Util.withKey(root.orphanLogs, slug, entries || [])
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
    if (!Util.sameList(orphans, root.orphanLogSlugs)) {
      root.orphanLogSlugs = orphans
      root.orphanLogs = Util.pickKeys(root.orphanLogs, orphans)
    }

    if (Util.sameList(slugs, root.goalSlugs)) return
    root.goalSlugs = slugs
    // Drop stale entries for goals whose files disappeared.
    root.goalsData = Util.pickKeys(root.goalsData, slugs)
  }

  readonly property var todaySummary: computeTodaySummary(goalsData, dayEntries)

  // ---- write path: <slug>.md (read-modify-write, re-read every time) -----
  // Every change to a goal file, and every new one, goes through goalFiles
  // (the SerialFileWriter at the bottom of this file), so two writes -- two
  // tasks ticked quickly -- run one after the other, each on its own fresh
  // read, and never stomp each other.
  property string writeError: ""

  function showWriteError(message) {
    root.writeError = message
    writeErrorTimer.restart()
  }

  // What a failed goal-file write is called in the messages the user sees,
  // by SerialFileWriter's reason for it.
  function goalWriteMessage(reason) {
    if (reason === "declined") return "goal file changed unexpectedly"
    if (reason === "readFailed") return "couldn't read the goal file"
    if (reason === "saveFailed") return "couldn't save the goal file"
    return ""
  }

  // Every edit of an existing goal: toggle, add and edit a task; close,
  // reopen and cancel the goal; the Edit goal dialog. `editLines(lines)`
  // gets the file freshly read and split into lines, and returns the new
  // lines, or null to leave the file alone (Writer.js's functions have
  // exactly that shape). The file's own line endings are kept.
  //
  // `verb` finishes the banner's "Couldn't <verb> (<why>)." on a failure,
  // e.g. "update the task"; pass "" when the caller shows the failure itself
  // (the Edit goal dialog does). resultFn(ok, message), if given, gets the
  // same <why>, "" on success.
  //
  // One helper rather than a handler per action: the six handlers this
  // replaced were the same ten lines with a different Writer call and verb.
  function editGoalFile(slug, verb, editLines, resultFn) {
    goalFiles.modify(Paths.goalFile(slug), function(text) {
      var out = editLines(Writer.splitLines(text))
      return out ? Writer.joinLines(out, Writer.detectEol(text)) : null
    }, function(ok, reason) {
      var message = ok ? "" : root.goalWriteMessage(reason)
      if (!ok && verb !== "") root.showWriteError("Couldn't " + verb + (message ? " (" + message + ")" : "") + ".")
      if (resultFn) resultFn(ok, message)
    })
  }

  // ---- write path: <slug>.log.md / days/YYYY-MM-DD.md (append-only) ------
  function handleAddEvent(payload, resultFn) {
    var entryText = Writer.formatEventEntry(payload.whenDate, payload.minutes, payload.kind, payload.what, payload.countsToward)
    var slug = String(payload.slug || "")
    var path
    if (slug.length > 0 && /^[a-z0-9][a-z0-9-]*$/.test(slug)) {
      path = Paths.goalLog(slug)
    } else {
      path = Paths.dayFile(Parser.dayKey(payload.whenDate))
    }
    appender.append(path, entryText, function(ok) {
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

  property bool newGoalDialogOpen: false
  property string newGoalError: ""
  property string editGoalSlug: ""

  // ---- write path: creating a new goal (<slug>.md), goal-files.md §3 -----
  // A probe of each candidate slug's path either loads (something is
  // already there -- read its title to decide "same goal, no-op" vs.
  // "someone else's goal, try <base>-2, <base>-3, ...") or fails (the slug
  // is free, write the new file there). Every candidate is a fresh read
  // right before any decision is made about it, the same "re-read
  // immediately before mutating" discipline goal edits follow.
  //
  // Each step after the first is queued `next`, straight from the previous
  // step's result: the whole search-and-write runs as one uninterrupted
  // stretch of the queue, so two goals with the same title created back to
  // back can't both find the slug free and both write it.
  function createGoalFile(fields, onDone) {
    var base = Writer.deriveSlug(fields.title)
    function attempt(n, options) {
      var slug = n === 1 ? base : base + "-" + n
      var path = Paths.goalFile(slug)
      goalFiles.probe(path, function(exists, text) {
        if (!exists) {
          // Nothing at this slug -- free to create. Only reached when the
          // read just failed, so this never writes over a goal.
          goalFiles.write(path, Writer.buildNewGoalFile(fields), function(ok) {
            if (ok) onDone(true, "", slug)
            else onDone(false, "couldn't create the goal file", "")
          }, { next: true })
          return
        }
        var meta = Parser.parseGoalFile(text)
        if (meta && meta.title === fields.title) {
          // Same title at this slug -- same goal. Creating it again is a
          // no-op, not an error (goal-files.md §3).
          onDone(true, "", slug)
          return
        }
        // Slug is taken by a different goal (or an unparseable file). A
        // generous but finite cap keeps this from spinning forever if
        // something truly pathological is going on.
        if (n > 500) { onDone(false, "couldn't find a free slug", ""); return }
        attempt(n + 1, { next: true })
      }, options)
    }
    attempt(1)
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
    root.createGoalFile(clean, function(ok, message, slug) {
      // Don't wait on the 2s directory poll -- a goal just created should
      // show up in the list right away.
      if (ok) listProc.running = true
      if (resultFn) resultFn(ok, message, slug)
    })
  }

  // Today's pomodoros across every goal log and the day file.
  function computeTodaySummary(data, entries) {
    var todayKey = Parser.dayKey(new Date())
    var today = []
    function collect(list) {
      for (var i = 0; i < list.length; i++) {
        if (Parser.dayKey(list[i].date) === todayKey) today.push(list[i])
      }
    }
    for (var slug in data) collect(data[slug].logEntries || [])
    collect(entries || [])
    return { poms: Parser.pomodoroCount(today), minutes: Parser.pomodoroMinutes(today) }
  }

  // ---- directory listing: polled since Quickshell has no folder watcher --
  Process {
    id: listProc
    command: ["/usr/bin/find", Paths.goalsDir, "-maxdepth", "1", "-type", "f", "-name", "*.md"]
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
        path: Paths.goalLog(orphanLoader.modelData)
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
        path: Paths.goalFile(loader.slug)
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
        path: Paths.goalLog(loader.slug)
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
      var dateIso = Paths.journalDateIso(p)
      if (dateIso === "") continue
      files.push({ path: p, dateIso: dateIso })
    }
    files.sort(function(a, b) { return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0) })

    if (Util.sameList(files, root.journalFiles, function(f) { return f.path })) return
    root.journalFiles = files
    root.journalContents = Util.pickKeys(root.journalContents, files.map(function(f) { return f.path }))
  }

  function setJournalContent(path, text) {
    root.journalContents = Util.withKey(root.journalContents, path, text)
  }

  Process {
    id: journalListProc
    // Missing directory is not an error here: `find` writes to stderr, stdout
    // stays empty, and the screen shows today as the one (not-yet-created)
    // day -- which is exactly the state of a journal nobody has written in.
    command: ["/usr/bin/find", Paths.journalDir, "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "*.md"]
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

  // The writers. goalFiles serves both editing and creating goals, so a new
  // goal's slug search and an edit can never interleave; appender serves the
  // append-only logs. Both are serial -- see their files for the Quickshell
  // bugs that makes them work around.
  SerialFileWriter { id: goalFiles }
  Appender { id: appender }

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

      // Test hook: OMVISION_TEST names a .qml file (an absolute path, or one
      // relative to this directory) that drives the real app from inside,
      // the way ShotDriver does for screenshots. Qt's qmltestrunner can't
      // load Quickshell's modules, so a test that needs the real screens,
      // FileViews and write paths has to run inside `qs` like this. The file
      // must declare every property set below. Unset or empty, nothing is
      // loaded -- a normal launch never sees it. Behind everything for the
      // same reason as the driver: anything it draws must not cover the app.
      Loader {
        anchors.fill: parent
        z: -1
        readonly property string testFile: Quickshell.env("OMVISION_TEST") || ""
        active: testFile !== ""
        source: testFile === "" ? "" : (testFile.charAt(0) === "/" ? "file://" + testFile : Qt.resolvedUrl(testFile))
        onLoaded: {
          item.app = root
          item.journal = journalScreen
          item.goalDetail = goalDetailScreen
          item.coaching = coachingScreen
          item.target = contentRoot
          item.window = window
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
            NumberAnimation { duration: Theme.slideDuration; easing.type: Theme.slideEasing }
          }

          Sidebar {
            id: inFlowSidebar
            height: parent.height
            x: sidebarSlot.width - width
            currentScreen: root.currentScreen === "goalDetail" ? root.goalBackScreen : root.currentScreen
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
          onOpenGoal: function(slug) { root.openGoal(slug, "goals") }
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
          backLabel: root.goalBackScreen === "journal" ? "← Journal" : "← Goals"
          onBack: root.currentScreen = root.goalBackScreen
          onToggleTask: function(index) {
            root.editGoalFile(root.openGoalSlug, "update the task", function(lines) {
              return Writer.toggleTask(lines, index)
            })
          }
          onAddTask: function(text) {
            root.editGoalFile(root.openGoalSlug, "add the task", function(lines) {
              return Writer.addTask(lines, text)
            }, function(ok, message) { goalDetailScreen.onAddTaskResult(ok, message) })
          }
          onEditTask: function(index, text) {
            root.editGoalFile(root.openGoalSlug, "update the task", function(lines) {
              return Writer.editTask(lines, index, text)
            }, function(ok, message) { goalDetailScreen.onEditTaskResult(ok, message) })
          }
          onCloseGoal: root.editGoalFile(root.openGoalSlug, "close the goal", function(lines) {
            return Writer.setStatus(lines, "done")
          })
          onReopenGoal: root.editGoalFile(root.openGoalSlug, "reopen the goal", function(lines) {
            return Writer.setStatus(lines, "active")
          })
          onCancelGoal: function(reason, takeaway) {
            root.editGoalFile(root.openGoalSlug, "cancel the goal", function(lines) {
              var out = Writer.setStatus(lines, "cancelled")
              if (!out) return null
              return Writer.appendCancelNote(out, Writer.headingTimestamp(new Date()), reason, takeaway)
            }, function(ok, message) { goalDetailScreen.onCancelResult(ok, message) })
          }
          onAddEventRequested: root.openEventDialog(root.openGoalSlug)
          onEditGoalRequested: root.openEditGoalDialog(root.openGoalSlug)
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
          goalsData: root.goalsData
          sidebarShown: !root.sidebarHidden()
          onToggleSidebar: root.toggleSidebar()
          onOpenGoal: function(slug) { root.openGoal(slug, "journal") }
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
      // a modal has to sit above everything, the sidebar included, so it
      // lives at the same level EventDialog does. Driven entirely by goalDetailScreen's own
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
            // No banner (verb ""): the dialog shows the failure itself.
            root.editGoalFile(root.editGoalSlug, "", function(lines) {
              return Writer.updateGoalFields(lines, fields)
            }, function(ok, message) {
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

      // A failed write is never silent. Every goal edit and event append
      // reports its failure through showWriteError(), which surfaces here
      // for a few seconds on whichever screen is showing when it happens.
      // The New/Edit goal dialog's saves are the exception: the dialog stays
      // open and shows the failure itself (newGoalError).
      Rectangle {
        id: writeErrorBanner
        visible: root.writeError.length > 0
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: Theme.spaceMd
        width: Math.min(parent.width - Theme.noticeWindowMargin * 2, bannerText.implicitWidth + Theme.noticePaddingX * 2)
        height: bannerText.implicitHeight + Theme.noticePaddingY * 2
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
