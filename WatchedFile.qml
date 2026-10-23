import Quickshell.Io

// A file the app shows and keeps up to date: read when its path is set, and
// read again whenever it changes on disk -- the timer, a coaching session or
// a hand edit can rewrite any of the notes while the app is open. Errors are
// not printed: a goal with no log yet, or today's day file before the first
// run, is a normal state, and each user handles onLoadFailed itself.
//
// A FileView only watches a file that exists. One pointed at a path with no
// file yet never sees it appear, so NotesStore's listing is what notices a
// new file, and it calls reload() on the WatchedFile then.
FileView {
  watchChanges: true
  printErrors: false
  onFileChanged: reload()
}
