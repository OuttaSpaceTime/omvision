import QtQuick
import Quickshell.Io

import "Util.js" as Util

// The journal's write path: everything that puts a day's text on disk, and
// everything the journal knows about what is on disk already. No UI -- the
// buffer, the open day and the error line are JournalScreen's; this says
// what may be written and writes it.
//
// Writes go through a SerialFileWriter, one at a time, each carrying the
// path and text it was queued with. That is what makes "switch days
// mid-write" safe: a write already headed for day A still lands as day A's
// even when the screen has moved on to B by the time it runs. The journal is
// Omvision's alone -- no second writer to race against -- so a plain atomic
// whole-file write is the right tool, no O_APPEND trick like the logs need.
//
// ---- Never write a day whose disk text is unknown ---------------------------
// omvision.qml discovers journal files with a `find` every 2s and then reads
// each through its own FileView, so for the first moments after launch, and
// for a day this screen has not written yet, the journal does not know what
// a day's file says. A page opened then is blank, and text typed into it
// used to be written straight over the file: the day's earlier writing was
// replaced by the few words typed onto the blank page. The rule now is that
// a write is only ever computed from a known disk text:
//   - The screen calls save(path, text, based), where `based` says the
//     buffer was derived from that day's disk text (or from text of ours
//     still on its way to disk). Only a based buffer is written.
//   - Text typed into an unbased buffer is held in `waiting`, and the day's
//     text is found out: mkdir -p, touch, then a read through the writer's
//     own queue (probe). When it arrives -- or when omvision.qml's FileView
//     delivers it first -- the typed text is added *after* the day's text
//     (mergeTyped) and that is what gets written. Nothing on disk is lost,
//     and nothing typed is lost.
// Rejected alternatives:
//   - Refusing the write and showing the error line: safe for the file, but
//     the user is left with a page that disagrees with the file and no way
//     forward but copying their words out by hand.
//   - Dropping the typed text and showing the disk text: loses what was
//     typed, which is the same bug pointed the other way.
//   - Putting the typed text first: the journal reads top to bottom in the
//     order it was written, and the typed words are the newest.
//   - A compare-and-swap on every write (modify() checking the disk text
//     against the buffer's base): it would catch this too, but every
//     keystroke's save would then need its own read, and write()'s
//     supersede and pendingTextFor only cover write() jobs.
//
// Why touch before the probe: it creates an empty file for a new day and
// leaves an existing one alone (it only bumps mtime, never truncates). The
// probe after it then either reads the day's real text or "" for a new day,
// and a failed read means the file really can't be read -- then nothing is
// written. Without it a failed read would mean either "no file yet" or "can't
// read it", and only one of those is safe to write over. It is also why
// FileView's setText("") -- a silent no-op on a path never loaded -- is never
// needed to create a file.
//
// ---- API --------------------------------------------------------------------
//   journalContents  in: omvision.qml's path -> text for the files it has read
//   openPath         in: the day open in the editor
//   writesDisabled   in: bin/shot's `mention` typing; nothing is written
//   written          path -> the text this store last knows is on disk: from
//                    its own confirmed write or its own read ("" for a day
//                    it deleted). Newer than
//                    journalContents until omvision.qml's FileView catches up.
//   busy             a write, read or file creation is under way
//   knownText(path)       what the day's file says, or undefined if unknown
//   pendingTextFor(path)  the newest queued/in-flight write's text, or undefined
//   waitingTextFor(path)  text typed into that day before its disk text was
//                         known, not yet written, or undefined
//   hasPending(path)      any of the above is under way for `path`
//   save(path, text, based)   writes the day, or deletes its file when `text`
//                             is blank and the day had text
//   mergeTyped(diskText, typed)  the text a based save writes after a merge
//   prune()               forget `written` entries omvision.qml has caught up on
//   signals: saved(path, text), failed(path, message), diskTextKnown(path)
QtObject {
  id: store

  property var journalContents: ({})
  property string openPath: ""
  property bool writesDisabled: false

  property var written: ({})
  property var waiting: ({})
  // Days whose disk text is being found out (mkdir, touch, probe), oldest
  // first; the head is the one in progress.
  property var resolveQueue: []

  readonly property bool busy: files.busy || resolveQueue.length > 0

  signal saved(string path, string text)
  signal failed(string path, string message)
  // The store has just read `path` itself (see resolve); knownText(path) now
  // answers. omvision.qml's FileView delivering it is journalContentsChanged.
  signal diskTextKnown(string path)

  function setWritten(path, text) { store.written = Util.withKey(store.written, path, text) }
  function writtenFor(path) { return store.written[path] !== undefined ? store.written[path] : "" }

  function knownText(path) {
    if (store.written[path] !== undefined) return store.written[path]
    if (store.journalContents[path] !== undefined) return store.journalContents[path]
    return undefined
  }
  function pendingTextFor(path) { return files.pendingTextFor(path) }
  function waitingTextFor(path) { return store.waiting[path] }
  function hasPending(path) {
    return files.hasPending(path) || store.waiting[path] !== undefined
           || store.resolveQueue.indexOf(path) >= 0
  }

  function setWaiting(path, text) {
    if (text === undefined || text === "") {
      if (store.waiting[path] === undefined) return
      var d = {}
      for (var k in store.waiting) if (k !== path) d[k] = store.waiting[k]
      store.waiting = d
    } else {
      store.waiting = Util.withKey(store.waiting, path, text)
    }
  }

  // The day's text with what was typed onto its blank page added after it,
  // as a paragraph of its own.
  function mergeTyped(diskText, typed) {
    if (typed === "" || typed === diskText) return diskText
    if (diskText === "") return typed
    var sep = /\n\n$/.test(diskText) ? "" : (/\n$/.test(diskText) ? "\n" : "\n\n")
    return diskText + sep + typed
  }

  function save(path, text, based) {
    if (store.writesDisabled || path === "") return
    var pending = files.pendingTextFor(path)
    var known = pending !== undefined ? pending : store.knownText(path)
    if (!based || known === undefined) {
      // Nothing typed is nothing to keep: opening a day must not create its
      // file.
      store.setWaiting(path, text)
      if (text !== "") store.resolve(path)
      return
    }
    store.setWaiting(path, undefined)
    if (text === known) return
    // A page whose text was all deleted deletes the day: a day nothing is
    // written on has no file, the way a day never opened has none, so it
    // drops out of the day list and the page turns. Refusing to write a
    // blank page over a day with text, as this used to, kept the emptied
    // day's old text on disk; that guard was for a page opened before its
    // file was read, which is unbased now and never gets here. Only
    // whitespace left counts as blank too -- a lone newline is not an entry.
    var blank = text.trim() === ""
    if (blank && known.trim() === "") return
    var onDisk = blank ? "" : text
    var done = function(ok) {
      if (ok) {
        store.setWritten(path, onDisk)
        store.saved(path, onDisk)
      } else if (blank) {
        store.failed(path, "Couldn't delete the emptied day -- its old text is still on disk.")
      } else {
        // The text is not lost: it is still in the screen's buffer if this
        // is the open day, and `written` still disagrees with it, so the
        // next keystroke or reopening the day tries again.
        store.failed(path, "Couldn't save the last change -- it's still here, not on disk.")
      }
    }
    if (blank) files.remove(path, done, { supersede: true })
    else files.write(path, text, done, { supersede: true })
  }

  function prune() {
    var d = {}
    var changed = false
    for (var k in store.written) {
      // Kept while work on the day is under way, and until omvision.qml's own
      // read says the same thing; then that read answers knownText() alike.
      // The open day is dropped too: its record kept for good would hide
      // a change made to the file from outside, which syncBufferFromDisk()
      // is there to take. A file `find` does not list reads as "", which is
      // how a day this store deleted stops being kept.
      var disk = store.journalContents[k] !== undefined ? store.journalContents[k] : ""
      if (store.hasPending(k) || disk !== store.written[k]) { d[k] = store.written[k]; continue }
      changed = true
    }
    if (changed) store.written = d
  }
  onJournalContentsChanged: prune()

  // ---- finding out a day's disk text ---------------------------------------
  function resolve(path) {
    if (store.resolveQueue.indexOf(path) >= 0) return
    store.resolveQueue = store.resolveQueue.concat([path])
    if (store.resolveQueue.length === 1) store.startResolve()
  }

  function startResolve() {
    if (store.resolveQueue.length === 0) return
    mkdirProc.command = ["/usr/bin/mkdir", "-p", Paths.journalDir]
    mkdirProc.running = true
  }

  // Ends the head job; `text` is the day's disk text, or undefined when it
  // could not be found out (the typed text then stays in `waiting`, and is
  // tried again on the next save).
  function finishResolve(path, text) {
    store.resolveQueue = store.resolveQueue.slice(1)
    if (text !== undefined) {
      store.setWritten(path, text)
      var typed = store.waiting[path]
      store.setWaiting(path, undefined)
      if (path === store.openPath) {
        // The screen's buffer may hold more than `waiting` by now; it merges
        // its own and saves.
        store.diskTextKnown(path)
      } else if (typed !== undefined) {
        store.save(path, store.mergeTyped(text, typed), true)
      }
    }
    store.startResolve()
  }

  property Process mkdirProc: Process {
    id: mkdirProc
    onExited: function(exitCode, exitStatus) {
      var path = store.resolveQueue[0]
      if (exitCode !== 0) {
        store.failed(path, "Couldn't make the journal folder -- nothing was written.")
        store.finishResolve(path, undefined)
        return
      }
      touchProc.command = ["/usr/bin/touch", path]
      touchProc.running = true
    }
  }

  property Process touchProc: Process {
    id: touchProc
    onExited: function(exitCode, exitStatus) {
      var path = store.resolveQueue[0]
      if (exitCode !== 0) {
        store.failed(path, "Couldn't create the day's file -- nothing was written.")
        store.finishResolve(path, undefined)
        return
      }
      // Through the writer's queue, so the read lands after any write to
      // this path that is already on its way.
      files.probe(path, function(exists, text) {
        if (!exists) store.failed(path, "Couldn't read the day's file -- nothing was written.")
        store.finishResolve(path, exists ? text : undefined)
      })
    }
  }

  property SerialFileWriter files: SerialFileWriter { id: files }
}
