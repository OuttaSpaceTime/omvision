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
      writeDebounce.stop()
      flushWrite()
      root.listOpen = false
      return
    }
    if (root.selectedPath === "") root.openDay(root.todayPath)
    else editor.forceActiveFocus()
  }
  Component.onCompleted: if (root.visible && root.selectedPath === "") root.openDay(root.todayPath)

  FontMetrics {
    id: writingMetrics
    font.family: Theme.fontFamily
    font.pointSize: Theme.writingPointSize
  }

  // ---- the canvas -----------------------------------------------------------
  Flickable {
    id: canvas
    anchors.fill: parent
    // A screenful of slack under the last line, so writing stays in the
    // middle of the window instead of creeping down to its bottom edge.
    contentHeight: Math.max(height, editor.height + editor.y + 260)
    clip: true
    boundsBehavior: Flickable.StopAtBounds

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

    // One centred column at a fixed measure -- the window can be any width,
    // the line length does not change. Measured in characters off the actual
    // font rather than in pixels, so changing the writing size moves the
    // column with it instead of silently making lines longer.
    TextEdit {
      id: editor
      x: Math.round((canvas.width - width) / 2)
      // Clears the sticky header (which floats over this Flickable rather
      // than sitting in it) and then some: the first line of the day starts
      // well down the page, the way a page of writing does.
      y: stickyHeader.height + Theme.space3xl
      width: Math.min(Math.round(writingMetrics.advanceWidth("0") * Theme.writingColumns),
                      canvas.width - Theme.writingGutter * 2)
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
      onTextChanged: { root.bufferText = text; writeDebounce.restart() }
      onCursorRectangleChanged: canvas.ensureVisible(cursorRectangle)
      Keys.onEscapePressed: root.listOpen = false
      Keys.onPressed: function(event) {
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
        onLoaded: if (item) item.document = editor.textDocument
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
        font.letterSpacing: 1
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
      text: "DAYS"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      font.letterSpacing: 1
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
