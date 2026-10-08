.pragma library
.import "Parser.js" as Parser

// Write-path helpers for the ompom/Omvision file contract -- see
// docs/goal-files.md. Parser.js reads tolerantly;
// this file writes precisely, and does it by surgical line edits rather
// than reparse-and-reserialize, so anything not being changed -- unknown
// front-matter keys, section order, blank lines, the user's own prose in
// "## Coaching" -- survives byte for byte. Nothing here throws: every
// entry point returns null on anything it can't safely edit, and the
// caller (omvision.qml) must treat null as "do not write" (same posture
// as every reader in Parser.js, and the same rule goal-files.md §6 sets
// for a reader that can't parse a file).
//
// What counts as a goal file, and how a task line splits into text and
// estimate, are Parser.js's rules, imported rather than copied: Writer
// may only edit what the reader would show, and two copies of a rule
// drift (they did -- see setFrontMatterValue and editTask). The
// dependency runs one way, so Parser.js stays free of imports.
//
// `<slug>.md` is the only thing this file edits in place. `<slug>.log.md`
// and the day files are append-only per the contract (§2) -- Writer.js
// only *formats* those entries (formatEventEntry); omvision.qml appends
// the result with a shell-free O_APPEND write (`tee -a`), never through
// this file's line-editing machinery, and never after a read.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

// Omvision's own convention, layered on top of the free-text event body
// line the contract already allows to be anything (§4: "one free-text
// line, no key: prefix"). It marks an event as counting toward the
// goal's invested-time figure in the Goal Detail header (see
// Parser.investedMinutes). Not part of goal-files.md's grammar -- a
// reader that doesn't know this convention just sees it as the start of
// the note text, which is harmless and exactly what §6's "skip what you
// don't understand" posture is for.
var EVENT_COUNTS_MARKER = "[+time] "

function detectEol(text) {
  return String(text || "").indexOf("\r\n") !== -1 ? "\r\n" : "\n"
}

function splitLines(text) {
  return String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n")
}

function joinLines(lines, eol) {
  return lines.join(eol || "\n")
}

function rtrim(line) {
  return String(line).replace(/\s+$/, "")
}

// ---- front matter ----------------------------------------------------------
// Whether a file is a goal file at all, and where its front matter is, is
// Parser.goalFrontMatter()'s call, not this file's: every entry point below
// that edits <slug>.md in place asks it first and returns null when it says
// no (goal-files.md §6: "not a goal file ... leave it alone, drop the
// operation, don't guess"). Writer used to keep its own fence-only check,
// which passed files the parser skips (a stray line that isn't "key:
// value", a missing title), and the task edits skipped the check entirely,
// so a half-hand-edited file still got tasks ticked, rewritten, or a "##
// Tasks" section stuck on top. Asking the reader means Writer never edits
// a file the app can't show.

// Sets `status:`, inserting it before the closing fence if absent. Goes
// through setFrontMatterValue(), so closing an already-closed goal leaves
// the line (and any trailing space on it) alone. A blank status is refused
// rather than taken as setFrontMatterValue's "remove the key": nothing asks
// for that, and a missing status reads as `active`, so it would be a silent
// reopen.
function setStatus(lines, newStatus) {
  if (String(newStatus === undefined || newStatus === null ? "" : newStatus).trim() === "") return null
  return setFrontMatterValue(lines, "status", newStatus)
}

// Sets `key: value` in the front matter, inserting it before the closing
// fence if absent; an empty value removes the key (estimate and done_by
// are optional, and "absent" is how §6 spells "not set"). The line edited
// is the one Parser read the value from (Parser.goalFrontMatter's lineOf:
// the last one, if a hand edit left the key twice), and removing a key
// removes every line of it, or clearing the later one would bring the
// earlier one back.
//
// A line whose value already equals `value` is left untouched, so saving
// the Edit goal dialog without changing anything rewrites nothing. "Equal"
// ignores a trailing "# note" only where Parser.frontMatterValue() does,
// which is `estimate` alone: saving the dialog keeps the coach's
// "estimate: 6   # was 9" note, while a title of "Fix bug #12" is all
// title, so renaming it "Fix bug" is a change and gets written. Applying
// the note rule to every key was the old behaviour, and it swallowed that
// rename without a word.
function setFrontMatterValue(lines, key, value) {
  var fm = Parser.goalFrontMatter(lines)
  if (!fm) return null
  var out = lines.slice()
  var v = (value === undefined || value === null) ? "" : String(value).replace(/[\r\n]+/g, " ").trim()
  if (v === "") {
    for (var i = fm.close - 1; i > fm.open; i--) {
      if (fm.keyAt[i] === key) out.splice(i, 1)
    }
    return out
  }
  var at = fm.lineOf[key]
  if (at === undefined) {
    out.splice(fm.close, 0, key + ": " + v)
    return out
  }
  var current = fm.fields[key].trim()
  if (current === v || Parser.frontMatterValue(key, current) === v) return out
  out[at] = key + ": " + v
  return out
}

