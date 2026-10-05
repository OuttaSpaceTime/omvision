import QtQuick
import Quickshell

// Screenshot driver -- only ever loaded when OMVISION_SHOT_DIR is set, which
// only bin/shot does. It drives the real app (real data from ~/Notes, real
// screens, real sizes) to one state, grabs the window to PNGs and quits.
// Run under QT_QPA_PLATFORM=offscreen, so no window ever appears.
//
// This replaced a recipe that launched a real window (setsid, then hyprctl
// and grim to find and capture it). Those windows outlived the shell that
// started them and piled up on the user's desktop, and untargeted hyprctl
// dispatches kept landing on the user's terminal. See docs/layout-rules.md,
// "Screenshotting".
//
// It paints the paper behind the app, too: grabToImage captures the item, not
// the window, so anything transparent (the journal canvas) would otherwise
// come out black.
Rectangle {
  id: driver

  // Set by omvision.qml.
  property var app: null         // the ShellRoot: currentScreen, openGoalSlug, toggleSidebar()
  property Item target: null     // what to grab: the window's content
  property var journal: null     // JournalScreen, for its day list
  property var goalDetail: null  // GoalDetailScreen, which owns the cancel dialog's state

  readonly property string outDir: Quickshell.env("OMVISION_SHOT_DIR")
  readonly property string screen: Quickshell.env("OMVISION_SHOT_SCREEN") || "goals"
  readonly property string action: Quickshell.env("OMVISION_SHOT_ACTION") || ""
  readonly property int settleMs: parseInt(Quickshell.env("OMVISION_SHOT_SETTLE") || "1500")
  // Milliseconds after the action (or after settling, with no action) at
  // which to grab. Several values catch an animation part-way.
  readonly property var frames: String(Quickshell.env("OMVISION_SHOT_FRAMES") || "0")
                                  .split(",").map(function(s) { return parseInt(s) })
                                  .filter(function(n) { return n >= 0 })

  property int frameIndex: 0
  property real t0: 0

  color: Theme.paper

  function nameFor(ms) {
    var base = driver.screen + (driver.action !== "" ? "-" + driver.action : "")
    return base.replace(/[^A-Za-z0-9_-]+/g, "_") + "-" + ms + "ms.png"
  }

  function applyScreen() {
    if (driver.screen.indexOf("goal:") === 0) {
      driver.app.openGoalSlug = driver.screen.slice(5)
      driver.app.currentScreen = "goalDetail"
    } else {
      driver.app.currentScreen = driver.screen
    }
  }

  function runAction() {
    if (driver.action === "sidebar") driver.app.toggleSidebar()
    else if (driver.action === "days" && driver.journal) driver.journal.openList(!driver.journal.listOpen)
    // The dialogs only open -- nothing is typed or submitted, so nothing is
    // written. Opening one is the same call its button makes.
    else if (driver.action === "event") driver.app.openEventDialog(driver.app.currentScreen === "goalDetail" ? driver.app.openGoalSlug : "")
    else if (driver.action === "newgoal") driver.app.openNewGoalDialog()
    else if (driver.action === "cancel" && driver.goalDetail) driver.goalDetail.cancelDialogOpen = true
    else if (driver.action === "editgoal") driver.app.openEditGoalDialog(driver.app.openGoalSlug)
    else if (driver.action === "edittask" && driver.goalDetail && driver.goalDetail.tasks.length > 0)
      driver.goalDetail.startEditTask(0, driver.goalDetail.tasks[0].text)
    // Types `@` and a query into the journal to show the goal list. The
    // journal's writes are switched off first (typeMentionForShot), so the
    // day's file is never touched.
    else if (driver.action.indexOf("mention") === 0 && driver.journal)
      driver.journal.typeMentionForShot(driver.action.slice("mention".length).replace(/^:/, ""))
    // Turns the journal one page back or forward, the way `‹`/`›` do. Writes
    // are switched off first: leaving a day flushes it, and although an
    // unchanged day is never written, a shot has no business finding out.
    else if ((driver.action === "prevday" || driver.action === "nextday") && driver.journal) {
      driver.journal.writesDisabled = true
      driver.journal.turnPage(driver.action === "prevday" ? -1 : 1)
    }
    // Opens the first goal the journal's tags name, the way clicking it does:
    // from the tags the highlighter styled, so only one a click could open.
    else if (driver.action === "opentag" && driver.journal) {
      if (driver.journal.tagSpans.length > 0) driver.journal.openGoal(driver.journal.tagSpans[0].slug)
    }
    else if (driver.action !== "") console.warn("shot: unknown action", driver.action)
  }

  function scheduleNext() {
    if (driver.frameIndex >= driver.frames.length) { Qt.quit(); return }
    var wait = driver.frames[driver.frameIndex] - (Date.now() - driver.t0)
    grabTimer.interval = Math.max(0, wait)
    grabTimer.start()
  }

  // The screen is switched only after the data has loaded, the way a click
  // in a running app would, so every screen is drawn from its real data.
  // Switching at startup used to leave the journal blank for good -- it
  // never picked up a day's text that arrived after it opened. That is
  // fixed (JournalScreen.syncBufferFromDisk), but a shot taken before the
  // files are read would still show whatever had loaded by then.
  Timer {
    interval: driver.settleMs
    running: true
    onTriggered: {
      driver.applyScreen()
      actionTimer.start()
    }
  }

  // Lets the new screen lay out, and entering the journal finish hiding the
  // sidebar, before the action and the frame clock start.
  Timer {
    id: actionTimer
    interval: 400
    onTriggered: {
      driver.t0 = Date.now()
      driver.runAction()
      driver.scheduleNext()
    }
  }

  Timer {
    id: grabTimer
    repeat: false
    onTriggered: {
      var ms = driver.frames[driver.frameIndex]
      var actual = Math.round(Date.now() - driver.t0)
      driver.target.grabToImage(function(result) {
        var path = driver.outDir + "/" + driver.nameFor(ms)
        if (result.saveToFile(path)) console.log("shot:", path, "(at " + actual + "ms)")
        else console.warn("shot: could not write", path)
        driver.frameIndex++
        driver.scheduleNext()
      })
    }
  }
}
