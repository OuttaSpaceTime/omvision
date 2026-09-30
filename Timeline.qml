import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// The goal detail's "What happened": a goal's log entries, newest first,
// grouped under one header per day. Read-only; scrolls on its own. One
// entry's row is TimelineEntry.qml.
Flickable {
  id: root

  // The goal's log entries as Parser.parseLogEntries returns them,
  // newest last (as stored).
  property var logEntries: []

  contentHeight: timelineColumn.height
  clip: true

  // Day groups, newest day first, each holding its entries newest first.
  function groupByDay(entries) {
    var byDay = {}
    var order = []
    for (var i = entries.length - 1; i >= 0; i--) { // newest first
      var e = entries[i]
      var key = Parser.dayKey(e.date)
      if (!byDay[key]) { byDay[key] = { key: key, date: e.date, entries: [] }; order.push(key) }
      byDay[key].entries.push(e)
    }
    var out = []
    for (var j = 0; j < order.length; j++) out.push(byDay[order[j]])
    return out
  }
  readonly property var dayGroups: groupByDay(logEntries)

  // A day header's duration: "50 min", "1 h", "1 h 05". Not
  // Parser.formatHCaption, which leaves the minutes unpadded ("1 h 5").
  function formatDayDuration(total) {
    var h = Math.floor(total / 60), m = total % 60
    if (h === 0) return m + " min"
    if (m === 0) return h + " h"
    return h + " h " + (m < 10 ? "0" + m : String(m))
  }

  TextMetrics {
    id: timeMetrics
    font.family: Theme.fontFamily
    font.pixelSize: Theme.captionSize
    text: "00:00"
  }

  Column {
    id: timelineColumn
    // Clear of the rail's hairline by the same gap the rail keeps on
    // its side of it; wrapped lines used to run right up to the rule.
    width: parent.width - Theme.spaceLg
    spacing: Theme.spaceSm

    Text {
      text: "What happened"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      font.bold: true
      color: Theme.dim
    }

    Text {
      visible: root.dayGroups.length === 0
      text: "No sessions logged yet."
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
      color: Theme.faint
    }

    Repeater {
      model: root.dayGroups
      delegate: Column {
        id: dayBlock
        required property var modelData
        width: timelineColumn.width
        spacing: Theme.spaceXs

        RowLayout {
          width: dayBlock.width
          spacing: Theme.spaceSm
          Text {
            text: Parser.dayHeaderLabel(dayBlock.modelData.date)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            color: Theme.ink
          }
          Text {
            text: {
              var n = Parser.pomodoroCount(dayBlock.modelData.entries)
              return n + (n === 1 ? " pom · " : " poms · ")
                + root.formatDayDuration(Parser.pomodoroMinutes(dayBlock.modelData.entries))
            }
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySmallSize
            color: Theme.dim
          }
          // Holds the row's surplus width. Without it the layout spread
          // that width between the two labels and the day's summary
          // drifted to the middle of the column.
          Item { Layout.fillWidth: true }
        }

        Repeater {
          model: dayBlock.modelData.entries
          delegate: TimelineEntry {
            required property var modelData
            width: dayBlock.width
            entry: modelData
            // Wide enough for any HH:MM at this size, so every entry's
            // rule and node sit on one vertical line. A typed 40 fitted
            // 11px digits and clipped larger ones.
            timeWidth: Math.ceil(timeMetrics.advanceWidth)
          }
        }
      }
    }
  }
}
