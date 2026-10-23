import QtQuick

import MarkdownHighlight

// The journal's live markdown styling, in a file of its own so a missing or
// unbuilt MarkdownHighlight module costs the journal its styling and nothing
// more. QML imports are resolved when a file is loaded, so an `import
// MarkdownHighlight` sitting directly in JournalScreen.qml would take the
// whole screen -- and with it the whole app -- down if the module were not on
// the import path. Loaded through a Loader instead, a failed import is one
// line in the log and a plain-text editor.
//
// Every colour is a Theme token solved against the live omarchy theme, so the
// journal follows a theme switch like the rest of the app; the highlighter
// itself invents nothing.
MarkdownHighlighter {
  id: highlight

  // Where the highlighter left a gap for each `@` tag's title, from
  // mentionSpans(): what JournalMentions hit-tests and the journal draws the
  // titles over. Read from the text's layout, so it is asked again, a moment
  // later (once the layout has caught up), whenever the highlighter says the
  // tags or the layout changed. A day with no tags keeps its empty list, so
  // the titles' Repeater isn't reset for nothing on every reflow.
  property var tagSpans: []
  function refreshTagSpans() {
    var spans = highlight.mentionSpans()
    if (spans.length === 0 && highlight.tagSpans.length === 0) return
    highlight.tagSpans = spans
  }
  onMentionSpansChanged: Qt.callLater(highlight.refreshTagSpans)

  basePointSize: Theme.writingPointSize
  // Percent. Measured against omawrite on the same file: 135 keeps a list's
  // items together as one list, and a blank line still opens a clear gap
  // between blocks. 185 spaced every line like its own paragraph.
  lineHeight: 135
  bodyColor: Theme.ink
  markerColor: Theme.markup
  accentColor: Theme.accentColor
  quoteColor: Theme.faint
  codeColor: Theme.ink
  codeBackground: Theme.fill
}