// The Edit goal dialog's fields, applied one key at a time. The slug (and
// so the file name) never changes: <slug>.log.md and the engine's active
// goal both point at it.
function updateGoalFields(lines, fields) {
  if (String(fields.title || "").trim() === "") return null
  var out = setFrontMatterValue(lines, "title", fields.title)
  if (out) out = setFrontMatterValue(out, "why", fields.why)
  if (out) out = setFrontMatterValue(out, "estimate", fields.estimate)
  if (out) out = setFrontMatterValue(out, "done_by", fields.doneBy)
  return out
}

// ---- tasks -------------------------------------------------------------
// Searches from `from`, the line after the front matter's closing fence:
// the same lines Parser.parseTasks() is handed.
function findTasksSection(lines, from) {
  for (var i = from || 0; i < lines.length; i++) {
    if (/^##\s+Tasks\s*$/.test(rtrim(lines[i]))) {
      var start = i + 1
      var end = lines.length
      for (var j = start; j < lines.length; j++) {
        if (/^##\s+/.test(rtrim(lines[j]))) { end = j; break }
      }
      return { heading: i, start: start, end: end }
    }
  }
  return null
}

// Flips the Nth task line's "[ ]"/"[x]" marker, 0-indexed in the same
// top-to-bottom order Parser.parseTasks() reads them in -- that's what
// keeps a UI row index and a file line in agreement. Returns null (do not
// write) if the file isn't a goal file, there's no "## Tasks" section or
// the index is out of range, e.g. because the file changed under us since
// the screen last read it.
function toggleTask(lines, taskIndex) {
  var fm = Parser.goalFrontMatter(lines)
  if (!fm) return null
  var sec = findTasksSection(lines, fm.close + 1)
  if (!sec) return null
  var out = lines.slice()
  var seen = -1
  for (var i = sec.start; i < sec.end; i++) {
    // Matched against the line as-is, not its rtrimmed form: "(\].*)$"
    // already captures any trailing whitespace on the line, and
    // reconstructing from a trimmed match would silently drop it.
    var m = out[i].match(/^(-\s*\[)( |x|X)(\].*)$/)
    if (!m) continue
    seen++
    if (seen === taskIndex) {
      var newChar = (m[2] === " ") ? "x" : " "
      out[i] = m[1] + newChar + m[3]
      return out
    }
  }
  return null
}

// Appends a new, unchecked task as the last line of "## Tasks", right
// after the last existing task line (so a trailing blank line or the next
// "## " section stays exactly where it was). Creates the section -- right
// after the front-matter fence, or right before "## Coaching" if that
// exists but Tasks doesn't -- when the goal has none yet (§6: "no ##
// Tasks section yet -> zero tasks, not an error", the state a
// freshly-created or hand-written goal can be in). Returns null (no-op)
// for blank input, matching the UI spec ("empty input is a no-op"), and
// for a file that isn't a goal file, which gets no section added either.
function addTask(lines, taskText) {
  var text = String(taskText || "").replace(/[\r\n]+/g, " ").trim()
  if (text === "") return null
  var fm = Parser.goalFrontMatter(lines)
  if (!fm) return null

  var out = lines.slice()
  var sec = findTasksSection(out, fm.close + 1)
  if (sec) {
    var insertAt = sec.start
    for (var i = sec.start; i < sec.end; i++) {
      if (/^-\s*\[( |x|X)\]/.test(rtrim(out[i]))) insertAt = i + 1
    }
    out.splice(insertAt, 0, "- [ ] " + text)
    return out
  }

  var anchor = fm.close + 1
  for (var k = anchor; k < out.length; k++) {
    if (/^##\s+Coaching\s*$/.test(rtrim(out[k]))) { anchor = k; break }
  }
  out.splice(anchor, 0, "## Tasks", "- [ ] " + text)
  return out
}

// Replaces the Nth task line's text (same 0-indexed order as toggleTask)
// and nothing else. The "[ ]"/"[x]" marker and the spaces after it stay,
// and so does the suffix Parser.splitTaskBody() cuts off the text -- a
// "≈N" estimate with the run of spaces before it, and any trailing
// whitespace -- byte for byte. Parser.parseTasks() shows the text without
// that suffix, so an edit driven from the row's .text must not clobber it.
// This used to rebuild the suffix as " ≈N", which collapsed the "   ≈2"
// alignment the coach skill writes (and asks every writer to keep) on
// each edit. Blank text deletes the task line: emptying a task and saving
// it means "remove it". Returns null (do not write) for a file that isn't
// a goal file or an out-of-range index, same as toggleTask.
function editTask(lines, taskIndex, newText) {
  var text = String(newText || "").replace(/[\r\n]+/g, " ").trim()

  var fm = Parser.goalFrontMatter(lines)
  if (!fm) return null
  var sec = findTasksSection(lines, fm.close + 1)
  if (!sec) return null
  var out = lines.slice()
  var seen = -1
  for (var i = sec.start; i < sec.end; i++) {
    var m = out[i].match(/^(-\s*\[)( |x|X)(\]\s*)(.*)$/)
    if (!m) continue
    seen++
    if (seen === taskIndex) {
      if (text === "") { out.splice(i, 1); return out }
      out[i] = m[1] + m[2] + m[3] + text + Parser.splitTaskBody(m[4]).suffix
      return out
    }
  }
  return null
}

// ---- cancel note ----------------------------------------------------------
// Appends the cancel reason/takeaway as its own section at the end of the
// file. This is Omvision's own addition, not part of goal-files.md's
// fixed grammar -- a reader that doesn't recognise "## Cancelled" simply
// treats it the way §6 already requires treating any unrecognised
// section: inert, never fatal, never mistaken for "## Coaching" (whose
// heading it deliberately does not reuse). Trims trailing blank lines
// first so this doesn't accumulate a growing gap on repeated writes.
//
// The file keeps its final newline, if it had one. Trimming used to take
// it along with the blank lines, so a cancelled goal ended mid-line: a
// change nobody asked for, and a trap for the next tool that appends to
// the file (the coach's next "## Coaching" entry, an `echo >>`) and would
// glue its first line onto "takeaway: ...". Returns null for a file that
// isn't a goal file, like every other in-place edit here.
function appendCancelNote(lines, headingTs, reasonLabel, takeaway) {
  if (!Parser.goalFrontMatter(lines)) return null
  var out = lines.slice()
  var finalNewline = out[out.length - 1] === ""
  while (out.length > 0 && rtrim(out[out.length - 1]) === "") out.pop()
  out.push("")
  out.push("## Cancelled")
  out.push("### " + headingTs)
  out.push("reason: " + String(reasonLabel || "").replace(/[\r\n]+/g, " ").trim())
  out.push("takeaway: " + String(takeaway || "").replace(/[\r\n]+/g, " ").trim())
  if (finalNewline) out.push("")
  return out
}

function headingTimestamp(date) {
  var d = date || new Date()
  var hh = ("0" + d.getHours()).slice(-2)
  var mm = ("0" + d.getMinutes()).slice(-2)
  return d.getDate() + " " + MONTHS[d.getMonth()] + " " + hh + ":" + mm
}

// ---- log/day entry formatting (goal-files.md §4) ---------------------------
// Minutes under 60 are "<n>m"; 60 and over are "<h>h" or "<h>h<mm>" with
// the leftover minutes zero-padded and no trailing "m" -- the same rule
// notes-helper.py's format_duration() implements, reused as-is so
// headings never diverge in style between the two writers.
function formatDuration(minutes) {
  var m = Math.max(0, Math.round(Number(minutes) || 0))
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60), rem = m % 60
  if (rem === 0) return h + "h"
  return h + "h" + (rem < 10 ? "0" + rem : String(rem))
}

// Builds one event entry block exactly per §4: "### <D Mon HH:MM> ·
// event · <kind> · <duration>" then one free-text body line, followed by
// a blank line so appends never run two entries together. `started` is a
// local-time JS Date; the caller (never this function) decides the file
// this lands in, from that same Date -- goal log if a goal was chosen, a
// day file named after `started`'s local day otherwise (§4/§"append-day").
function formatEventEntry(started, minutes, kind, what, countsToward) {
  var ts = headingTimestamp(started || new Date())
  var dur = formatDuration(minutes)
  var body = String(what || "").replace(/[\r\n]+/g, " ").trim()
  if (countsToward) body = EVENT_COUNTS_MARKER + body
  return "### " + ts + " · event · " + String(kind || "other") + " · " + dur + "\n" + body + "\n\n"
}

// ---- small input parsers, used by the Add Event dialog ---------------------
// "today HH:MM" / "yesterday HH:MM" / "YYYY-MM-DD HH:MM" / bare "HH:MM"
// (defaults to today). Returns null on anything else so the dialog can
// refuse to submit rather than log a guessed time.
function parseWhen(str, now) {
  var s = String(str || "").trim()
  var base = now || new Date()
  var m

  m = s.match(/^today\s+(\d{1,2}):(\d{2})$/i)
  if (m) return new Date(base.getFullYear(), base.getMonth(), base.getDate(), Number(m[1]), Number(m[2]), 0, 0)

  m = s.match(/^yesterday\s+(\d{1,2}):(\d{2})$/i)
  if (m) {
    var d = new Date(base.getFullYear(), base.getMonth(), base.getDate(), Number(m[1]), Number(m[2]), 0, 0)
    d.setDate(d.getDate() - 1)
    return d
  }

  m = s.match(/^(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})$/)
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]), 0, 0)

  m = s.match(/^(\d{1,2}):(\d{2})$/)
  if (m) return new Date(base.getFullYear(), base.getMonth(), base.getDate(), Number(m[1]), Number(m[2]), 0, 0)

  return null
}

