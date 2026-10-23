import QtQuick

import "Parser.js" as Parser

// One entry on the goal detail's timeline (Timeline.qml): its time, a node
// on the vertical rule, and what the entry says (EntryNotes). A pomodoro's
// node is a bordered square, an event's is dashed.
Item {
  id: root

  // A log entry, as Parser.parseLogEntries returns it.
  property var entry: ({})
  // The time column's width. Timeline gives every entry the same one, so
  // the rules of all entries sit on one vertical line.
  property int timeWidth: 0

  height: contentCol.height + Theme.spaceMd

  function entryLabel(e) {
    if (e.type === "pomodoro") return Parser.durationLabel(e.minutes)
    if (e.type === "event") return "event · " + String(e.kind || "") + " · " + Parser.durationLabel(e.minutes)
    return ""
  }

  Text {
    id: timeText
    text: Parser.entryTime(root.entry)
    width: root.timeWidth
    horizontalAlignment: Text.AlignRight
    anchors.top: parent.top
    anchors.left: parent.left
    // The entry label's size, so the two top-aligned lines
    // also share a baseline across the rule.
    font.family: Theme.fontFamily
    font.pixelSize: Theme.captionSize
    color: Theme.faint
  }

  Rectangle {
    id: rule
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: timeText.right
    anchors.leftMargin: Theme.spaceLg
    width: Theme.hairlineWidth
    color: Theme.hairline
  }

  Rectangle {
    id: node
    // Centred on the rule only. It was also anchored to the
    // rule's left edge, and with both set Qt sized it to fit
    // between them: the square came out a 1px sliver.
    width: Theme.timelineNodeSize
    height: Theme.timelineNodeSize
    anchors.horizontalCenter: rule.horizontalCenter
    anchors.top: parent.top
    anchors.topMargin: Theme.spaceXs
    color: Theme.paper
    border.color: Theme.ink
    // An event's outline is the dashed Canvas below: a solid border under it
    // filled the dashes' gaps, and its node read as a pomodoro's.
    border.width: root.entry.type === "event" ? 0 : Theme.borderWidth

    // Dashed look for events: Quickshell/QtQuick has no
    // native dashed border, so approximate with a dashed
    // Canvas outline. Inset by half the line, so the line
    // lands on whole pixels instead of blurring across two.
    Canvas {
      anchors.fill: parent
      visible: root.entry.type === "event"
      onPaint: {
        var ctx = getContext("2d")
        var line = Theme.borderWidth
        ctx.reset()
        ctx.strokeStyle = Theme.ink
        ctx.lineWidth = line
        ctx.setLineDash(Theme.timelineDash)
        ctx.strokeRect(line / 2, line / 2, width - line, height - line)
      }
    }
  }

  Column {
    id: contentCol
    anchors.left: rule.right
    anchors.leftMargin: Theme.spaceMd
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Theme.spaceXxs

    CaptionLabel { text: root.entryLabel(root.entry) }
    EntryNotes {
      width: contentCol.width
      spacing: Theme.spaceXxs
      entry: root.entry
    }
  }
}
