pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import "Parser.js" as Parser
import "Writer.js" as Writer
import "Util.js" as Util

// The app's data: every goal, log, day and journal file under
// ~/Notes/Omvision, read and kept up to date, and every write except the
// journal's (JournalStore makes those, from the journal screen). The screens
// get what this holds already parsed, and ask for a change through one of
// the functions below; none of them reads or writes a file itself, and
// nothing here draws anything.
//
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
//
// ---- API --------------------------------------------------------------------
//   now, todayKey     the time, to the minute, and the day it is
//                     (YYYY-MM-DD): the one clock the app goes by
//   goalsData         slug -> { meta, logEntries }; meta is null for a goal
//                     file that doesn't parse
//   goalSlugs         the goal files' slugs, sorted
//   orphanLogs        slug -> entries, for logs with no goal file
//   dayEntries        today's day file's entries (goal-less runs, events)
//   journalFiles      [{ path, dateIso }], sorted by path
//   journalContents   path -> raw text
//   writeFailed(message)
//                     a failed write no caller shows in place: the app
//                     shows the message in its banner
//   toggleTask, addTask, editTask, closeGoal, reopenGoal, cancelGoal,
//   updateGoal, createGoal, addEvent
//                     the changes, each described where it is defined. One
//                     given an onDone(ok, why) leaves showing a failure to
//                     the caller (a dialog or a field, which keeps what was
//                     typed) unless onDone returns false; one without, or
//                     handed back that false, reports it through
//                     writeFailed.
Scope {
  id: store

  // ---- the day --------------------------------------------------------------
  // Moved on by a timer, so an app left open overnight starts showing the new
  // day: Today reads the new day file, and the journal's "Today" row and
  // Ctrl+N move to the new date. Nothing jumps on its own -- an open journal
  // day stays open, since swapping the file out from under a sentence would
  // lose its place. A test stops the clock (followClock) and sets `now` to
  // move the day without waiting for midnight.
  property date now: new Date()
  readonly property string todayKey: Parser.dayKey(store.now)
  readonly property string todayPath: Paths.dayFile(store.todayKey)
  property bool followClock: true

  // Fires just after each minute turns, not a minute after the app
  // started, so the new day starts at midnight rather than up to a minute
  // later.
  Timer {
    running: store.followClock
    interval: 60000 - store.now.getTime() % 60000 + 100
    onTriggered: {
      store.now = new Date()
      restart()
    }
  }

  // ---- what is on disk ------------------------------------------------------
  property var goalsData: ({})
  property var goalSlugs: []
  property var orphanLogSlugs: []
  property var orphanLogs: ({})
  property var dayEntries: []
  property var journalFiles: []
  property var journalContents: ({})

  // Which logs, and whether today's day file, the last listing found. A
  // FileView never sees a file appear that wasn't there when it was pointed
  // at it (WatchedFile), so the listing is what notices a goal's first log
  // entry, or the day's first goal-less run; the loader then reads it
  // (onLogListedChanged, onTodayFileListedChanged).
  property var logSlugs: []
  property bool todayFileListed: false
  onTodayFileListedChanged: dayFile.reload()

  // Each of these state objects is replaced whole, never edited in place:
  // see Util.js for why. `part` is the half of a goal one file gave:
  // { meta } from <slug>.md, { logEntries } from its log.
  function syncGoal(slug, part) {
    var goal = Object.assign({ meta: null, logEntries: [] }, store.goalsData[slug], part)
    store.goalsData = Util.withKey(store.goalsData, slug, goal)
  }

  function syncOrphanLog(slug, entries) {
    store.orphanLogs = Util.withKey(store.orphanLogs, slug, entries || [])
  }

  function setJournalContent(path, text) {
    store.journalContents = Util.withKey(store.journalContents, path, text)
  }

  // ---- the listing ----------------------------------------------------------
  // Quickshell has no folder watcher, so the three folders are listed by one
  // `find` every two seconds. A folder that doesn't exist yet only costs a
  // line on find's stderr: a journal nobody has written in lists no days,
  // which is exactly its state.
  Process {
    id: listProc
    command: ["/usr/bin/find", Paths.goalsDir, Paths.daysDir, Paths.journalDir,
              "-mindepth", "1", "-maxdepth", "1", "-type", "f", "-name", "*.md"]
    stdout: StdioCollector {
      onStreamFinished: store.applyListing(text)
    }
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: listProc.running = true
  }

  // `text` is listProc's output, one path a line.
  function applyListing(text) {
    var lines = String(text || "").split("\n")
    var goalPaths = []
    var journalPaths = []
    var todayListed = false
    for (let i = 0; i < lines.length; i++) {
      const p = lines[i].trim()
      if (p === "") continue
      if (p.indexOf(Paths.goalsDir + "/") === 0) goalPaths.push(p)
      else if (p.indexOf(Paths.journalDir + "/") === 0) journalPaths.push(p)
      else if (p === store.todayPath) todayListed = true
    }
    store.todayFileListed = todayListed
    store.applyGoalPaths(goalPaths)
    store.applyJournalPaths(journalPaths)
  }

  function applyGoalPaths(paths) {
    var slugs = []
    var logStems = []
    for (let i = 0; i < paths.length; i++) {
      const stem = paths[i].replace(/^.*\//, "").replace(/\.md$/, "")
      if (stem.match(/\.log$/)) logStems.push(stem.replace(/\.log$/, "")) // "<slug>.log.md"
      else slugs.push(stem)
    }
    slugs.sort()
    logStems.sort()
    if (!Util.sameList(logStems, store.logSlugs)) store.logSlugs = logStems

    // A log whose goal file is gone (renamed, deleted, or written by the
    // timer against a slug that never had one) still describes pomodoros
    // that really happened. The goal loaders are driven by `slugs`, so these
    // are loaded separately, and Today shows them under their slug.
    var have = {}
    for (let h = 0; h < slugs.length; h++) have[slugs[h]] = true
    var orphans = logStems.filter(function(s) { return !have[s] })
    if (!Util.sameList(orphans, store.orphanLogSlugs)) {
      store.orphanLogSlugs = orphans
      store.orphanLogs = Util.pickKeys(store.orphanLogs, orphans)
    }

    if (Util.sameList(slugs, store.goalSlugs)) return
    store.goalSlugs = slugs
    store.goalsData = Util.pickKeys(store.goalsData, slugs)
  }

  function applyJournalPaths(paths) {
    var files = []
    for (let i = 0; i < paths.length; i++) {
      const dateIso = Paths.journalDateIso(paths[i])
      if (dateIso !== "") files.push({ path: paths[i], dateIso: dateIso })
    }
    files.sort(function(a, b) { return a.path < b.path ? -1 : (a.path > b.path ? 1 : 0) })
    if (Util.sameList(files, store.journalFiles, function(f) { return f.path })) return
    store.journalFiles = files
    store.journalContents = Util.pickKeys(store.journalContents, files.map(function(f) { return f.path }))
  }

  // ---- the loaders ----------------------------------------------------------
  Instantiator {
    model: store.goalSlugs
    delegate: QtObject {
      id: loader
      required property string modelData
      readonly property bool logListed: store.logSlugs.indexOf(loader.modelData) >= 0
      onLogListedChanged: logFile.reload()

      property WatchedFile mdFile: WatchedFile {
        path: Paths.goalFile(loader.modelData)
        onLoaded: store.syncGoal(loader.modelData, { meta: Parser.parseGoalFile(text()) })
        onLoadFailed: function(error) { store.syncGoal(loader.modelData, { meta: null }) }
      }

      property WatchedFile logFile: WatchedFile {
        path: Paths.goalLog(loader.modelData)
        onLoaded: store.syncGoal(loader.modelData, { logEntries: Parser.parseLogEntries(text(), store.now) })
        // No log yet is normal (§6): zero entries, not an error.
        onLoadFailed: function(error) { store.syncGoal(loader.modelData, { logEntries: [] }) }
      }
    }
  }

  Instantiator {
    model: store.orphanLogSlugs
    delegate: WatchedFile {
      id: orphanFile
      required property string modelData
      path: Paths.goalLog(orphanFile.modelData)
      onLoaded: store.syncOrphanLog(orphanFile.modelData, Parser.parseLogEntries(text(), store.now))
      onLoadFailed: function(error) { store.syncOrphanLog(orphanFile.modelData, []) }
    }
  }

  // Goal-less runs and events. Its path follows todayKey; a path change
  // starts a read of its own.
  WatchedFile {
    id: dayFile
    path: store.todayPath
    onLoaded: store.dayEntries = Parser.parseLogEntries(text(), store.now)
    onLoadFailed: function(error) { store.dayEntries = [] }
  }

  Instantiator {
    model: store.journalFiles
    delegate: WatchedFile {
      id: journalFile
      required property var modelData
      path: journalFile.modelData.path
      onLoaded: store.setJournalContent(journalFile.modelData.path, text())
      onLoadFailed: function(error) { store.setJournalContent(journalFile.modelData.path, "") }
    }
  }

  // ---- the writers ----------------------------------------------------------
  // goalFiles serves both editing and creating goals, so a new goal's slug
  // search and an edit can never interleave; appender serves the
  // append-only logs. Both are serial -- see their files for the Quickshell
  // bugs that makes them work around.
  SerialFileWriter { id: goalFiles }
  Appender { id: appender }

  signal writeFailed(string message)

  // What a failed goal-file write is called in the messages the user sees,
  // by SerialFileWriter's reason for it.
  function goalWriteMessage(reason) {
    if (reason === "declined") return "goal file changed unexpectedly"
    if (reason === "readFailed") return "couldn't read the goal file"
    return "couldn't save the goal file"
  }

  // Every edit of an existing goal goes through here. `editLines(lines)`
  // gets the file freshly read and split into lines, and returns the new
  // lines, or null to leave the file alone (Writer.js's functions have
  // exactly that shape). The file's own line endings are kept.
  //
  // `verb` finishes the banner's "Couldn't <verb> (<why>).", e.g. "update
  // the task". onDone(ok, why) gets the <why>, "" on success.
  function editGoalFile(slug, verb, editLines, onDone) {
    goalFiles.modify(Paths.goalFile(slug), function(text) {
      var out = editLines(Writer.splitLines(text))
      return out ? Writer.joinLines(out, Writer.detectEol(text)) : null
    }, function(ok, reason) {
      var why = ok ? "" : store.goalWriteMessage(reason)
      var shown = onDone ? onDone(ok, why) !== false : false
      if (!ok && !shown) store.writeFailed("Couldn't " + verb + " (" + why + ").")
    })
  }

  function toggleTask(slug, index) {
    store.editGoalFile(slug, "update the task", function(lines) { return Writer.toggleTask(lines, index) })
  }

  function addTask(slug, text, onDone) {
    store.editGoalFile(slug, "add the task", function(lines) { return Writer.addTask(lines, text) }, onDone)
  }

  function editTask(slug, index, text, onDone) {
    store.editGoalFile(slug, "update the task", function(lines) { return Writer.editTask(lines, index, text) }, onDone)
  }

  function closeGoal(slug) {
    store.editGoalFile(slug, "close the goal", function(lines) { return Writer.setStatus(lines, "done") })
  }

  function reopenGoal(slug) {
    store.editGoalFile(slug, "reopen the goal", function(lines) { return Writer.setStatus(lines, "active") })
  }

  function cancelGoal(slug, reason, takeaway, onDone) {
    store.editGoalFile(slug, "cancel the goal", function(lines) {
      var out = Writer.setStatus(lines, "cancelled")
      if (!out) return null
      return Writer.appendCancelNote(out, Writer.headingTimestamp(new Date()), reason, takeaway)
    }, onDone)
  }

  function updateGoal(slug, fields, onDone) {
    store.editGoalFile(slug, "save the goal", function(lines) { return Writer.updateGoalFields(lines, fields) }, onDone)
  }

  // ---- creating a goal (<slug>.md), goal-files.md §3 -------------------------
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
  //
  // `fields` are the dialog's as they came, so create and edit take one
  // payload and a field the dialog gains reaches both. Writer makes each
  // value one line. onDone(ok, message, slug).
  function createGoal(fields, onDone) {
    var title = String(fields.title || "").trim()
    if (title === "") { onDone(false, "Title is required.", ""); return }
    // The trimmed title, since the slug and the same-goal check are taken
    // from it.
    fields = Object.assign({}, fields, { title: title })
    var base = Writer.deriveSlug(title)

    function done(ok, message, slug) {
      // Don't wait on the next listing: a goal just created should show up
      // in the list right away.
      if (ok) listProc.running = true
      onDone(ok, message, slug)
    }

    function attempt(n, options) {
      var slug = n === 1 ? base : base + "-" + n
      var path = Paths.goalFile(slug)
      goalFiles.probe(path, function(exists, text) {
        if (!exists) {
          // Nothing at this slug -- free to create. Only reached when the
          // read just failed, so this never writes over a goal.
          goalFiles.write(path, Writer.buildNewGoalFile(fields), function(ok) {
            if (ok) done(true, "", slug)
            else done(false, "couldn't create the goal file", "")
          }, { next: true })
          return
        }
        var meta = Parser.parseGoalFile(text)
        if (meta && meta.title === title) {
          // Same title at this slug -- same goal. Creating it again is a
          // no-op, not an error (goal-files.md §3).
          done(true, "", slug)
          return
        }
        // Slug is taken by a different goal (or an unparseable file). A
        // generous but finite cap keeps this from spinning forever if
        // something truly pathological is going on.
        if (n > 500) { done(false, "couldn't find a free slug", ""); return }
        attempt(n + 1, { next: true })
      }, options)
    }
    attempt(1)
  }

  // ---- logging an event (append-only) ----------------------------------------
  // To the goal's log when the event counts toward one, else to the day file
  // of the day it happened. onDone(ok): the Add event dialog shows a failure.
  function addEvent(payload, onDone) {
    var entryText = Writer.formatEventEntry(payload.whenDate, payload.minutes, payload.kind, payload.what, payload.countsToward)
    var slug = String(payload.slug || "")
    var path = slug.length > 0 && /^[a-z0-9][a-z0-9-]*$/.test(slug)
      ? Paths.goalLog(slug)
      : Paths.dayFile(Parser.dayKey(payload.whenDate))
    appender.append(path, entryText, onDone)
  }
}
