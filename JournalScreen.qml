import QtQuick

import "Parser.js" as Parser
import "GoalMatch.js" as GoalMatch

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
// JournalStore's: it creates a day's file the first time it is typed into,
// saves the debounced text through a SerialFileWriter, and never writes a day
// whose disk text it does not know (see its header). This screen owns the
// editor's buffer and decides when to save it.
//
// The parts: JournalStore (the write path), DayList (the list of days),
// MentionPopup (the `@` goal list), CornerButton (the two corner controls)
// and GoalMatch.js (how a query matches a goal). The root keeps the API
// omvision.qml, ShotDriver and the tests use; functions that moved keep a
// delegate here under their old name.
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

  // The TextEdit, for a test that needs to type into it or read its cursor.
  property alias editor: editor

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

  readonly property string home: Paths.home
  readonly property string journalDir: Paths.journalDir

  // Re-evaluated on a timer so an app left open across midnight starts
  // offering the new day. It never moves the selection on its own -- that
  // would swap the file out from under a sentence someone is in the middle
  // of -- it only changes which day the list calls "Today" and which one a
  // fresh visit to the screen opens.
  property string todayIso: Parser.dayKey(new Date())
  readonly property string todayPath: Paths.journalFile(todayIso)

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

  function dateIsoFromPath(path) { return Paths.journalDateIso(path) }
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
        path: Paths.journalFile(todayIso),
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

  // ---- the buffer and the write path ----------------------------------------
  property string bufferText: ""     // live TextEdit content

  // Whether `bufferText` was derived from the open day's disk text (or from
  // text of ours still on its way there). A day opened before its file has
  // been read starts unbased with an empty buffer: its text is unknown, not
  // empty. syncBufferFromDisk() bases it when the text arrives, and until
  // then JournalStore will not write it -- see its header for why.
  property bool bufferBased: false
  // The disk text the buffer was based on or last saved as. The buffer has
  // unsaved edits exactly when it differs from this.
  property string bufferBase: ""

  // path -> the text last known to be on disk, from this screen's own writes
  // and reads (JournalStore.written). It covers the gap until omvision.qml's
  // 2s `find` poll lists a file this screen just created, so the canvas never
  // goes blank for it.
  property alias written: store.written

  property string writeError: ""

  // Delegates kept under the names the old hand-rolled write queue had.
  function setWritten(path, text) { store.setWritten(path, text) }
  function writtenFor(path) { return store.writtenFor(path) }
  function hasQueued(path) { return store.hasPending(path) }
  // The most recent not-yet-confirmed text queued or in flight for a path,
  // if any -- checked so reopening a day this screen is still in the middle
  // of writing shows that text, not a possibly-stale disk read. Newest
  // first: the old queue checked the in-flight job before the queue, which
  // returned older text when a newer write was already queued behind it.
  function pendingTextFor(path) { return store.pendingTextFor(path) }
  function pruneWritten() { store.prune() }

  JournalStore {
    id: store
    journalContents: root.journalContents
    openPath: root.selectedPath
    writesDisabled: root.writesDisabled
    onSaved: function(path, text) {
      if (path !== root.selectedPath) return
      root.writeError = ""
      if (root.bufferBased) root.bufferBase = text
    }
    onFailed: function(path, message) {
      if (path === root.selectedPath) root.writeError = message
    }
    onDiskTextKnown: function(path) {
      if (path === root.selectedPath) root.syncBufferFromDisk()
    }
  }

  // The entry the canvas shows: the disk-confirmed one once omvision.qml knows
  // about it, else this screen's own record of what it just wrote, else an
  // empty day that does not exist on disk yet.
  function entryForDisplay(path) {
    if (path === "") return null
    var e = findEntry(path)
    if (e) return e
    var dateIso = Paths.journalDateIso(path)
    if (dateIso === "") return null
    var w = store.written[path]
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
    // be written anyway. Text typed into the day before its file was read
    // comes back too, still unbased, to be merged when the file arrives.
    var pending = store.pendingTextFor(path)
    var waiting = store.waitingTextFor(path)
    var known = store.knownText(path)
    root.selectedPath = path
    if (pending !== undefined) root.setBuffer(pending, true)
    else if (waiting !== undefined) root.setBuffer(waiting, false)
    else if (known !== undefined) root.setBuffer(known, true)
    else root.setBuffer("", false)
    root.writeError = ""
    editor.forceActiveFocus()
    editor.cursorPosition = editor.text.length
  }

  function setBuffer(text, based) {
    root.bufferBased = based
    root.bufferBase = based ? text : ""
    root.bufferText = text
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
  readonly property var mentionMatches: GoalMatch.filterGoals(root.goals, root.mentionQuery)

  // The matching itself lives in GoalMatch.js; these keep the old names.
  function filterGoals(goals, query) { return GoalMatch.filterGoals(goals, query) }
  function foldForMatch(s) { return GoalMatch.foldForMatch(s) }
  function matchScore(t, q) { return GoalMatch.matchScore(t, q) }

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
  // today. `bufferText` is the editor's own state, so when the open day's
  // disk text becomes known after the day was opened -- omvision.qml's
  // FileView reading it, or JournalStore reading it before a first save --
  // the buffer has to be brought in line here:
  //   - Unbased and untouched: take the disk text. This is what used to be
  //     missing: a journal opened before its files were read stayed blank
  //     over a non-empty day. The old version read `entries`, which had not
  //     been recomputed yet when journalContentsChanged fired, and it gave up
  //     for good while the save debounce was running; nothing called it again.
  //     It now reads the contents themselves (JournalStore.knownText), runs a
  //     turn later (Qt.callLater, once every binding has settled), and the
  //     test for unsaved edits is the buffer against its base, not a timer.
  //   - Unbased with typing in it: the day's text first, then what was typed
  //     (JournalStore.mergeTyped), and saved -- never the typed text alone.
  //   - Based, with no unsaved edits and nothing of ours on the way to disk:
  //     take a change made to the file from outside. With unsaved edits, the
  //     buffer wins, as it always has.
  function syncBufferFromDisk() {
    var path = root.selectedPath
    if (path === "") return
    var disk = store.knownText(path)
    if (disk === undefined) return
    if (!root.bufferBased) {
      var typed = root.bufferText
      if (typed === "") {
        root.setBuffer(disk, true)
        editor.cursorPosition = editor.text.length
        return
      }
      var merged = store.mergeTyped(disk, typed)
      var cursor = editor.cursorPosition
      root.bufferBased = true
      root.bufferBase = disk
      root.bufferText = merged
      editor.cursorPosition = Math.min(merged.length, cursor + merged.length - typed.length)
      root.flushWrite()
      return
    }
    if (store.hasPending(path)) return // our own text is newer
    if (root.bufferText !== root.bufferBase) return // unsaved edits win
    if (disk === root.bufferBase) return
    root.setBuffer(disk, true)
  }
  onJournalContentsChanged: Qt.callLater(root.syncBufferFromDisk)

  function flushWrite() {
    if (root.writesDisabled) return
    if (root.selectedPath === "") return
    store.save(root.selectedPath, root.bufferText, root.bufferBased)
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
    contentHeight: Math.max(height, editor.height + editor.y + Theme.journalBottomSlack)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    // The friction on the trackpad glide below (flick() decelerates by this;
    // a mouse wheel uses Qt's separate wheel deceleration and is untouched).
    // A glide covers v² / 2a, so a fast swipe travels quadratically further
    // than a slow one -- the "throw it and it keeps going" feel.
    flickDeceleration: 1250
    maximumFlickVelocity: 12000

    // Keeps the cursor's line in view with a margin of space around it.
    function ensureVisible(r) {
      var top = editor.y + r.y
      var bottom = top + r.height + Theme.spaceXl
      if (contentY >= top - Theme.spaceXl) contentY = Math.max(0, top - Theme.spaceXl)
      else if (contentY + height <= bottom) contentY = bottom - height
    }

    // Click anywhere on the paper -- not just on the text -- and you are
    // writing. Inside a Flickable "parent" is the content item, which is only
    // as tall as contentHeight, so this covers the viewport as well.
    MouseArea {
      width: canvas.width
      height: Math.max(canvas.height, editor.height + editor.y + Theme.journalBottomSlack)
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
  // Over the canvas rather than in it, so the canvas's clip cannot cut it
  // off, and below the day list, which closes it anyway. See MentionPopup.
  MentionPopup {
    id: mentionPopup
    visible: root.mentionOpen && root.visible && !root.listOpen
    z: 25
    textEdit: editor
    scroller: canvas
    mentionStart: root.mentionStart
    matches: root.mentionMatches
    currentIndex: root.mentionIndex
    query: root.mentionQuery
    goalCount: root.goals.length
    bottomInset: statusBacking.height
    onHighlight: function(index) { root.mentionIndex = index }
    onAccept: function(index) { root.acceptMention(index); editor.forceActiveFocus() }
  }

  // ---- corner controls ------------------------------------------------------
  // The only chrome on the screen: two quiet squares in the top-left corner
  // (CornerButton). Both live at the corner of the window itself (this
  // screen fills it while writing), clear of the text column, which starts
  // further down.
  //
  // One sticky row: both controls and the day's date, floating over the text
  // rather than scrolling with it. Opaque (paper, not translucent) so lines
  // scrolled past disappear behind it the way a normal editor's header
  // works -- the text used to slide straight through the controls.
  Rectangle {
    id: stickyHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Theme.journalHeaderHeight
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
      // centred against a corner control, so it takes the control's height
      // rather than the Row's baseline.
      Item {
        width: Theme.journalDateGap
        height: Theme.smallControlHeight
      }
      Text {
        height: Theme.smallControlHeight
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
  // A click outside the open list puts it away and goes back to writing.
  MouseArea {
    anchors.fill: parent
    visible: root.listOpen
    enabled: root.listOpen
    z: 30
    onClicked: { root.settleIntoWriting(); editor.forceActiveFocus() }
  }

  DayList {
    id: dayList
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    z: 40
    open: root.listOpen
    entries: root.entries
    selectedPath: root.selectedPath
    onDayClicked: function(path) {
      root.listOpen = false
      root.openDay(path)
    }
  }
}
