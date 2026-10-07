import QtQuick

// The Coaching screen's `start in kitty`: Goal detail's `Coach this goal`
// leads here with that goal picked, and the button opens a session for the
// goal and method on screen. bin/test puts tests/bin first on PATH, so the
// `kitty` the app launches is a stub that writes its argv to the test HOME;
// no window opens and claude never runs.
OmvisionTest {
  name: "coaching"

  readonly property string argvFile: home + "/kitty.argv"

  function test_start_opens_the_picked_goal_in_kitty() {
    // Clicking start with the real kitty on PATH would open a window with a
    // live claude session in it, so make sure it's the stub first.
    var which = run(["/usr/bin/sh", "-c", "command -v kitty"])
    compare(which.out.trim(), testDir.replace(/\/app$/, "/bin/kitty"), "kitty is the test stub")

    openGoal("write-the-report")
    click("coachButton")
    tryCompare(app, "currentScreen", "coaching")
    click("coachMethod:polya")
    click("coachStartButton")

    expectFile(argvFile, [
      "--directory", home + "/Notes/Omvision", "--title", "coach · write-the-report",
      "claude", "/ompom-coach write-the-report --method polya", ""
    ].join("\n"))
    // What `copy` would hand over is the same command, the prompt quoted.
    compare(coaching.command, "claude '/ompom-coach write-the-report --method polya'")
    // Starting a session writes nothing itself; the skill does, later.
    expectFileUnchanged("goals/write-the-report.md", 500)
  }
}
