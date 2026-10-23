import QtQuick

import "../../Parser.js" as Parser

// Logging an event through the Add event dialog: one entry appended to the
// day file (no goal picked), in goal-files.md §4's grammar, and the app
// reads it back. The only test of the append path (Appender.qml, `tee -a`).
// The fixture has no days/ folder, so the append has to create it, and the
// day file appears after the app started, as a goal-less run's does.
OmvisionTest {
  name: "event"

  function test_add_an_event_to_the_day() {
    var day = "days/" + Parser.dayKey(new Date()) + ".md"
    var before = readFile(day) || ""
    app.openEventDialog("")
    tryCompare(app, "eventDialogOpen", true)
    type("Bouldering")
    click("eventLengthField")
    type("1h30")
    key(Qt.Key_Return)
    tryCompare(app, "eventDialogOpen", false)
    expectFile(day, function(text) {
      var added = text.slice(before.length)
      return text.indexOf(before) === 0
        && /^### \d{1,2} [A-Z][a-z]{2} \d\d:\d\d · event · training · 1h30\nBouldering\n\n$/.test(added)
    })
    tryVerify(function() {
      return app.dayEntries.some(function(e) { return e.type === "event" && e.title === "Bouldering" && e.minutes === 90 })
    }, 5000, "the app reads the event back")
  }

  // A day file another program creates while the app runs -- ompom's first
  // goal-less run of the day -- shows up too. A file that didn't exist when
  // the app started used to stay unseen until a restart.
  function test_a_day_file_written_elsewhere_shows() {
    run(["/usr/bin/mkdir", "-p", notesPath("days")])
    writeFile("days/" + Parser.dayKey(new Date()) + ".md", "### 1 Jan 09:00 · 25m\nid: x\ndone: from ompom\n\n")
    tryVerify(function() { return app.dayEntries.some(function(e) { return e.done === "from ompom" }) }, 8000,
              "the app reads the new day file")
  }
}
