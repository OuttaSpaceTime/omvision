import QtQuick

import "../lib"
import "../../Parser.js" as Parser

// The base type of every whole-app test (tests/app/tst_*.qml): a QsTestCase
// (tests/lib/QsTestCase.qml, which has the runner, the result lines and the
// clicking, typing and file helpers) loaded inside the running app.
//
// omvision.qml's test hook (OMVISION_TEST=<file>) loads the file, the way
// ShotDriver is for screenshots, so it clicks and types into the real
// screens, and the real write paths put real bytes on disk -- in a throwaway
// HOME that bin/test seeded from tests/fixtures/home.
//
// What a test file gets, besides QsTestCase's helpers:
//   properties set by the hook: app (App.qml: app.notes, app.nav and the
//     open dialog), journal,
//     goalDetail, coaching (the screens), target (the window's content item,
//     the tree click() searches), window
//   openGoal(slug)                click the goal's row on the Goals screen
//   today                         "journal/<today>.md", the fixture's entry
//   openJournal()                 the Journal screen, on today, its text in
//   dayPath(back)                 the journal file `back` days before today
//   addDays({back: text})         write older days, wait until the journal
//                                 lists them; returns back -> path
//
// Before every test the fixture files are put back and the app is waited on
// until it shows them again, so each test starts from the same notes whatever
// the previous one wrote. The screen is set back to Goals. In-memory state the
// app keeps across screens (an open journal day's buffer, say) is not reset:
// tests that depend on it get a file, and so a fresh app, of their own.
QsTestCase {
  id: base

  // ---- set by omvision.qml's test hook ------------------------------------
  // All six must exist: the hook passes them without checking. target and
  // window are QsTestCase's.
  property var app: null
  property var journal: null
  property var goalDetail: null
  property var coaching: null

  // Called the moment the hook hands over the app, before its files have
  // loaded (they load on the event loop, and this runs inside the hook's
  // setSource(), as it sets the initial properties). The tests themselves
  // start a turn later. For a file that needs to act before anything is read.
  function started() {}

  onAppChanged: if (app) base.started()

  // The paper behind the screens, for the failure screenshots: this item
  // sits behind the whole app (the hook gives it z -1, as the screenshot
  // driver has), and without it a grab has black where the window's own
  // colour would be. A plain property of the window, so no Theme import.
  Rectangle {
    anchors.fill: parent
    color: base.window ? base.window.color : "white"
  }

  // ---- the journal --------------------------------------------------------------
  // Today's entry: the fixture's journal/TODAY.md, installed under today's
  // date by seed-home.sh.
  readonly property string today: "journal/" + Parser.dayKey(new Date()) + ".md"

  // The open day carries over from the last test, so this opens today
  // rather than trusting the journal to be on it.
  function openJournal() {
    base.app.nav.screen = "journal"
    base.journal.openToday()
    tryCompare(base.journal, "bufferText", fixtureText(base.today), 5000)
  }

  function dayPath(back) {
    var d = new Date()
    d.setDate(d.getDate() - back)
    return notesPath("journal/" + Parser.dayKey(d) + ".md")
  }

  // days: { daysBack: text }. Writes them all, then waits once for the
  // journal's next listing to show them, rather than a poll per file.
  // Returns daysBack -> path.
  function addDays(days) {
    var paths = {}
    for (let back in days) {
      paths[back] = dayPath(back)
      writeFile(paths[back], days[back])
    }
    tryVerify(function() {
      for (let b in days) {
        const e = base.journal.findEntry(paths[b])
        if (e === null || e.content !== days[b]) return false
      }
      return true
    }, 8000, "the journal lists the new days")
    return paths
  }

  // ---- fixture reset --------------------------------------------------------------
  function resetFixture() {
    resetHome()

    // Back to the Goals screen, on today, and anything left open closed.
    if (base.goalDetail) {
      base.goalDetail.cancelEditTask()
      base.goalDetail.cancelAddTask()
    }
    base.app.closeDialog()
    base.app.notes.followClock = true
    base.app.notes.now = new Date()
    base.app.nav.screen = "goals"
    mouseMove(base.target, 1, base.target.height - 1)

    tryVerify(function() { return base.appShowsFixture() }, 12000,
              "the app never showed the restored fixture files")
  }

  // Whether every fixture file is what the app has loaded -- goal files,
  // logs and journal days -- and nothing else is.
  function appShowsFixture() {
    var a = base.app.notes
    var slugs = [], journalPaths = []
    var now = new Date()
    for (let rel in base.fixture) {
      const text = base.fixture[rel]
      let m = rel.match(/^goals\/(.+)\.log\.md$/)
      if (m) {
        const g = a.goalsData[m[1]]
        if (!g || JSON.stringify(g.logEntries) !== JSON.stringify(Parser.parseLogEntries(text, now))) return false
        continue
      }
      m = rel.match(/^goals\/(.+)\.md$/)
      if (m) {
        slugs.push(m[1])
        const g2 = a.goalsData[m[1]]
        if (!g2 || JSON.stringify(g2.meta) !== JSON.stringify(Parser.parseGoalFile(text))) return false
        continue
      }
      if (/^journal\//.test(rel)) {
        journalPaths.push(notesPath(rel))
        if (a.journalContents[notesPath(rel)] !== text) return false
      }
    }
    if (JSON.stringify(a.goalSlugs) !== JSON.stringify(slugs.sort())) return false
    var listed = a.journalFiles.map(function(f) { return f.path }).sort()
    return JSON.stringify(listed) === JSON.stringify(journalPaths.sort())
  }

  // Clicks the goal's row on the Goals screen and waits for its detail.
  function openGoal(slug) {
    base.app.nav.screen = "goals"
    var row = item("goalRow:" + slug)
    settle(row)
    // Near the row's left edge: the edit pencil sits at its right.
    mouseMove(row, 10, row.height / 2)
    mouseClick(row, 10, row.height / 2)
    tryVerify(function() {
      return base.goalDetail.visible && base.goalDetail.slug === slug && base.goalDetail.meta !== null
    }, base.timeout, "goal " + slug + " did not open")
  }
}
