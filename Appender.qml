import QtQuick
import Quickshell.Io

// Appends text to files, one append at a time: `tee -a <path>` with the text
// written to its stdin.
//
// For the append-only files of the goal file contract, <slug>.log.md and
// days/YYYY-MM-DD.md (goal-files.md §2). `tee -a` opens the file O_APPEND and
// never reads it first, so this can run while a coaching session rewrites the
// same goal's <slug>.md, or while ompom's notes-helper.py appends to the same
// log, and neither side can observe or clobber bytes the other already wrote
// -- the same discipline notes-helper.py's append_entry() follows, for the
// same reason. A FileView can't do this: it only writes whole files, so an
// append through it would be a read-modify-write that races the other
// writers. `tee` is run directly, never through a shell, so nothing in the
// path or the text is ever interpreted.
//
// ---- API --------------------------------------------------------------------
//   append(path, text, onDone)
//     Queues one append and returns at once. Appends run strictly in the
//     order they were queued, one at a time. `text` goes in as given: the
//     caller supplies any trailing newline. The file's folder is created
//     first if it is missing. onDone(ok) runs when `tee` exits; ok is exit
//     code 0 from both steps.
QtObject {
  id: appender

  // Appends not yet started, oldest first, and the one under way, or null.
  // Nothing binds to either, so the queue is changed in place.
  property var queue: []
  property var current: null

  function append(path, text, onDone) {
    appender.queue.push({ path: path, text: text, onDone: onDone })
    appender.pump()
  }

  // Unlike SerialFileWriter this starts the next append straight from the
  // previous one's onExited. Process has none of FileView's dropped-signal
  // bugs, and back-to-back appends have always gone out this way.
  function pump() {
    if (appender.current !== null || appender.queue.length === 0) return
    appender.current = appender.queue.shift()
    appender.mkdirProc.command = ["/usr/bin/mkdir", "-p", "--", appender.current.path.replace(/\/[^\/]*$/, "")]
    appender.mkdirProc.running = true
  }

  function finish(ok) {
    var job = appender.current
    appender.current = null
    if (job.onDone) job.onDone(ok)
    appender.pump()
  }

  // The folder first, as notes-helper.py's sub_dir_fd() does: `tee` can't
  // create one, and the first event logged with no goal, on a machine where
  // nothing had written a day file yet, failed for want of `days/`.
  // No ids on these two: one named like its property would shadow it
  // (qmllint's [id-shadows-member]).
  property Process mkdirProc: Process {
    onExited: function(exitCode) {
      if (exitCode !== 0) { appender.finish(false); return }
      appender.teeProc.command = ["/usr/bin/tee", "-a", "--", appender.current.path]
      appender.teeProc.stdinEnabled = true
      appender.teeProc.running = true
    }
  }

  property Process teeProc: Process {
    onStarted: {
      appender.teeProc.write(appender.current.text)
      appender.teeProc.stdinEnabled = false // closes stdin: tee sees EOF and exits
    }
    onExited: function(exitCode) { appender.finish(exitCode === 0) }
  }
}
