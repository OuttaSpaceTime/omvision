import QtQuick
import Quickshell.Io

// A serial job queue over one atomic FileView: every whole-file write in the
// app goes through one of these, one job at a time.
//
// It exists because Quickshell's FileView (0.3.1, this build) fails silently
// in several ways (CLAUDE.md lists them), and every hand-written writer in
// the app had to work around them on its own, each copy got right -- or not
// -- separately. Here is how this one handles each:
//   - setText() called inside the FileView's own onLoaded, or reload()
//     inside its own onSaved/onLoaded, does its work but never fires the
//     completion signal, so a queue waiting on it stalls for good. Nothing
//     here calls either from inside a FileView handler: every step starts
//     from a zero-interval Timer on the next event-loop turn. The old goal
//     writer reload()ed straight out of onSaved for the next job, so of two
//     quick writes (a double click on a task) the second was lost and every
//     write after it never ran.
//   - setText() with exactly the text the FileView already holds is a no-op
//     that fires no signal either. A job whose new text equals the file's is
//     finished as a success without writing -- the file already says that --
//     instead of waiting for a signal that never comes. Saving the Edit goal
//     dialog unchanged used to wedge the queue this way. A timeout on the
//     signal was the rejected alternative: it would have to guess how long
//     a slow disk may take, and report a write that did land as failed.
//   - setText("") on a path that was never loaded is a no-op too. A write of
//     "" to a file that does not exist fails at once with reason "empty":
//     create empty files with `touch`, as the journal does.
//   - writeAdapter() is JsonAdapter-only and is never used; text goes
//     through setText().
//
// Every job re-reads its file right before acting on it. That is the goal
// file contract's rule for <slug>.md (goal-files.md §2, "re-read
// immediately before mutating") and it costs nothing for a plain write,
// where it is what makes the unchanged-text check possible. The FileView is
// atomicWrites (temp file + rename, the same guarantee notes-helper.py's
// write_atomic() gives): a crash mid-write never leaves half a file.
//
// ---- API --------------------------------------------------------------------
// Each call queues one job and returns at once; jobs run strictly in order,
// one at a time.
//
//   modify(path, mutate, onDone, options)
//     Read-modify-write. Reads `path` fresh, calls mutate(text), and writes
//     what it returns. mutate returning null or undefined (or throwing) means
//     "do not write" (Writer.js's convention for a file it can't safely
//     edit).
//     onDone(ok, reason):  ok=true, reason ""          written
//                          ok=true, reason "unchanged" mutate returned the
//                                                      text already there
//                          ok=false, reason "declined"   mutate returned null
//                          ok=false, reason "readFailed" couldn't read path
//                          ok=false, reason "saveFailed" the write failed
//
//   write(path, text, onDone, options)
//     Write `text` to `path`, whatever is there, creating the file if it is
//     missing. `path` and `text` are captured now, when the job is queued,
//     so a caller whose own state moves on before the job runs still gets
//     this text in this file.
//     onDone(ok, reason): as modify, with "empty" in place of "declined"
//     and never "readFailed".
//
//   probe(path, onDone, options)
//     Only reads. onDone(exists, text): whether `path` could be loaded, and
//     its text if so ("" if not). The new-goal slug search uses it.
//
//   remove(path, onDone, options)
//     Delete `path` (`rm -f`, so a file already gone is a success). A job in
//     the queue like the others, so it lands after every write to `path`
//     queued before it and before every one queued after it -- a separate
//     `rm` run beside the queue could delete a write that came later. The
//     journal uses it for a day whose text was all deleted.
//     onDone(ok, reason): ok=true, reason "" removed (or already gone)
//                         ok=false, reason "removeFailed"
//
//   options (all optional):
//     supersede: true -- write() and remove() only. If the last job still
//       waiting in the queue is a write or remove of the same path, replace
//       it with this one instead of queueing behind it: whatever it would
//       leave on disk is replaced a moment later anyway. The replaced job's
//       onDone is never called. A job already in flight is never replaced.
//     next: true -- put this job at the head of the queue instead of the
//       tail. For a multi-step operation: queued from inside the previous
//       step's onDone, the follow-up runs before anything anyone else queued
//       in the meantime, so the whole operation is atomic with respect to
//       the queue. Each `next` job goes in front of the previous one, so
//       queue at most one per onDone.
//
//   busy                 -- true while any job is queued or in flight.
//   hasPending(path)     -- a job for `path` is queued or in flight.
//   pendingTextFor(path) -- the text of the newest write() for `path` that
//                           is queued or in flight ("" for a remove()), or
//                           undefined: what the file is about to say, before
//                           it says it.
//
// onDone runs once per job, after the job's FileView work is over. By then
// the job no longer counts toward busy, hasPending() or pendingTextFor(), so
// a callback that checks them sees only what is still to come. It may queue
// more jobs; they start on a later event-loop turn, never inside it.
//
// A write() queued while nothing is in flight still waits one event-loop
// turn before it starts, so it can be superseded until then.
QtObject {
  id: writer

  // Jobs not yet started, oldest first. Reassigned rather than mutated in
  // place, so `busy` and anything else bound to it re-evaluates.
  property var queue: []
  // The job being worked on, or null. Its `phase` is "read" while its
  // reload() is out, "save" while its setText() is and "remove" while its
  // `rm` runs.
  property var current: null

  readonly property bool busy: current !== null || queue.length > 0

  function modify(path, mutate, onDone, options) {
    enqueue({ kind: "modify", path: path, mutate: mutate, onDone: onDone }, options)
  }

  function write(path, text, onDone, options) {
    enqueue({ kind: "write", path: path, text: String(text), onDone: onDone }, options)
  }

  function probe(path, onDone, options) {
    enqueue({ kind: "probe", path: path, onDone: onDone }, options)
  }

  function remove(path, onDone, options) {
    enqueue({ kind: "remove", path: path, text: "", onDone: onDone }, options)
  }

  function hasPending(path) {
    if (writer.current && writer.current.path === path) return true
    for (var i = 0; i < writer.queue.length; i++) if (writer.queue[i].path === path) return true
    return false
  }

  function pendingTextFor(path) {
    for (var i = writer.queue.length - 1; i >= 0; i--) {
      var q = writer.queue[i]
      if (writer.changesText(q) && q.path === path) return q.text
    }
    var c = writer.current
    if (c && writer.changesText(c) && c.path === path) return c.text
    return undefined
  }

  // A job that decides the file's whole text by itself: a write() or a
  // remove(). Only these can supersede each other or answer pendingTextFor.
  function changesText(job) { return job.kind === "write" || job.kind === "remove" }

  function enqueue(job, options) {
    var opts = options || {}
    job.phase = ""
    var q = writer.queue.slice()
    var last = q.length > 0 ? q[q.length - 1] : null
    if (opts.supersede && writer.changesText(job) && last && writer.changesText(last) && last.path === job.path) {
      q[q.length - 1] = job
    } else if (opts.next) {
      q.unshift(job)
    } else {
      q.push(job)
    }
    writer.queue = q
    writer.kick()
  }

  function kick() {
    if (writer.current === null && writer.queue.length > 0) dispatchTimer.restart()
  }

  // Runs from dispatchTimer, never from a FileView handler (bug 4).
  function dispatch() {
    if (writer.current !== null || writer.queue.length === 0) return
    var q = writer.queue.slice()
    var job = q.shift()
    writer.queue = q
    writer.current = job
    if (job.kind === "remove") {
      // Nothing to read first: the file goes whatever it says.
      job.phase = "remove"
      rmProc.command = ["/usr/bin/rm", "-f", "--", job.path]
      rmProc.running = true
      return
    }
    job.phase = "read"
    // Setting a new path starts a load of it by itself (FileView preloads);
    // reload() on top of that would start a second one. Only an unchanged
    // path needs the explicit reload() to read the file fresh.
    if (writer.file.path === job.path) writer.file.reload()
    else writer.file.path = job.path
  }

  function finish(ok, detail) {
    var job = writer.current
    writer.current = null
    writer.kick()
    if (job && job.onDone) job.onDone(ok, detail)
  }

  // The read came back (or failed): decide what, if anything, to write.
  function afterRead(loaded, text) {
    var job = writer.current
    if (!job || job.phase !== "read") return
    if (job.kind === "probe") { writer.finish(loaded, loaded ? text : ""); return }

    var newText
    if (job.kind === "modify") {
      if (!loaded) { writer.finish(false, "readFailed"); return }
      try { newText = job.mutate(text) } catch (e) { newText = null }
      if (newText === null || newText === undefined) { writer.finish(false, "declined"); return }
      newText = String(newText)
    } else {
      newText = job.text
      if (!loaded && newText === "") { writer.finish(false, "empty"); return }
    }
    if (loaded && newText === text) { writer.finish(true, "unchanged"); return }
    job.phase = "save"
    job.saveText = newText
    saveTimer.restart() // bug 1: never setText() inside onLoaded
  }

  property FileView file: FileView {
    printErrors: false
    watchChanges: false
    atomicWrites: true
    // A signal with no job in the matching phase is ignored: a load the
    // path change started can land after the job has moved on to saving.
    onLoaded: writer.afterRead(true, text())
    onLoadFailed: function(error) { writer.afterRead(false, "") }
    onSaved: {
      if (writer.current && writer.current.phase === "save") writer.finish(true, "")
    }
    onSaveFailed: function(error) {
      if (writer.current && writer.current.phase === "save") writer.finish(false, "saveFailed")
    }
  }

  property Process rmProc: Process {
    onExited: function(exitCode, exitStatus) {
      var ok = exitCode === 0
      writer.finish(ok, ok ? "" : "removeFailed")
    }
  }

  property Timer dispatchTimer: Timer {
    interval: 0
    repeat: false
    onTriggered: writer.dispatch()
  }

  property Timer saveTimer: Timer {
    interval: 0
    repeat: false
    onTriggered: {
      if (writer.current && writer.current.phase === "save") writer.file.setText(writer.current.saveText)
    }
  }
}
