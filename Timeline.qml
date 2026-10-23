pragma ComponentBehavior: Bound

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
    var byDay = {}, out = []
    for (let i = entries.length - 1; i >= 0; i--) { // newest first
      const e = entries[i], key = Parser.dayKey(e.date)
      if (!byDay[key]) out.push(byDay[key] = { key: key, date: e.date, entries: [] })
      byDay[key].entries.push(e)
    }
    return out
  }
  readonly property var dayGroups: groupByDay(logEntries)

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

    CaptionLabel { text: "What happened" }

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
          CaptionLabel {
            text: Parser.dayHeaderLabel(dayBlock.modelData.date)
            color: Theme.ink
          }
          Text {
            text: Parser.pomsLabel(Parser.pomodoroCount(dayBlock.modelData.entries)) + " · "
                  + Parser.durationLabel(Parser.pomodoroMinutes(dayBlock.modelData.entries))
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