// Accepts a bare integer ("25", minutes) in addition to the "<h>h<mm>" /
// "<n>m" shapes §4 writes -- a duration the user types is free-form,
// unlike one this app formats itself. Returns 0 (which the dialog treats
// as invalid) if nothing matches.
function parseDurationInput(str) {
  var s = String(str || "").trim()
  if (/^\d+$/.test(s)) return Number(s)
  var m = s.match(/^(\d+)h(\d{2})?$/)
  if (m) return Number(m[1]) * 60 + (m[2] ? Number(m[2]) : 0)
  m = s.match(/^(\d+)m$/)
  if (m) return Number(m[1])
  return 0
}

// ---- new goal creation (Omvision only, goal-files.md §3 + §7) -------------

// Slug derivation, exactly per §3: lowercase the title, replace every run
// of characters outside [a-z0-9] with one "-", strip leading/trailing
// "-", and fall back to "goal" if nothing survives (a title that's all
// punctuation or non-ASCII). This is deliberately identical in shape to
// notes-helper.py's own derivation -- both sides of the contract have to
// agree on the same slug for the same title.
function deriveSlug(title) {
  var s = String(title || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return s.length > 0 ? s : "goal"
}

// One "key: value" front-matter line. The grammar (§6) is one key: value
// pair per line with no multi-line values, so a value that contains a
// newline (pasted text, a stray CR) would silently corrupt the file's
// shape -- collapse it to spaces and trim before it ever reaches a line.
// Only null and undefined count as "no value": a `value || ""` test here
// once turned an estimate of 0 into "estimate: " with nothing after it.
function fmLine(key, value) {
  var s = (value === undefined || value === null) ? "" : String(value)
  return key + ": " + s.replace(/[\r\n]+/g, " ").trim()
}

// Builds a brand-new <slug>.md from scratch: front matter (title, why,
// status: active, plus estimate/done_by only when the caller supplied
// them) and an empty "## Tasks" section, per the "New goal" dialog spec.
// An estimate of 0 is written as "estimate: 0", not left out: §6 keeps
// "absent" and "zero" apart ("Missing estimate -> simply absent ... not a
// zero"), Parser reads 0 as 0, and the goal detail shows "≈ 0 poms left",
// which is what the user typed. Omitting it would turn their answer into
// "no estimate".
// Always "\n" line endings -- there is no pre-existing file whose EOL
// style this needs to match, unlike every other Writer.js entry point.
function buildNewGoalFile(fields) {
  var lines = ["---"]
  lines.push(fmLine("title", fields.title))
  lines.push(fmLine("why", fields.why))
  lines.push("status: active")
  if (fields.estimate !== undefined && fields.estimate !== null && fields.estimate !== "") {
    lines.push(fmLine("estimate", fields.estimate))
  }
  if (fields.doneBy !== undefined && fields.doneBy !== null && fields.doneBy !== "") {
    lines.push(fmLine("done_by", fields.doneBy))
  }
  lines.push("---")
  lines.push("## Tasks")
  lines.push("")
  return lines.join("\n")
}
