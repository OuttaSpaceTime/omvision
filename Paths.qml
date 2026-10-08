pragma Singleton
import QtQuick
import Quickshell

// Where Omvision's files live, in one place. The layout is the goal file
// contract's (docs/goal-files.md):
//   ~/Notes/Omvision/goals/<slug>.md       the goal: front matter, tasks
//   ~/Notes/Omvision/goals/<slug>.log.md   its pomodoros and events, append-only
//   ~/Notes/Omvision/days/YYYY-MM-DD.md    runs and events with no goal, append-only
//   ~/Notes/Omvision/journal/YYYY-MM-DD.md the journal, one file per day
//
// A singleton the same way Theme is. There is no qmldir in this directory:
// Quickshell scans the config's QML files and, for any that starts with
// `pragma Singleton`, synthesizes the qmldir entry that registers it (its
// scanner logs "Synthesizing qmldir for directory"). A hand-written qmldir
// would switch that off for the whole directory, and Theme with it.
//
// HOME is read here once, so a test run pointed at a fixture HOME (see
// docs/layout-rules.md, "Screenshotting") moves every path together.
QtObject {
  readonly property string home: Quickshell.env("HOME")
  readonly property string notesDir: home + "/Notes/Omvision"
  readonly property string goalsDir: notesDir + "/goals"
  readonly property string daysDir: notesDir + "/days"
  // The journal is not filed under a goal: one free-form file per calendar
  // day, flat, about whatever was on your mind that day. A reader (the coach
  // skill) takes the directory whole and decides for itself what is relevant.
  readonly property string journalDir: notesDir + "/journal"

  function goalFile(slug) { return goalsDir + "/" + slug + ".md" }
  function goalLog(slug) { return goalsDir + "/" + slug + ".log.md" }
  // `dayKey` is Parser.dayKey()'s YYYY-MM-DD.
  function dayFile(dayKey) { return daysDir + "/" + dayKey + ".md" }
  function journalFile(dayKey) { return journalDir + "/" + dayKey + ".md" }

  // The day a journal file is for, from its name: ".../2026-09-24.md" ->
  // "2026-09-24". "" for anything that isn't a journal day file, which is how
  // a stray file in the directory is told apart from an entry.
  function journalDateIso(path) {
    var m = String(path).replace(/^.*\//, "").match(/^(\d{4}-\d{2}-\d{2})\.md$/)
    return m ? m[1] : ""
  }
}
