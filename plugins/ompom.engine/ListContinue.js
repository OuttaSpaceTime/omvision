.pragma library

// Return inside a markdown list item, for every writing surface that has
// one: Omvision's journal (JournalScreen.qml) and the break's notes
// (NoteSection.qml), so Return does the same thing in both. It lives in the
// engine plugin's folder rather than at the repo root because the plugin is
// deployed on its own, and only its folder goes; the app runs from the repo
// and imports it from here.
//
// The way omawrite and Typora do it: `- `, `* ` and `+ ` repeat, `1.` and
// `1)` count on (keeping the `.` or `)`), and the indent carries over.
// Return on an item with nothing after its marker ends the list instead:
// the marker is removed and the line left empty. Nothing happens with a
// selection, or with the caret in the indent or the marker itself.
//
// Takes the field's text, caret and selection, and returns null when Return
// should do what it always does, or the edit to make instead: replace
// text[from, to) with `text`, then put the caret at `cursor`. applyTo()
// makes it on a TextEdit.
function edit(text, pos, selectionStart, selectionEnd) {
  if (selectionStart !== selectionEnd) return null
  var lineStart = text.lastIndexOf("\n", pos - 1) + 1
  var lineEnd = text.indexOf("\n", pos)
  if (lineEnd < 0) lineEnd = text.length
  var line = text.substring(lineStart, lineEnd)
  var m = line.match(/^(\s*)([-*+]|(\d{1,9})([.)]))([ \t]+|$)/)
  if (!m) return null
  if (pos < lineStart + m[0].length) return null
  if (line.substring(m[0].length).trim() === "") {
    return { from: lineStart, to: lineEnd, text: "", cursor: lineStart }
  }
  var marker = m[3] !== undefined ? (parseInt(m[3], 10) + 1) + m[4] : m[2]
  var insert = "\n" + m[1] + marker + " "
  return { from: pos, to: pos, text: insert, cursor: pos + insert.length }
}

// Return on `field` (a TextEdit): makes edit()'s change and returns true, or
// returns false for the field to handle the key itself.
function applyTo(field) {
  var e = edit(field.text, field.cursorPosition, field.selectionStart, field.selectionEnd)
  if (e === null) return false
  if (e.to > e.from) field.remove(e.from, e.to)
  if (e.text !== "") field.insert(e.from, e.text)
  field.cursorPosition = e.cursor
  return true
}
