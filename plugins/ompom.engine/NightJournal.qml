import QtQuick
import qs.Commons

import "ListContinue.js" as ListContinue

// The night's page: Omvision's journal for the day (Cycle.js, "the night's
// journal"), set the way the Journal screen sets it -- one centred column at
// the writing size, the journal's markdown styling, the caret at the end of
// the day's text, a quiet header and word count -- without the app around
// it: no sidebar, day list or page turns. The text is the engine's
// (journalText); every edit goes back through setJournal(), which saves it
// on a pause in the typing.
Item {
  id: page

  required property var engine
  property real pointSize
  property real columnWidth

  readonly property int wordCount: {
    const t = page.engine.journalText.trim()
    return t === "" ? 0 : t.split(/\s+/).length
  }

  // The page's day as a date, never "Today": a page left open past midnight
  // stays on its day, and a label read off a clock nothing re-evaluates
  // would go on calling it today.
  readonly property string dayLabel: page.engine.journalDay === "" ? ""
    : Qt.formatDate(new Date(page.engine.journalDay + "T00:00:00"), "ddd d MMM")

  // The one way the engine's text reaches the editor, and only when the two
  // differ, so typing (which the engine then catches up with) leaves the
  // caret alone. A `text:` binding as well would put a merged text in first
  // and leave the caret at 0. When they differ the page has been read, or
  // merged with a save made in Omvision (Cycle.mergeJournal()); either way
  // writing goes on at the end, where the Journal screen opens a day too.
  Connections {
    target: page.engine
    function onJournalTextChanged() {
      if (editor.text === page.engine.journalText) return
      editor.text = page.engine.journalText
      editor.cursorPosition = editor.length
    }
    function onJournalLoadedChanged() {
      if (page.engine.journalLoaded) editor.cursorPosition = editor.length
    }
  }
  onVisibleChanged: if (visible) editor.forceActiveFocus()

  Flickable {
    id: canvas
    objectName: "journalPage"
    anchors.fill: parent
    clip: true
    // Half a screen of slack under the last line, so writing stays clear of
    // the bottom edge.
    contentHeight: Math.max(height, editor.y + editor.height + height / 2)

    function ensureVisible(r) {
      const top = editor.y + r.y - header.height
      const bottom = editor.y + r.y + r.height + Style.space(32)
      if (top < contentY) contentY = Math.max(0, top)
      else if (bottom > contentY + height) contentY = bottom - height
    }

    // A click anywhere on the paper is writing, at the end of the day.
    MouseArea {
      width: canvas.width
      height: canvas.contentHeight
      cursorShape: Qt.IBeamCursor
      onClicked: {
        editor.forceActiveFocus()
        editor.cursorPosition = editor.length
      }
    }

    TextEdit {
      id: editor
      objectName: "journalEditor"
      x: Math.round((canvas.width - width) / 2)
      y: header.height + Style.space(48)
      width: Math.min(page.columnWidth, canvas.width)
      // Nothing typed before the day's text is in could be saved without
      // writing over it (Cycle.journalReadExited()).
      readOnly: !page.engine.journalLoaded
      wrapMode: TextEdit.Wrap
      textFormat: TextEdit.PlainText
      color: Color.popups.text
      font.family: Style.font.family
      font.pointSize: page.pointSize
      selectionColor: Util.alpha(Color.accent, 0.12)
      selectedTextColor: Color.popups.text
      selectByMouse: true
      persistentSelection: true
      onTextChanged: if (text !== page.engine.journalText) page.engine.setJournal(text)
      onCursorRectangleChanged: if (activeFocus) canvas.ensureVisible(cursorRectangle)
      // Return in a list goes on with it, as in the journal; Shift+Return,
      // and Return anywhere else, is a plain line break.
      Keys.onReturnPressed: function(event) { event.accepted = !(event.modifiers & Qt.ShiftModifier) && ListContinue.applyTo(editor) }
      Keys.onEnterPressed: function(event) { event.accepted = !(event.modifiers & Qt.ShiftModifier) && ListContinue.applyTo(editor) }

      Loader {
        source: "NoteHighlighterHost.qml"
        onLoaded: {
          item.basePointSize = page.pointSize
          item.document = editor.textDocument
        }
      }
    }
  }

  // Opaque, as the Journal screen's header is, so lines scrolled past go
  // behind it; it takes its own clicks for the same reason.
  Rectangle {
    id: header
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: Style.space(56)
    color: Color.background

    MouseArea { anchors.fill: parent }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(16)

      OverlayButton {
        objectName: "journalBackButton"
        label: "←"
        implicitHeight: Style.space(22)
        implicitWidth: Style.space(28)
        onActivated: page.engine.closeNotes()
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: page.dayLabel
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    // The night goes on while the page is open, so its countdown stays in
    // sight, where the Journal screen has its page turns.
    Text {
      anchors.right: parent.right
      anchors.rightMargin: Style.space(24)
      anchors.verticalCenter: parent.verticalCenter
      text: page.engine.countdownLabel + " until " + page.engine.wakeLabel
      color: Util.alpha(Color.popups.text, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // The word count, and the one error, bottom-right on their own patch of
  // background, as on the Journal screen.
  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: status.implicitWidth + Style.space(48)
    height: status.implicitHeight + Style.space(32)
    color: Color.background

    Column {
      id: status
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Style.space(16)

      // A failed read leaves the page unread: only opening it again helps.
      // A failed save is tried again by leaving the page, or more typing.
      Text {
        objectName: "journalNotSaved"
        anchors.right: parent.right
        visible: page.engine.journalFailed
        text: page.engine.journalLoaded ? "Journal not saved — Esc tries again"
                                        : "Journal couldn't be read — Esc, then Take notes, tries again"
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        text: page.wordCount === 1 ? "1 word" : page.wordCount + " words"
        color: Util.alpha(Color.popups.text, 0.6)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
