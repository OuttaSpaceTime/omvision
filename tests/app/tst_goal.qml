import QtQuick

// Closing and reopening a goal from its detail screen: one `status:` line
// changes on disk and nothing else does.
OmvisionTest {
  name: "goal"

  readonly property string goal: "goals/write-the-report.md"

  function test_close_and_reopen_a_goal() {
    openGoal("write-the-report")
    click("closeGoalButton")
    var text = fixtureText(goal)
    verify(text.indexOf("status: active\n") !== -1)
    expectFile(goal, text.replace("status: active\n", "status: done\n"))
    tryVerify(function() { return goalDetail.meta && goalDetail.meta.status === "done" }, 5000,
              "the screen shows the goal done")

    // A done goal offers Reopen instead of Close, and reopening it puts
    // back exactly the file it started as.
    click("reopenGoalButton")
    expectFile(goal, text)
    tryVerify(function() { return goalDetail.meta && goalDetail.meta.status === "active" }, 5000,
              "the screen shows the goal active again")
    item("closeGoalButton")
  }

  // The Edit goal dialog's "can be focused on at the laptop" box: unticking
  // it adds one `focusable: no` line, ticking it again puts back the file
  // as it was.
  function test_mark_a_goal_not_focusable() {
    var text = fixtureText(goal)
    // Before the closing fence, after done_by.
    var off = text.replace("done_by: 2026-10-09\n", "done_by: 2026-10-09\nfocusable: no\n")
    verify(off !== text)
    toggleFocusable()
    expectFile(goal, off)
    tryVerify(function() { return app.goalsData["write-the-report"].meta.focusable === false }, 5000,
              "the app reads the goal back as not focusable")

    toggleFocusable()
    expectFile(goal, text)
  }

  function toggleFocusable() {
    openGoal("write-the-report")
    click("editGoalButton")
    tryCompare(app, "newGoalDialogOpen", true)
    click("goalFocusableToggle")
    key(Qt.Key_Return)
    tryCompare(app, "newGoalDialogOpen", false)
  }
}
