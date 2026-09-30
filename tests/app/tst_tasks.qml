import QtQuick

// Tasks on the Goal detail screen, driven by real clicks and keys and
// checked on disk. The fixture goal is tests/fixtures/home/Notes/Omvision/
// goals/write-the-report.md: three tasks, the first one done.
OmvisionTest {
  name: "tasks"

  readonly property string goal: "goals/write-the-report.md"

  // The fixture goal file with one exact edit, the whole file compared: an
  // edit that also moved a byte somewhere else must fail.
  function edited(from, to) {
    var text = fixtureText(goal)
    verify(text.indexOf(from) !== -1, "fixture has " + JSON.stringify(from))
    return text.replace(from, to)
  }

  // Opens task `index`'s inline edit with its pencil and waits for the field.
  function startEditing(index) {
    click("taskEdit:" + index)
    tryCompare(goalDetail, "editingTaskIndex", index)
    var field = item("taskEditField:" + index)
    tryVerify(function() { return field.activeFocus }, 3000, "the edit field has the keyboard")
    return field
  }

  // A press on the timeline's empty lower half: part of this screen, away
  // from the task field, and on nothing that acts on a click.
  function clickAway() {
    mouseClick(goalDetail, goalDetail.width * 0.3, goalDetail.height - 40)
  }

  function test_tick_a_task() {
    openGoal("write-the-report")
    click("taskRow:1")
    expectFile(goal, edited("- [ ] Draft the summary", "- [x] Draft the summary"))
    tryCompare(goalDetail, "tasksDone", 2)
  }

  function test_edit_a_task_and_click_away() {
    openGoal("write-the-report")
    var field = startEditing(1)
    compare(field.text, "Draft the summary", "the field starts with the task's text, without its ≈3")
    key(Qt.Key_A, Qt.ControlModifier)
    type("Draft the intro")
    compare(goalDetail.editTaskText, "Draft the intro")
    clickAway()
    // Writer.editTask replaces only the text: the ≈3 and its alignment
    // spaces stay as they were.
    expectFile(goal, edited("- [ ] Draft the summary   ≈3", "- [ ] Draft the intro   ≈3"))
    tryCompare(goalDetail, "editingTaskIndex", -1)
  }

  // Emptying a task and saving deletes it, and every task below moves up an
  // index. The click that saved it is swallowed: passed on, its toggle would
  // be queued behind the delete and tick the task *after* the one clicked.
  // So the first task is emptied and the second clicked -- with the last
  // one clicked, the shifted index would be out of range and the stray tick
  // would be refused anyway, hiding the bug.
  function test_empty_a_task_and_click_another() {
    openGoal("write-the-report")
    startEditing(0)
    key(Qt.Key_A, Qt.ControlModifier)
    key(Qt.Key_Backspace)
    compare(goalDetail.editTaskText, "")
    click("taskRow:1")
    var want = edited("- [x] Collect the numbers\n", "")
    expectFile(goal, want)
    wait(1000)
    compare(readFile(goal), want, "the click on the next task did not tick it")
    tryCompare(goalDetail, "editingTaskIndex", -1)
  }

  function test_escape_writes_nothing() {
    openGoal("write-the-report")
    startEditing(1)
    type(" and the appendix")
    key(Qt.Key_Escape)
    tryCompare(goalDetail, "editingTaskIndex", -1)
    expectFileUnchanged(goal, 1500)
    compare(goalDetail.tasks[1].text, "Draft the summary")
  }

  function test_add_a_task() {
    openGoal("write-the-report")
    click("addTaskButton")
    tryCompare(goalDetail, "addingTask", true)
    var field = item("addTaskField")
    tryVerify(function() { return field.activeFocus }, 3000, "the add field has the keyboard")
    type("call the printer")
    key(Qt.Key_Return)
    expectFile(goal, edited("- [ ] Send it round   ≈1\n", "- [ ] Send it round   ≈1\n- [ ] call the printer\n"))
    tryCompare(goalDetail, "addingTask", false)
    tryVerify(function() { return goalDetail.tasks.length === 4 }, 5000, "the screen shows four tasks")
  }
}
