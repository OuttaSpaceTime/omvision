.pragma library

// Parsing for the ompom / Omvision / coach file contract.
// See ~/Code/ompom-engine/docs/goal-files.md §6 for the tolerance rules this
// file implements. Nothing here throws: a file that doesn't fit the grammar
// is skipped (front matter) or has the offending piece skipped (tasks, log
// entries) — never fatal to the caller.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var WEEKDAYS_TITLE = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

// "2026-09-24" -> "Thu 24 Sep". Anything that doesn't parse as YYYY-MM-DD is
// returned unchanged — done_by is free-text as far as §6 is concerned, so a
// reader tolerates whatever a hand-written goal file put there.
function formatShortDate(iso) {
  var m = String(iso || "").match(/^(\d{4})-(\d{2})-(\d{2})/)
  if (!m) return iso
  var d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
  if (isNaN(d.getTime())) return iso
  return WEEKDAYS_TITLE[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()]
}

function normalize(text) {
  return String(text || "").replace(/\r\n/g, "\n").replace(/\r/g, "\n")
}

function rtrim(line) {
  return line.replace(/\s+$/, "")
}

// ---- §6 front matter -------------------------------------------------------
// Restricted YAML subset: a "---" line (after any leading blank lines), one
// "key: value" pair per line, a closing "---" line. Anything else (no
// closing fence, a stray line that isn't "key: value", no fence at all) is
// not a goal file: skip the whole file. Missing `title` also means skip.
//
// goalFrontMatter() is that rule, and the only copy of it: parseGoalFile()
// reads through it, and Writer.js calls it before every in-place edit and
// refuses (returns null) whenever it does. Writer used to carry its own
// check that only looked for the two fences, so it would edit a file this
// parser had already skipped -- a status set on a file the Goals screen
// doesn't list. One function means the two can't drift apart again.
//
// Takes lines as Writer.splitLines() or normalize().split() give them (no
// "\r"; trailing whitespace is ignored here, and left on the lines for
// Writer to keep). Returns null, or:
//   open, close  the indices of the two fence lines
//   fields       key -> value as written (after "key:" and at most one
//                space), for every key; a repeated key's last line wins
//   lineOf       key -> the index of the line `fields` took the value from,
//                so a Writer edit lands on the line the reader shows
//   keyAt        line index -> key, for each line between the fences
var FRONT_MATTER_LINE = /^([A-Za-z0-9_-]+):\s?(.*)$/

function goalFrontMatter(lines) {
  if (!lines) return null
  var i = 0
  while (i < lines.length && rtrim(lines[i]) === "") i++
  if (i >= lines.length || rtrim(lines[i]) !== "---") return null

  var fm = { open: i, close: -1, fields: {}, lineOf: {}, keyAt: {} }
  for (var j = i + 1; j < lines.length; j++) {
    var line = rtrim(lines[j])
    if (line === "---") { fm.close = j; break }
    var m = line.match(FRONT_MATTER_LINE)
    if (!m) return null // a line that isn't key: value and isn't the fence
    fm.fields[m[1]] = m[2]
    fm.lineOf[m[1]] = j
    fm.keyAt[j] = m[1]
  }
  if (fm.close === -1) return null
  if (!fm.fields.title) return null
  return fm
}

// A front-matter value with its trailing "# note" removed, for the keys
// that may carry one. goal-files.md §6 shows exactly one such note, the
// coach's `estimate: 6   # was 9 — session 2`, and never one on any other
// key, so only `estimate` gets this treatment. That is also the only key
// where it is safe: an estimate is a number and can't contain "#", while
// title, why and done_by are free text in which "#" is content -- "Fix bug
// #12" is a title, not "Fix bug" plus a note. (Stripping it from every key
// was tried, in Writer.js, and made that rename impossible.) As in YAML,
// "#" starts a note only at the start of the value or after whitespace, so
// "6#9" is not 6.
//
// Writer.setFrontMatterValue() uses the same function to tell "the dialog
// saved the estimate unchanged" (keep the note) from a real change.
var COMMENT_KEYS = { estimate: true }

