pragma ComponentBehavior: Bound

import QtQuick

import "Parser.js" as Parser
import "plugins/ompom.engine/ListContinue.js" as ListContinue

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
// means gone in writing mode (Navigator's `writingMode`) -- and the `»`
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
// Reading the files is NotesStore's; this screen receives what it read as
// props. Writing is JournalStore's: it creates a day's file the first time it is typed into,
// saves the debounced text through a SerialFileWriter, deletes the file when
// the day's text is all deleted, and never writes a day whose disk text it
// does not know (see its header). This screen owns the
// editor's buffer and decides when to save it.
//
// The parts: JournalStore (the write path), JournalMentions (the `@` goal
// tags) and MentionPopup (their list), DayList (the list of days),
// CornerButton (the header's controls) and TrackpadGlide (the canvas's
// kinetic scrolling). The root keeps the API omvision.qml, ShotDriver and
// the tests use.
Item {
  id: root
  // The day list slides in from off the left edge. With the app sidebar out,
  // that edge is the sidebar's, and unclipped the list would slide across it
  // on the way in. (Tooltips are popups in the window overlay, so they are
  // not cut off by this.)
  clip: true

  required property App app
  readonly property var journalContents: root.app.notes.journalContents // path -> raw text

  // How far this screen's left edge sits from the window's -- the rail's
  // animated width while it is out; see Theme.pageX.
  property int leftInset: 0

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
    root.app.nav.hideSidebar()
  }

  // The day it is (NotesStore.todayKey), moved on at midnight. It never
  // moves the selection on its own -- that would swap the file out from
  // under a sentence someone is in the middle of -- it only changes which
  // day the list calls "Today" and which one a fresh visit to the screen
  // opens.
  readonly property string todayIso: root.app.notes.todayKey
  readonly property string todayPath: Paths.journalFile(todayIso)

  property string selectedPath: ""
  property bool listOpen: false

  function labelFor(dateIso) {
    return dateIso === root.todayIso ? "Today" : Parser.formatShortDate(dateIso)
  }

  function buildEntries(files, contents, todayIso) {
    var out = []
    var sawToday = false
    for (let i = 0; i < files.length; i++) {
      const f = files[i]
      // The file list (found in one pass) and each file's content (loaded one
      // FileView at a time) settle at different speeds. Keep every discovered
      // file in the list from the start -- with a blank preview until its
      // content arrives -- so the list never reorders under the cursor.
      const text = contents[f.path] !== undefined ? contents[f.path] : ""
      if (f.dateIso === todayIso) sawToday = true
      out.push({
        path: f.path,
        dateIso: f.dateIso,
        dateLabel: root.labelFor(f.dateIso),
        preview: Parser.journalPreview(text),
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
        dateLabel: root.labelFor(todayIso),
        preview: "",
        content: ""
      })
    }
    out.sort(function(a, b) { return a.dateIso < b.dateIso ? 1 : (a.dateIso > b.dateIso ? -1 : 0) })
    return out
  }
  readonly property var entries: buildEntries(root.app.notes.journalFiles, root.journalContents, root.todayIso)

  function findEntry(path) {
    for (let i = 0; i < entries.length; i++) if (entries[i].path === path) return entries[i]
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

  property string writeError: ""

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

  // The entry the canvas shows: the disk-confirmed one once NotesStore knows
  // about it, else this screen's own record of what it just wrote
  // (JournalStore.written, which covers the gap until NotesStore's 2s
  // `find` poll lists a file this screen just created, so the canvas never
  // goes blank for it), else an empty day that does not exist on disk yet.
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
      // Only the day list reads previews, and this entry isn't in it.
      preview: "",
      content: w !== undefined ? w : ""
    }
  }
  readonly property var displayEntry: entryForDisplay(root.selectedPath)

  readonly property int wordCount: {
    var t = String(root.bufferText).trim()
    return t === "" ? 0 : t.split(/\s+/).length
  }

  // ---- opening a day --------------------------------------------------------
  // Opens a day with the cursor at the end of its text, where writing goes
  // on. A page turn in flight is dropped: whatever asked for this day
  // (the day list, Ctrl+N) came after the turn did, and the turn finishing
  // later would swap the page back out from under it.
  function openDay(path) {
    root.cancelTurn()
    root.showDay(path, false)
  }

  // `atTop` is a page turn's way in: the page starts scrolled to its top,
  // the cursor on its first character, the way a turned page is read from
  // the top. Otherwise the cursor goes to the end, and the page scrolls to
  // it.
  function showDay(path, atTop) {
    root.pageAtTop = atTop
    if (path === root.selectedPath) {
      editor.forceActiveFocus()
      if (atTop) root.placeCursor()
      return
    }
    root.mentions.close()
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
    root.placeCursor()
  }

  // Where the open day's cursor goes, once its text is in: to the end, or,
  // for a turned page, to the top with the page scrolled up to it. Any
  // glide still running from the last day is stopped first, or it would
  // carry on down the new one. Called again when a day's text arrives
  // after it was opened (syncBufferFromDisk), hence the flag.
  function placeCursor() {
    if (!root.pageAtTop) { editor.cursorPosition = editor.text.length; return }
    editor.cursorPosition = 0
    canvas.cancelFlick()
    canvas.contentY = 0
  }

  // ---- turning pages --------------------------------------------------------
  // The header's `‹`/`›` (and Alt+←/→, Ctrl+PgUp/PgDn) page through the
  // journal like a notebook: one page per day that has an entry, the way
  // the day list has one row per day, so a day nothing was written on is
  // not a blank page to flip past. Never past today: there is nothing ahead of it to
  // read, and a future day typed into would be a file dated wrong. A day
  // file dated ahead of today (a hand edit, a clock that was wrong) still
  // has its row in the day list; it is just not a page `›` reaches.
  //
  // A turn is two movements, after Omarchy's own (see Theme.pageLeaveDuration):
  // the page slides a little toward where it is going and fades, then the
  // next day is put in and slides in from the other side. The day only
  // changes in between, at commitTurn(), so the text never swaps while it can
  // be seen. Going back in time the pages move right, the way a notebook's
  // pages do when you leaf back through it; going forward they move left.
  property bool pageAtTop: false
  property string turnTarget: ""   // the day a turn in flight will open
  property int turnStep: 0         // -1 back in time, 1 forward
  property real pageShift: 0
  property real pageOpacity: 1

  // Counted from the day a turn in flight is heading for, so a second click
  // before the first page has gone turns one page further, not the same one.
  readonly property string turnFrom: root.turnTarget !== "" ? root.turnTarget : root.selectedPath
  readonly property string olderPath: root.neighbourPath(root.turnFrom, -1, root.entries, root.todayIso)
  readonly property string newerPath: root.neighbourPath(root.turnFrom, 1, root.entries, root.todayIso)

  // The nearest entry before (step -1) or after (step 1) the day at `path`;
  // after stops at today. `entries` is newest first. Matched on the date,
  // not the row, so a day that has no row (yet) still has neighbours.
  function neighbourPath(path, step, entries, todayIso) {
    var day = Paths.journalDateIso(path)
    if (day === "") return ""
    var newer = ""
    for (let i = 0; i < entries.length; i++) {
      const d = entries[i].dateIso
      if (step < 0) {
        if (d < day) return entries[i].path
      } else {
        if (d <= day) break
        if (d <= todayIso) newer = entries[i].path
      }
    }
    return newer
  }

  function turnPage(step) {
    var to = step < 0 ? root.olderPath : root.newerPath
    if (to === "") return
    root.mentions.close()
    // While the old page is still leaving (a target is set until
    // commitTurn), the turn just heads for the new target. Once the next
    // page is arriving, a click sends it on out again from wherever it has
    // got to: clicking through several days never waits for one to settle.
    var leaving = root.turnTarget !== ""
    root.turnTarget = to
    root.turnStep = step
    if (!leaving) pageTurn.restart()
  }

  function commitTurn() {
    var path = root.turnTarget
    root.turnTarget = ""
    if (path !== "") root.showDay(path, true)
  }

  function cancelTurn() {
    pageTurn.stop()
    root.turnTarget = ""
    root.pageShift = 0
    root.pageOpacity = 1
  }

  SequentialAnimation {
    id: pageTurn
    ParallelAnimation {
      NumberAnimation {
        target: root; property: "pageShift"
        to: -root.turnStep * Theme.space2xl
        duration: Theme.pageLeaveDuration
      }
      NumberAnimation {
        target: root; property: "pageOpacity"; to: 0
        duration: Theme.pageLeaveDuration
      }
    }
    ScriptAction { script: root.commitTurn() }
    ParallelAnimation {
      NumberAnimation {
        target: root; property: "pageShift"
        from: root.turnStep * Theme.space2xl; to: 0
        duration: Theme.pageArriveDuration
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.pageArriveCurve
      }
      NumberAnimation {
        target: root; property: "pageOpacity"; from: 0; to: 1
        duration: Theme.pageArriveDuration
        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.pageArriveCurve
      }
    }
  }

  function setBuffer(text, based) {
    root.bufferBased = based
    root.bufferBase = based ? text : ""
    root.bufferText = text
  }

  // Return inside a list item starts the next one (ListContinue.js, which
  // the break's notes share). Shift+Return is a plain line break. Returns
  // false when the line is not a list item, so the TextEdit handles the key
  // as usual.
  function continueList(edit) {
    return ListContinue.applyTo(edit)
  }

  // ---- `@` goal tags ------------------------------------------------------
  readonly property JournalMentions mentions: JournalMentions {
    textEdit: editor
    goalsData: root.app.notes.goalsData
    highlighter: highlightLoader.item
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
    root.mentions.maybeOpen()
    editor.insert(editor.cursorPosition, query)
    editor.cursorPosition = editor.text.length
    root.mentions.follow()
  }

  function openToday() {
    root.listOpen = false
    root.openDay(root.todayPath)
  }

  // The canvas always shows *some* day, and on a fresh visit that day is
  // today. `bufferText` is the editor's own state, so when the open day's
  // disk text becomes known after the day was opened -- NotesStore's
  // FileView reading it, or JournalStore reading it before a first save --
  // the buffer has to be brought in line here:
  //   - Unbased and untouched: take the disk text, so a journal opened
  //     before its files were read doesn't stay blank over a non-empty day.
  //     It reads the contents themselves (JournalStore.knownText), not
  //     `entries`, which have not been recomputed yet when
  //     journalContentsChanged fires; it runs a turn later (Qt.callLater,
  //     once every binding has settled); and the test for unsaved edits is
  //     the buffer against its base, not a timer.
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
      const typed = root.bufferText
      if (typed === "") {
        root.setBuffer(disk, true)
        root.placeCursor()
        return
      }
      const merged = store.mergeTyped(disk, typed)
      const cursor = editor.cursorPosition
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
      root.cancelTurn()
      root.mentions.close()
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
    objectName: "journalCanvas"
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

    TrackpadGlide {
      flickable: canvas
    }

    // One column at a fixed measure -- the window can be any width, the line
    // length does not change. It is Theme's page column, the one every other
    // screen sets its text in, measured in characters off the writing font
    // (Theme.pageMeasure). Centred on the window rather than on this canvas,
    // so the text stays still while the sidebar slides in beside it.
    TextEdit {
      id: editor
      objectName: "journalEditor"
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
      // A page turn moves only the page: the header and the word count stay
      // put. A Translate, so the column's own x stays where every screen
      // puts it.
      opacity: root.pageOpacity
      transform: Translate { x: root.pageShift }
      color: Theme.ink
      selectionColor: Theme.accentFill
      selectedTextColor: Theme.ink
      selectByMouse: true
      persistentSelection: true
      text: root.bufferText
      onTextChanged: {
        root.bufferText = text
        writeDebounce.restart()
        root.mentions.follow()
      }
      onCursorPositionChanged: root.mentions.follow()
      onCursorRectangleChanged: canvas.ensureVisible(cursorRectangle)
      Keys.onEscapePressed: {
        if (root.mentions.open) root.mentions.close()
        else root.listOpen = false
      }
      Keys.onPressed: function(event) {
        if (root.mentions.handleKey(event)) { event.accepted = true; return }
        // Alt+←/→ turn a page, as well as Ctrl+PgUp/PgDn below: the browser's
        // back and forward, and on a laptop PgUp/PgDn sit behind Fn. The
        // editor does nothing with Alt+arrows, and Omarchy binds them only
        // together with Super, so neither loses anything to this.
        if (event.modifiers === Qt.AltModifier
            && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
          root.turnPage(event.key === Qt.Key_Left ? -1 : 1)
          event.accepted = true
          return
        }
        // After the key has gone into the text, not now: the `@` is not
        // there yet.
        if (event.text === "@") Qt.callLater(root.mentions.maybeOpen)
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
        // Ctrl+B here too: the TextEdit would otherwise swallow it before
        // the window's handler saw it.
        else if (event.key === Qt.Key_B) { root.app.nav.toggleSidebar(); event.accepted = true }
        else if (event.key === Qt.Key_PageUp) { root.turnPage(-1); event.accepted = true }
        else if (event.key === Qt.Key_PageDown) { root.turnPage(1); event.accepted = true }
      }

      // Live styling, attached to this editor's own QTextDocument. Held at
      // arm's length through a Loader so that a MarkdownHighlight module that
      // is missing, unbuilt or off the import path degrades to a plain-text
      // journal instead of failing the screen's import and taking the app
      // down with it -- see JournalHighlight.qml. For the same reason the
      // screen never names the JournalHighlight type (an `as` cast would tie
      // it to that type's import again), so its properties go in as
      // setSource()'s initial properties: assigned in onLoaded, they were
      // writes to members qmllint can't find on a plain QObject.
      Loader {
        id: highlightLoader
        Component.onCompleted: setSource("JournalHighlight.qml", {
          document: editor.textDocument,
          mentions: Qt.binding(function() { return root.mentions.goalTitles })
        })
      }

      // The goal titles over the tags' gaps (see JournalMentions).
      // Children of the editor, so they share its coordinates and scroll
      // with it, and are drawn over its text. In the slug's own font -- a
      // heading's weight, `**` bold -- and on the line's baseline, the way
      // the text around it is set.
      Repeater {
        id: tagTitles
        model: root.mentions.tagSpans
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
      //
      // Any other click on the text is starting to write, like a click on the
      // paper around it (the MouseArea above): the sidebar and the day list
      // go away. The TextEdit takes its own clicks, so that MouseArea only
      // ever saw the margins and the space under the last line, and a click
      // into the words left the sidebar out. A drag that selects is reading,
      // not writing, and DragThreshold already keeps it from being a tap.
      TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: function(eventPoint) {
          var slug = root.mentions.slugAt(eventPoint.position.x, eventPoint.position.y)
          if (slug !== "") root.app.nav.openGoal(slug, "journal")
          else root.settleIntoWriting()
        }
      }
      HoverHandler {
        id: tagHover
        cursorShape: root.mentions.slugAt(tagHover.point.position.x, tagHover.point.position.y) !== ""
                     ? Qt.PointingHandCursor : Qt.IBeamCursor
      }
    }

  }

  // ---- the `@` list ---------------------------------------------------------
  // Over the canvas rather than in it, so the canvas's clip cannot cut it
  // off, and below the day list, which closes it anyway. See MentionPopup.
  MentionPopup {
    id: mentionPopup
    visible: root.mentions.open && root.visible && !root.listOpen
    z: 25
    textEdit: editor
    scroller: canvas
    mentionStart: root.mentions.start
    matches: root.mentions.matches
    currentIndex: root.mentions.index
    query: root.mentions.query
    goalCount: root.mentions.goals.length
    bottomInset: statusBacking.height
    onHighlight: function(index) { root.mentions.index = index }
    onAccept: function(index) { root.mentions.accept(index); editor.forceActiveFocus() }
  }

  // ---- corner controls ------------------------------------------------------
  // The only chrome on the screen: quiet squares (CornerButton), two in the
  // top-left corner and the page turns in the top-right. They live at the
  // corners of the window itself (this screen fills it while writing), clear
  // of the text column, which starts further down.
  //
  // One sticky row: the controls and the day's date, floating over the text
  // rather than scrolling with it. Opaque (paper, not translucent) so lines
  // scrolled past disappear behind it the way a normal editor's header
  // does, instead of sliding through the controls.
  Rectangle {
    id: stickyHeader
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: Theme.journalHeaderHeight
    color: Theme.paper
    z: 20

    // The header takes its own clicks and hover. Without this, anything
    // that missed a control -- the gap between them, the date, a disabled
    // page turn -- fell through to the text scrolled underneath it: the
    // cursor jumped into a line hidden behind the header, or a goal tag
    // there opened. First in the header, so the controls sit above it.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
    }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Theme.spaceLg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spaceXs

      CornerButton {
        glyph: "»"
        tip: "Show sidebar (Ctrl+B)"
        visible: root.app.nav.sidebarHidden
        onActivated: { root.listOpen = false; root.app.nav.toggleSidebar() }
      }
      CornerButton {
        glyph: "≡"
        tip: root.listOpen ? "Hide days (Ctrl+O)" : "All days (Ctrl+O)"
        onActivated: root.openList(!root.listOpen)
      }

      // The day you are in, on the same line as the controls. Vertically
      // centred against a corner control, so it takes the control's height
      // rather than the Row's baseline.
      //
      // Set off from `≡` by this spaceSm plus the Row's spaceXs either side:
      // spaceLg in all, the step between controls in a row, where the two
      // controls sit only spaceXs apart, and the same spaceLg the row keeps
      // from the window's edge. spaceMd, the other neighbour, would give 20
      // in all: more than the row's margin, for no reason a reader could
      // see.
      Item {
        width: Theme.spaceSm
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

    // The page turns, at the right end of the same row: on the controls'
    // line and as far in from the right edge as `»` is from the left, so
    // the header's chrome sits in its two corners and nowhere between.
    // Spaced like the left pair. `‹` and `›` are the single guillemets, the
    // same chevron as `»` at the same stroke and height, so the two corners
    // read as one set of controls. `←`/`→` read as a sign rather than a
    // button, plain `<`/`>` were thinner and taller than `»`, and the Nerd
    // Font angles were heavier than anything else up here. `›` stays in
    // place on today, unavailable, rather than disappearing: `‹` would jump
    // right if it went.
    Row {
      anchors.right: parent.right
      anchors.rightMargin: Theme.spaceLg
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.spaceXs

      CornerButton {
        objectName: "prevDayButton"
        glyph: "‹"
        tip: "Previous day (Alt+←)"
        enabled: root.olderPath !== ""
        onActivated: root.turnPage(-1)
      }
      CornerButton {
        objectName: "nextDayButton"
        glyph: "›"
        tip: "Next day (Alt+→)"
        enabled: root.newerPath !== ""
        onActivated: root.turnPage(1)
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
