import QtQuick
import Ompom.Highlight 1.0

// Isolates the "import Ompom.Highlight 1.0" line in its own file, loaded
// via a Loader from Service.qml instead of imported directly there. A
// QML import failure is a hard, whole-file load error with no way to
// catch it in-place -- but a Loader's failed component surfaces as
// Loader.status === Loader.Error on the *parent* without that failure
// propagating, so if this native plugin isn't available (e.g.
// QML2_IMPORT_PATH isn't wired up yet -- see native/README.md), the rest
// of Service.qml (the timer, the overlay, plain-text note-taking) keeps
// working normally; only live markdown highlighting is missing.
Item {
  property alias document: highlighter.document

  function setColors(background, foreground, accent) {
    highlighter.setColors(background, foreground, accent)
  }

  NoteHighlighter {
    id: highlighter
  }
}
