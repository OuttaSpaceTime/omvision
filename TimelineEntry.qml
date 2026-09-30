import QtQuick

import "Parser.js" as Parser

// One entry on the goal detail's timeline (Timeline.qml): its time, a node
// on the vertical rule, and what the entry says. A pomodoro's node is a
// bordered square, a coaching session's is filled accent, an event's is
// dashed.
Item {
  id: root

  // A log entry, as Parser.parseLogEntries returns it.
  property var entry: ({})
  // The time column's width. Timeline gives every entry the same one, so
  // the rules of all entries sit on one vertical line.
  property int timeWidth: 0

  height: contentCol.height + Theme.spaceMd

  function entryLabel(e) {
    if (e.type === "pomodoro") return e.minutes + " min"
    if (e.type === "coaching") return "coaching"
    if (e.type === "event") return "event · " + String(e.kind || "") + " · " + Parser.formatHCaption(e.minutes)
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
    color: root.entry.type === "coaching" ? Theme.accentColor : Theme.paper
    border.color: root.entry.type === "coaching" ? Theme.accentColor : Theme.ink
    border.width: Theme.borderWidth
    radius: 0

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

    Text {
      text: root.entryLabel(root.entry)
      font.family: Theme.fontFamily
      font.pixelSize: Theme.captionSize
      font.bold: true
      color: Theme.dim
    }
    Text {
      visible: root.entry.type === "pomodoro" && !!root.entry.focus
      width: contentCol.width
      text: "focus: " + root.entry.focus
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
      color: Theme.ink
    }
    Text {
      visible: root.entry.type === "event" && !!root.entry.title
      width: contentCol.width
      text: root.entry.title ? root.entry.title : ""
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
      color: Theme.ink
    }
    Text {
      visible: root.entry.type === "pomodoro" && !!root.entry.done
      width: contentCol.width
      text: "done: " + root.entry.done
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.dim
    }
    Text {
      visible: root.entry.type === "pomodoro" && !!root.entry.left
      width: contentCol.width
      text: "left: " + root.entry.left
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.dim
    }
    Text {
      // goal-files.md §4's "Anything else?" line, written
      // only when the break's open question was answered.
      visible: root.entry.type === "pomodoro" && !!root.entry.other
      width: contentCol.width
      text: "else: " + root.entry.other
      wrapMode: Text.WordWrap
      lineHeight: Theme.proseLineHeight
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySmallSize
      color: Theme.dim
    }
  }
}
