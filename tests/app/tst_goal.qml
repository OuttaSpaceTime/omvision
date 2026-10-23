import QtQuick

// Closing and reopening a goal from its detail screen: one `status:` line
// changes on disk and nothing else does.
OmvisionTest {
  name: "goal"

  readonly property string goal: "goals/write-the-report.md"

  // Ending a goal through the cancel dialog: `status: cancelled`, and a
  // `## Cancelled` note at the end with the reason picked and the takeaway
  // typed. The dialog closes once the file says so.
  function test_cancel_a_goal() {
    openGoal("write-the-report")
    click("cancelGoalButton")
    tryCompare(app, "dialog", "cancel")
    type("Smaller pieces.") // the takeaway field has the keyboard
    click("endGoalButton")
    tryCompare(app, "dialog", "")
    var text = fixtureText(goal)
    expectFile(goal, function(now) {
      var head = text.replace("status: active\n", "status: cancelled\n").replace(/\n+$/, "")
      return now.indexOf(head + "\n\n## Cancelled\n### ") === 0
        && /\nreason: Not relevant any more\ntakeaway: Smaller pieces\.\n$/.test(now)
    })
    tryVerify(function() { return goalDetail.meta && goalDetail.meta.status === "cancelled" }, 5000,
              "the screen shows the goal cancelled")
  }

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
    tryVerify(function() { return app.notes.goalsData["write-the-report"].meta.focusable === false }, 5000,
              "the app reads the goal back as not focusable")

    toggleFocusable()
    expectFile(goal, text)
  }

  // The same box on a new goal: unticked, the file is created with
  // `focusable: no`. The create path once passed every field but this one
  // on, so the box did nothing there.
  function test_create_a_goal_not_focusable() {
    app.openDialog("goal")
    tryCompare(app, "dialog", "goal")
    type("Train legs")
    click("goalFocusableToggle")
    key(Qt.Key_Return)
    tryCompare(app, "dialog", "")
    expectFile("goals/train-legs.md",
               "---\ntitle: Train legs\nwhy: \nstatus: active\nfocusable: no\n---\n## Tasks\n")
  }

  function toggleFocusable() {
    openGoal("write-the-report")
    click("editGoalButton")
    tryCompare(app, "dialog", "goal")
    click("goalFocusableToggle")
    key(Qt.Key_Return)
    tryCompare(app, "dialog", "")
  }
}
