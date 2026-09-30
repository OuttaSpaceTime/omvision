import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io

import "Parser.js" as Parser

// Journal — a writing surface, not a list screen.
//
// An entry is a day, not a goal: `~/Notes/Omvision/journal/YYYY-MM-DD.md`,
// free-form, about whatever is on your mind. Nothing here picks a goal, and
// nothing here is filed under one -- a reader (the coach skill) takes the
// whole directory and decides for itself what is relevant.
//
// The screen opens straight into today's entry with the cursor in it. There
// is no read mode and no edit mode: the text is always live, the way iA
// Writer, Typora and omawrite are. The chrome the rest of the app wears --
// screen title, buttons, the day list -- is gone, leaving one centred column
// of text on paper. The app sidebar is gone rather than railed -- collapsed
// means gone in writing mode (omvision.qml's `writingMode`) -- and the `»`
// control here brings back the ordinary sidebar every other screen has.
//
// Markdown is styled live, the way omawrite does it: the document holds plain
// markdown and a C++ QSyntaxHighlighter (the MarkdownHighlight module built by
// highlighter/build.sh) formats it in place -- block markers left visible and
// faint, emphasis markers and link targets drawn at 1pt, nothing ever deleted.
// So the text reads as styled while the file on disk stays byte-for-byte what
// was typed, which QML's own TextEdit.MarkdownText cannot promise: it
// regenerates the markdown from the document and rewraps paragraphs at ~78
// columns on the way out.
//
// File discovery/loading happens in omvision.qml (same idiom as the goal
// loaders); this screen receives that already-read data as props. Writing is
// this screen's own job: creating a day's file the first time it is typed
// into (mkdir -p, then touch -- see the "write path" comment for why not a
// FileView write), and debounced saves while the user types, which go through
// a plain Quickshell.Io FileView.setText() (writeAdapter() is JsonAdapter-only
// and not used here). The journal is Omvision's alone -- no second writer to
// race against -- so an ordinary read-modify-write FileView (atomicWrites:
// true, temp file + rename) is exactly the right tool, no O_APPEND trick like
// the log file needs.
//
// omvision.qml polls `find` for new journal files every 2s and only then
// starts a per-file FileView for it, so a file this screen just created is
// briefly known to disk but not yet to `journalFiles`/`journalContents`.
// `written` (path -> last text this screen itself wrote) covers that gap so
// the canvas never goes blank for the file it just made, and doubles as the
// baseline every write is checked against -- see the "write path" comment
// below for how writes are queued and dispatched one at a time.
Item {
  id: root
  // The day list slides in from off the left edge. With the app sidebar out,
  // that edge is the sidebar's, and unclipped the list would slide across it
  // on the way in. (Tooltips are popups in the window overlay, so they are
  // not cut off by this.)
  clip: true

  property var journalFiles: []      // [{path, dateIso}]
  property var journalContents: ({}) // path -> raw text

  // Ctrl+B from inside the editor: the TextEdit would otherwise swallow it
  // before the window-level handler ever saw it. The sidebar itself is the
  // app's ordinary one -- this screen only asks for it to be toggled, and
  // only says whether it is currently out, so the reveal control can step
  // aside while it is.
  property bool sidebarShown: false
  signal toggleSidebar()

  // How far this screen's left edge sits from the window's -- the rail's
  // animated width while it is out; see Theme.pageX.
  property int leftInset: 0

  // slug -> { meta, logEntries }, the app's goals, for `@` tags: the picker
  // offers them and a click on a tag opens one (openGoal; omvision.qml
  // brings you back here from the goal's own back link).
  property var goalsData: ({})
  signal openGoal(string slug)

  // bin/shot only: the driver types into the editor to show the `@` picker,
  // and those keystrokes must never reach the real day's file. Nothing else
  // sets it.
  property bool writesDisabled: false

  function openList(open) {
    root.listOpen = open
  }

  // Starting to write -- a click on the paper or a keystroke that edits --
  // puts away whatever was opened to look around: the day list, and the app
  // sidebar if it was brought back. Writing always goes on with nothing down
  // the side of the page, the same way it starts.
  function settleIntoWriting() {
    root.listOpen = false
    if (root.sidebarShown) root.toggleSidebar()
  }

  readonly property string home: Quickshell.env("HOME")
  readonly property string journalDir: home + "/Notes/Omvision/journal"

  // Re-evaluated on a timer so an app left open across midnight starts
  // offering the new day. It never moves the selection on its own -- that
  // would swap the file out from under a sentence someone is in the middle
  // of -- it only changes which day the list calls "Today" and which one a
  // fresh visit to the screen opens.
  property string todayIso: Parser.dayKey(new Date())
  readonly property string todayPath: journalDir + "/" + todayIso + ".md"

  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: {
      var k = Parser.dayKey(new Date())
      if (k !== root.todayIso) root.todayIso = k
    }
  }

  property string selectedPath: ""
  property bool listOpen: false

  function dateIsoFromPath(path) {
    var base = String(path).replace(/^.*\//, "")
    var m = base.match(/^(\d{4}-\d{2}-\d{2})\.md$/)
    return m ? m[1] : ""
  }
  function labelFor(dateIso) {
    return dateIso === root.todayIso ? "Today" : Parser.formatShortDate(dateIso)
  }

  function buildEntries(files, contents, todayIso) {
    var out = []
    var sawToday = false
    for (var i = 0; i < files.length; i++) {
      var f = files[i]
      // The file list (found in one pass) and each file's content (loaded one
      // FileView at a time) settle at different speeds. Keep every discovered
      // file in the list from the start -- with a blank preview until its
      // content arrives -- so the list never reorders under the cursor.
      var text = contents[f.path] !== undefined ? contents[f.path] : ""
      if (f.dateIso === todayIso) sawToday = true
      out.push({
        path: f.path,
        dateIso: f.dateIso,
        dateLabel: root.labelFor(f.dateIso),
        firstLine: Parser.firstMeaningfulLine(text),
        content: text
      })
    }
    // Today always has a row, whether or not its file exists yet: opening the
    // journal and typing is what creates the file, so the row has to be there
    // to be opened before there is anything on disk to list.
    if (!sawToday) {
      out.push({
        path: root.journalDir + "/" + todayIso + ".md",
        dateIso: todayIso,
        dateLabel: "Today",
        firstLine: "",
        content: ""
      })
    }
    out.sort(function(a, b) { return a.dateIso < b.dateIso ? 1 : (a.dateIso > b.dateIso ? -1 : 0) })
    return out
  }
  readonly property var entries: buildEntries(root.journalFiles, root.journalContents, root.todayIso)

  function findEntry(path) {
    for (var i = 0; i < entries.length; i++) if (entries[i].path === path) return entries[i]
    return null
  }

  // ---- write path ----------------------------------------------------------
  // Every write (a debounced save while typing, or the empty file for a day
  // written into for the first time) goes through one shared FileView, one at
  // a time, off a queue -- never two writes in flight together, and never a
  // second write started while the first is still out. That's what makes
  // "switch days mid-write" safe: each queued job carries its own path and
  // text captured at queue time, so a write already headed for day A still
  // lands as day A's write even though `selectedPath` (and so `bufferText`)
  // may have already moved on to B by the time it completes -- nothing here
  // ever reads `writerFile.path` back out of the live property to find out
  // what it just wrote, which is the shape that let one entry's text get filed
  // under another's path.
  property string bufferText: ""     // live TextEdit content

  // path -> last text this screen knows is safely on disk for that path --
  // either confirmed by a successful write, or (for a file not yet split out
  // into journalFiles/journalContents by omvision.qml's 2s `find` poll) the
  // text this screen itself just wrote. Serves both as the fallback content
  // source for `displayEntry` and as the dirty-check/never-blank-over-content
  // baseline in `flushWrite`, so the two can never disagree about what's on
  // disk.
  property var written: ({})

  property var writeQueue: []        // [{path, text}], oldest first, not yet sent
  property bool writeInFlight: false
  property string inFlightPath: ""   // path/text of the job writerFile is
  property string inFlightText: ""   // currently mid-write on, if any

  property string writeError: ""
  property string pendingPath: ""    // file being created (mkdir -> touch)
  property string pendingKind: ""    // "" | "create"

  function setWritten(path, text) {
    var d = {}
    for (var k in root.written) d[k] = root.written[k]
    d[path] = text
    root.written = d
  }
  function writtenFor(path) {
    return root.written[path] !== undefined ? root.written[path] : ""
  }
  function hasQueued(path) {
    for (var i = 0; i < root.writeQueue.length; i++) if (root.writeQueue[i].path === path) return true
    return false
  }
  // The most recent not-yet-confirmed text queued or in flight for a path, if
  // any -- checked so reopening a day this screen is still in the middle of
  // writing shows that text, not a possibly-stale disk read.
  function pendingTextFor(path) {
    if (root.inFlightPath === path) return root.inFlightText
    for (var i = root.writeQueue.length - 1; i >= 0; i--) {
      if (root.writeQueue[i].path === path) return root.writeQueue[i].text
    }
    return undefined
  }
  function pruneWritten() {
    var d = {}
    var changed = false
    for (var k in root.written) {
      // Never drop the day currently open, mid-write, or queued -- only a path
      // this screen has no live interest in any more.
      if (k === root.selectedPath || root.inFlightPath === k || root.hasQueued(k)) { d[k] = root.written[k]; continue }
      var e = findEntry(k)
      if (e && e.content === root.written[k]) { changed = true; continue }
      d[k] = root.written[k]
    }
    if (changed) root.written = d
  }

  // Writes are dispatched from a zero-interval Timer rather than straight out
  // of queueWrite()/onSaved -- on this Quickshell build, calling
  // FileView.setText() synchronously from inside another FileView's own signal
  // handler (the shape onSaved -> kickQueue -> dispatch would be) writes the
  // file but silently drops the follow-up saved/saveFailed signal, which would
  // wedge the queue forever on the next job. Deferring by one event-loop tick
  // sidesteps it the same way omvision.qml's own writer already had to.
  function queueWrite(path, text) {
    var q = root.writeQueue.slice()
    if (q.length > 0 && q[q.length - 1].path === path) {
      q[q.length - 1] = { path: path, text: text } // supersede the not-yet-sent job for this path
    } else {
      q.push({ path: path, text: text })
    }
    root.writeQueue = q
    root.kickQueue()
  }
  function kickQueue() {
    if (root.writeInFlight) return
    if (root.writeQueue.length === 0) return
    writeKickTimer.restart()
  }
  function dispatchNextWrite() {
    if (root.writeInFlight) return
    if (root.writeQueue.length === 0) return
    var q = root.writeQueue.slice()
    var job = q.shift()
    root.writeQueue = q
    root.writeInFlight = true
    root.inFlightPath = job.path
    root.inFlightText = job.text
    writerFile.path = job.path
    writerFile.setText(job.text) // writes the file directly; writeAdapter() is JsonAdapter-only
  }

  // The entry the canvas shows: the disk-confirmed one once omvision.qml knows
  // about it, else this screen's own record of what it just wrote, else an
  // empty day that does not exist on disk yet.
  function entryForDisplay(path) {
    if (path === "") return null
    var e = findEntry(path)
    if (e) return e
    var dateIso = root.dateIsoFromPath(path)
    if (dateIso === "") return null
    var w = root.written[path]
    return {
      path: path,
      dateIso: dateIso,
      dateLabel: root.labelFor(dateIso),
      firstLine: w !== undefined ? Parser.firstMeaningfulLine(w) : "",
      content: w !== undefined ? w : ""
    }
  }
  readonly property var displayEntry: entryForDisplay(root.selectedPath)

  readonly property int wordCount: {
    var t = String(root.bufferText).trim()
    return t === "" ? 0 : t.split(/\s+/).length
  }

  onEntriesChanged: pruneWritten()

  // ---- opening a day --------------------------------------------------------
  function openDay(path) {
    if (path === root.selectedPath) { editor.forceActiveFocus(); return }
    root.closeMention()
    writeDebounce.stop()
    flushWrite() // the day being left is written before the buffer moves on
    // Prefer any not-yet-confirmed text already queued or in flight for this
    // path over what the list holds -- the list's copy can be a moment stale
    // if the user comes back to a day whose last edit is still on its way to
    // disk; this is what stops that visit from reverting text that is about to
    // be written anyway.
    var pending = root.pendingTextFor(path)
    var e = root.entryForDisplay(path)
    root.selectedPath = path
    root.bufferText = (pending !== undefined) ? pending : (e ? e.content : "")
    root.writeError = ""
    editor.forceActiveFocus()
    editor.cursorPosition = editor.text.length
  }

  // Return inside a list item starts the next one, the way omawrite and
  // Typora do: `- ` repeats, `1.` counts on (keeping `.` or `)`), and the
  // indent carries over. Return on an item with nothing after its marker ends
  // the list instead -- the marker is removed and the line left empty.
  // Shift+Return is a plain line break. Returns false when the line is not a
  // list item, so the TextEdit handles the key as usual.
  function continueList(edit) {
    if (edit.selectionStart !== edit.selectionEnd) return false
    var text = edit.text
    var pos = edit.cursorPosition
    var lineStart = text.lastIndexOf("\n", pos - 1) + 1
    var lineEnd = text.indexOf("\n", pos)
    if (lineEnd < 0) lineEnd = text.length
    var line = text.substring(lineStart, lineEnd)
    var m = line.match(/^(\s*)([-*+]|(\d{1,9})([.)]))([ \t]+|$)/)
    if (!m) return false
    var markerEnd = lineStart + m[0].length
    if (pos < markerEnd) return false // cursor in the indent or the marker itself
    if (line.substring(m[0].length).trim() === "") {
      edit.remove(lineStart, lineEnd)
      edit.cursorPosition = lineStart
      return true
    }
    var marker = m[3] !== undefined ? (parseInt(m[3], 10) + 1) + m[4] : m[2]
    var insert = "\n" + m[1] + marker + " "
    edit.insert(pos, insert)
    edit.cursorPosition = pos + insert.length
    return true
  }

  // ---- `@` goal tags ------------------------------------------------------
  // Typing `@` opens a list of every goal under the cursor, and what follows
  // it filters the list. Accepting one writes `@<slug>` into the text: the
  // slug, not the title, because it is one word (so it cannot be mistaken
  // for where the tag ends), it never changes when a goal is renamed (the
  // file name is the slug; Writer.updateGoalFields keeps it), and a reader
  // -- the coach skill, or grep -- can find every mention of a goal in the
  // journal with a plain search. What you read is the goal's title as it is
  // now: the highlighter hides the slug in a gap the title's width, and
  // tagTitles draws the title in it, so a rename shows at once. The
  // highlighter styles only tags that name a goal that exists, and those are
  // what a click opens.
  //
  // The list only opens on a typed `@`, never because the cursor happened
  // to land on an existing tag: arrowing through a paragraph must not keep
  // popping a menu up. It closes when the cursor leaves the word after the
  // `@`, on Escape, or on a character a slug cannot hold (a space, say).
  readonly property var goals: {
    var out = []
    for (var slug in root.goalsData) {
      var m = root.goalsData[slug] ? root.goalsData[slug].meta : null
      if (!m) continue
      // A goal file with no status: key is active, as on the Goals screen.
      out.push({ slug: slug, title: m.title, status: m.status || "active" })
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
    for (var i = 0; i < root.goals.length; i++) out[root.goals[i].slug] = root.goals[i].title
    return out
  }

  // Where the highlighter left a gap for a title, from mentionSpans(): what
  // tagTitles draws and what mentionAt() hit-tests. Read from the text's
  // layout, so it is asked again, a moment later (once the layout has caught
  // up), whenever the highlighter says the tags or the layout changed. A day
  // with no tags keeps its empty list, so the Repeater isn't reset for
  // nothing on every reflow.
  property var tagSpans: []
  function refreshTagSpans() {
    var h = highlightLoader.item
    var spans = h ? h.mentionSpans() : []
    if (spans.length === 0 && root.tagSpans.length === 0) return
    root.tagSpans = spans
  }

  property int mentionStart: -1   // index of the `@` while the list is open
  property string mentionQuery: ""
  property int mentionIndex: 0    // the highlighted row
  readonly property bool mentionOpen: root.mentionStart >= 0
  readonly property var mentionMatches: root.filterGoals(root.goals, root.mentionQuery)

  // Fuzzy and case-blind: the query's letters have to appear in the slug or
  // the title in order, not side by side, so `wsq` and `WallSq` both find
  // Wall Squat. Plain substring matching missed those, and a query is typed
  // fast and half-remembered. Tighter matches rank first -- see matchScore
  // -- and ties keep the list's own order (active goals first).
  function filterGoals(goals, query) {
    var q = root.foldForMatch(query)
    if (q === "") return goals
    var scored = []
    for (var i = 0; i < goals.length; i++) {
      var g = goals[i]
      var score = Math.min(root.matchScore(root.foldForMatch(g.slug), q),
                           root.matchScore(root.foldForMatch(g.title), q))
      if (score < Infinity) scored.push({ g: g, score: score, i: i })
    }
    scored.sort(function(a, b) { return a.score !== b.score ? a.score - b.score : a.i - b.i })
    return scored.map(function(s) { return s.g })
  }

  // Lower case, accents dropped (a title's `Diät` has to answer to `dia`:
  // the query is a would-be slug, so it can only hold ASCII), and every run
  // of spaces or hyphens made one hyphen, so a slug and a title compare
  // alike and a hyphen typed in the query matches a space in a title.
  function foldForMatch(s) {
    var t = String(s).toLowerCase()
    if (typeof t.normalize === "function") t = t.normalize("NFD").replace(/[̀-ͯ]/g, "")
    return t.replace(/[\s-]+/g, "-")
  }

  // How well the folded query q matches the folded text t, lower is better,
  // Infinity for no match. In tiers: the start of the text, then the start
  // of a word, then anywhere as one piece, then scattered in order. Hyphens
  // in the query are ignored for the scattered tier, so `wall-sq` and
  // `wallsq` rank alike there.
  //
  // A scattered match is scored the way initials are read: a letter that
  // follows the previous one costs nothing, one that begins a word costs a
  // little, one lost in the middle of a word costs most, and a hair more for
  // every letter skipped breaks ties. The best placement is searched for,
  // not the first: taking each letter where it first appears reads `sa` in
  // Study Software Architecture as the `a` inside "software", and ranks it
  // below Wall Squat, when the `a` of "architecture" is plainly meant.
  function matchScore(t, q) {
    if (t.indexOf(q) === 0) return 0
    if (("-" + t).indexOf("-" + q) >= 0) return 1
    if (t.indexOf(q) >= 0) return 2
    var letters = q.replace(/-/g, "")
    if (letters === "") return Infinity
    // cost[j]: the cheapest placement of the letters so far, the last at j.
    var cost = []
    for (var k = 0; k < letters.length; k++) {
      var next = []
      for (var j = 0; j < t.length; j++) {
        next.push(Infinity)
        if (t.charAt(j) !== letters.charAt(k)) continue
        var wordStart = j === 0 || t.charAt(j - 1) === "-"
        if (k === 0) { next[j] = wordStart ? 0 : 3; continue }
        if (j > 0 && cost[j - 1] < Infinity) next[j] = cost[j - 1]
        for (var p = 0; p < j - 1; p++)
          if (cost[p] < Infinity)
            next[j] = Math.min(next[j], cost[p] + (wordStart ? 1 : 3) + 0.01 * (j - p - 1))
      }
      cost = next
    }
    var best = Math.min.apply(null, cost)
    return best < Infinity ? 3 + best / (3 * letters.length + t.length + 1) : Infinity
  }

  // Called just after a typed `@` has gone into the text. Not after a word
  // character or another `@`, so writing an e-mail address opens nothing --
  // the same rule the highlighter's mentionRe uses.
  function maybeOpenMention() {
    var t = editor.text
    var pos = editor.cursorPosition
    if (pos < 1 || t.charAt(pos - 1) !== "@") return
    if (pos >= 2 && /[\w@]/.test(t.charAt(pos - 2))) return
    root.mentionQuery = ""
    root.mentionIndex = 0
    root.mentionStart = pos - 1
  }

  function closeMention() {
    root.mentionStart = -1
    root.mentionQuery = ""
    root.mentionIndex = 0
  }

  // Follows the text and the cursor while the list is open.
  function updateMention() {
    if (!root.mentionOpen) return
    var t = editor.text
    var pos = editor.cursorPosition
    if (t.charAt(root.mentionStart) !== "@" || pos <= root.mentionStart) { root.closeMention(); return }
    var q = t.substring(root.mentionStart + 1, pos)
    if (!/^[A-Za-z0-9-]*$/.test(q)) { root.closeMention(); return }
    if (q !== root.mentionQuery) {
      root.mentionQuery = q
      root.mentionIndex = 0
    }
  }

  function moveMention(step) {
    var n = root.mentionMatches.length
    if (n === 0) return
    root.mentionIndex = (root.mentionIndex + step + n) % n
  }

  // Replaces the `@` and whatever of the word follows it -- up to the end
  // of the word, not just the cursor, so accepting inside `@lea|rn` does
  // not leave `rn` dangling -- with `@<slug>`. A space follows at the end of
  // a line, where the next thing typed is a word; before punctuation or an
  // existing space it does not, so `@slug.` and `@slug ,` stay as written.
  function acceptMention(i) {
    var g = root.mentionMatches[i]
    if (!g) return false
    var start = root.mentionStart
    root.closeMention()
    var t = editor.text
    var end = editor.cursorPosition
    while (end < t.length && /[A-Za-z0-9-]/.test(t.charAt(end))) end++
    var next = t.charAt(end)
    var insert = "@" + g.slug + ((next === "" || next === "\n") ? " " : "")
    editor.remove(start, end)
    editor.insert(start, insert)
    editor.cursorPosition = start + insert.length + (next === " " ? 1 : 0)
    return true
  }

  // The goal slug of the tag drawn at (x, y) in the editor, or "": a hit on
  // one of tagSpans, from the `@` to the end of the title, on its line. The
  // highlighter already decided which tags count (a known slug, not inside
  // a code span or a link), so nothing here re-reads the text.
  function mentionAt(x, y) {
    for (var i = 0; i < root.tagSpans.length; i++) {
      var s = root.tagSpans[i]
      if (x >= s.left && x <= s.x + s.width && y >= s.top && y <= s.top + s.height) return s.slug
    }
    return ""
  }

  // bin/shot's `mention` action: writes `@` and a query at the end of the
  // day the way typing would, with writes switched off first.
  function typeMentionForShot(query) {
    root.writesDisabled = true
    editor.forceActiveFocus()
    editor.cursorPosition = editor.text.length
    var lead = editor.text.length > 0 && editor.text.charAt(editor.text.length - 1) !== "\n" ? "\n\n" : ""
    editor.insert(editor.cursorPosition, lead + "@")
    editor.cursorPosition = editor.text.length
    root.maybeOpenMention()
    editor.insert(editor.cursorPosition, query)
    editor.cursorPosition = editor.text.length
    root.updateMention()
  }

  function openToday() {
    root.listOpen = false
    root.openDay(root.todayPath)
  }

  // The canvas always shows *some* day, and on a fresh visit that day is
  // today. Content arriving later (the 2s poll, then the per-file read) is
  // picked up through `displayEntry`, but `bufferText` is the editor's own
  // state and has to be refreshed once when the text for the open day first
  // lands -- otherwise opening the journal on an existing entry before its
  // FileView has read would leave an empty canvas over a non-empty file.
  function syncBufferFromDisk() {
    if (root.selectedPath === "") return
    if (root.writeInFlight || root.writeQueue.length > 0) return
    if (writeDebounce.running) return
    var e = findEntry(root.selectedPath)
    if (!e) return
    if (e.content === root.bufferText) return
    if (root.written[root.selectedPath] !== undefined) return // this screen's own text is newer
    root.bufferText = e.content
  }
  onJournalContentsChanged: syncBufferFromDisk()

  function flushWrite() {
    if (root.writesDisabled) return
    if (root.selectedPath === "") return
    var path = root.selectedPath
    var text = root.bufferText
    var known = root.writtenFor(path)
    var onDisk = findEntry(path)
    if (onDisk && root.written[path] === undefined) known = onDisk.content
    if (text === known) return
    // Never let a not-yet-loaded/blank buffer clobber a day that had text.
    if (text.length === 0 && known.length > 0) return
    // A day typed into for the first time has no file yet: make the directory
    // and the empty file first, then let the queue write the text into it.
    // Not writerFile.setText("") for that: FileView compares against its
    // (empty, never-loaded) internal buffer and treats an empty write as a
    // no-op, so no file is ever created. `touch` is also the more precise
    // primitive -- it creates an empty file if missing and otherwise only
    // bumps mtime, so it can never truncate a day that already has text.
    if (!onDisk && root.written[path] === undefined) {
      if (root.pendingKind === "create") return // already on its way; the debounce will come round again
      root.pendingPath = path
      root.pendingKind = "create"
      mkdirProc.command = ["/usr/bin/mkdir", "-p", root.journalDir]
      mkdirProc.running = true
      return
    }
    root.queueWrite(path, text)
  }

  Process {
    id: mkdirProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.pendingKind = ""
        root.writeError = "Couldn't make the journal folder -- nothing was written."
        return
      }
      touchProc.command = ["/usr/bin/touch", root.pendingPath]
      touchProc.running = true
    }
  }

  Process {
    id: touchProc
    onExited: function(exitCode, exitStatus) {
      if (root.pendingKind !== "create") return
      root.pendingKind = ""
      if (exitCode !== 0) {
        root.writeError = "Couldn't create today's file -- nothing was written."
        return
      }
      root.setWritten(root.pendingPath, "")
      if (root.pendingPath === root.selectedPath) root.flushWrite()
    }
  }

  FileView {
    id: writerFile
    printErrors: false
    watchChanges: false
    atomicWrites: true
    onSaved: {
      var path = root.inFlightPath
      var text = root.inFlightText
      root.setWritten(path, text)
      if (path === root.selectedPath) root.writeError = ""
      root.writeInFlight = false
      root.inFlightPath = ""
      root.inFlightText = ""
      root.kickQueue()
    }
    onSaveFailed: function(error) {
      var path = root.inFlightPath
      root.writeInFlight = false
      root.inFlightPath = ""
      root.inFlightText = ""
      // The text that failed to save is still sitting in `written`'s old value
      // and in `bufferText` if this is still the open day -- it is not lost,
      // just not on disk yet. A later keystroke or reopening the day queues
      // another attempt, since `writtenFor(path)` still disagrees with
      // whatever the editor holds.
      if (path === root.selectedPath) {
        root.writeError = "Couldn't save the last change -- it's still here, not on disk."
      }
      root.kickQueue()
    }
  }

  Timer {
    id: writeKickTimer
    interval: 0
    repeat: false
    onTriggered: root.dispatchNextWrite()
  }

  Timer {
    id: writeDebounce
    interval: 800
    repeat: false
    onTriggered: root.flushWrite()
  }

  onVisibleChanged: {
    if (!root.visible) {
      root.closeMention()
      writeDebounce.stop()
      flushWrite()
      root.listOpen = false
      return
    }
    if (root.selectedPath === "") root.openDay(root.todayPath)
    else editor.forceActiveFocus()
  }
  Component.onCompleted: if (root.visible && root.selectedPath === "") root.openDay(root.todayPath)

  // ---- the canvas -----------------------------------------------------------
  Flickable {
    id: canvas
    anchors.fill: parent
    // A screenful of slack under the last line, so writing stays in the
    // middle of the window instead of creeping down to its bottom edge.
    contentHeight: Math.max(height, editor.height + editor.y + 260)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // The friction on the trackpad glide below (flick() decelerates by this;
    // a mouse wheel uses Qt's separate wheel deceleration and is untouched).
    // A glide covers v² / 2a, so a fast swipe travels quadratically further
    // than a slow one -- the "throw it and it keeps going" feel.
    flickDeceleration: 1250
    maximumFlickVelocity: 12000

    function ensureVisible(r) {
      var top = editor.y + r.y
      var bottom = top + r.height + 24
      if (contentY >= top - 24) contentY = Math.max(0, top - 24)
      else if (contentY + height <= bottom) contentY = bottom - height
    }

    // Click anywhere on the paper -- not just on the text -- and you are
    // writing. Inside a Flickable "parent" is the content item, which is only
    // as tall as contentHeight, so this covers the viewport as well.
    MouseArea {
      width: canvas.width
      height: Math.max(canvas.height, editor.height + editor.y + 260)
      cursorShape: Qt.IBeamCursor
      onClicked: {
        root.settleIntoWriting()
        editor.forceActiveFocus()
        editor.cursorPosition = editor.text.length
      }
    }

    // Kinetic scrolling for the trackpad. Other apps keep gliding after you
    // lift your fingers; Qt Quick on Wayland does not: the compositor sends
    // no momentum events, only ScrollEnd, and Flickable just stops there. So
    // Flickable keeps tracking the fingers 1:1 itself, and this handler only
    // watches -- `blocking: false` passes every event on to it -- measuring
    // how fast the page was moving and, on ScrollEnd, throwing it on at that
    // speed.
    //
    // Taking the whole gesture over instead was rejected: Flickable would
    // still see ScrollBegin (it carries no delta, so this handler declines
    // it) but never the matching ScrollEnd, and be left mid-drag. Mouse wheel
    // events (NoScrollPhase) are left alone too, to Qt's own wheel handling.
    // acceptedDevices must name TouchPad: Qt's Wayland backend marks trackpad
    // scrolls as synthesized, which a WheelHandler ignores by default.
    WheelHandler {
      id: trackpadGlide
      target: null
      blocking: false
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

      // Velocity is read over the last `windowMs` ms of the gesture; if the
      // fingers rested longer than `restMs` before lifting, there is no glide,
      // so a careful scroll to a spot stays put.
      readonly property int windowMs: 80
      readonly property int restMs: 50
      readonly property real boost: 1.5
      readonly property real minVelocity: 100
      property var samples: []

      onWheel: (event) => {
        const now = Date.now()
        if (event.phase === Qt.ScrollUpdate) {
          samples.push({ t: now, dy: event.pixelDelta.y })
          while (samples.length > 0 && now - samples[0].t > windowMs) samples.shift()
        } else if (event.phase === Qt.ScrollEnd) {
          const s = samples
          samples = []
          if (s.length < 2 || now - s[s.length - 1].t > restMs) return
          let dy = 0
          for (let i = 1; i < s.length; ++i) dy += s[i].dy
          const ms = s[s.length - 1].t - s[0].t
          if (ms <= 0) return
          const v = dy / ms * 1000 * boost
          if (Math.abs(v) < minVelocity) return
          // Later, not now: Flickable handles this same ScrollEnd right
          // after us, and its returnToBounds() can reset the timeline a
          // flick started here would run on. Putting fingers back down
          // (ScrollBegin) resets it on purpose, which catches the glide.
          Qt.callLater(() => canvas.flick(0, v))
        }
      }
    }

    // One column at a fixed measure -- the window can be any width, the line
    // length does not change. It is Theme's page column, the one every other
    // screen sets its text in, measured in characters off the writing font
    // (Theme.pageMeasure). Centred on the window rather than on this canvas,
    // so the text stays still while the sidebar slides in beside it.
    TextEdit {
      id: editor
      x: Theme.pageX(canvas.width, root.leftInset)
      // Clears the sticky header (which floats over this Flickable rather
      // than sitting in it) and then some: the first line of the day starts
      // well down the page, the way a page of writing does.
      y: stickyHeader.height + Theme.space3xl
      width: Theme.pageWidth(canvas.width)
      wrapMode: TextEdit.Wrap
      font.family: Theme.fontFamily
      // Points, not pixels -- see Theme.writingPointSize for why the
      // highlighter needs the document font to be sized the same way its
      // character formats are.
      font.pointSize: Theme.writingPointSize
      color: Theme.ink
      selectionColor: Theme.accentFill
      selectedTextColor: Theme.ink
      selectByMouse: true
      persistentSelection: true
      text: root.bufferText
      onTextChanged: {
        root.bufferText = text
        writeDebounce.restart()
        root.updateMention()
      }
      onCursorPositionChanged: root.updateMention()
      onCursorRectangleChanged: canvas.ensureVisible(cursorRectangle)
      Keys.onEscapePressed: {
        if (root.mentionOpen) root.closeMention()
        else root.listOpen = false
      }
      Keys.onPressed: function(event) {
        // The `@` list, while open, takes the keys a menu takes. Return and
        // Tab with nothing to accept close it and fall through, so Return
        // still ends the line.
        if (root.mentionOpen && !(event.modifiers & Qt.ControlModifier)) {
          if (event.key === Qt.Key_Down) { root.moveMention(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up) { root.moveMention(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Tab) {
            if (root.acceptMention(root.mentionIndex)) { event.accepted = true; return }
            root.closeMention()
          }
        }
        // After the key has gone into the text, not now: the `@` is not
        // there yet.
        if (event.text === "@") Qt.callLater(root.maybeOpenMention)
        if (!(event.modifiers & Qt.ControlModifier)) {
          // Anything that produces text (letters, Return, Backspace...) is
          // writing; arrows and Escape carry none and leave things as they are.
          // Not accepted, so the key still reaches the TextEdit.
          if (event.text !== "" && event.key !== Qt.Key_Escape) root.settleIntoWriting()
          if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
              && !(event.modifiers & Qt.ShiftModifier)
              && root.continueList(editor)) event.accepted = true
          return
        }
        if (event.key === Qt.Key_O) { root.openList(!root.listOpen); event.accepted = true }
        else if (event.key === Qt.Key_N) { root.openToday(); event.accepted = true }
        else if (event.key === Qt.Key_B) { root.toggleSidebar(); event.accepted = true }
      }

      // Live styling, attached to this editor's own QTextDocument. Held at
      // arm's length through a Loader so that a MarkdownHighlight module that
      // is missing, unbuilt or off the import path degrades to a plain-text
      // journal instead of failing the screen's import and taking the app
      // down with it -- see JournalHighlight.qml.
      Loader {
        id: highlightLoader
        source: "JournalHighlight.qml"
        onLoaded: {
          if (!item) return
          item.document = editor.textDocument
          item.mentions = Qt.binding(function() { return root.goalTitles })
          item.mentionSpansChanged.connect(function() { Qt.callLater(root.refreshTagSpans) })
        }
      }

      // The goal titles over the tags' gaps (see the `@` goal tags section).
      // Children of the editor, so they share its coordinates and scroll
      // with it, and are drawn over its text. In the slug's own font -- a
      // heading's weight, `**` bold -- and on the line's baseline, the way
      // the text around it is set.
      Repeater {
        id: tagTitles
        model: root.tagSpans
        Text {
          required property var modelData
          x: modelData.x
          y: modelData.baseline - baselineOffset
          width: modelData.width
          text: modelData.title
          font: modelData.font
          color: Theme.accentColor
          elide: Text.ElideRight
        }
      }

      // A click on a goal tag opens the goal. A plain click, not Ctrl+click:
      // tags are few and short, and the cursor can still be put inside one
      // with the arrow keys. The TapHandler only watches (a passive grab),
      // so the TextEdit still places the cursor and a drag still selects --
      // DragThreshold drops the tap once the pointer moves -- and coming back
      // from the goal finds the cursor on the tag you left from.
      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: function(eventPoint) {
          var slug = root.mentionAt(eventPoint.position.x, eventPoint.position.y)
          if (slug !== "") root.openGoal(slug)
        }
      }
      HoverHandler {
        id: tagHover
        cursorShape: root.mentionAt(tagHover.point.position.x, tagHover.point.position.y) !== ""
                     ? Qt.PointingHandCursor : Qt.IBeamCursor
      }
    }

  }

  // ---- the `@` list ---------------------------------------------------------
  // Hangs under the `@` it belongs to, left edge on the `@`, like any
  // editor's completion list; flips above the line when there is no room
  // below, and is pulled back inside the window at the right. Over the
  // canvas rather than in it, so the canvas's clip cannot cut it off, and
  // below the day list, which closes it anyway.
  Rectangle {
    id: mentionPopup
    readonly property int rowHeight: Theme.bodySize + Theme.spaceSm * 2 + Theme.spaceXxs
    readonly property int maxRows: 6
    // Rebinds on scroll and on reflow (cursorRectangle moves with both the
    // text and the width), which positionToRectangle() alone would not.
    readonly property rect anchorRect: {
      var dep = editor.cursorRectangle
      var r = root.mentionOpen ? editor.positionToRectangle(root.mentionStart) : Qt.rect(0, 0, 0, 0)
      return Qt.rect(editor.x + r.x - canvas.contentX, editor.y + r.y - canvas.contentY, r.width, r.height)
    }
    readonly property bool fitsBelow: anchorRect.y + anchorRect.height + Theme.spaceXs + height
                                      <= root.height - statusBacking.height

    visible: root.mentionOpen && root.visible && !root.listOpen
    z: 25
    width: Math.min(Math.round(Theme.pageMeasure / 2), root.width - Theme.spaceLg * 2)
    height: (root.mentionMatches.length > 0
             ? Math.min(root.mentionMatches.length, maxRows) * rowHeight
             : emptyText.implicitHeight + Theme.spaceSm * 2) + Theme.borderWidth * 2
    // The rows' text starts on the `@` itself.
    x: Math.max(Theme.spaceLg, Math.min(anchorRect.x - Theme.spaceMd - Theme.borderWidth,
                                        root.width - width - Theme.spaceLg))
    y: fitsBelow ? anchorRect.y + anchorRect.height + Theme.spaceXs
                 : anchorRect.y - height - Theme.spaceXs
    color: Theme.paper
    border.color: Theme.border
    border.width: Theme.borderWidth

    Text {
      id: emptyText
      visible: root.mentionMatches.length === 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Theme.spaceMd
      anchors.rightMargin: Theme.spaceMd
      elide: Text.ElideRight
      text: root.goals.length === 0 ? "No goals yet" : "No goal matches “" + root.mentionQuery + "”"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      color: Theme.faint
    }

    ListView {
      id: mentionList
      anchors.fill: parent
      anchors.margins: Theme.borderWidth
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.mentionMatches
      currentIndex: root.mentionIndex
      onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

      delegate: Rectangle {
        id: mentionRow
        required property var modelData
        required property int index
        readonly property bool current: index === root.mentionIndex

        width: mentionList.width
        height: mentionPopup.rowHeight
        color: current ? Theme.hoverFill : "transparent"

        Rectangle {
          visible: mentionRow.current
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 3
          color: Theme.accentColor
        }

        // One line: the title, and a closed goal's status on the right. The
        // `@slug` used to sit under the title, but the tag is drawn as the
        // title anyway, so the slug only added noise to the list.
        Text {
          id: mentionTitle
          anchors.left: parent.left
          anchors.right: statusText.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Theme.spaceMd
          anchors.rightMargin: statusText.text === "" ? 0 : Theme.spaceSm
          text: mentionRow.modelData.title
          elide: Text.ElideRight
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySize
          color: mentionRow.modelData.status === "active" ? Theme.ink : Theme.dim
        }
        Text {
          id: statusText
          anchors.right: parent.right
          anchors.baseline: mentionTitle.baseline
          anchors.rightMargin: Theme.spaceMd
          text: mentionRow.modelData.status === "active" ? "" : mentionRow.modelData.status
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.faint
        }

        // Hover moves the highlight rather than drawing a second one, the
        // way a menu does. It never takes focus, so the cursor stays in the
        // text and typing goes on filtering.
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.mentionIndex = mentionRow.index
          onClicked: { root.acceptMention(mentionRow.index); editor.forceActiveFocus() }
        }
      }
    }
  }

  // ---- corner controls ------------------------------------------------------
  // The only chrome on the screen: two quiet squares in the top-left corner.
  // Faint, no border, no fill until hovered -- present enough to find, not
  // loud enough to read as content. Both live at the corner of the window
  // itself (this screen fills it while writing), clear of the text column,
  // which starts 72px down.
  component CornerButton: Rectangle {
    id: cb
    property string glyph: ""
    property string tip: ""
    signal activated()

    width: 24
    height: 24
    color: cbArea.containsMouse ? Theme.hoverFill : "transparent"

    Text {
      anchors.centerIn: parent
      text: cb.glyph
      font.family: Theme.fontFamily
      font.pixelSize: Theme.subtitleSize
      color: cbArea.containsMouse ? Theme.dim : Theme.faint
    }

    MouseArea {
      id: cbArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: cb.activated()
    }

    ToolTip.visible: cbArea.containsMouse
    ToolTip.delay: 400
    ToolTip.text: cb.tip
  }

  // One sticky row: both controls and the day's date, floating over the text
  // rather than scrolling with it. Opaque (paper, not translucent) so lines
  // scrolled past disappear behind it the way a normal editor's header
  // works -- the text used to slide straight through the controls.
  Rectangle {
    id: stickyHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 56
    color: Theme.paper
    z: 20

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Theme.spaceLg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spaceXs

      CornerButton {
        glyph: "»"
        tip: "Show sidebar (Ctrl+B)"
        visible: !root.sidebarShown
        onActivated: { root.listOpen = false; root.toggleSidebar() }
      }
      CornerButton {
        glyph: "≡"
        tip: root.listOpen ? "Hide days (Ctrl+O)" : "All days (Ctrl+O)"
        onActivated: root.openList(!root.listOpen)
      }

      // The day you are in, on the same line as the controls. Vertically
      // centred against a 24px control, so it needs its own height rather
      // than the Row's baseline.
      Item {
        width: 10
        height: 24
      }
      Text {
        height: 24
        verticalAlignment: Text.AlignVCenter
        text: root.displayEntry ? root.displayEntry.dateLabel : ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.faint
      }
    }
  }

  // Word count and the one error this screen can produce, bottom-right, out
  // of the way. The count is the only thing on screen that moves while you
  // type, which is the point: it is how a writing tool says "still saving,
  // still here" without a status bar. On its own opaque patch of paper for
  // the same reason the header has one -- text scrolls underneath it.
  //
  // The patch sizes itself from the labels' *implicit* widths, and the
  // labels take their width from the patch. Sizing it from their actual
  // widths instead would be a binding loop.
  Rectangle {
    id: statusBacking
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: Math.max(wordCountText.implicitWidth,
                    writeErrorText.visible ? writeErrorText.implicitWidth : 0)
           + Theme.spaceXl * 2
    height: (writeErrorText.visible ? writeErrorText.implicitHeight + Theme.spaceXxs : 0)
            + wordCountText.implicitHeight + Theme.space2xl
    color: Theme.paper
    z: 20

    Column {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: Theme.spaceLg
      anchors.bottomMargin: Theme.spaceLg
      spacing: Theme.spaceXxs

      Text {
        id: writeErrorText
        width: statusBacking.width - Theme.spaceXl * 2
        horizontalAlignment: Text.AlignRight
        visible: root.writeError.length > 0
        text: root.writeError
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.red
      }
      Text {
        id: wordCountText
        width: statusBacking.width - Theme.spaceXl * 2
        horizontalAlignment: Text.AlignRight
        text: root.wordCount === 1 ? "1 word" : root.wordCount + " words"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.captionSize
        color: Theme.faint
      }
    }
  }

  // ---- day list -------------------------------------------------------------
  // Collapsed by default and an overlay when open, never an in-flow pane: the
  // text column must not shift when you glance at the list of days. Same
  // shape the app sidebar takes in this mode, on the same edge -- so opening
  // one closes the other (see the reveal control above).
  MouseArea {
    anchors.fill: parent
    visible: root.listOpen
    enabled: root.listOpen
    z: 30
    onClicked: { root.settleIntoWriting(); editor.forceActiveFocus() }
  }

  Rectangle {
    id: dayList
    width: 260
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    x: root.listOpen ? 0 : -width
    visible: x > -width
    z: 40
    color: Theme.paper
    clip: true

    Behavior on x {
      NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
    }

    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: 1
      color: Theme.hairline
    }

    Text {
      id: dayListHeading
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: Theme.panelPadding
      anchors.topMargin: Theme.spaceLg
      text: "Days"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      color: Theme.faint
    }

    Flickable {
      id: dayFlick
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: dayListHeading.bottom
      anchors.bottom: parent.bottom
      anchors.topMargin: Theme.spaceMd
      anchors.rightMargin: Theme.spaceXxs
      contentHeight: daysColumn.height
      clip: true

      Column {
        id: daysColumn
        width: dayFlick.width

        Repeater {
          model: root.entries
          delegate: Rectangle {
            id: dayRow
            required property var modelData
            required property int index

            readonly property bool isSelected: root.selectedPath === modelData.path
            property bool hovered: false

            width: daysColumn.width
            height: 60
            color: (isSelected || hovered) ? Theme.fill : "transparent"

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: 1
              color: Theme.hairline
              visible: dayRow.index > 0
            }

            Rectangle {
              visible: dayRow.isSelected
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 3
              color: Theme.accentColor
            }

            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Theme.panelPadding
              anchors.rightMargin: Theme.spaceMd
              spacing: Theme.spaceXxs

              Text {
                width: parent.width
                text: dayRow.modelData.dateLabel
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                font.bold: true
                color: Theme.ink
              }
              Text {
                width: parent.width
                text: dayRow.modelData.firstLine === "" ? "empty" : dayRow.modelData.firstLine
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: dayRow.modelData.firstLine === "" ? Theme.faint : Theme.dim
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: dayRow.hovered = true
              onExited: dayRow.hovered = false
              onClicked: {
                root.listOpen = false
                root.openDay(dayRow.modelData.path)
              }
            }
          }
        }
      }
    }
  }
}
