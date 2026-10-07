import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

import "../../Parser.js" as Parser

// The base type of every whole-app test (tests/app/tst_*.qml).
//
// A test file is loaded *inside the running app* by omvision.qml's test hook
// (OMVISION_TEST=<file>), the way ShotDriver is for screenshots, so it clicks
// and types into the real screens, and the real write paths put real bytes
// on disk -- in a throwaway HOME that bin/test seeded from
// tests/fixtures/home. Qt's own qmltestrunner can't do this: it can't load
// Quickshell's modules, which only exist inside the `qs` binary.
//
// What a test file gets:
//   properties set by the hook: app (omvision.qml's root), journal,
//     goalDetail, coaching (the screens), target (the window's content item,
//     the tree click() searches), window
//   openGoal(slug)                click the goal's row on the Goals screen
//   click(objectName)             hover it, wait until it can be clicked,
//                                 click its centre
//   item(objectName)              the visible item with that name, waiting
//                                 for it to appear
//   type(text), key(key, mods)    real key events to the focused item
//   notesPath(rel)                "$HOME/Notes/Omvision/" + rel
//   readFile(rel)                 the file's text now, or null if missing
//   writeFile(rel, text)          write a file the way an outside editor
//                                 would (the reset deletes what isn't fixture)
//   today                         "journal/<today>.md", the fixture's entry
//   openJournal()                 the Journal screen, on today, its text in
//   dayPath(back)                 the journal file `back` days before today
//   addDays({back: text})         write older days, wait until the journal
//                                 lists them; returns back -> path
//   expectFile(rel, want)         wait until the file says `want` (a string,
//                                 or a function(text) -> bool)
//   expectFileUnchanged(rel)      the file stays as the fixture left it
//   fixtureText(rel)              what the fixture put there
// plus everything TestCase has: compare, verify, tryCompare, tryVerify,
// mouseClick, mouseMove, keyClick, wait, expectFailContinue, skip, ...
//
// Before every test the fixture files are put back (tests/app/seed-home.sh)
// and the app is waited on until it shows them again, so each test starts
// from the same notes whatever the previous one wrote. The screen is set back
// to Goals. In-memory state the app keeps across screens (an open journal
// day's buffer, say) is not reset: tests that depend on it get a file, and
// so a fresh app, of their own.
//
// Results go to stdout, one line per test, for bin/test to read:
//   PASS <file>::<test>
//   FAIL <file>::<test>: <what failed, where>      (+ a screenshot)
//   XFAIL <file>::<test>: <why>   known failure, counted as passing
//   SKIP <file>::<test>: <why>
// then `DONE <file> <passed> passed, <failed> failed, ...` and the app quits
// with 0, or 1 if anything failed.
TestCase {
  id: base

  // Never started by Qt's own scheduler (that needs qmltestrunner's
  // QTestRootObject to report a shown window, which nothing sets here):
  // runAll() below drives the tests once the hook has handed over the app.
  when: false

  // ---- set by omvision.qml's test hook ------------------------------------
  // All six must exist: the hook assigns them without checking.
  property var app: null
  property var journal: null
  property var goalDetail: null
  property var coaching: null
  property Item target: null
  property var window: null

  // A per-file default for how long a helper waits before giving up.
  property int timeout: 8000

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string testDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string fixtureHome: Quickshell.env("OMVISION_TEST_FIXTURES")
                                        || testDir.replace(/\/app$/, "/fixtures/home")
  readonly property string outDir: Quickshell.env("OMVISION_TEST_OUT") || home
  // bin/test can run one test of a file: OMVISION_TEST_ONLY=test_name.
  readonly property string only: Quickshell.env("OMVISION_TEST_ONLY") || ""
  readonly property string fileName: String(base.name || "test")

  // Set false in a file whose tests need the app exactly as it started (the
  // journal's first load, say): no fixture reset, and no trip back to the
  // Goals screen, before each test. bin/test seeded HOME before the start.
  property bool resetBeforeEachTest: true

  // Called the moment the hook hands over the app, before its files have
  // loaded (they load on the event loop, and this runs inside the hook's own
  // onLoaded). The tests themselves start a turn later. For a file that
  // needs to act before anything is read.
  function started() {}

  onAppChanged: if (app) { base.started(); startTimer.start() }

  // The paper behind the screens, for the failure screenshots: this item
  // sits behind the whole app (the hook gives it z -1, as the screenshot
  // driver has), and without it a grab has black where the window's own
  // colour would be. A plain property of the window, so no Theme import.
  Rectangle {
    anchors.fill: parent
    color: base.window ? base.window.color : "white"
  }

  Timer {
    id: startTimer
    interval: 0
    onTriggered: base.runAll()
  }

  // ---- the qtest_results workaround ----------------------------------------
  // TestCase's assertions report through an internal object, qtest_results.
  // Its default is a TestResult, which logs through QtTest's C++ logger --
  // set up by qmltestrunner's main() and by nothing in `qs`. So the property
  // is pointed at this stand-in instead: it records failures for runAll()
  // and borrows the real TestResult only for its helpers that don't log
  // (wait, sleep). This is the one place that knows TestCase's internals:
  // `qtest_results` and the methods it calls on it are private API
  // (QtTest/TestCase.qml, Qt 6.11), so a Qt upgrade that changes them breaks
  // this file and nothing else. Rejected: running tests through Qt's own
  // scheduler (qtest_run) -- it drives the logger at every step, so the
  // stand-in would have to fake all of it, not just the assertions.
  qtest_results: results

  TestResult { id: realResults }

  QtObject {
    id: results

    // Per test.
    property var failures: []
    property var xfails: []
    property string skipMessage: ""
    property string pendingXfail: ""
    property bool pendingXfailAborts: false

    property bool failed: failures.length > 0
    property bool skipped: skipMessage !== ""

    function begin() {
      failures = []; xfails = []; skipMessage = ""; pendingXfail = ""; pendingXfailAborts = false
    }

    function where(file, line) {
      return file ? " (" + String(file).replace(/^.*\//, "") + ":" + line + ")" : ""
    }

    // One assertion's outcome. Returns what TestCase expects: false stops the
    // test (TestCase throws), true lets it go on.
    function outcome(ok, detail) {
      if (pendingXfail !== "") {
        var why = pendingXfail, aborts = pendingXfailAborts
        pendingXfail = ""
        if (ok) { failures = failures.concat(["XPASS (expected to fail: " + why + "): " + detail]); return true }
        xfails = xfails.concat([why])
        return !aborts
      }
      if (!ok) failures = failures.concat([detail])
      return ok
    }

    function fail(msg, file, line) { outcome(false, (msg || "fail()") + where(file, line)) }
    function verify(cond, msg, file, line) { return outcome(!!cond, "verify failed" + (msg ? ": " + msg : "") + where(file, line)) }
    function compare(ok, msg, act, exp, file, line) {
      return outcome(ok, (msg ? msg + ": " : "") + "got " + act + ", expected " + exp + where(file, line))
    }
    function fuzzyCompare(a, b, delta) { return Math.abs(a - b) <= delta }
    function skip(msg, file, line) { skipMessage = msg || "skipped" }
    function expectFail(tag, msg, file, line) { pendingXfail = msg || "expected failure"; pendingXfailAborts = true; return true }
    function expectFailContinue(tag, msg, file, line) { pendingXfail = msg || "expected failure"; pendingXfailAborts = false; return true }
    function warn(msg, file, line) { console.warn(base.fileName + ": " + msg) }
    function ignoreWarning(msg) {}
    function failOnWarning(msg) {}
    function stringify(v) {
      if (v === undefined) return "undefined"
      if (v === null) return "null"
      if (typeof v === "string") return JSON.stringify(v)
      if (typeof v === "object") { try { return JSON.stringify(v) } catch (e) { return String(v) } }
      return String(v)
    }
    function wait(ms) { realResults.wait(ms) }
    function sleep(ms) { realResults.sleep(ms) }
    function waitForRendering(item, timeout) { realResults.wait(50); return true }
    function isPolishScheduled(item) { return realResults.isPolishScheduled(item) }
    function waitForPolish(item, timeout) { return realResults.waitForPolish(item, timeout) }
  }

  // ---- running ----------------------------------------------------------------
  property var testNames: []

  function testFunctions() {
    var names = []
    for (var p in base) {
      if (p.indexOf("test_") === 0 && typeof base[p] === "function") names.push(p)
    }
    names.sort()
    if (base.only !== "") names = names.filter(function(n) { return n === base.only })
    return names
  }

  function say(line) {
    // console.info goes to stderr with Quickshell's prefix; bin/test reads
    // the line out of that by its leading keyword.
    console.info("[omvision-test] " + line)
  }

  function runAll() {
    var counts = { pass: 0, fail: 0, xfail: 0, skip: 0 }
    if (!safeHome()) {
      say("FAIL " + base.fileName + "::setup: refusing to run: HOME (" + base.home
          + ") is not a test home made by bin/test (a temp dir with .omvision-test-home)")
      say("DONE " + base.fileName + " 0 passed, 1 failed, 0 xfail, 0 skipped")
      Qt.exit(2)
      return
    }
    var names = testFunctions()
    for (var i = 0; i < names.length; i++) {
      var status = runOne(names[i])
      counts[status]++
    }
    say("DONE " + base.fileName + " " + counts.pass + " passed, " + counts.fail + " failed, "
        + counts.xfail + " xfail, " + counts.skip + " skipped")
    Qt.exit(counts.fail > 0 || names.length === 0 ? 1 : 0)
  }

  function runStep(fn) {
    try {
      fn()
    } catch (e) {
      var m = String(e && e.message !== undefined ? e.message : e)
      if (m.indexOf("QtQuickTest::") !== 0)
        results.failures = results.failures.concat(["uncaught exception: " + m
          + (e && e.fileName ? " (" + String(e.fileName).replace(/^.*\//, "") + ":" + e.lineNumber + ")" : "")])
    }
  }

  function runOne(name) {
    results.begin()
    var label = base.fileName + "::" + name
    if (base.resetBeforeEachTest) runStep(function() { base.resetFixture() })
    else runStep(function() { base.readFixture(base.fixtureFiles()) })
    if (!results.failed) runStep(function() { base.init() })
    if (!results.failed && !results.skipped) runStep(function() { base[name]() })
    runStep(function() { base.cleanup() })

    if (results.failed) {
      say("FAIL " + label + ": " + results.failures.join(" | "))
      screenshot(name)
      return "fail"
    }
    if (results.skipped) { say("SKIP " + label + ": " + results.skipMessage); return "skip" }
    if (results.xfails.length > 0) { say("XFAIL " + label + ": " + results.xfails.join(" | ")); return "xfail" }
    say("PASS " + label)
    return "pass"
  }

  function screenshot(name) {
    if (!base.target) return
    var path = base.outDir + "/" + base.fileName + "-" + name + ".png"
    var done = false
    base.target.grabToImage(function(result) {
      if (result.saveToFile(path)) say("SHOT " + path)
      done = true
    })
    for (var t = 0; t < 3000 && !done; t += 50) wait(50)
  }

  // ---- shell commands -----------------------------------------------------------
  Component {
    id: processComponent
    Process {
      id: proc
      property bool finished: false
      property int code: -1
      property string out: ""
      property bool streamDone: false
      stdout: StdioCollector {
        onStreamFinished: { proc.out = text; proc.streamDone = true }
      }
      onExited: function(exitCode, exitStatus) { proc.code = exitCode; proc.finished = true }
    }
  }

  // Runs argv to completion and returns { code, out }. Waits with wait(),
  // which keeps the app's event loop turning meanwhile.
  function run(argv, ms) {
    var p = processComponent.createObject(base, { command: argv })
    p.running = true
    var limit = ms || 10000
    var t = 0
    for (; t < limit && !p.finished; t += 10) wait(10)
    // stdout's end can arrive a turn after the exit.
    for (var s = 0; s < 500 && !p.streamDone; s += 10) wait(10)
    var r = { code: p.finished ? p.code : -1, out: p.out }
    p.destroy()
    return r
  }

  function safeHome() {
    if (base.home === "") return false
    return run(["/usr/bin/test", "-f", base.home + "/.omvision-test-home"]).code === 0
  }

  // ---- files ------------------------------------------------------------------------
  function notesPath(rel) { return base.home + "/Notes/Omvision/" + rel }

  function readFile(rel) {
    var r = run(["/usr/bin/cat", "--", rel.charAt(0) === "/" ? rel : notesPath(rel)])
    return r.code === 0 ? r.out : null
  }

  function writeFile(rel, text) {
    var path = rel.charAt(0) === "/" ? rel : notesPath(rel)
    var r = run(["/usr/bin/sh", "-c", 'printf "%s" "$1" > "$2"', "sh", text, path])
    compare(r.code, 0, "wrote " + path)
  }

  // ---- the journal --------------------------------------------------------------
  // Today's entry: the fixture's journal/TODAY.md, installed under today's
  // date by seed-home.sh.
  readonly property string today: "journal/" + Parser.dayKey(new Date()) + ".md"

  // The open day carries over from the last test, so this opens today
  // rather than trusting the journal to be on it.
  function openJournal() {
    base.app.currentScreen = "journal"
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
    for (var back in days) {
      paths[back] = dayPath(back)
      writeFile(paths[back], days[back])
    }
    tryVerify(function() {
      for (var b in days) {
        var e = base.journal.findEntry(paths[b])
        if (e === null || e.content !== days[b]) return false
      }
      return true
    }, 8000, "the journal lists the new days")
    return paths
  }

  // rel -> text, as the fixture left it at the start of this test.
  property var fixture: ({})

  function fixtureText(rel) {
    var t = base.fixture[rel]
    return t === undefined ? null : t
  }

  // Waits until `rel` says `want`: a string to match exactly, or a function
  // taking the text (null for a missing file) and returning true when it is
  // right. Fails with the last text seen.
  function expectFile(rel, want, ms, msg) {
    var limit = ms || base.timeout
    var ok = function(t) { return typeof want === "function" ? want(t) : t === want }
    var text = readFile(rel)
    for (var t = 0; t < limit && !ok(text); t += 100) { wait(100); text = readFile(rel) }
    if (!ok(text)) {
      qtest_fail((msg ? msg + ": " : "") + rel + " is " + results.stringify(text)
                 + (typeof want === "function" ? "" : ", expected " + results.stringify(want)), 1)
    }
    return text
  }

  // Watches `rel` for `ms` and fails the moment it differs from what the
  // fixture put there. For "this action writes nothing": give a write that
  // shouldn't happen the time it would take if it did.
  function expectFileUnchanged(rel, ms, msg) {
    var want = fixtureText(rel)
    var limit = ms || 1500
    for (var t = 0; t <= limit; t += 100) {
      var text = readFile(rel)
      if (text !== want) {
        qtest_fail((msg ? msg + ": " : "") + rel + " changed to " + results.stringify(text)
                   + ", expected it untouched: " + results.stringify(want), 1)
      }
      wait(100)
    }
  }

  // ---- fixture reset --------------------------------------------------------------
  // Records what each fixture file says now, for fixtureText().
  function readFixture(files) {
    var prefix = base.home + "/Notes/Omvision/"
    var fx = {}
    for (var i = 0; i < files.length; i++) {
      if (files[i].indexOf(prefix) !== 0) continue
      fx[files[i].slice(prefix.length)] = readFile(files[i])
    }
    base.fixture = fx
  }

  // The installed fixture files, without installing them again.
  function fixtureFiles() {
    var r = run(["/usr/bin/find", base.home + "/Notes/Omvision", "-type", "f"])
    return r.out.split("\n").filter(function(p) { return p !== "" }).sort()
  }

  function resetFixture() {
    var r = run([base.testDir + "/seed-home.sh", base.fixtureHome, base.home])
    if (r.code !== 0) qtest_fail("seed-home.sh failed (" + r.code + ")", 1)
    readFixture(r.out.split("\n").filter(function(p) { return p !== "" }))

    // Back to the Goals screen, and anything left open closed.
    if (base.goalDetail) {
      base.goalDetail.cancelEditTask()
      base.goalDetail.cancelAddTask()
      base.goalDetail.cancelDialogOpen = false
    }
    base.app.eventDialogOpen = false
    base.app.newGoalDialogOpen = false
    base.app.currentScreen = "goals"
    mouseMove(base.target, 1, base.target.height - 1)

    tryVerify(function() { return base.appShowsFixture() }, 12000,
              "the app never showed the restored fixture files")
  }

  // Whether every fixture file is what the app has loaded -- goal files,
  // logs and journal days -- and nothing else is.
  function appShowsFixture() {
    var a = base.app
    var slugs = [], journalPaths = []
    var now = new Date()
    for (var rel in base.fixture) {
      var text = base.fixture[rel]
      var m = rel.match(/^goals\/(.+)\.log\.md$/)
      if (m) {
        var g = a.goalsData[m[1]]
        if (!g || JSON.stringify(g.logEntries) !== JSON.stringify(Parser.parseLogEntries(text, now))) return false
        continue
      }
      m = rel.match(/^goals\/(.+)\.md$/)
      if (m) {
        slugs.push(m[1])
        var g2 = a.goalsData[m[1]]
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

  // ---- finding and clicking things -----------------------------------------------
  function effectiveOpacity(it) {
    var o = 1
    for (var p = it; p; p = p.parent) o *= p.opacity
    return o
  }

  function findNamed(root, name) {
    if (!root) return null
    if (root.objectName === name && root.visible) return root
    var kids = root.children
    for (var i = 0; kids && i < kids.length; i++) {
      var r = findNamed(kids[i], name)
      if (r) return r
    }
    return null
  }

  // The visible item called `name`, waiting for it to appear. By objectName
  // only. A fallback that found items by their label or their delegate's
  // properties (locate(), from before the names were on the controls) was
  // removed: it made a renamed or dropped objectName go unnoticed, because
  // the test still found the control another way.
  function item(name, ms) {
    var found = null
    tryVerify(function() {
      found = findNamed(base.target, name)
      return found !== null
    }, ms || base.timeout, "no visible item named " + name)
    return found
  }

  // Waits until `it` stops moving. A Repeater's delegates exist before their
  // Column has placed them -- straight after a goal opens, all three task
  // rows reported the same y -- and a click aimed then lands on whichever row
  // ends up under that point.
  function settle(it) {
    var last = null
    for (var t = 0; t < 2000; t += 50) {
      var p = it.mapToItem(base.target, 0, 0)
      var here = p.x + "," + p.y + "," + it.width + "," + it.height
      if (here === last) return
      last = here
      wait(50)
    }
  }

  // Hovers the item first, the way a pointer arrives before it clicks:
  // several controls (the task pencils) only become clickable under the
  // pointer.
  function click(name, ms) {
    var it = item(name, ms)
    settle(it)
    var x = it.width / 2, y = it.height / 2
    mouseMove(it, x, y)
    tryVerify(function() { return it.visible && it.enabled && base.effectiveOpacity(it) > 0 },
              ms || base.timeout, name + " never became clickable")
    mouseClick(it, x, y)
    return it
  }

  function type(text) {
    for (var i = 0; i < text.length; i++) {
      var c = text.charAt(i)
      if (c === "\n") keyClick(Qt.Key_Return)
      else keyClick(c)
    }
  }

  function key(k, modifiers) {
    keyClick(k, modifiers === undefined ? Qt.NoModifier : modifiers)
  }

  // Clicks the goal's row on the Goals screen and waits for its detail.
  function openGoal(slug) {
    base.app.currentScreen = "goals"
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
