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
}
