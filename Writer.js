.pragma library

// Write-path helpers for the ompom/Omvision file contract -- see
// ~/Code/ompom-engine/docs/goal-files.md. Parser.js reads tolerantly;
// this file writes precisely, and does it by surgical line edits rather
// than reparse-and-reserialize, so anything not being changed -- unknown
// front-matter keys, section order, blank lines, the user's own prose in
// "## Coaching" -- survives byte for byte. Nothing here throws: every
// entry point returns null on anything it can't safely edit, and the
// caller (omvision.qml) must treat null as "do not write" (same posture
// as every reader in Parser.js, and the same rule goal-files.md §6 sets
// for a reader that can't parse a file).
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
// Same restricted-YAML shape Parser.parseGoalFile reads (goal-files.md §6):
// a "---" line (after any leading blank lines), then a closing "---" line.
function findFrontMatter(lines) {
  var i = 0
  while (i < lines.length && rtrim(lines[i]) === "") i++
  if (i >= lines.length || rtrim(lines[i]) !== "---") return null
  var open = i
  for (var j = i + 1; j < lines.length; j++) {
    if (rtrim(lines[j]) === "---") return { open: open, close: j }
  }
  return null
}

// Sets (or, if absent, inserts) the `status:` front-matter key. Returns a
// new lines array, or null if the file has no parseable front matter --
// the caller must not write in that case (goal-files.md §6).
function setStatus(lines, newStatus) {
  var fm = findFrontMatter(lines)
  if (!fm) return null
  var out = lines.slice()
  for (var i = fm.open + 1; i < fm.close; i++) {
    if (/^status:\s?/.test(rtrim(out[i]))) {
      out[i] = "status: " + newStatus
      return out
    }
  }
  out.splice(fm.close, 0, "status: " + newStatus)
  return out
}

// ---- tasks -------------------------------------------------------------
function findTasksSection(lines) {
  for (var i = 0; i < lines.length; i++) {
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
// write) if there's no "## Tasks" section or the index is out of range,
// e.g. because the file changed under us since the screen last read it.
function toggleTask(lines, taskIndex) {
  var sec = findTasksSection(lines)
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
// for blank input, matching the UI spec ("empty input is a no-op").
function addTask(lines, taskText) {
  var text = String(taskText || "").replace(/[\r\n]+/g, " ").trim()
  if (text === "") return null

  var out = lines.slice()
  var sec = findTasksSection(out)
  if (sec) {
    var insertAt = sec.start
    for (var i = sec.start; i < sec.end; i++) {
      if (/^-\s*\[( |x|X)\]/.test(rtrim(out[i]))) insertAt = i + 1
    }
    out.splice(insertAt, 0, "- [ ] " + text)
    return out
  }

  var fm = findFrontMatter(out)
  var anchor = fm ? fm.close + 1 : 0
  for (var k = anchor; k < out.length; k++) {
    if (/^##\s+Coaching\s*$/.test(rtrim(out[k]))) { anchor = k; break }
  }
  out.splice(anchor, 0, "## Tasks", "- [ ] " + text)
  return out
}

// ---- cancel note ----------------------------------------------------------
// Appends the cancel reason/takeaway as its own section at the end of the
// file. This is Omvision's own addition, not part of goal-files.md's
// fixed grammar -- a reader that doesn't recognise "## Cancelled" simply
// treats it the way §6 already requires treating any unrecognised
// section: inert, never fatal, never mistaken for "## Coaching" (whose
// heading it deliberately does not reuse). Trims trailing blank lines
// first so this doesn't accumulate a growing gap on repeated writes.
function appendCancelNote(lines, headingTs, reasonLabel, takeaway) {
  var out = lines.slice()
  while (out.length > 0 && rtrim(out[out.length - 1]) === "") out.pop()
  out.push("")
  out.push("## Cancelled")
  out.push("### " + headingTs)
  out.push("reason: " + String(reasonLabel || "").replace(/[\r\n]+/g, " ").trim())
  out.push("takeaway: " + String(takeaway || "").replace(/[\r\n]+/g, " ").trim())
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
function fmLine(key, value) {
  return key + ": " + String(value || "").replace(/[\r\n]+/g, " ").trim()
}

// Builds a brand-new <slug>.md from scratch: front matter (title, why,
// status: active, plus estimate/done_by only when the caller supplied
// them) and an empty "## Tasks" section, per the "New goal" dialog spec.
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
