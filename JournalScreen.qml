import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import "Parser.js" as Parser

// Journal — a two-pane reader/editor. Left: entries across every goal's
// journal/ directory, newest first. Right: the selected entry, rendered as
// rich text the way omawrite does (headings bold at body size, "-" markers
// dimmed, ">" quotes italic, inline code on a faint fill, links accent +
// underline) when not editing -- plain monospace markdown while editing.
//
// File discovery/loading for entries that are already on disk happens in
// omvision.qml (same idiom as the goal loaders); this screen receives that
// already-read data as props. Writing is this screen's own job: creating
// today's file for a goal (mkdir -p, then touch -- see the "write path"
// comment for why not a FileView write), and debounced saves while the user
// types, which go through a plain Quickshell.Io FileView.setText()
// (writeAdapter() is JsonAdapter-only and not used here), the same
// underlying FileView type omvision.qml's own M3 write path uses for
// <slug>.md, because goal-files.md says the journal is "Omvision only" --
// there is no second writer to race against, so the ordinary
// read-modify-write FileView (atomicWrites: true, temp file + rename) is
// exactly the right tool, no O_APPEND trick needed the way the log file
// needs one.
//
// omvision.qml polls `find` for new journal files every 2s and only then
// starts a per-file FileView for it, so a file this screen just created is
// briefly known to disk but not yet to `journalFiles`/`journalContents`.
// `written` (path -> last text this screen itself wrote) covers that gap so
// the right pane never goes blank for the file it just made, and doubles as
// the baseline every write is checked against -- see the "write path"
// comment below for how writes are queued and dispatched one at a time.
Item {
  id: root

  property var journalFiles: []      // [{slug, path, dateIso}]
  property var journalContents: ({}) // path -> raw text
  property var goalsData: ({})       // slug -> {meta, logEntries}, for titles

  property string selectedPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string goalsDir: home + "/Notes/Omvision/goals"

  function cssColor(c) {
    return "rgb(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + ")"
  }
  function cssRgba(c, a) {
    return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
  }
  readonly property var mdStyles: ({
    accent: cssColor(Theme.accentColor),
    dim: cssColor(Theme.dim),
    codeBg: cssRgba(Theme.foreground, 0.06)
  })

  function buildEntries(files, contents, data) {
    var out = []
    for (var i = 0; i < files.length; i++) {
      var f = files[i]
      // The file list (found in one pass) and each file's content (loaded
      // one FileView at a time) settle at different speeds. Keep every
      // discovered file in the list from the start -- with a blank preview
      // until its content arrives -- so `entries[0]` (and so the default
      // selection) never flickers to whichever file's content happened to
      // resolve first.
      var text = contents[f.path] !== undefined ? contents[f.path] : ""
      var g = data[f.slug]
      var title = (g && g.meta) ? g.meta.title : f.slug
      out.push({
        path: f.path,
        slug: f.slug,
        goalTitle: title,
        dateIso: f.dateIso,
        dateLabel: Parser.formatShortDate(f.dateIso),
        firstLine: Parser.firstMeaningfulLine(text),
        content: text
      })
    }
    out.sort(function(a, b) {
      if (a.dateIso !== b.dateIso) return a.dateIso < b.dateIso ? 1 : -1 // newest first
      return a.slug < b.slug ? -1 : (a.slug > b.slug ? 1 : 0)
    })
    return out
  }
  readonly property var entries: buildEntries(root.journalFiles, root.journalContents, root.goalsData)

  function findEntry(path) {
    for (var i = 0; i < entries.length; i++) if (entries[i].path === path) return entries[i]
    return null
  }
  readonly property var selectedEntry: findEntry(root.selectedPath)

  // ---- write path ----------------------------------------------------------
  // Every write (a debounced save while editing, or the empty file for a
  // brand-new entry) goes through one shared FileView, one at a time, off a
  // queue -- never two writes in flight together, and never a second write
  // started while the first is still out. That's what makes "switch entries
  // mid-write" safe: each queued job carries its own path and text captured
  // at queue time, so a write already headed for entry A still lands as
  // entry A's write even though editingPath (and so `bufferText`) may have
  // already moved on to B by the time it completes -- nothing here ever
  // reads `writerFile.path` back out of the live property to find out what
  // it just wrote, which is the shape that let one entry's text get filed
  // under another's path.
  property string editingPath: ""    // "" when the right pane is in read mode
  property bool editing: false
  property string bufferText: ""     // live TextEdit content

  // path -> last text this screen knows is safely on disk for that path --
  // either confirmed by a successful write, or (for an entry not yet split
  // out into journalFiles/journalContents by omvision.qml's 2s `find` poll)
  // the text this screen itself just wrote. Serves both as the fallback
  // content source for `entryForDisplay` and as the dirty-check/
  // never-blank-over-content baseline in `flushWrite`, so the two can never
  // disagree about what's on disk.
  property var written: ({})

  property var writeQueue: []        // [{path, text}], oldest first, not yet sent
  property bool writeInFlight: false
  property string inFlightPath: ""   // path/text of the job writerFile is
  property string inFlightText: ""   // currently mid-write on, if any

  property string writeError: ""
  property string createError: ""
  property string pendingKind: ""    // "" | "create"
  property string pendingPath: ""

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
  // The most recent not-yet-confirmed text queued or in flight for a path,
  // if any -- checked so reopening an entry that this screen is still in
  // the middle of writing shows that text, not a possibly-stale disk read.
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
      // Never drop the entry currently being edited, mid-write, or queued --
      // only a path this screen has no live interest in any more.
      if (k === root.editingPath || root.inFlightPath === k || root.hasQueued(k)) { d[k] = root.written[k]; continue }
      var e = findEntry(k)
      if (e && e.content === root.written[k]) { changed = true; continue }
      d[k] = root.written[k]
    }
    if (changed) root.written = d
  }

  // Writes are dispatched from a zero-interval Timer rather than straight
  // out of queueWrite()/onSaved -- on this Quickshell build, calling
  // FileView.setText() synchronously from inside another FileView's own
  // signal handler (the shape onSaved -> kickQueue -> dispatch would be)
  // writes the file but silently drops the follow-up saved/saveFailed
  // signal, which would wedge the queue forever on the next job. Deferring
  // by one event-loop tick sidesteps it the same way omvision.qml's own
  // writer already had to.
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

  function slugFromPath(path) {
    var parts = String(path).split("/")
    return parts.length >= 3 ? parts[parts.length - 3] : ""
  }
  function dateIsoFromPath(path) {
    var base = String(path).replace(/^.*\//, "")
    var m = base.match(/^(\d{4}-\d{2}-\d{2})\.md$/)
    return m ? m[1] : ""
  }

  // The entry the right pane shows: the disk-confirmed one once omvision.qml
  // knows about it, else this screen's own record of what it just wrote,
  // else nothing.
  function entryForDisplay(path) {
    if (path === "") return null
    var e = findEntry(path)
    if (e) return e
    var w = root.written[path]
    if (w === undefined) return null
    var slug = root.slugFromPath(path)
    var dateIso = root.dateIsoFromPath(path)
    var g = root.goalsData[slug]
    return {
      path: path, slug: slug,
      goalTitle: (g && g.meta && g.meta.title) ? g.meta.title : slug,
      dateIso: dateIso,
      dateLabel: Parser.formatShortDate(dateIso),
      firstLine: Parser.firstMeaningfulLine(w),
      content: w
    }
  }
  readonly property var displayEntry: entryForDisplay(root.selectedPath)

  onEntriesChanged: {
    pruneWritten()
    // Don't steal the selection out from under an active edit, or an entry
    // this screen just created/wrote that omvision.qml's poll hasn't caught
    // up to yet (`written` still holds it) -- either way `displayEntry`
    // above already covers it.
    if (root.editingPath !== "" || (root.selectedPath !== "" && root.written[root.selectedPath] !== undefined)) return
    if (entries.length === 0) { if (root.selectedPath === "") return; selectedPath = ""; return }
    if (!findEntry(selectedPath)) selectedPath = entries[0].path
  }

  function goalOptions() {
    var out = []
    for (var slug in root.goalsData) {
      var g = root.goalsData[slug]
      if (g && g.meta && g.meta.title) out.push({ slug: slug, title: g.meta.title })
    }
    out.sort(function(a, b) { return a.title < b.title ? -1 : (a.title > b.title ? 1 : 0) })
    return out
  }

  function openForEdit(path, content) {
    // Prefer any not-yet-confirmed text this screen already has queued or in
    // flight for this path over `content` -- `content` can be a moment
    // stale (it comes from props/findEntry, or from a caller's own earlier
    // read) if the user re-opens an entry while its last edit is still on
    // its way to disk; this is what stops that re-open from visually
    // reverting text that's about to be written anyway.
    var pending = root.pendingTextFor(path)
    var initial = (pending !== undefined) ? pending : content
    root.selectedPath = path
    root.bufferText = initial
    if (root.written[path] === undefined) root.setWritten(path, content)
    root.editingPath = path
    root.editing = true
    root.writeError = ""
    editBody.forceActiveFocus()
    editBody.cursorPosition = editBody.text.length
  }

  function beginEditCurrent() {
    var e = root.displayEntry
    if (!e) return
    root.openForEdit(e.path, e.content)
  }

  function flushWrite() {
    if (root.editingPath === "") return
    var path = root.editingPath
    var text = root.bufferText
    var known = root.writtenFor(path)
    if (text === known) return
    // Never let a not-yet-loaded/blank buffer clobber an entry that had text.
    if (text.length === 0 && known.length > 0) return
    root.queueWrite(path, text)
  }

  function exitEditing() {
    writeDebounce.stop()
    flushWrite()
    root.editing = false
    root.editingPath = ""
  }

  function selectEntry(path) {
    if (root.editing) root.exitEditing()
    root.selectedPath = path
  }

  property bool pickerOpen: false
  property string pickerDefaultSlug: ""

  function startCreateFlow() {
    if (root.pickerOpen) return
    if (root.editing) root.exitEditing()
    root.createError = ""
    var opts = goalOptions()
    if (opts.length === 0) { root.createError = "No goals yet -- create a goal before journaling."; return }
    if (opts.length === 1) { beginCreateForSlug(opts[0].slug); return }
    var cur = root.displayEntry
    pickerDefaultSlug = cur ? cur.slug : opts[0].slug
    pickerOpen = true
  }

  function beginCreateForSlug(slug) {
    var dateIso = Parser.dayKey(new Date())
    var path = root.goalsDir + "/" + slug + "/journal/" + dateIso + ".md"
    var dir = root.goalsDir + "/" + slug + "/journal"
    root.createError = ""

    var already = findEntry(path)
    if (already) { root.openForEdit(path, already.content); return }
    if (root.written[path] !== undefined) { root.openForEdit(path, root.written[path]); return }

    root.pendingPath = path
    root.pendingKind = "create"
    mkdirProc.command = ["/usr/bin/mkdir", "-p", dir]
    mkdirProc.running = true
  }

  Process {
    id: mkdirProc
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.pendingKind = ""
        root.createError = "Couldn't create today's entry -- the journal folder wouldn't create."
        return
      }
      // Not writerFile.setText("") here: FileView compares against its
      // (empty, never-loaded) internal buffer and treats an empty write as a
      // no-op, so no file is ever created. `touch` is also the more precise
      // primitive: it creates an empty file if missing and otherwise only
      // bumps mtime, so it can never truncate an entry that already has text
      // even under the race this screen already guards against above.
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
        root.createError = "Couldn't create today's entry -- nothing was written."
        return
      }
      root.setWritten(root.pendingPath, "")
      root.openForEdit(root.pendingPath, "")
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
      if (path === root.editingPath) root.writeError = ""
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
      // The text that failed to save is still sitting in `written`'s old
      // value and in `bufferText` if this is still the open entry -- it is
      // not lost, just not on disk yet. A later edit, a blur, or switching
      // away and back will queue another attempt, since `writtenFor(path)`
      // still disagrees with whatever the editor holds.
      if (path === root.editingPath) {
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

  focus: true
  onVisibleChanged: if (root.visible) root.forceActiveFocus()
  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_N && (event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
      root.startCreateFlow()
      event.accepted = true
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Theme.panelPadding
    spacing: 16

    RowLayout {
      Layout.fillWidth: true
      spacing: 10
      Text {
        text: "Journal"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.headingSize
        font.bold: true
        color: Theme.ink
      }
      Item { Layout.fillWidth: true }
      Button {
        label: "+ entry"
        inert: false
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: Theme.controlHeight
        onActivated: root.startCreateFlow()
      }
    }

    Text {
      visible: root.createError.length > 0
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: root.createError
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      color: Theme.red
    }

    Text {
      visible: root.entries.length === 0 && root.displayEntry === null && root.createError.length === 0
      text: "No journal entries yet."
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
      color: Theme.faint
    }

    // The panes below are the only Layout.fillHeight child, so when they are
    // hidden (no entries yet) nothing absorbs the leftover height: the layout
    // engine spreads it across the remaining rows and centres each one, which
    // strands the header and the empty-state line in the middle of the screen.
    // This spacer takes that slack instead, keeping both at the top.
    Item {
      visible: !(root.entries.length > 0 || root.displayEntry !== null)
      Layout.fillWidth: true
      Layout.fillHeight: true
    }

    RowLayout {
      visible: root.entries.length > 0 || root.displayEntry !== null
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      // ---- left: entry list ------------------------------------------------
      // Same bleed idiom as GoalsScreen, but only bled to the left (the true
      // content edge) since the right side borders the reading pane, not
      // empty margin.
      Item {
        id: leftPaneWrap
        Layout.preferredWidth: 260
        Layout.fillHeight: true

        Flickable {
          id: leftFlick
          x: -Theme.panelPadding
          width: leftPaneWrap.width + Theme.panelPadding
          height: parent.height
          contentHeight: entriesColumn.height
          clip: true

          Column {
            id: entriesColumn
            width: leftFlick.width

            Repeater {
              model: root.entries
              delegate: Rectangle {
                id: entryRow
                required property var modelData
                required property int index

                readonly property bool isSelected: root.selectedPath === modelData.path
                property bool hovered: false

                width: entriesColumn.width
                height: 54
                color: (isSelected || hovered) ? Theme.fill : "transparent"

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: 1
                  color: Theme.hairline
                  visible: entryRow.index > 0
                }

                Rectangle {
                  visible: entryRow.isSelected
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
                  anchors.rightMargin: 14
                  spacing: 2

                  Text {
                    width: parent.width
                    text: entryRow.modelData.dateLabel
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.bold: true
                    color: Theme.ink
                  }
                  Text {
                    width: parent.width
                    text: entryRow.modelData.firstLine
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySmallSize
                    color: Theme.dim
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: entryRow.hovered = true
                  onExited: entryRow.hovered = false
                  onClicked: root.selectEntry(entryRow.modelData.path)
                }
              }
            }
          }
        }
      }

      Rectangle {
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Theme.hairline
      }

      // ---- right: rendered / edited entry -----------------------------------
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
          anchors.fill: parent
          anchors.leftMargin: 20
          spacing: 10

          RowLayout {
            Layout.fillWidth: true
            visible: !!root.displayEntry
            spacing: 10
            Text {
              text: root.displayEntry ? root.displayEntry.dateLabel : ""
              font.family: Theme.fontFamily
              font.pixelSize: Theme.titleSize
              font.bold: true
              color: Theme.ink
            }
            Text {
              Layout.fillWidth: true
              elide: Text.ElideRight
              text: root.displayEntry ? root.displayEntry.goalTitle : ""
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.dim
            }
          }

          Text {
            visible: root.writeError.length > 0
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: root.writeError
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            color: Theme.red
          }

          // ---- read mode: rendered markdown --------------------------------
          Flickable {
            id: readFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.displayEntry && !root.editing
            contentHeight: bodyText.height
            clip: true

            Text {
              id: bodyText
              width: readFlick.width
              textFormat: Text.RichText
              wrapMode: Text.WordWrap
              text: root.displayEntry ? Parser.mdToHtml(root.displayEntry.content, root.mdStyles) : ""
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              onLinkActivated: {} // not followed
            }

            MouseArea {
              // Not anchors.fill: parent -- inside a Flickable "parent" is the
              // content item, which is only as tall as contentHeight (one line
              // for a short entry, one line for a freshly created empty one).
              // That left every pixel below the first line of text dead, so
              // click-to-edit only worked if you happened to hit the text.
              // Cover the viewport as well as the content, whichever is taller.
              width: readFlick.width
              height: Math.max(readFlick.height, bodyText.height)
              cursorShape: Qt.IBeamCursor
              // omawrite's live rendering hides markdown markers by drawing
              // them at pointSize 1.0 through a C++ QSyntaxHighlighter; QML's
              // TextEdit has no equivalent, and this repo's half-finished
              // native highlighter crashed the compositor twice trying. So:
              // click starts plain-markdown editing at the end of the text,
              // not at the clicked point -- Text.positionAt() would only give
              // an offset into the rendered/stripped string, which doesn't
              // line up with the raw markdown source this writes back.
              onClicked: root.beginEditCurrent()
            }
          }

          // ---- edit mode: plain monospace markdown -------------------------
          Flickable {
            id: editFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !!root.displayEntry && root.editing
            contentHeight: Math.max(height, editBody.contentHeight)
            clip: true

            TextEdit {
              id: editBody
              width: editFlick.width
              wrapMode: TextEdit.Wrap
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.ink
              selectByMouse: true
              persistentSelection: true
              text: root.bufferText
              onTextChanged: { root.bufferText = text; writeDebounce.restart() }
              onActiveFocusChanged: if (!activeFocus) root.exitEditing()
              Keys.onEscapePressed: editBody.focus = false
            }
          }
        }
      }
    }
  }

  JournalGoalPicker {
    anchors.fill: parent
    visible: root.pickerOpen
    goalOptions: root.goalOptions()
    defaultSlug: root.pickerDefaultSlug
    onChosen: function(slug) { root.pickerOpen = false; root.beginCreateForSlug(slug) }
    onDismissed: root.pickerOpen = false
  }
}
