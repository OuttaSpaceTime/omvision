pragma ComponentBehavior: Bound

import QtQuick

import "Parser.js" as Parser

// What a log entry says, under its heading line (Parser.entryNoteLines): a
// pomodoro's `focus:` or an event's free line at body size, then a
// pomodoro's notes at bodySmall in dim, all wrapped prose. The Today screen
// and the goal detail's timeline both show an entry this way; each used to
// draw the same five lines itself, and Today once dropped the notes of a
// run logged without `focus:`.
//
// Out of the parent's layout when the entry says nothing, so a bare entry
// adds no spacing under its heading. The parent sets the width and, to
// match its own rhythm, the spacing.
Column {
  id: notes

  // A log entry, as Parser.parseLogEntries returns it.
  property var entry: ({})
  readonly property var lines: Parser.entryNoteLines(entry)

  visible: lines.length > 0

  Repeater {
    model: notes.lines
    Text {
      required property var modelData
      width: notes.width
      text: modelData.text
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      font.family: Theme.fontFamily
      font.pixelSize: modelData.prominent ? Theme.bodySize : Theme.bodySmallSize
      color: modelData.prominent ? Theme.ink : Theme.dim
    }
  }
}