function frontMatterValue(key, raw) {
  var v = String(raw === undefined || raw === null ? "" : raw)
  if (COMMENT_KEYS[key] === true) v = v.replace(/(^|\s)#.*$/, "")
  return v.trim()
}

function parseGoalFile(text) {
  var lines = normalize(text).split("\n").map(rtrim)
  var front = goalFrontMatter(lines)
  if (!front) return null
  var fm = front.fields
  var est = frontMatterValue("estimate", fm.estimate)

  var meta = {
    title: fm.title,
    why: fm.why !== undefined ? fm.why : "",
    status: fm.status ? fm.status : "active",
    estimate: (est !== "" && !isNaN(Number(est))) ? Number(est) : undefined,
    done_by: fm.done_by ? fm.done_by : undefined,
    raw: fm
  }

  var rest = lines.slice(front.close + 1)
  meta.tasks = parseTasks(rest)
  meta.coaching = parseCoaching(rest)
  meta.cancelled = parseCancelNote(rest)
  return meta
}

// ---- Tasks ------------------------------------------------------------------
// "## Tasks" holds "- [ ]" / "- [x]" lines with an optional trailing "≈N".
// No "## Tasks" section → zero tasks, not an error.
function parseTasks(lines) {
  var tasks = []
  var start = -1
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].match(/^##\s+Tasks\s*$/)) { start = i + 1; break }
  }
  if (start === -1) return tasks

  for (var j = start; j < lines.length; j++) {
    var line = lines[j]
    if (line.match(/^##\s+/)) break // next section
    var m = line.match(/^-\s*\[( |x|X)\]\s*(.*)$/)
    if (!m) continue
    var body = splitTaskBody(m[2])
    tasks.push({
      done: (m[1] === "x" || m[1] === "X"),
      text: body.text,
      estimate: body.estimate
    })
  }
  return tasks
}

// A task line's body (what follows "- [ ] ") cut into the task's text and
// the suffix after it: an optional "≈N" with whatever spaces sit before it,
// then any trailing whitespace. text + suffix is always the whole body, and
// text never ends in whitespace. parseTasks() shows `text` and `estimate`;
// Writer.editTask() replaces `text` and keeps `suffix` byte for byte, so
// the coach's "   ≈2" alignment survives an edit. Sharing the split is what
// makes "the text the row shows" and "the text an edit replaces" the same
// characters. "≈ 5" (a space after the sign) is not an estimate, as before.
function splitTaskBody(body) {
  var s = String(body === undefined || body === null ? "" : body)
  var m = s.match(/^(.*?)(\s*≈(\d+))?\s*$/)
  // Only a stray line break defeats "." -- callers split lines first.
  if (!m) return { text: s, estimate: undefined, suffix: "" }
  return {
    text: m[1],
    estimate: m[3] !== undefined ? Number(m[3]) : undefined,
    suffix: s.slice(m[1].length)
  }
}

// ---- "## Coaching" section ----------------------------------------------------
// "## Coaching" holds "### Session <N> · <D Mon> · <method>" headings, each
// followed by free-text lines the coach skill wrote. No "## Coaching" section
// → zero sessions, not an error (§6, same tolerance as "## Tasks").
var COACHING_SESSION_HEAD = /^###\s+Session\s+(\d+)\s*·\s*([^·]+?)\s*·\s*(.+?)\s*$/

function parseCoaching(lines) {
  var sessions = []
  var start = -1
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].match(/^##\s+Coaching\s*$/)) { start = i + 1; break }
  }
  if (start === -1) return sessions

  var i2 = start
  while (i2 < lines.length) {
    var line = lines[i2]
    if (line.match(/^##[^#]/) || line === "##") break // next level-2 section
    var m = line.match(COACHING_SESSION_HEAD)
    if (m) {
      var num = Number(m[1]), date = m[2], method = m[3]
      i2++
      var summary = ""
      while (i2 < lines.length && !lines[i2].match(/^###\s/) && !(lines[i2].match(/^##[^#]/) || lines[i2] === "##")) {
        if (summary === "" && lines[i2].trim() !== "") summary = lines[i2].trim()
        i2++
      }
      sessions.push({ session: num, date: date, method: method, summary: summary })
    } else {
      i2++
    }
  }
  return sessions
}

// ---- §4 log entry grammar ----------------------------------------------------
var POM_HEAD = /^###\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2}):(\d{2})\s*·\s*(\d+)m\s*$/
var EVT_HEAD = /^###\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{2}):(\d{2})\s*·\s*event\s*·\s*([^·]+?)\s*·\s*(.+?)\s*$/

function monthIndex(abbrev) {
  for (var i = 0; i < MONTHS.length; i++) {
    if (MONTHS[i].toLowerCase() === String(abbrev).toLowerCase()) return i
  }
  return -1
}

// Headings carry no year. Entries are read against "now"'s year, with a
// year-wrap allowance: if the resulting date would land more than ~2 days in
// the future, assume it belongs to last year instead (handles reading old
// logs in January without a year rolling entries into "the future").
function resolveDate(day, monIdx, hh, mm, now) {
  var year = now.getFullYear()
  var d = new Date(year, monIdx, day, hh, mm, 0, 0)
  var twoDaysMs = 2 * 24 * 60 * 60 * 1000
  if (d.getTime() - now.getTime() > twoDaysMs) {
    d = new Date(year - 1, monIdx, day, hh, mm, 0, 0)
  }
  return d
}

// Omvision's own "counts toward the goal's invested time" marker on an
// event's free-text body line -- see Writer.js's EVENT_COUNTS_MARKER for
// why this is safe to layer on top of §4's freeform body line rather than
// needing a new field in the fixed grammar. Duplicated here (not
// imported from Writer.js) so Parser.js keeps its zero-dependency,
// read-only character; the two files just have to agree on the literal
// string, which is exactly what the comment on each side is for.
var EVENT_COUNTS_MARKER = "[+time] "

function stripEventCountsMarker(title) {
  var t = String(title || "")
  if (t.indexOf(EVENT_COUNTS_MARKER) === 0) {
    return { countsToward: true, text: t.slice(EVENT_COUNTS_MARKER.length) }
  }
  return { countsToward: false, text: t }
}

function parseDurationToMinutes(s) {
  var m = String(s || "").match(/^(\d+)h(\d{2})?$/)
  if (m) return Number(m[1]) * 60 + (m[2] ? Number(m[2]) : 0)
  m = String(s || "").match(/^(\d+)m$/)
  if (m) return Number(m[1])
  return 0
}

// Parses a flat log/day file into an array of entries, newest-last (as
// stored). A "###" line that doesn't match either heading shape, and its
// body, is skipped — it does not abort the rest of the file.
function parseLogEntries(text, now) {
  var lines = normalize(text).split("\n").map(rtrim)
  var entries = []
  var i = 0
  var referenceNow = now || new Date()

  while (i < lines.length) {
    var line = lines[i]
    if (line.match(/^###\s/)) {
      var pm = line.match(POM_HEAD)
      var em = !pm ? line.match(EVT_HEAD) : null
      if (pm) {
        var day = Number(pm[1]), monIdx = monthIndex(pm[2])
        var hh = Number(pm[3]), mm = Number(pm[4]), minutes = Number(pm[5])
        i++
        var body = []
        while (i < lines.length && !lines[i].match(/^###\s/)) { body.push(lines[i]); i++ }
        if (monIdx === -1) continue // unparseable month, skip entry silently
        // `else:` is goal-files.md §4's "Anything else?" line, written only
        // when the break's open question was answered -- so its absence is
        // the normal case and never an error.
        var focus = "", done = "", left = "", other = ""
        for (var b = 0; b < body.length; b++) {
          var fm2 = body[b].match(/^focus:\s?(.*)$/)
          var dm = body[b].match(/^done:\s?(.*)$/)
          var lm = body[b].match(/^left:\s?(.*)$/)
          var om = body[b].match(/^else:\s?(.*)$/)
          if (fm2) focus = fm2[1]
          else if (dm) done = dm[1]
          else if (lm) left = lm[1]
          else if (om) other = om[1]
        }
        entries.push({
          type: "pomodoro",
          date: resolveDate(day, monIdx, hh, mm, referenceNow),
          minutes: minutes,
          heading: pm[1] + " " + pm[2] + " " + pm[3] + ":" + pm[4],
          focus: focus, done: done, left: left, other: other
        })
      } else if (em) {
        var day2 = Number(em[1]), monIdx2 = monthIndex(em[2])
        var hh2 = Number(em[3]), mm2 = Number(em[4])
        var kind = em[5], duration = em[6]
        i++
        var body2 = []
        while (i < lines.length && !lines[i].match(/^###\s/)) { body2.push(lines[i]); i++ }
        if (monIdx2 === -1) continue
        var freeText = ""
        for (var b2 = 0; b2 < body2.length; b2++) {
          if (body2[b2].trim() !== "") { freeText = body2[b2].trim(); break }
        }
        var stripped = stripEventCountsMarker(freeText)
        entries.push({
          type: "event",
          date: resolveDate(day2, monIdx2, hh2, mm2, referenceNow),
          minutes: parseDurationToMinutes(duration),
          heading: em[1] + " " + em[2] + " " + em[3] + ":" + em[4],
          kind: kind, duration: duration, title: stripped.text,
          countsToward: stripped.countsToward
        })
      } else {
        // Malformed "###" heading: skip just this line, keep scanning.
        i++
      }
    } else {
      i++
    }
  }
  return dedupePomodoros(entries)
}

// One pomodoro, one entry.
//
// `.log.md` and `days/*.md` are append-only by contract, so a writer that
// saves the same run twice leaves two entries behind and can never take one
// back. ompom used to do exactly that -- pressing the notes screen's back
// control again, or reopening "Take notes" during the same break, appended
// the same run under the same `### <D Mon HH:MM> · <N>m` heading, with
// whatever done/left/else had been typed by then. That is fixed at the
// source now, but the duplicates it already wrote are on disk forever, and
// nothing here may rewrite an append-only file to clean them up.
//
// So the reader collapses them: same heading and same duration is the same
// pomodoro -- two runs cannot start in the same minute -- and the last one
// wins, because each re-save carried the fuller note. Display only; the file
// is untouched.
function dedupePomodoros(entries) {
  var lastIndexByKey = {}
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].type !== "pomodoro") continue
    lastIndexByKey[entries[i].heading + "·" + entries[i].minutes] = i
  }
  var out = []
  for (var j = 0; j < entries.length; j++) {
    var e = entries[j]
    if (e.type === "pomodoro" && lastIndexByKey[e.heading + "·" + e.minutes] !== j) continue
    out.push(e)
  }
  return out
}

// Total minutes actually invested in a goal: every pomodoro, plus any
// event explicitly marked "counts toward goal time" when it was logged
// (see EVENT_COUNTS_MARKER above). An event without that mark is real
// history on the timeline but stays out of this figure, same as it stays
// out of the "poms" progress count -- it never went through the timer.
function investedMinutes(entries) {
  var n = 0
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (e.type === "pomodoro") n += e.minutes
    else if (e.type === "event" && e.countsToward) n += e.minutes
  }
  return n
}

// How many pomodoros `entries` holds, and how many minutes they ran. Events
// count in neither, even ones marked to count toward the goal's time: these
// two are the timer's own figures (a day's "3 poms · 1 h 15"), while
// investedMinutes() above is the goal's total. Take a day's entries first to
// get one day's figures.
function pomodoroCount(entries) {
  var n = 0
  for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n++
  return n
}

function pomodoroMinutes(entries) {
  var n = 0
  for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n += entries[i].minutes
  return n
}

// How many of a goal's tasks (meta.tasks) are ticked. The Goals rows and
// the goal detail both show it, and each used to count it by hand.
function doneTaskCount(tasks) {
  var n = 0
  for (var i = 0; i < tasks.length; i++) if (tasks[i].done) n++
  return n
}

// The clock time an entry's heading carries: "28 Sep 09:30" -> "09:30". The
// timeline and the Today screen show it in their time column.
function entryTime(e) {
  return String(e.heading).split(" ").pop()
}

// ---- "## Cancelled" (Omvision's own section, see Writer.appendCancelNote) --
// Takes the same already-normalized `rest` lines parseTasks()/
// parseCoaching() do. Reads the *last* such section in the file (a goal
// is only meant to be cancelled once, but re-reading defensively costs
// nothing). No section -> null, same "absent is not an error" posture as
// everything else in this file.
function parseCancelNote(lines) {
  var found = null
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].match(/^##\s+Cancelled\s*$/)) continue
    var when = "", reason = "", takeaway = ""
    var j = i + 1
    if (j < lines.length && lines[j].match(/^###\s+(.+)$/)) { when = lines[j].replace(/^###\s+/, ""); j++ }
    for (; j < lines.length && !lines[j].match(/^##\s+/); j++) {
      var rm = lines[j].match(/^reason:\s?(.*)$/)
      var tm = lines[j].match(/^takeaway:\s?(.*)$/)
      if (rm) reason = rm[1]
      else if (tm) takeaway = tm[1]
    }
    found = { when: when, reason: reason, takeaway: takeaway }
  }
  return found
}

function dayKey(date) {
  var y = date.getFullYear()
  var m = ("0" + (date.getMonth() + 1)).slice(-2)
  var d = ("0" + date.getDate()).slice(-2)
  return y + "-" + m + "-" + d
}

function dayHeaderLabel(date) {
  return WEEKDAYS_TITLE[date.getDay()] + " " + date.getDate() + " " + MONTHS[date.getMonth()]
}

function formatHm(totalMinutes) {
  var h = Math.floor(totalMinutes / 60)
  var m = totalMinutes % 60
  if (h === 0) return m + "m"
  if (m === 0) return h + "h"
  return h + "h " + m + "m"
}

// "1 h 15"-style caption: Today's summary line and a timeline event's label.
function formatHCaption(totalMinutes) {
  var h = Math.floor(totalMinutes / 60)
  var m = totalMinutes % 60
  if (h === 0) return m + " min"
  if (m === 0) return h + " h"
  return h + " h " + m
}

// ---- Journal --------------------------------------------------------------
// First non-blank line of a journal entry, markdown syntax stripped, for use
// as a list preview. Tolerant of anything: an entry is free-form markdown
// (goal-files.md, journal section) with no grammar to fail to parse.
function firstMeaningfulLine(text) {
  var lines = normalize(text).split("\n")
  for (var i = 0; i < lines.length; i++) {
    var t = lines[i].trim()
    if (t === "") continue
    t = t.replace(/^#{1,6}\s+/, "")
    t = t.replace(/^[-*]\s+/, "")
    t = t.replace(/^>\s?/, "")
    t = t.replace(/`([^`]+)`/g, "$1")
    t = t.replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    return t
  }
  return ""
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

// Inline code + links, applied to already-escaped text. `styles` carries the
// caller's colours as CSS colour strings (Parser.js has no Theme dependency,
// so the QML side hands these in already formatted).
function mdInline(s, styles) {
  s = s.replace(/`([^`]+)`/g, function(_, code) {
    return '<span style="background-color:' + styles.codeBg + ';"> ' + code + ' </span>'
  })
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, url) {
    return '<a href="' + url + '" style="color:' + styles.accent + '; text-decoration:underline;">' + label + '</a>'
  })
  return s
}

// Renders a journal entry's markdown as Qt rich text (Text.RichText): headings
// bold at body size (not larger), "-"/"*" list markers dimmed, ">" quotes
// italic, inline code on a faint fill, links accent-coloured and underlined.
// The markdown characters themselves are never shown — only their effect.
function mdToHtml(text, styles) {
  var lines = normalize(text).split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var raw = lines[i]
    var trimmed = raw.trim()

    var h = trimmed.match(/^(#{1,6})\s+(.*)$/)
    var listM = trimmed.match(/^[-*]\s+(.*)$/)
    var quoteM = trimmed.match(/^>\s?(.*)$/)

    if (h) {
      out.push('<p><b>' + mdInline(escapeHtml(h[2]), styles) + '</b></p>')
    } else if (listM) {
      out.push('<p><span style="color:' + styles.dim + ';">-</span> ' + mdInline(escapeHtml(listM[1]), styles) + '</p>')
    } else if (quoteM) {
      out.push('<p><i>' + mdInline(escapeHtml(quoteM[1]), styles) + '</i></p>')
    } else if (trimmed === "") {
      out.push('<p></p>')
    } else {
      out.push('<p>' + mdInline(escapeHtml(raw), styles) + '</p>')
    }
  }
  return out.join("\n")
}
