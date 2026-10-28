import QtQuick

// The break's notes page: one markdown file to the keyboard, in three
// folding sections, with lists that go on and a caret that stays in view.
EngineTest {
  name: "notes"

  // A break with its notes open and the caret in Done.
  function openNotes() {
    toBreak()
    click("takeNotesButton")
    verify(engine.notesOpen)
    tryVerify(function() { return section("done").edit.activeFocus }, 4000, "the caret in Done")
  }

  function test_lists_go_on_and_the_first_letter_moves_nothing() {
    openNotes()
    var nextY = section("left").y
    key(Qt.Key_Minus)
    wait(50)
    compare(section("left").y, nextY, "typing into an empty section doesn't push the next one down")
    type(" one\n")
    compare(engine.doneText, "- one\n- ", "Return continues a list")
    type("\n")
    compare(engine.doneText, "- one\n", "and ends it on an empty item")
    key(Qt.Key_Return, Qt.ShiftModifier)
    compare(engine.doneText, "- one\n\n", "Shift+Return is a plain line break")
  }

  function test_ctrl_g_belongs_to_the_countdown() {
    openNotes()
    key(Qt.Key_G, Qt.ControlModifier)
    verify(!overlay.goalPickerOpen && engine.notesOpen, "Ctrl+G does nothing on the notes page")
  }

  function test_return_on_the_last_line_scrolls_with_it() {
    openNotes()
    var els = section("else")
    var flick = item("notesPage")
    settle(els.edit)
    mouseClick(els.edit, 10, 5)
    verify(els.edit.activeFocus, "the caret in Notes")
    for (let i = 0; i < 20; i++) type("line " + i + "\n")
    wait(50)
    var caret = els.edit.mapToItem(flick, els.edit.cursorRectangle)
    verify(flick.contentY > 0 && caret.y >= 0 && caret.y + caret.height + flick.bottomRoom <= flick.height + 1,
           "the caret stays on screen, clear of the bottom edge: y " + caret.y + " of " + flick.height)
  }

  function test_the_page_fills_the_screen_before_it_scrolls() {
    openNotes()
    var flick = item("notesPage")
    for (let i = 1; i <= 14; i++) type("line " + i + "\n")
    wait(50)
    compare(flick.contentY, 0, "fourteen lines don't scroll the page")
    for (let i = 15; i <= 24; i++) type("line " + i + "\n")
    wait(50)
    var edit = section("done").edit
    var bottom = edit.mapToItem(flick, edit.cursorRectangle).y + edit.cursorRectangle.height
    verify(flick.contentY > 0 && bottom <= flick.height, "past the bottom it scrolls, the caret in view: " + bottom)
  }

  function test_headings_fold() {
    openNotes()
    var done = section("done")
    compare(done.heading.text, "# Done", "a markdown heading")
    mouseClick(done.heading, 20, done.heading.height / 2)
    verify(!done.open && !done.edit.visible, "a click folds its section")
    mouseClick(done.heading, 20, done.heading.height / 2)
    verify(done.open && done.edit.activeFocus, "and unfolds it, caret inside")
    type("x")
    mouseClick(done.heading, 20, done.heading.height / 2)
    verify(!done.open && done.heading.activeFocus, "folding from inside the text leaves the caret on the heading")
  }

  // The arrows run through the page as through one markdown file, stopping
  // on the headings and skipping folded text.
  function test_the_arrows_run_through_the_page() {
    openNotes()
    var done = section("done"), left = section("left"), els = section("else")
    type("- one\ntwo")
    done.edit.cursorPosition = 3
    key(Qt.Key_Up)
    verify(done.heading.activeFocus, "Up off a section's first line lands on its heading")
    // Qt paints no caret on a read-only field, so the heading draws its own.
    var caret = null
    for (let i = 0; i < done.heading.children.length; i++)
      if (done.heading.children[i].lit !== undefined) caret = done.heading.children[i]
    verify(caret && caret.visible && caret.height > 0, "the heading shows a caret")
    key(Qt.Key_Up)
    verify(done.heading.activeFocus, "Up on the first heading stays there")
    key(Qt.Key_Down)
    verify(done.edit.activeFocus && done.edit.cursorPosition === 3, "Down goes back, same column")
    key(Qt.Key_Down); key(Qt.Key_Down)
    verify(left.heading.activeFocus, "Down off a section's last line lands on the next heading")
    key(Qt.Key_Down); key(Qt.Key_Down)
    verify(els.heading.activeFocus, "and on through an empty section")
    key(Qt.Key_Up)
    verify(left.edit.activeFocus, "Up goes back into it")
    key(Qt.Key_Up)
    type("x")
    verify(left.heading.activeFocus && left.heading.text === "# Next" && engine.leftText === "",
           "typing on a heading changes nothing")
    key(Qt.Key_Return)
    verify(!left.open && left.heading.activeFocus, "Return on a heading folds it, caret stays")
    key(Qt.Key_Down)
    verify(els.heading.activeFocus, "Down skips folded text")
    key(Qt.Key_Up); key(Qt.Key_Return)
    verify(left.open && left.heading.activeFocus, "Return unfolds it again")
    left.heading.cursorPosition = 0
    key(Qt.Key_Left)
    verify(done.edit.activeFocus && done.edit.cursorPosition === done.edit.length,
           "Left at a line's start goes to the end of the line before")
    key(Qt.Key_Right)
    verify(left.heading.activeFocus && left.heading.cursorPosition === 0, "Right at the end goes to the start of the next")
    key(Qt.Key_Left)
    done.edit.cursorPosition = 0
    key(Qt.Key_Up, Qt.ShiftModifier)
    verify(done.edit.activeFocus, "Shift+Up stays in the field")
  }

  function test_leaving_the_notes_keeps_them_and_writes_nothing() {
    openNotes()
    type("kept")
    var before = allEntries(dayLog()).length
    key(Qt.Key_Escape)
    verify(!engine.notesOpen, "Escape goes back to the countdown")
    compare(engine.phase, "break")
    click("takeNotesButton")
    tryCompare(section("done").edit, "text", "kept")
    click("notesBackButton")
    verify(!engine.notesOpen, "and so does the back arrow")
    wait(300)
    compare(allEntries(dayLog()).length, before, "nothing is written until the break ends")
  }
}
