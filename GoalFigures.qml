import QtQuick

import "Parser.js" as Parser

// The goal detail's figures line: poms and time in, poms left, tasks done.
//
// Independent facts, not a rigid row: each sized to its own content in a
// Flow so it wraps onto a second line at narrow widths instead of
// running off the edge.
Flow {
  id: root

  property int poms: 0
  // Minutes invested (Parser.investedMinutes), not only the pomodoros'.
  property int minutes: 0
  // The goal's `estimate:`, or undefined when it has none.
  property var estimate: undefined
  property int tasksDone: 0
  property int taskCount: 0

  spacing: Theme.spaceXl

  Text {
    // Parser.formatHm, not a local hours-only calculation: flooring to
    // whole hours rendered two pomodoros as "0 h in", which is both wrong
    // and the most discouraging possible way to state 50 minutes of work.
    text: root.poms + (root.poms === 1 ? " pom · " : " poms · ") + Parser.formatHm(root.minutes) + " in"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    color: Theme.ink
  }
  Text {
    // `estimate:` is poms REMAINING, not the goal's total -- the coach
    // rewrites it down each session, so this is a direct read of the
    // field, never `est - poms` (that double-counts: a goal with 2
    // poms done and estimate: 3 means 3 poms remain, not 1). Says
    // "poms left", not just "left": this sits beside "N of M tasks" in
    // the same row, and a bare number there would read as a second
    // fraction over that M instead of a different unit.
    visible: root.estimate !== undefined
    text: "≈ " + (root.estimate !== undefined ? root.estimate : 0) + " poms left"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    color: Theme.ink
  }
  Text {
    text: root.tasksDone + " of " + root.taskCount + " tasks"
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    color: Theme.ink
  }
}
