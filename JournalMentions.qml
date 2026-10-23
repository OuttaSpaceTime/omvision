import QtQuick

import "GoalMatch.js" as GoalMatch

// The journal's `@` goal tags: the list a typed `@` opens, accepting a goal
// from it, and where the tags already in the text are drawn. No UI of its
// own -- JournalScreen draws the list (MentionPopup) and the titles, and
// passes the editor's keys and clicks in here.
//
// Typing `@` opens a list of every goal under the cursor, and what follows
// it filters the list. Accepting one writes `@<slug>` into the text: the
// slug, not the title, because it is one word (so it cannot be mistaken for
// where the tag ends), it never changes when a goal is renamed (the file
// name is the slug; Writer.updateGoalFields keeps it), and a reader -- the
// coach skill, or grep -- can find every mention of a goal in the journal
// with a plain search. What you read is the goal's title as it is now: the
// highlighter hides the slug in a gap the title's width, and JournalScreen
// draws the title in it (tagSpans), so a rename shows at once. The
// highlighter styles only tags that name a goal that exists, and those are
// what a click opens.
//
// The list only opens on a typed `@`, never because the cursor happened to
// land on an existing tag: arrowing through a paragraph must not keep
// popping a menu up. It closes when the cursor leaves the word after the
// `@`, on Escape, or on a character a slug cannot hold (a space, say).
QtObject {
  id: mentions

  property TextEdit textEdit: null
  // slug -> { meta, logEntries }, the app's goals.
  property var goalsData: ({})
  // The loaded JournalHighlight, or null: where tagSpans come from. Typed
  // `var`, not JournalHighlight: naming that type would tie this file to the
  // compiled module's import, which JournalScreen keeps behind a Loader.
  property var highlighter: null

  readonly property var goals: {
    var out = []
    for (let slug in mentions.goalsData) {
      const m = mentions.goalsData[slug] ? mentions.goalsData[slug].meta : null
      if (!m) continue
      // Parser reads a goal file with no status: key as active.
      out.push({ slug: slug, title: m.title, status: m.status })
    }
    // Active goals first -- those are what a day's writing is about -- then
    // done and cancelled ones, each group by title.
    out.sort(function(a, b) {
      var ra = a.status === "active" ? 0 : 1, rb = b.status === "active" ? 0 : 1
      if (ra !== rb) return ra - rb
      var ta = a.title.toLowerCase(), tb = b.title.toLowerCase()
      return ta < tb ? -1 : (ta > tb ? 1 : 0)
    })
    return out
  }
  // slug -> title, what the highlighter sizes each tag's gap to.
  readonly property var goalTitles: {
    var out = {}
    for (let i = 0; i < mentions.goals.length; i++) out[mentions.goals[i].slug] = mentions.goals[i].title
    return out
  }

  // ---- the tags in the text -------------------------------------------------
  // Where the highlighter left a gap for a title (JournalHighlight.tagSpans):
  // what JournalScreen draws titles over and what slugAt() hit-tests.
  readonly property var tagSpans: mentions.highlighter ? mentions.highlighter.tagSpans : []

  // The goal slug of the tag drawn at (x, y) in the editor, or "": a hit on
  // one of tagSpans, from the `@` to the end of the title, on its line. The
  // highlighter already decided which tags count (a known slug, not inside a
  // code span or a link), so nothing here re-reads the text.
  function slugAt(x, y) {
    for (let i = 0; i < mentions.tagSpans.length; i++) {
      const s = mentions.tagSpans[i]
      if (x >= s.left && x <= s.x + s.width && y >= s.top && y <= s.top + s.height) return s.slug
    }
    return ""
  }

  // ---- the `@` list ---------------------------------------------------------
  property int start: -1   // index of the `@` while the list is open
  property string query: ""
  property int index: 0    // the highlighted row
  readonly property bool open: mentions.start >= 0
  readonly property var matches: GoalMatch.filterGoals(mentions.goals, mentions.query)

  // Called just after a typed `@` has gone into the text. Not after a word
  // character or another `@`, so writing an e-mail address opens nothing --
  // the same rule the highlighter's mentionRe uses.
  function maybeOpen() {
    var t = mentions.textEdit.text
    var pos = mentions.textEdit.cursorPosition
    if (pos < 1 || t.charAt(pos - 1) !== "@") return
    if (pos >= 2 && /[\w@]/.test(t.charAt(pos - 2))) return
    mentions.close()
    mentions.start = pos - 1
  }

  function close() {
    mentions.start = -1
    mentions.query = ""
    mentions.index = 0
  }

  // Follows the text and the cursor while the list is open.
  function follow() {
    if (!mentions.open) return
    var t = mentions.textEdit.text
    var pos = mentions.textEdit.cursorPosition
    if (t.charAt(mentions.start) !== "@" || pos <= mentions.start) { mentions.close(); return }
    var q = t.substring(mentions.start + 1, pos)
    if (!/^[A-Za-z0-9-]*$/.test(q)) { mentions.close(); return }
    if (q !== mentions.query) {
      mentions.query = q
      mentions.index = 0
    }
  }

  function move(step) {
    var n = mentions.matches.length
    if (n === 0) return
    mentions.index = (mentions.index + step + n) % n
  }

  // Replaces the `@` and whatever of the word follows it -- up to the end of
  // the word, not just the cursor, so accepting inside `@lea|rn` does not
  // leave `rn` dangling -- with `@<slug>`. A space follows at the end of a
  // line, where the next thing typed is a word; before punctuation or an
  // existing space it does not, so `@slug.` and `@slug ,` stay as written.
  function accept(i) {
    var g = mentions.matches[i]
    if (!g) return false
    var at = mentions.start
    mentions.close()
    var edit = mentions.textEdit
    var t = edit.text
    var end = edit.cursorPosition
    while (end < t.length && /[A-Za-z0-9-]/.test(t.charAt(end))) end++
    var next = t.charAt(end)
    var insert = "@" + g.slug + ((next === "" || next === "\n") ? " " : "")
    edit.remove(at, end)
    edit.insert(at, insert)
    edit.cursorPosition = at + insert.length + (next === " " ? 1 : 0)
    return true
  }

  // The list's keys, while it is open: those a menu takes. Return and Tab
  // with nothing to accept close it and are left unaccepted, so Return
  // still ends the line. Returns whether the key was taken.
  function handleKey(event) {
    if (!mentions.open || (event.modifiers & Qt.ControlModifier)) return false
    if (event.key === Qt.Key_Down) { mentions.move(1); return true }
    if (event.key === Qt.Key_Up) { mentions.move(-1); return true }
    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
      if (mentions.accept(mentions.index)) return true
      mentions.close()
    }
    return false
  }
}
