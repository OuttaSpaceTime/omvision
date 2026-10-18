import QtQuick
import QtTest

import "../../Parser.js" as Parser
import "../../Writer.js" as Writer

// tests/contract/cases.json against Parser.js and Writer.js: what the app
// reads of each case, and for events what it writes. tests/contract/check.py
// runs the same cases against notes-helper.py, the other writer and reader
// of the same files, so a case is how the two are kept agreeing.
TestCase {
  name: "Contract"

  // bin/test runs this layer with QML_XHR_ALLOW_FILE_READ=1.
  readonly property var cases: {
    var x = new XMLHttpRequest()
    x.open("GET", Qt.resolvedUrl("../contract/cases.json"), false)
    x.send()
    return JSON.parse(x.responseText)
  }

  readonly property var now: new Date(2026, 9, 18, 12, 0)

  // "2026-10-16T09:30:12" as the local time the engine means by it.
  function localDate(iso) {
    var m = iso.match(/^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)$/)
    return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), Number(m[6]))
  }

  function rows(section) {
    return cases[section].map(function(c) { return Object.assign({ tag: c.name }, c) })
  }

  function test_focusable_data() { return rows("focusable") }
  function test_focusable(c) {
    compare(Parser.isFocusable(c.raw === null ? undefined : c.raw), c.focusable)
  }

  function test_goalFiles_data() { return rows("goalFiles") }
  function test_goalFiles(c) {
    var meta = Parser.parseGoalFile(c.text)
    var got = meta === null ? null
      : { title: meta.title, status: meta.raw.status === undefined ? null : meta.raw.status, focusable: meta.focusable }
    compare(got, c.goal)
  }

  function test_pomodoros_data() { return rows("pomodoros") }
  function test_pomodoros(c) {
    var e = Parser.parseLogEntries(c.text, now)
    compare(e.length, 1, "one entry")
    var got = {}
    for (var k in c.parsed) got[k] = e[0][k]
    compare(got, c.parsed)
    compare(e[0].type, "pomodoro")
  }

  function test_events_data() { return rows("events") }
  function test_events(c) {
    var p = c.payload
    compare(Writer.formatEventEntry(localDate(p.started), p.minutes, p.kind, p.title, false), c.text, "Writer writes it")
    var e = Parser.parseLogEntries(c.text, now)
    compare(e.length, 1, "one entry")
    var got = {}
    for (var k in c.parsed) got[k] = e[0][k]
    compare(got, c.parsed)
    compare(e[0].type, "event")
  }
}
