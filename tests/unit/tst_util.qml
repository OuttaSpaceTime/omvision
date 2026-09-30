import QtQuick
import QtTest

import "../../Util.js" as Util

// Util.js's helpers build new state objects and lists; none of them may
// change what they were given.
TestCase {
  name: "Util"

  function test_goalsByTitle() {
    var data = {
      "b-goal": { meta: { title: "Beta" }, logEntries: [{ type: "pomodoro" }] },
      "broken": { meta: null, logEntries: [] },
      "a-goal": { meta: { title: "Alpha" } },
      "gone": null
    }
    var list = Util.goalsByTitle(data)
    compare(list.length, 2, "a goal without meta, or with no entry at all, is left out")
    compare(list[0].slug, "a-goal")
    compare(list[1].slug, "b-goal")
    compare(list[0].meta.title, "Alpha")
    compare(list[0].logEntries.length, 0, "missing logEntries read as none")
    compare(list[1].logEntries.length, 1)
    compare(Object.keys(data).length, 4, "the input is left alone")
    compare(Util.goalsByTitle({}).length, 0)
  }
}
