import QtQuick
import QtTest
import Quickshell
import Quickshell.Io

// The base of every test that runs inside `qs`: tests/app's (OmvisionTest,
// in the running app) and tests/engine's (EngineTest, beside the ompom
// engine and its overlay). Qt's own qmltestrunner can't run these: it can't
// load Quickshell's modules, which only exist inside the `qs` binary.
//
// The file under test is loaded by a hook in the program it tests, which
// sets `target` (the item tree click() searches and a screenshot grabs) and
// `window`, plus what its own base type declares; the tests start a turn
// after `target` is set.
//
// What a test file gets, besides everything TestCase has (compare, verify,
// tryCompare, tryVerify, mouseClick, keyClick, wait, expectFailContinue,
// skip, ...):
//   click(objectName)             hover it, wait until it can be clicked,
//                                 click its centre
//   item(objectName)              the visible item with that name, waiting
//                                 for it to appear
//   type(text), key(key, mods)    real key events to the focused item
//   notesPath(rel)                "$HOME/Notes/Omvision/" + rel
//   readFile(rel)                 the file's text now, or null if missing
//                                 (rel under Notes/Omvision, or absolute)
//   writeFile(rel, text)          write a file the way an outside editor
//                                 would (the reset deletes what isn't fixture)
//   expectFile(rel, want)         wait until the file says `want` (a string,
//                                 or a function(text) -> bool)
//   expectFileUnchanged(rel)      the file stays as the fixture left it
//   fixtureText(rel)              what the fixture put there
//
// Before every test the fixture files are put back (tests/lib/seed-home.sh,
// from every fixture home in OMVISION_TEST_FIXTURES) and resetFixture() runs,
// which a base type extends to put its program back as well.
//
// Results go to stdout, one line per test, for bin/test to read:
//   PASS <file>::<test>
//   FAIL <file>::<test>: <what failed, where>      (+ a screenshot)
//   XFAIL <file>::<test>: <why>   known failure, counted as passing
//   SKIP <file>::<test>: <why>
// then `DONE <file> <passed> passed, <failed> failed, ...` and qs quits with
// 0, or 1 if anything failed.
TestCase {
  id: base

  // Never started by Qt's own scheduler (that needs qmltestrunner's
  // QTestRootObject to report a shown window, which nothing sets here):
  // runAll() below drives the tests once the hook has handed everything over.
  when: false

  property Item target: null
  property var window: null

  // A per-file default for how long a helper waits before giving up.
  property int timeout: 8000

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string libDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  // Colon-separated, laid over each other in order; see seed-home.sh.
  readonly property var fixtureHomes: (Quickshell.env("OMVISION_TEST_FIXTURES")
                                       || libDir.replace(/\/lib$/, "/fixtures/home")).split(":")
  readonly property string outDir: Quickshell.env("OMVISION_TEST_OUT") || home
  // bin/test can run one test of a file: OMVISION_TEST_ONLY=test_name.
  readonly property string only: Quickshell.env("OMVISION_TEST_ONLY") || ""
  readonly property string fileName: String(base.name || "test")

  // Set false in a file whose tests need the program exactly as it started
  // (the journal's first load, say): no reset before each test. bin/test
  // seeded HOME before the start.
  property bool resetBeforeEachTest: true

  onTargetChanged: if (target) startTimer.start()

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
        const why = pendingXfail, aborts = pendingXfailAborts
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
  function testFunctions() {
    var names = []
    for (let p in base) {
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
    for (let i = 0; i < names.length; i++) {
      const status = runOne(names[i])
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
      const m = String(e && e.message !== undefined ? e.message : e)
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
    for (let t = 0; t < 3000 && !done; t += 50) wait(50)
  }

  // ---- shell commands -----------------------------------------------------------
  // A named type, so run() can cast what createObject() returns to it:
  // createObject() is typed as returning a plain QObject, and qmllint then
  // finds none of these members on it.
  component RunProcess: Process {
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

  Component {
    id: processComponent
    RunProcess {}
  }

  // Runs argv to completion and returns { code, out }. Waits with wait(),
  // which keeps the event loop turning meanwhile.
  function run(argv, ms) {
    var p = processComponent.createObject(base, { command: argv }) as RunProcess
    p.running = true
    var limit = ms || 10000
    var t = 0
    for (; t < limit && !p.finished; t += 10) wait(10)
    // stdout's end can arrive a turn after the exit.
    for (let s = 0; s < 500 && !p.streamDone; s += 10) wait(10)
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
    for (let t = 0; t < limit && !ok(text); t += 100) { wait(100); text = readFile(rel) }
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
    for (let t = 0; t <= limit; t += 100) {
      const text = readFile(rel)
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
    for (let i = 0; i < files.length; i++) {
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

  // Puts the fixture files back. A base type extends this to put its
  // program back too (OmvisionTest: the Goals screen; EngineTest: a fresh
  // run at noon), calling resetHome() first.
  function resetFixture() { resetHome() }

  function resetHome() {
    var r = run([base.libDir + "/seed-home.sh"].concat(base.fixtureHomes, [base.home]))
    if (r.code !== 0) qtest_fail("seed-home.sh failed (" + r.code + ")", 1)
    readFixture(r.out.split("\n").filter(function(p) { return p !== "" }))
  }

  // ---- finding and clicking things -----------------------------------------------
  function effectiveOpacity(it) {
    var o = 1
    for (let p = it; p; p = p.parent) o *= p.opacity
    return o
  }

  function findNamed(root, name) {
    if (!root) return null
    if (root.objectName === name && root.visible) return root
    var kids = root.children
    for (let i = 0; kids && i < kids.length; i++) {
      const r = findNamed(kids[i], name)
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

  // Whether a visible item called `name` is there now, without waiting.
  function shows(name) { return findNamed(base.target, name) !== null }

  // Waits until `it` stops moving. A Repeater's delegates exist before their
  // Column has placed them -- straight after a goal opens, all three task
  // rows reported the same y -- and a click aimed then lands on whichever row
  // ends up under that point.
  function settle(it) {
    var last = null
    for (let t = 0; t < 2000; t += 50) {
      const p = it.mapToItem(base.target, 0, 0)
      const here = p.x + "," + p.y + "," + it.width + "," + it.height
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
    for (let i = 0; i < text.length; i++) {
      const c = text.charAt(i)
      if (c === "\n") keyClick(Qt.Key_Return)
      else keyClick(c)
    }
  }

  function key(k, modifiers) {
    keyClick(k, modifiers === undefined ? Qt.NoModifier : modifiers)
  }
}
