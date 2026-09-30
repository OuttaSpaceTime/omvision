import QtQuick
import QtTest

import "../../Writer.js" as Writer
import "../../Parser.js" as Parser
import "workedexample.js" as Example

// Golden tests for Writer.js, the only code that edits the user's goal files
// in place. Each test states the whole expected file, not just the line that
// should change: the promise Writer.js makes (see its header) is that
// everything it was not asked to touch survives byte for byte, and only a
// full-file comparison can catch a stray blank line or a lost "\r".
//
// Every edit goes through apply(): detectEol, splitLines, the edit,
// joinLines -- the same wrapping the app puts around each Writer call, so
// these are the bytes it would write.
//
// Known bugs are pinned with expectFailContinue("", "BUG: ..."): they report
// XFAIL, and turn into a failure (XPASS) the day the bug is fixed, which is
// the reminder to drop the expectFail.
TestCase {
  name: "Writer"

  // The contract's worked example (goal-files.md, "Worked example"),
  // checked against the contract by bin/test on every run.
  readonly property string goal: Example.goal
  readonly property string log: Example.log

  function apply(text, fn) {
    var eol = Writer.detectEol(text)
    var out = fn(Writer.splitLines(text))
    return out === null ? null : Writer.joinLines(out, eol)
  }
  function crlf(s) { return s.replace(/\n/g, "\r\n") }
  // `text` with exactly one occurrence of `from` replaced. Failing loudly
  // when `from` is missing keeps a typo in a test from passing vacuously.
  function edited(text, from, to) {
    var at = text.indexOf(from)
    verify(at !== -1, "fixture does not contain " + JSON.stringify(from))
    verify(text.indexOf(from, at + 1) === -1, "fixture contains " + JSON.stringify(from) + " twice")
    return text.slice(0, at) + to + text.slice(at + from.length)
  }

  // Files the contract says are not goal files (goal-files.md §6). Every
  // entry point that edits a goal file must refuse them with null.
  readonly property var notGoalFiles: [
    "## Tasks\n- [ ] no front matter\n",
    "---\ntitle: never closed\n## Tasks\n- [ ] a\n",
    "title: no fences\n## Tasks\n- [ ] a\n",
    ""
  ]

  // ---- line helpers ------------------------------------------------------
  function test_detectEol() {
    compare(Writer.detectEol("a\nb"), "\n")
    compare(Writer.detectEol("a\r\nb"), "\r\n")
    compare(Writer.detectEol("a\nb\r\nc"), "\r\n", "any CRLF makes the file CRLF")
    compare(Writer.detectEol("a\rb"), "\n", "a lone CR is not CRLF")
    compare(Writer.detectEol(""), "\n")
    compare(Writer.detectEol(null), "\n")
    compare(Writer.detectEol(undefined), "\n")
  }

  function test_splitLines() {
    compare(Writer.splitLines("a\r\nb\rc\nd"), ["a", "b", "c", "d"])
    compare(Writer.splitLines("x\n"), ["x", ""], "a final newline is a trailing empty line")
    compare(Writer.splitLines("x\n\n"), ["x", "", ""])
    compare(Writer.splitLines(""), [""])
    compare(Writer.splitLines(null), [""])
    compare(Writer.splitLines("a  \n"), ["a  ", ""], "trailing whitespace is kept")
  }

  function test_joinLines() {
    compare(Writer.joinLines(["a", "b", ""]), "a\nb\n")
    compare(Writer.joinLines(["a", "b"], "\r\n"), "a\r\nb")
    compare(Writer.joinLines([""], "\n"), "")
  }

  function test_split_join_round_trip_data() {
    return [
      { tag: "worked example", text: goal },
      { tag: "worked example, CRLF", text: crlf(goal) },
      { tag: "log", text: log },
      { tag: "no final newline", text: "---\ntitle: T\n---" },
      { tag: "trailing blank lines", text: "---\ntitle: T\n---\n\n\n" },
      { tag: "trailing whitespace", text: "---  \ntitle: T \n---\n- [ ] a   \n" },
      { tag: "empty", text: "" }
    ]
  }
  function test_split_join_round_trip(row) {
    compare(Writer.joinLines(Writer.splitLines(row.text), Writer.detectEol(row.text)), row.text)
  }

  // ---- the worked example, nothing changed ---------------------------------
  // Each of these is an edit that asks for what the file already says. The
  // app does this whenever the Edit goal dialog is saved untouched, so any
  // byte that moves here is a spurious rewrite of the user's file.
  function test_worked_example_noop_data() {
    return [
      { tag: "LF", eol: "\n" },
      { tag: "CRLF", eol: "\r\n" }
    ]
  }
  function test_worked_example_noop(row) {
    var text = row.eol === "\n" ? goal : crlf(goal)
    compare(apply(text, function(l) { return l }), text, "split + join")
    compare(apply(text, function(l) { return Writer.setStatus(l, "active") }), text, "setStatus active")
    compare(apply(text, function(l) {
      return Writer.updateGoalFields(l, {
        title: "Ship the goal files doc",
        why: "Blocks every other milestone — Omvision and the coach skill can't start without it.",
        estimate: "3", doneBy: "2026-09-21" })
    }), text, "updateGoalFields, same values")
    compare(apply(text, function(l) {
      return Writer.updateGoalFields(l, {
        title: "  Ship the goal files doc ",
        why: "Blocks every other milestone — Omvision and the coach skill can't start without it.",
        estimate: 3, doneBy: "2026-09-21" })
    }), text, "updateGoalFields, numeric estimate and padded title")
    for (var i = 0; i < 3; i++) {
      compare(apply(apply(text, function(l) { return Writer.toggleTask(l, i) }),
                    function(l) { return Writer.toggleTask(l, i) }), text, "toggleTask twice, task " + i)
    }
  }

  function test_worked_example_parses() {
    var m = Parser.parseGoalFile(goal)
    verify(m !== null)
    compare(m.title, "Ship the goal files doc")
    compare(m.status, "active")
    compare(m.estimate, 3)
    compare(m.done_by, "2026-09-21")
    compare(m.tasks.length, 3)
    compare(m.coaching.length, 1)
  }

  // ---- toggleTask ----------------------------------------------------------
  function test_toggleTask_worked_example() {
    compare(apply(goal, function(l) { return Writer.toggleTask(l, 0) }),
            edited(goal, "- [x] Read the plan", "- [ ] Read the plan"))
    compare(apply(goal, function(l) { return Writer.toggleTask(l, 1) }),
            edited(goal, "- [ ] Write docs/goal-files.md   ≈2", "- [x] Write docs/goal-files.md   ≈2"),
            "the ≈N and its alignment spaces are untouched")
    compare(apply(crlf(goal), function(l) { return Writer.toggleTask(l, 2) }),
            crlf(edited(goal, "- [ ] Get it reviewed", "- [x] Get it reviewed")), "CRLF stays CRLF")
  }

  function test_toggleTask_out_of_range() {
    compare(apply(goal, function(l) { return Writer.toggleTask(l, 3) }), null)
    compare(apply(goal, function(l) { return Writer.toggleTask(l, -1) }), null)
    compare(apply("---\ntitle: T\n---\n", function(l) { return Writer.toggleTask(l, 0) }), null,
            "no ## Tasks section")
  }

  // The UI's row index comes from Parser.parseTasks and the write goes to
  // Writer.toggleTask's Nth line: the two must count the same lines, or a
  // click ticks the wrong task. This section mixes every shape either
  // regex could disagree on.
  readonly property string oddTasks:
    "---\ntitle: T\n---\n" +
    "## Tasks\n" +
    "Some prose under the heading\n" +
    "- [ ] one\n" +
    "-[x] two\n" +
    "  - [ ] indented, not a task\n" +
    "- [X] three   \n" +
    "* [ ] star bullet, not a task\n" +
    "\n" +
    "## Notes\n" +
    "- [ ] under another heading, not a task\n"

  function test_toggleTask_agrees_with_parser() {
    var before = Parser.parseGoalFile(oddTasks).tasks
    compare(before.map(function(t) { return t.text }), ["one", "two", "three"])
    for (var i = 0; i < before.length; i++) {
      var after = Parser.parseGoalFile(apply(oddTasks, function(l) { return Writer.toggleTask(l, i) })).tasks
      compare(after.length, before.length)
      for (var j = 0; j < before.length; j++)
        compare(after[j].done, j === i ? !before[j].done : before[j].done, "toggle " + i + ", task " + j)
    }
    compare(apply(oddTasks, function(l) { return Writer.toggleTask(l, 3) }), null,
            "a task under the next heading is not counted")
  }

  function test_toggleTask_keeps_trailing_whitespace_and_case() {
    compare(apply(oddTasks, function(l) { return Writer.toggleTask(l, 2) }),
            edited(oddTasks, "- [X] three   \n", "- [ ] three   \n"))
    compare(apply(oddTasks, function(l) { return Writer.toggleTask(l, 1) }),
            edited(oddTasks, "-[x] two\n", "-[ ] two\n"))
  }

  // ---- addTask -------------------------------------------------------------
  function test_addTask_worked_example() {
    var want = edited(goal, "- [ ] Get it reviewed   ≈1\n", "- [ ] Get it reviewed   ≈1\n- [ ] Ship it\n")
    compare(apply(goal, function(l) { return Writer.addTask(l, "Ship it") }), want,
            "after the last task, before the blank line and ## Coaching")
    compare(apply(crlf(goal), function(l) { return Writer.addTask(l, "Ship it") }), crlf(want))
    var tasks = Parser.parseGoalFile(want).tasks
    compare(tasks.length, 4)
    compare(tasks[3].text, "Ship it")
    compare(tasks[3].done, false)
  }

  function test_addTask_collapses_newlines_and_trims() {
    compare(apply("---\ntitle: T\n---\n## Tasks\n", function(l) { return Writer.addTask(l, "  two\nlines \r\n ") }),
            "---\ntitle: T\n---\n## Tasks\n- [ ] two lines\n")
  }

  function test_addTask_blank_is_null_data() {
    return [ { tag: "empty", v: "" }, { tag: "spaces", v: "   " }, { tag: "newlines", v: "\n\r\n" },
             { tag: "null", v: null }, { tag: "undefined", v: undefined } ]
  }
  function test_addTask_blank_is_null(row) {
    compare(apply(goal, function(l) { return Writer.addTask(l, row.v) }), null)
  }

  function test_addTask_creates_section() {
    compare(apply("---\ntitle: T\n---\n", function(l) { return Writer.addTask(l, "x") }),
            "---\ntitle: T\n---\n## Tasks\n- [ ] x\n", "after the front matter")
    var withCoaching = "---\ntitle: T\n---\n\n## Coaching\n### Session 1 · 1 Sep · MI\nhi\n"
    var want = "---\ntitle: T\n---\n\n## Tasks\n- [ ] x\n## Coaching\n### Session 1 · 1 Sep · MI\nhi\n"
    compare(apply(withCoaching, function(l) { return Writer.addTask(l, "x") }), want, "before ## Coaching")
    var m = Parser.parseGoalFile(want)
    compare(m.tasks.length, 1)
    compare(m.coaching.length, 1)
  }

  function test_addTask_empty_section() {
    compare(apply("---\ntitle: T\n---\n## Tasks\n\n## Coaching\n", function(l) { return Writer.addTask(l, "x") }),
            "---\ntitle: T\n---\n## Tasks\n- [ ] x\n\n## Coaching\n", "right under the heading")
    compare(apply("---\ntitle: T\n---\n## Tasks\nprose\n", function(l) { return Writer.addTask(l, "x") }),
            "---\ntitle: T\n---\n## Tasks\n- [ ] x\nprose\n", "no tasks yet: under the heading, above prose")
  }

  // ---- editTask ------------------------------------------------------------
  function test_editTask_keeps_estimate() {
    // The ≈N stays, but the run of alignment spaces before it collapses to
    // one: editTask rebuilds the line as "<marker><text> ≈N". Parser reads
    // the same estimate either way. Pinned here so a change is deliberate.
    var want = edited(goal, "- [ ] Write docs/goal-files.md   ≈2", "- [ ] Write the doc ≈2")
    compare(apply(goal, function(l) { return Writer.editTask(l, 1, "Write the doc") }), want)
    compare(Parser.parseGoalFile(want).tasks[1].estimate, 2)
    compare(Parser.parseGoalFile(want).tasks[1].text, "Write the doc")
  }

  function test_editTask_keeps_done_marker() {
    compare(apply(goal, function(l) { return Writer.editTask(l, 0, "Read it all") }),
            edited(goal, "- [x] Read the plan and notes-helper.py", "- [x] Read it all"))
    compare(apply(oddTasks, function(l) { return Writer.editTask(l, 2, "tres") }),
            edited(oddTasks, "- [X] three   \n", "- [X] tres\n"), "uppercase X kept")
    compare(apply(oddTasks, function(l) { return Writer.editTask(l, 1, "dos") }),
            edited(oddTasks, "-[x] two\n", "-[x] dos\n"), "a marker with no space before its box")
    compare(Parser.parseGoalFile(apply(oddTasks, function(l) { return Writer.editTask(l, 1, "dos") })).tasks[1].text, "dos")
  }

  function test_editTask_empty_deletes_data() {
    return [ { tag: "empty", v: "" }, { tag: "spaces", v: "   " }, { tag: "null", v: null } ]
  }
  function test_editTask_empty_deletes(row) {
    compare(apply(goal, function(l) { return Writer.editTask(l, 2, row.v) }),
            edited(goal, "- [ ] Get it reviewed   ≈1\n", ""))
    compare(apply(crlf(goal), function(l) { return Writer.editTask(l, 0, row.v) }),
            crlf(edited(goal, "- [x] Read the plan and notes-helper.py\n", "")))
  }

  function test_editTask_collapses_newlines() {
    compare(apply(goal, function(l) { return Writer.editTask(l, 0, " a\nb \r\n") }),
            edited(goal, "- [x] Read the plan and notes-helper.py", "- [x] a b"))
  }

  function test_editTask_out_of_range() {
    compare(apply(goal, function(l) { return Writer.editTask(l, 3, "x") }), null)
    compare(apply(goal, function(l) { return Writer.editTask(l, -1, "x") }), null)
    compare(apply("---\ntitle: T\n---\n", function(l) { return Writer.editTask(l, 0, "x") }), null)
    compare(apply(oddTasks, function(l) { return Writer.editTask(l, 3, "x") }), null,
            "a task under the next heading is not counted")
  }

  // ---- task edits refuse files that aren't goal files -----------------------
  // goal-files.md §6: a file with no front matter, or front matter that never
  // closes, "is not a goal file ... leave it alone, drop the operation", and
  // Writer.js's header promises null "on anything it can't safely edit".
  // setStatus and updateGoalFields honour that. The task edits only look for
  // "## Tasks" and never check the front matter, and omvision.qml doesn't
  // check either before calling them, so a goal file broken by a
  // half-finished hand edit still gets a task ticked, added or rewritten
  // (addTask even creates "## Tasks" at the top of a file with no front
  // matter). Expected to fail until Writer.js checks findFrontMatter() here.
  function test_task_edits_refuse_non_goal_files_data() {
    var rows = []
    for (var i = 0; i < notGoalFiles.length; i++) rows.push({ tag: "file " + i, text: notGoalFiles[i] })
    return rows
  }
  function test_task_edits_refuse_non_goal_files(row) {
    var text = row.text
    // The empty file has no task to tick or edit, so those two return null
    // for that reason already; only addTask can show the bug there.
    if (text.indexOf("- [ ]") !== -1) {
      expectFailContinue("", "BUG: toggleTask ignores missing/unterminated front matter")
      compare(apply(text, function(l) { return Writer.toggleTask(l, 0) }), null, "toggleTask")
    }
    if (text.indexOf("- [ ]") !== -1) {
      expectFailContinue("", "BUG: editTask ignores missing/unterminated front matter")
      compare(apply(text, function(l) { return Writer.editTask(l, 0, "x") }), null, "editTask")
    }
    expectFailContinue("", "BUG: addTask ignores missing/unterminated front matter")
    compare(apply(text, function(l) { return Writer.addTask(l, "x") }), null, "addTask")
  }

  // ---- setStatus -----------------------------------------------------------
  function test_setStatus_replaces() {
    compare(apply(goal, function(l) { return Writer.setStatus(l, "done") }),
            edited(goal, "status: active\n", "status: done\n"))
    compare(apply(crlf(goal), function(l) { return Writer.setStatus(l, "cancelled") }),
            crlf(edited(goal, "status: active\n", "status: cancelled\n")))
    compare(apply("---\ntitle: T\nstatus:\n---\n", function(l) { return Writer.setStatus(l, "done") }),
            "---\ntitle: T\nstatus: done\n---\n", "an empty status: line")
  }

  function test_setStatus_inserts_and_keeps_unknown_keys() {
    var text = "\n\n---\ntitle: T\nfoo_bar: baz qux\nstatusline: not status\n---\n## Tasks\n\nstatus: body text\n"
    compare(apply(text, function(l) { return Writer.setStatus(l, "done") }),
            "\n\n---\ntitle: T\nfoo_bar: baz qux\nstatusline: not status\nstatus: done\n---\n## Tasks\n\nstatus: body text\n",
            "before the closing fence; leading blank lines, unknown keys and the body untouched")
    compare(Parser.parseGoalFile(apply(text, function(l) { return Writer.setStatus(l, "done") })).raw.foo_bar, "baz qux")
  }

  function test_setStatus_refuses_non_goal_files_data() {
    var rows = []
    for (var i = 0; i < notGoalFiles.length; i++) rows.push({ tag: "file " + i, text: notGoalFiles[i] })
    return rows
  }
  function test_setStatus_refuses_non_goal_files(row) {
    compare(apply(row.text, function(l) { return Writer.setStatus(l, "done") }), null)
  }

  // Front matter that is fenced but has a line that isn't `key: value`.
  // Parser.parseGoalFile skips such a file as not a goal file (§6: "front
  // matter that doesn't parse -> skip the whole file"); Writer's
  // findFrontMatter only looks for the two fences, so it still edits it.
  // Minor -- it only touches the status line -- but it is the "don't guess"
  // rule broken. Expected to fail until findFrontMatter checks the lines.
  function test_setStatus_refuses_unparseable_front_matter() {
    var text = "---\ntitle: T\njust a sentence\n---\n## Tasks\n"
    compare(Parser.parseGoalFile(text), null, "the parser skips this file")
    expectFailContinue("", "BUG: Writer edits front matter Parser rejects")
    compare(apply(text, function(l) { return Writer.setStatus(l, "done") }), null)
  }

  // ---- updateGoalFields ------------------------------------------------------
  function fields(over) {
    var f = { title: "Ship the goal files doc",
              why: "Blocks every other milestone — Omvision and the coach skill can't start without it.",
              estimate: "3", doneBy: "2026-09-21" }
    for (var k in over) f[k] = over[k]
    return f
  }

  function test_updateGoalFields_changes_only_changed_keys() {
    compare(apply(goal, function(l) { return Writer.updateGoalFields(l, fields({ title: "Ship it" })) }),
            edited(goal, "title: Ship the goal files doc\n", "title: Ship it\n"))
    compare(apply(goal, function(l) { return Writer.updateGoalFields(l, fields({ why: "Because" })) }),
            edited(goal, "why: Blocks every other milestone — Omvision and the coach skill can't start without it.\n", "why: Because\n"))
    compare(apply(goal, function(l) { return Writer.updateGoalFields(l, fields({ estimate: "5" })) }),
            edited(goal, "estimate: 3\n", "estimate: 5\n"))
    compare(apply(crlf(goal), function(l) { return Writer.updateGoalFields(l, fields({ doneBy: "2026-10-01" })) }),
            crlf(edited(goal, "done_by: 2026-09-21\n", "done_by: 2026-10-01\n")))
  }

  // The coach rewrites the estimate as "6   # was 9 — session 2"
  // (goal-files.md §6). Saving the Edit goal dialog without touching the
  // estimate must keep that note.
  // (A plain replace, not edited(): that one calls verify(), which only
  // works inside a running test function, not in a property binding.)
  readonly property string coached: goal.replace("estimate: 3\n", "estimate: 6   # was 9 — session 2\n")

  function test_updateGoalFields_keeps_coach_comment() {
    compare(apply(coached, function(l) { return Writer.updateGoalFields(l, fields({ estimate: "6" })) }), coached)
    compare(apply(coached, function(l) { return Writer.updateGoalFields(l, fields({ estimate: 6 })) }), coached)
    compare(apply(coached, function(l) { return Writer.updateGoalFields(l, fields({ title: "Ship it", estimate: "6" })) }),
            edited(coached, "title: Ship the goal files doc\n", "title: Ship it\n"),
            "the comment survives an edit of another key")
    compare(apply(coached, function(l) { return Writer.updateGoalFields(l, fields({ estimate: "4" })) }),
            edited(goal, "estimate: 3\n", "estimate: 4\n"), "a real change replaces value and comment")
  }

  function test_updateGoalFields_removes_and_inserts() {
    compare(apply(goal, function(l) { return Writer.updateGoalFields(l, fields({ estimate: "", doneBy: "" })) }),
            edited(goal, "estimate: 3\ndone_by: 2026-09-21\n", ""), "empty removes the key")
    var bare = "---\ntitle: T\nwhy: W\nstatus: active\ncolour: teal\n---\n## Tasks\n"
    compare(apply(bare, function(l) { return Writer.updateGoalFields(l, { title: "T", why: "W", estimate: "4", doneBy: "2026-10-01" }) }),
            "---\ntitle: T\nwhy: W\nstatus: active\ncolour: teal\nestimate: 4\ndone_by: 2026-10-01\n---\n## Tasks\n",
            "absent keys go before the closing fence; unknown keys stay")
    compare(apply(bare, function(l) { return Writer.updateGoalFields(l, { title: "T", why: "W", estimate: "", doneBy: null }) }),
            bare, "an absent key left empty is not added")
    compare(apply(bare, function(l) { return Writer.updateGoalFields(l, { title: "T", why: "two\nlines", estimate: "" }) }),
            edited(bare, "why: W\n", "why: two lines\n"), "newlines collapse")
  }

  function test_updateGoalFields_blank_title_is_null() {
    compare(apply(goal, function(l) { return Writer.updateGoalFields(l, fields({ title: "" })) }), null)
    compare(apply(goal, function(l) { return Writer.updateGoalFields(l, fields({ title: "   " })) }), null)
  }

  function test_updateGoalFields_refuses_non_goal_files_data() {
    return test_setStatus_refuses_non_goal_files_data()
  }
  function test_updateGoalFields_refuses_non_goal_files(row) {
    compare(apply(row.text, function(l) { return Writer.updateGoalFields(l, fields({})) }), null)
  }

  // setFrontMatterValue strips a trailing "# comment" before comparing, for
  // the coach's estimate note. It does that for every key, so a title or why
  // that legitimately contains " #" can't be shortened to the part before
  // it: renaming "Fix bug #12" to "Fix bug" is taken as "unchanged" and
  // silently not written (and the dialog reports success). Expected to fail
  // until the comment rule is limited to the estimate (or to values that
  // differ only by the comment the file already has).
  function test_updateGoalFields_hash_in_title() {
    var text = "---\ntitle: Fix bug #12\nwhy: W\n---\n"
    expectFailContinue("", "BUG: '# comment' stripping applies to title/why")
    compare(apply(text, function(l) { return Writer.updateGoalFields(l, { title: "Fix bug", why: "W" }) }),
            "---\ntitle: Fix bug\nwhy: W\n---\n")
  }

  // ---- appendCancelNote --------------------------------------------------------
  // Note the result has no final newline: the trailing blank lines are
  // trimmed and the section is appended after them. Pinned here as current
  // behaviour; nothing reads that file by appending to it.
  readonly property string cancelSection:
    "\n## Cancelled\n### 30 Sep 10:00\nreason: Lost interest\ntakeaway: Pick smaller goals"

  function test_appendCancelNote() {
    compare(apply(goal, function(l) { return Writer.appendCancelNote(l, "30 Sep 10:00", "Lost interest", "Pick smaller goals") }),
            goal + cancelSection)
    compare(apply(goal + "\n\n  \n", function(l) { return Writer.appendCancelNote(l, "30 Sep 10:00", "Lost interest", "Pick smaller goals") }),
            goal + cancelSection, "trailing blank lines don't pile up")
    compare(apply(crlf(goal), function(l) { return Writer.appendCancelNote(l, "30 Sep 10:00", "Lost interest", "Pick smaller goals") }),
            crlf(goal + cancelSection))
    compare(apply(goal, function(l) { return Writer.appendCancelNote(l, "30 Sep 10:00", " Lost\ninterest ", "Pick\r\nsmaller goals") }),
            goal + cancelSection, "newlines collapse")
  }

  // Cancelling a goal is two Writer edits in one write: setStatus to
  // "cancelled", then appendCancelNote. Read back by the parser.
  function test_cancel_flow_parses_back() {
    var out = apply(goal, function(l) {
      var s = Writer.setStatus(l, "cancelled")
      return Writer.appendCancelNote(s, "30 Sep 10:00", "Lost interest", "Pick smaller goals")
    })
    var m = Parser.parseGoalFile(out)
    compare(m.status, "cancelled")
    compare(m.cancelled.when, "30 Sep 10:00")
    compare(m.cancelled.reason, "Lost interest")
    compare(m.cancelled.takeaway, "Pick smaller goals")
    compare(m.coaching.length, 1, "## Cancelled is not read as a coaching session")
    compare(m.tasks.length, 3)
  }

  // ---- log entries -------------------------------------------------------------
  function test_headingTimestamp() {
    compare(Writer.headingTimestamp(new Date(2026, 8, 5, 7, 3)), "5 Sep 07:03")
    compare(Writer.headingTimestamp(new Date(2026, 11, 31, 23, 59)), "31 Dec 23:59")
    compare(Writer.headingTimestamp(new Date(2026, 0, 1, 0, 0)), "1 Jan 00:00")
  }

  function test_formatDuration_data() {
    return [
      { tag: "0", m: 0, s: "0m" }, { tag: "25", m: 25, s: "25m" }, { tag: "59", m: 59, s: "59m" },
      { tag: "60", m: 60, s: "1h" }, { tag: "90", m: 90, s: "1h30" }, { tag: "125", m: 125, s: "2h05" },
      { tag: "120", m: 120, s: "2h" }, { tag: "59.6 rounds", m: 59.6, s: "1h" },
      { tag: "negative", m: -5, s: "0m" }, { tag: "garbage", m: "x", s: "0m" }
    ]
  }
  function test_formatDuration(row) {
    compare(Writer.formatDuration(row.m), row.s)
  }

  // Writer formats durations, Parser reads them back: every minute count
  // must survive the trip.
  function test_formatDuration_parses_back() {
    for (var m = 0; m <= 600; m++)
      compare(Parser.parseDurationToMinutes(Writer.formatDuration(m)), m, String(m))
  }

  function test_formatEventEntry_worked_example() {
    var entry = Writer.formatEventEntry(new Date(2026, 8, 20, 9, 0), 90, "training",
                                        "Bouldering — legs dead, head clear", false)
    compare(entry, "### 20 Sep 09:00 · event · training · 1h30\nBouldering — legs dead, head clear\n\n")
    verify(log.indexOf(entry) !== -1, "the entry is byte for byte the worked example's")
  }

  function test_formatEventEntry_counts_toward() {
    var entry = Writer.formatEventEntry(new Date(2026, 8, 20, 9, 0), 45, "reading", " two\nlines ", true)
    compare(entry, "### 20 Sep 09:00 · event · reading · 45m\n[+time] two lines\n\n")
    var e = Parser.parseLogEntries(entry, new Date(2026, 8, 30))
    compare(e.length, 1)
    compare(e[0].type, "event")
    compare(e[0].countsToward, true)
    compare(e[0].title, "two lines")
    compare(e[0].minutes, 45)
    compare(Writer.EVENT_COUNTS_MARKER, Parser.EVENT_COUNTS_MARKER, "the two files must agree on the marker")
  }

  function test_formatEventEntry_appends_cleanly() {
    // What `tee -a` does: two entries appended to the worked example's log
    // read back as two more entries, not one run together.
    var a = Writer.formatEventEntry(new Date(2026, 8, 21, 8, 0), 30, "", "", false)
    compare(a, "### 21 Sep 08:00 · event · other · 30m\n\n\n", "empty kind is `other`")
    var b = Writer.formatEventEntry(new Date(2026, 8, 21, 9, 0), 60, "meeting", "Standup", false)
    var entries = Parser.parseLogEntries(log + "\n" + a + b, new Date(2026, 8, 30))
    compare(entries.length, 5)
    compare(entries[3].kind, "other")
    compare(entries[4].title, "Standup")
    compare(entries[4].minutes, 60)
  }

  // ---- Add Event dialog parsers ---------------------------------------------------
  function test_parseWhen_data() {
    return [
      { tag: "today", s: "today 09:05", want: new Date(2026, 8, 30, 9, 5) },
      { tag: "Today, caps", s: " Today 9:05 ", want: new Date(2026, 8, 30, 9, 5) },
      { tag: "yesterday", s: "yesterday 23:10", want: new Date(2026, 8, 29, 23, 10) },
      { tag: "iso", s: "2026-09-01 7:30", want: new Date(2026, 8, 1, 7, 30) },
      { tag: "bare", s: "08:15", want: new Date(2026, 8, 30, 8, 15) },
      { tag: "tomorrow", s: "tomorrow 09:00", want: null },
      { tag: "empty", s: "", want: null },
      { tag: "no time", s: "today", want: null }
    ]
  }
  function test_parseWhen(row) {
    var got = Writer.parseWhen(row.s, new Date(2026, 8, 30, 12, 0))
    if (row.want === null) compare(got, null)
    else compare(got.getTime(), row.want.getTime())
  }

  function test_parseWhen_yesterday_across_month() {
    compare(Writer.parseWhen("yesterday 10:00", new Date(2026, 9, 1, 8, 0)).getTime(),
            new Date(2026, 8, 30, 10, 0).getTime())
  }

  function test_parseDurationInput_data() {
    return [
      { tag: "bare", s: "25", m: 25 }, { tag: "h+mm", s: "1h30", m: 90 }, { tag: "h", s: "2h", m: 120 },
      { tag: "m", s: "45m", m: 45 }, { tag: "padded", s: " 45m ", m: 45 },
      { tag: "one-digit minutes", s: "1h5", m: 0 }, { tag: "words", s: "abc", m: 0 }, { tag: "empty", s: "", m: 0 }
    ]
  }
  function test_parseDurationInput(row) {
    compare(Writer.parseDurationInput(row.s), row.m)
  }

  // ---- new goals ------------------------------------------------------------------
  function test_deriveSlug_data() {
    return [
      { tag: "contract 1", t: "Ship the goal files doc", s: "ship-the-goal-files-doc" },
      { tag: "contract 2", t: "λi: rethink Q3", s: "i-rethink-q3" },
      { tag: "contract 3", t: "???", s: "goal" },
      { tag: "contract 4", t: "Deep work", s: "deep-work" },
      { tag: "empty", t: "", s: "goal" },
      { tag: "null", t: null, s: "goal" },
      { tag: "runs", t: "  --A  b__c--  ", s: "a-b-c" },
      { tag: "umlaut", t: "Übung macht", s: "bung-macht" }
    ]
  }
  function test_deriveSlug(row) {
    compare(Writer.deriveSlug(row.t), row.s)
  }

  function test_buildNewGoalFile() {
    compare(Writer.buildNewGoalFile({ title: "Ship it", why: "Because" }),
            "---\ntitle: Ship it\nwhy: Because\nstatus: active\n---\n## Tasks\n")
    compare(Writer.buildNewGoalFile({ title: " Ship it ", why: "two\r\nlines", estimate: 3, doneBy: "2026-10-01" }),
            "---\ntitle: Ship it\nwhy: two lines\nstatus: active\nestimate: 3\ndone_by: 2026-10-01\n---\n## Tasks\n")
    compare(Writer.buildNewGoalFile({ title: "T", why: "", estimate: "", doneBy: "" }),
            "---\ntitle: T\nwhy: \nstatus: active\n---\n## Tasks\n", "\"\" is no estimate")
  }

  // NewGoalDialog passes the estimate as a Number, so typing 0 hands
  // buildNewGoalFile a numeric 0. The presence check lets it through, but
  // fmLine() formats `String(value || "")`, and 0 is falsy: the file gets
  // "estimate: " with no value, which Parser reads as no estimate at all.
  // Expected to fail until fmLine tests for null/undefined instead.
  function test_buildNewGoalFile_zero_estimate() {
    expectFailContinue("", "BUG: estimate 0 is written as an empty value")
    compare(Writer.buildNewGoalFile({ title: "T", why: "W", estimate: 0 }),
            "---\ntitle: T\nwhy: W\nstatus: active\nestimate: 0\n---\n## Tasks\n")
  }

  function test_buildNewGoalFile_parses_and_takes_a_task() {
    var text = Writer.buildNewGoalFile({ title: "Ship it", why: "Because", estimate: "3", doneBy: "2026-10-01" })
    var m = Parser.parseGoalFile(text)
    compare(m.title, "Ship it")
    compare(m.why, "Because")
    compare(m.status, "active")
    compare(m.estimate, 3)
    compare(m.done_by, "2026-10-01")
    compare(m.tasks.length, 0)
    var added = apply(text, function(l) { return Writer.addTask(l, "first") })
    compare(added, text + "- [ ] first\n")
    compare(Parser.parseGoalFile(added).tasks[0].text, "first")
  }
}
