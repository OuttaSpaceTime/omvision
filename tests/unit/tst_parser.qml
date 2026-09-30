import QtQuick
import QtTest

import "../../Parser.js" as Parser
import "workedexample.js" as Example

// Parser.js reads what three programs write (goal-files.md), so most of
// these check its §6 tolerance rules: what is skipped, what is read anyway,
// and that nothing throws. Dates are built with a fixed "now" -- log
// headings carry no year, and the parser resolves them against the one it
// is given.
TestCase {
  name: "Parser"

  readonly property string goal: Example.goal
  readonly property string log: Example.log
  readonly property var now: new Date(2026, 8, 30, 12, 0)

  function crlf(s) { return s.replace(/\n/g, "\r\n") }

  // ---- parseGoalFile ---------------------------------------------------------
  function test_parseGoalFile_worked_example() {
    var m = Parser.parseGoalFile(goal)
    compare(m.title, "Ship the goal files doc")
    compare(m.why, "Blocks every other milestone — Omvision and the coach skill can't start without it.")
    compare(m.status, "active")
    compare(m.estimate, 3)
    compare(m.done_by, "2026-09-21")
    compare(m.tasks, [
      { done: true, text: "Read the plan and notes-helper.py", estimate: undefined },
      { done: false, text: "Write docs/goal-files.md", estimate: 2 },
      { done: false, text: "Get it reviewed", estimate: 1 }
    ])
    compare(m.coaching, [{ session: 1, date: "19 Sep", method: "Pólya",
                           summary: "What's the actual blocker? — Nothing's blocked, it just hasn't been written yet." }])
    compare(m.cancelled, null)
    compare(Object.keys(m.raw).sort(), ["done_by", "estimate", "status", "title", "why"])
  }

  function test_parseGoalFile_crlf_and_trailing_whitespace() {
    var plain = Parser.parseGoalFile(goal)
    compare(Parser.parseGoalFile(crlf(goal)), plain, "CRLF reads the same")
    var spaced = goal.replace("---\n", "---   \n").replace("## Tasks\n", "## Tasks  \n")
                     .replace("title: Ship the goal files doc\n", "title: Ship the goal files doc  \n")
    compare(Parser.parseGoalFile(spaced), plain, "trailing whitespace on fences, keys and headings")
    compare(Parser.parseGoalFile("\n\n" + goal), plain, "leading blank lines")
  }

  function test_parseGoalFile_not_a_goal_file_data() {
    return [
      { tag: "empty", t: "" },
      { tag: "null", t: null },
      { tag: "no front matter", t: "## Tasks\n- [ ] a\n" },
      { tag: "never closed", t: "---\ntitle: T\n## Tasks\n" },
      { tag: "stray line", t: "---\ntitle: T\njust prose\n---\n" },
      { tag: "multi-line value", t: "---\ntitle: T\n  continued\n---\n" },
      { tag: "no title", t: "---\nwhy: W\n---\n" },
      { tag: "empty title", t: "---\ntitle:\n---\n" },
      { tag: "prose first", t: "hello\n---\ntitle: T\n---\n" }
    ]
  }
  function test_parseGoalFile_not_a_goal_file(row) {
    compare(Parser.parseGoalFile(row.t), null)
  }

  function test_parseGoalFile_defaults_and_unknown_keys() {
    var m = Parser.parseGoalFile("---\ntitle: T\nfuture_key: some value\nwhy:\n---\n")
    compare(m.status, "active", "missing status is active")
    compare(m.why, "")
    compare(m.estimate, undefined)
    compare(m.done_by, undefined)
    compare(m.tasks, [], "no ## Tasks is zero tasks")
    compare(m.coaching, [])
    compare(m.raw.future_key, "some value", "unknown keys are kept")
    compare(Parser.parseGoalFile("---\ntitle: T\nestimate: lots\n---\n").estimate, undefined, "non-numeric estimate")
    compare(Parser.parseGoalFile("---\ntitle: T\nestimate: 0\n---\n").estimate, 0)
    compare(Parser.parseGoalFile("---\ntitle: T\nstatus: done\n---\n").status, "done")
  }

  // goal-files.md §6: `estimate:` is poms *remaining*, and a reader shows it
  // as it is. Parser hands it over untouched, however much the log says was
  // done -- nothing here may compute `estimate - poms`.
  function test_estimate_is_poms_left() {
    var m = Parser.parseGoalFile(goal)
    var entries = Parser.parseLogEntries(log, now)
    compare(entries.filter(function(e) { return e.type === "pomodoro" }).length, 2)
    compare(m.estimate, 3, "3 poms left, not 3 - 2")
    compare(m.tasks.filter(function(t) { return !t.done })
                   .reduce(function(n, t) { return n + (t.estimate || 0) }, 0), m.estimate,
            "the worked example's estimate is the sum of its open tasks' ≈N")
  }

  // goal-files.md §6 spells the coach's rewrite as
  // `estimate: 6   # was 9 — session 2`, and Writer.js goes out of its way
  // to keep that note. Parser used to read the whole value with Number(),
  // get NaN, and report no estimate: after a coach session the Goal detail
  // header lost its "≈ N poms left" and the Goals list its estimate. raw
  // keeps the line's value as written.
  function test_parseGoalFile_coach_estimate_comment() {
    var text = goal.replace("estimate: 3\n", "estimate: 6   # was 9 — session 2\n")
    var m = Parser.parseGoalFile(text)
    compare(m.raw.estimate, "6   # was 9 — session 2")
    compare(m.estimate, 6)
    compare(Parser.parseGoalFile(crlf(text)).estimate, 6, "CRLF")
  }

  // Which values carry a note: "#" at the start of the value or after
  // whitespace (YAML's rule), and only on `estimate`, the one key §6 shows
  // with a note and the only one where "#" can't be content.
  function test_estimate_note_data() {
    return [
      { tag: "bare", v: "6", est: 6 },
      { tag: "coach", v: "6   # was 9 — session 2", est: 6 },
      { tag: "one space", v: "6 # was 9", est: 6 },
      { tag: "tab", v: "6\t# was 9", est: 6 },
      { tag: "empty note", v: "6 #", est: 6 },
      { tag: "zero with a note", v: "0   # done, was 2", est: 0 },
      { tag: "note only", v: "# was 9", est: undefined },
      { tag: "no space before #", v: "6#9", est: undefined },
      { tag: "a word, then a note", v: "six # was 9", est: undefined },
      { tag: "two numbers", v: "6 7 # was 9", est: undefined }
    ]
  }
  function test_estimate_note(row) {
    compare(Parser.parseGoalFile("---\ntitle: T\nestimate: " + row.v + "\n---\n").estimate, row.est)
  }

  // In every other key "#" is text: a title like "Fix bug #12" is read whole.
  function test_parseGoalFile_hash_is_text_elsewhere() {
    var m = Parser.parseGoalFile("---\ntitle: Fix bug #12\nwhy: see # 4\nstatus: active # no\ndone_by: 2026-10-01 # soft\n---\n")
    compare(m.title, "Fix bug #12")
    compare(m.why, "see # 4")
    compare(m.status, "active # no")
    compare(m.done_by, "2026-10-01 # soft")
    compare(Parser.parseGoalFile("---\ntitle: # not a note\n---\n").title, "# not a note")
  }

  function test_frontMatterValue() {
    compare(Parser.frontMatterValue("estimate", "6   # was 9"), "6")
    compare(Parser.frontMatterValue("estimate", " 6 "), "6")
    compare(Parser.frontMatterValue("estimate", undefined), "")
    compare(Parser.frontMatterValue("title", "Fix bug #12"), "Fix bug #12")
    compare(Parser.frontMatterValue("why", " a # b "), "a # b")
  }

  // The one "is this a goal file" rule, which Writer.js also asks before
  // every edit. Lines may carry trailing whitespace (Writer hands them over
  // unrtrimmed); a repeated key's last line wins.
  function test_goalFrontMatter() {
    compare(Parser.goalFrontMatter(null), null)
    compare(Parser.goalFrontMatter([]), null)
    compare(Parser.goalFrontMatter(["", "---  ", "title: T ", "k: v", "---", "## Tasks"]), {
      open: 1, close: 4, fields: { title: "T", k: "v" },
      lineOf: { title: 2, k: 3 }, keyAt: { 2: "title", 3: "k" } })
    var twice = Parser.goalFrontMatter(["---", "title: A", "title: B", "---"])
    compare(twice.fields.title, "B")
    compare(twice.lineOf.title, 2)
    compare(Parser.goalFrontMatter(["---", "title: T", "prose", "---"]), null, "a line that isn't key: value")
    compare(Parser.goalFrontMatter(["---", "why: W", "---"]), null, "no title")
    compare(Parser.goalFrontMatter(["---", "title: T"]), null, "never closed")
  }

  // ---- tasks, coaching, cancelled ------------------------------------------------
  function test_parseTasks() {
    var lines = ["## Tasks", "prose", "- [ ] a ≈3", "-[x]b", "- [X] c  ≈12  ", "  - [ ] indented",
                 "- [ ] d≈4", "- [ ] e ≈ 5", "", "## Coaching", "- [ ] not a task"]
    compare(Parser.parseTasks(lines), [
      { done: false, text: "a", estimate: 3 },
      { done: true, text: "b", estimate: undefined },
      { done: true, text: "c", estimate: 12 },
      { done: false, text: "d", estimate: 4 },
      { done: false, text: "e ≈ 5", estimate: undefined }
    ])
    compare(Parser.parseTasks(["no", "tasks"]), [])
  }

  // text + suffix is always the whole body; Writer.editTask replaces the
  // text and keeps the suffix, so this split is what an edit touches.
  function test_splitTaskBody_data() {
    return [
      { tag: "coach alignment", b: "Write docs/goal-files.md   ≈2", text: "Write docs/goal-files.md", est: 2, suffix: "   ≈2" },
      { tag: "no estimate", b: "plain", text: "plain", est: undefined, suffix: "" },
      { tag: "trailing space", b: "plain  ", text: "plain", est: undefined, suffix: "  " },
      { tag: "no space", b: "d≈4", text: "d", est: 4, suffix: "≈4" },
      { tag: "after ≈N", b: "a ≈12  ", text: "a", est: 12, suffix: " ≈12  " },
      { tag: "not an estimate", b: "e ≈ 5", text: "e ≈ 5", est: undefined, suffix: "" },
      { tag: "two, the last counts", b: "a ≈3 ≈4", text: "a ≈3", est: 4, suffix: " ≈4" },
      { tag: "only an estimate", b: "≈2", text: "", est: 2, suffix: "≈2" },
      { tag: "empty", b: "", text: "", est: undefined, suffix: "" },
      { tag: "null", b: null, text: "", est: undefined, suffix: "" }
    ]
  }
  function test_splitTaskBody(row) {
    compare(Parser.splitTaskBody(row.b), { text: row.text, estimate: row.est, suffix: row.suffix })
  }

  function test_parseCoaching() {
    var lines = ["## Coaching",
                 "### Session 1 · 19 Sep · Pólya", "", "  first line  ", "second",
                 "### not a session heading", "ignored",
                 "### Session 2 · 25 Sep · mi",
                 "## Cancelled", "### Session 3 · 1 Oct · mi"]
    compare(Parser.parseCoaching(lines), [
      { session: 1, date: "19 Sep", method: "Pólya", summary: "first line" },
      { session: 2, date: "25 Sep", method: "mi", summary: "" }
    ], "stops at the next ## section")
  }

  function test_parseCancelNote() {
    compare(Parser.parseCancelNote(["## Tasks"]), null)
    compare(Parser.parseCancelNote(["## Cancelled", "### 30 Sep 10:00", "reason: r", "takeaway: t"]),
            { when: "30 Sep 10:00", reason: "r", takeaway: "t" })
    compare(Parser.parseCancelNote(["## Cancelled", "reason: only"]), { when: "", reason: "only", takeaway: "" })
    compare(Parser.parseCancelNote(["## Cancelled", "### a", "reason: 1", "## Cancelled", "### b", "reason: 2"]),
            { when: "b", reason: "2", takeaway: "" }, "the last one wins")
  }

  // ---- parseLogEntries -------------------------------------------------------------
  function test_parseLogEntries_worked_example() {
    var e = Parser.parseLogEntries(log, now)
    compare(e.length, 3)

    compare(e[0].type, "pomodoro")
    compare(e[0].date.getTime(), new Date(2026, 8, 19, 16, 10).getTime())
    compare(e[0].minutes, 25)
    compare(e[0].heading, "19 Sep 16:10")
    compare(e[0].focus, "Read the plan and notes-helper.py")
    compare(e[0].done, "read both start to finish, understand the two-file split")
    compare(e[0].left, "haven't started writing yet")
    compare(e[0].other, "")

    compare(e[1].type, "event")
    compare(e[1].date.getTime(), new Date(2026, 8, 20, 9, 0).getTime())
    compare(e[1].kind, "training")
    compare(e[1].duration, "1h30")
    compare(e[1].minutes, 90)
    compare(e[1].title, "Bouldering — legs dead, head clear")
    compare(e[1].countsToward, false)

    compare(e[2].type, "pomodoro")
    compare(e[2].focus, "Write docs/goal-files.md")
    compare(e[2].done, "", "done: is optional")
    compare(e[2].left, "still drafting the parsing-rules section")

    compare(Parser.parseLogEntries(crlf(log), now).length, 3, "CRLF")
    compare(Parser.investedMinutes(e), 50, "the event isn't marked, so only the two pomodoros count")
  }

  // The timer's own figures, which the Goals rows, the goal detail and the
  // timeline's day headers show: an event counts in neither, even one
  // marked to count toward the goal's time (investedMinutes counts that).
  function test_pomodoroCount_and_pomodoroMinutes() {
    var e = Parser.parseLogEntries(log, now)
    compare(Parser.pomodoroCount(e), 2)
    compare(Parser.pomodoroMinutes(e), 50, "the 1h30 event is not a pomodoro")
    var marked = Parser.parseLogEntries(log.replace("Bouldering", "[+time] Bouldering"), now)
    compare(Parser.pomodoroMinutes(marked), 50, "marked to count, still not a pomodoro")
    compare(Parser.investedMinutes(marked), 140)
    compare(Parser.pomodoroCount([]), 0)
    compare(Parser.pomodoroMinutes([]), 0)
  }

  function test_entryTime() {
    var e = Parser.parseLogEntries(log, now)
    compare(Parser.entryTime(e[0]), "16:10")
    compare(Parser.entryTime(e[1]), "09:00", "an event's heading, too")
  }

  function test_doneTaskCount() {
    var meta = Parser.parseGoalFile(goal)
    compare(Parser.doneTaskCount(meta.tasks), 1)
    compare(Parser.doneTaskCount([]), 0)
  }

  function test_parseLogEntries_else_line() {
    // The contract's §4 example, with the break screen's "What else?" line.
    var text = "### 20 Sep 14:25 · 25m\n" +
               "focus: Wire the goal picker into the IPC\n" +
               "done: status call wired through the IPC\n" +
               "left: picker still caches the list on load\n" +
               "else: kept getting pulled into Slack, worth guarding the next run\n"
    var e = Parser.parseLogEntries(text, now)
    compare(e.length, 1)
    compare(e[0].other, "kept getting pulled into Slack, worth guarding the next run")
    compare(e[0].left, "picker still caches the list on load")
    compare(e[0].focus, "Wire the goal picker into the IPC")
  }

  function test_parseLogEntries_skips_what_it_cant_read() {
    var text = "stray prose before any heading\n" +
               "### not a heading we know\nfocus: dropped\n\n" +
               "### 19 Foo 16:10 · 25m\nfocus: bad month\n\n" +
               "### 19 Sep 16:10 · 25m\nfocus: kept\n\n" +
               "#### 19 Sep 16:10 · 25m\n" +
               "### 20 Sep 9:00 · 25m\nfocus: one-digit hour isn't the grammar\n"
    var e = Parser.parseLogEntries(text, now)
    compare(e.length, 1)
    compare(e[0].focus, "kept")
    compare(Parser.parseLogEntries("", now), [])
    compare(Parser.parseLogEntries(null, now), [])
  }

  function test_parseLogEntries_dedupes_repeated_saves() {
    var text = "### 19 Sep 16:10 · 25m\nfocus: f\n\n" +
               "### 19 Sep 16:10 · 25m\nfocus: f\ndone: fuller note\n\n" +
               "### 19 Sep 16:10 · 50m\nfocus: a different run length\n\n" +
               "### 19 Sep 16:10 · event · meeting · 25m\nsame minute, but an event\n"
    var e = Parser.parseLogEntries(text, now)
    compare(e.length, 3)
    compare(e[0].done, "fuller note", "the last save wins")
    compare(e[1].minutes, 50)
    compare(e[2].type, "event")
  }

  function test_parseLogEntries_year_wrap() {
    var jan = new Date(2027, 0, 2, 10, 0)
    var e = Parser.parseLogEntries("### 30 Dec 10:00 · 25m\n\n### 3 Jan 09:00 · 25m\n", jan)
    compare(e[0].date.getFullYear(), 2026, "more than two days ahead is last year")
    compare(e[1].date.getFullYear(), 2027, "within two days ahead is this year")
  }

  function test_parseLogEntries_counts_toward_marker() {
    var text = "### 20 Sep 09:00 · event · reading · 45m\n[+time] A chapter\n\n" +
               "### 20 Sep 10:00 · event · meeting · 1h\nStandup\n\n" +
               "### 20 Sep 11:00 · 25m\nfocus: x\n"
    var e = Parser.parseLogEntries(text, now)
    compare(e[0].countsToward, true)
    compare(e[0].title, "A chapter")
    compare(e[1].countsToward, false)
    compare(e[1].minutes, 60)
    compare(Parser.investedMinutes(e), 70)
    compare(Parser.investedMinutes([]), 0)
  }

  function test_stripEventCountsMarker() {
    compare(Parser.stripEventCountsMarker("[+time] x"), { countsToward: true, text: "x" })
    compare(Parser.stripEventCountsMarker("x [+time] "), { countsToward: false, text: "x [+time] " })
    compare(Parser.stripEventCountsMarker(undefined), { countsToward: false, text: "" })
  }

  function test_parseDurationToMinutes() {
    compare(Parser.parseDurationToMinutes("25m"), 25)
    compare(Parser.parseDurationToMinutes("1h"), 60)
    compare(Parser.parseDurationToMinutes("1h30"), 90)
    compare(Parser.parseDurationToMinutes("1h30m"), 0, "not the grammar")
    compare(Parser.parseDurationToMinutes(""), 0)
  }

  function test_monthIndex_and_resolveDate() {
    compare(Parser.monthIndex("Sep"), 8)
    compare(Parser.monthIndex("sep"), 8)
    compare(Parser.monthIndex("Sept"), -1)
    compare(Parser.resolveDate(20, 8, 9, 0, now).getTime(), new Date(2026, 8, 20, 9, 0).getTime())
  }

  // ---- small formatters --------------------------------------------------------------
  function test_dayKey() {
    compare(Parser.dayKey(new Date(2026, 0, 5, 23, 59)), "2026-01-05")
    compare(Parser.dayKey(new Date(2026, 11, 31)), "2026-12-31")
  }

  function test_dayHeaderLabel_and_formatShortDate() {
    compare(Parser.dayHeaderLabel(new Date(2026, 8, 24)), "Thu 24 Sep")
    compare(Parser.formatShortDate("2026-09-24"), "Thu 24 Sep")
    compare(Parser.formatShortDate("2026-09-24T10:00"), "Thu 24 Sep")
    compare(Parser.formatShortDate("next week"), "next week", "free text passes through")
    compare(Parser.formatShortDate(""), "")
  }

  function test_formatHm_data() {
    return [ { tag: "0", m: 0, s: "0m" }, { tag: "50", m: 50, s: "50m" }, { tag: "60", m: 60, s: "1h" },
             { tag: "75", m: 75, s: "1h 15m" }, { tag: "605", m: 605, s: "10h 5m" } ]
  }
  function test_formatHm(row) { compare(Parser.formatHm(row.m), row.s) }

  function test_formatHCaption_data() {
    return [ { tag: "5", m: 5, s: "5 min" }, { tag: "60", m: 60, s: "1 h" },
             { tag: "75", m: 75, s: "1 h 15" }, { tag: "90", m: 90, s: "1 h 30" } ]
  }
  function test_formatHCaption(row) { compare(Parser.formatHCaption(row.m), row.s) }

  // ---- journal ------------------------------------------------------------------------
  function test_firstMeaningfulLine_data() {
    return [
      { tag: "heading", t: "\n\n## A day  \nbody", s: "A day" },
      { tag: "list", t: "- item one", s: "item one" },
      { tag: "star list", t: "* item", s: "item" },
      { tag: "quote", t: "> quoted", s: "quoted" },
      { tag: "code and link", t: "`code` and [a link](https://x)", s: "code and a link" },
      { tag: "CRLF", t: "\r\n\r\nfirst\r\nsecond", s: "first" },
      { tag: "blank", t: "  \n\t\n", s: "" },
      { tag: "null", t: null, s: "" }
    ]
  }
  function test_firstMeaningfulLine(row) { compare(Parser.firstMeaningfulLine(row.t), row.s) }

  function test_escapeHtml() {
    compare(Parser.escapeHtml("<a & b>"), "&lt;a &amp; b&gt;")
  }

  function test_mdToHtml() {
    var styles = { codeBg: "#eee", accent: "#00f", dim: "#999" }
    compare(Parser.mdToHtml("# Title", styles), "<p><b>Title</b></p>")
    compare(Parser.mdToHtml("> q", styles), "<p><i>q</i></p>")
    compare(Parser.mdToHtml("- a", styles), '<p><span style="color:#999;">-</span> a</p>')
    compare(Parser.mdToHtml("", styles), "<p></p>")
    compare(Parser.mdToHtml("<b>x</b>", styles), "<p>&lt;b&gt;x&lt;/b&gt;</p>", "markup in the text is escaped")
    compare(Parser.mdToHtml("see [x](u)", styles),
            '<p>see <a href="u" style="color:#00f; text-decoration:underline;">x</a></p>')
    compare(Parser.mdToHtml("a\r\nb", styles), "<p>a</p>\n<p>b</p>")
    compare(Parser.mdInline("`c`", styles), '<span style="background-color:#eee;"> c </span>')
  }
}
