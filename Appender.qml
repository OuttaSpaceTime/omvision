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
//     order they were queued, one Process at a time. `text` goes in as given:
//     the caller supplies any trailing newline. onDone(ok) runs when `tee`
//     exits; ok is exit code 0.
//   busy -- true while an append is queued or running.
QtObject {
  id: appender

  property var queue: []
  property bool running: false
  readonly property bool busy: running || queue.length > 0

  function append(path, text, onDone) {
    var q = appender.queue.slice()
    q.push({ path: path, text: text, onDone: onDone })
    appender.queue = q
    appender.pump()
  }

  // Unlike SerialFileWriter this starts the next Process straight from the
  // previous one's onExited. Process has none of FileView's dropped-signal
  // bugs, and back-to-back appends have always gone out this way.
  function pump() {
    if (appender.running || appender.queue.length === 0) return
    var q = appender.queue.slice()
    var job = q.shift()
    appender.queue = q
    appender.running = true
    proc.pendingText = job.text
    proc.pendingDone = function(ok) {
      appender.running = false
      if (job.onDone) job.onDone(ok)
      appender.pump()
    }
    proc.command = ["/usr/bin/tee", "-a", job.path]
    proc.stdinEnabled = true
    proc.running = true
  }

  property Process proc: Process {
    id: proc
    property string pendingText: ""
    property var pendingDone: null
    command: []
    onStarted: {
      proc.write(proc.pendingText)
      proc.stdinEnabled = false // closes stdin: tee sees EOF and exits
    }
    onExited: function(exitCode) {
      var done = proc.pendingDone
      proc.pendingDone = null
      if (done) done(exitCode === 0)
    }
  }
}
