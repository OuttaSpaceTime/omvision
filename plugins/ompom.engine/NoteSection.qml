import QtQuick
import qs.Commons

// One section of the break's notes: its heading, drawn as the markdown
// heading it reads as ("# What's done?", in the journal's own styling), and
// the text under it. Clicking the heading folds the text away; a folded
// heading is dimmed, the only sign of it, since a ▾/▸ arrow beside it was one
// more thing on a page meant to look like writing. The heading is fixed
// rather than part of the text: the log keeps one line per question, and a
// heading typed away would leave nothing to file the text under.
//
// `text` is the engine's copy (Engine.doneText and so on); every edit goes
// back to it through edited(), so the engine never reaches into this field.
Column {
  id: section

  property string title: ""
  property string text: ""
  property real pointSize
  // The section's own, not the engine's: a fold is how the page looks, not
  // part of the cycle. Overlay.qml opens every section again for each break.
  property bool open: true
  readonly property alias heading: sectionHeading
  readonly property alias edit: sectionEdit

  signal edited(string text)
  // Which of the two fields: the caret can stand on the heading too. Only
  // the focused field's caret is reported, so a relayout or a reset of all
  // three texts doesn't scroll the page to whichever field moved last.
  signal cursorMoved(Item field)
  // A key in either field, offered to the page first: an arrow off this
  // section's edge moves the caret to the next section (Overlay.qml).
  signal keyPressed(Item field, var event)

  spacing: Style.space(8)

  // A folded section's text is hidden, and a hidden item drops keyboard
  // focus -- verified: afterwards nothing on the page had it, so typing
  // went nowhere. So folding from inside the text leaves the caret on the
  // heading, as an editor does. Unfolding with a click puts the caret in
  // the text just opened, where the click said the writing is; unfolding
  // with Return on the heading leaves it there, to go on with the arrows.
  function toggle(byKeyboard) {
    var textHadFocus = sectionEdit.activeFocus
    open = !open
    if (textHadFocus) sectionHeading.forceActiveFocus()
    else if (open && !byKeyboard) sectionEdit.forceActiveFocus()
  }

  // Both fields' caret moves and focus gains come through here.
  function caretMoved(field) {
    if (!field.activeFocus) return
    if (field === sectionHeading) {
      headingCaret.lit = true
      if (blink.running) blink.restart()
    }
    section.cursorMoved(field)
  }

  // The journal's markdown styling on one of this section's documents. See
  // NoteHighlighterHost.qml for why it's loaded rather than imported: a
  // missing native module costs the styling, not the engine its load.
  component Highlight: Loader {
    property Item target
    source: "NoteHighlighterHost.qml"
    onLoaded: {
      item.basePointSize = section.pointSize
      item.document = target.textDocument
    }
  }

  // Continues a "- ", "* ", or "1. " list line onto the next line,
  // auto-incrementing numbered markers. Pressing Return on an already-empty
  // list line ends the list instead of piling up empty markers.
  function continueList(event) {
    event.accepted = true
    var pos = sectionEdit.cursorPosition
    var text = sectionEdit.text
    var lineStart = text.lastIndexOf("\n", pos - 1) + 1
    var lineEnd = text.indexOf("\n", lineStart)
    if (lineEnd === -1) lineEnd = text.length
    var line = text.substring(lineStart, lineEnd)

    var bullet = line.match(/^(\s*)([-*])\s+(.*)$/)
    var numbered = line.match(/^(\s*)(\d+)\.\s+(.*)$/)
    var marker = bullet || numbered

    if (marker && marker[3].trim().length === 0) {
      sectionEdit.remove(lineStart, lineEnd)
      sectionEdit.insert(lineStart, "\n")
      sectionEdit.cursorPosition = lineStart + 1
      return
    }

    var continuation = "\n"
    if (bullet) {
      continuation += bullet[1] + bullet[2] + " "
    } else if (numbered) {
      continuation += numbered[1] + (parseInt(numbered[2], 10) + 1) + ". "
    }
    sectionEdit.insert(pos, continuation)
    sectionEdit.cursorPosition = pos + continuation.length
  }

  // A read-only TextEdit rather than a Text, so the same highlighter that
  // styles the writing styles the heading: its `#` dimmed, the title bold, at
  // the writing size. It's also a line the arrows stop on, as a heading is
  // in any markdown file, which is what makes a folded section reachable
  // from the keyboard: Return there folds and unfolds it. A click folds
  // too, but doesn't put the caret on the heading by itself (toggle()
  // decides where it goes).
  TextEdit {
    id: sectionHeading
    width: section.width
    readOnly: true
    activeFocusOnPress: false
    // Read-only turns caret movement off; this turns it back on. The caret
    // itself is headingCaret below.
    selectByKeyboard: true
    text: "# " + section.title
    textFormat: TextEdit.PlainText
    wrapMode: TextEdit.Wrap
    color: Color.popups.text
    font.family: Style.font.family
    font.pointSize: section.pointSize
    opacity: section.open ? 1 : 0.5
    onCursorRectangleChanged: section.caretMoved(sectionHeading)
    onActiveFocusChanged: section.caretMoved(sectionHeading)
    Keys.onPressed: function(event) { section.keyPressed(sectionHeading, event) }
    Keys.onReturnPressed: section.toggle(true)
    Keys.onEnterPressed: section.toggle(true)

    Highlight { target: sectionHeading }

    // Qt paints no caret on a read-only field, built-in or cursorDelegate,
    // whatever cursorVisible says -- verified: focused, cursorVisible true,
    // no caret in the screenshot and no delegate item created. So the
    // heading draws its own where Qt says the caret is: the built-in one's
    // width and colour, blinking at the system's rate (solid when blinking
    // is off), and solid again on every move (caretMoved()).
    Rectangle {
      id: headingCaret
      property bool lit: true
      x: sectionHeading.cursorRectangle.x
      y: sectionHeading.cursorRectangle.y
      width: 1 // check: allow-px the built-in caret's width, one device pixel
      height: sectionHeading.cursorRectangle.height
      color: Color.popups.text
      visible: sectionHeading.activeFocus && lit

      Timer {
        id: blink
        interval: Qt.styleHints.cursorFlashTime / 2
        // A flash time of 0 means don't blink; a 0 ms repeating timer
        // would spin instead.
        running: sectionHeading.activeFocus && Qt.styleHints.cursorFlashTime > 0
        repeat: true
        onTriggered: headingCaret.lit = !headingCaret.lit
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: section.toggle(false)
    }
  }

  TextEdit {
    id: sectionEdit
    visible: section.open
    width: section.width
    // An empty TextEdit is as tall as the font, not as a line: Qt sizes it
    // off the font when there's no text, and the highlighter's line spacing
    // only exists on a line with text in it -- measured: 27 empty, 36 with
    // one letter, so the first letter pushed every section below it down.
    // Held to one spaced line instead, measured off the heading, which is
    // set in the same size and spacing.
    height: length > 0 ? implicitHeight : sectionHeading.contentHeight / sectionHeading.lineCount
    text: section.text
    wrapMode: TextEdit.Wrap
    textFormat: TextEdit.PlainText
    color: Color.popups.text
    font.family: Style.font.family
    // The journal's writing size, not UI chrome's: this is the one thing on
    // screen you're meant to be focused on.
    font.pointSize: section.pointSize
    selectionColor: Util.alpha(Color.accent, 0.12)
    selectedTextColor: Color.popups.text
    persistentSelection: true
    selectByMouse: true
    // Kept in step both ways, and only when the two differ: that leaves the
    // caret alone when the engine's copy catches up with an edit made here.
    // The binding above gives the starting text; the section's own
    // onTextChanged below brings in later changes from the engine (cleared
    // for the next run, a restore), which a binding a user has typed into
    // can't be relied on for.
    onTextChanged: if (sectionEdit.text !== section.text) section.edited(sectionEdit.text)
    onCursorRectangleChanged: section.caretMoved(sectionEdit)
    onActiveFocusChanged: section.caretMoved(sectionEdit)
    Keys.onPressed: function(event) { section.keyPressed(sectionEdit, event) }
    Keys.onReturnPressed: function(event) { section.continueList(event) }

    Highlight { target: sectionEdit }
  }

  onTextChanged: if (sectionEdit.text !== section.text) sectionEdit.text = section.text
}
