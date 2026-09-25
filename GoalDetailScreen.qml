import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// Spec §Screen: Goal detail.
Item {
  id: root

  // How far this screen's left edge sits from the window's; see Theme.pageX.
  property int leftInset: 0

  property string slug: ""
  property var meta: null
  property var logEntries: []
  signal back()

  // Write-path signals. GoalDetailScreen owns none of the filesystem work
  // -- it only reports what the user did; omvision.qml re-reads
  // <slug>.md immediately before applying each of these (goal-files.md's
  // "re-read right before writing, never from a copy taken when the
  // screen was opened" rule), which this screen has no way to honour on
  // its own since it only ever sees whatever omvision.qml last loaded.
  signal toggleTask(int index)
  signal addTask(string text)
  signal closeGoal()
  signal cancelGoal(string reason, string takeaway)
  signal addEventRequested()
  signal coachRequested()

  // Result callbacks from omvision.qml: called directly on this instance
  // (it holds the id) rather than routed back through a signal, so the
  // inline add-task field and the cancel dialog can keep what the user
  // typed on a failed write instead of clearing it optimistically.
  function onAddTaskResult(ok, message) {
    if (ok) { addingTask = false; addTaskText = ""; addTaskInput.text = "" }
    else addTaskError = message || "couldn't save"
  }
  function onCancelResult(ok, message) {
    if (ok) { cancelDialogOpen = false; cancelError = "" }
    else cancelError = message || "couldn't save"
  }

  function commitAddTask() {
    var text = root.addTaskText.trim()
    if (text === "") { root.addingTask = false; return } // empty input is a no-op
    root.addTaskError = ""
    root.addTask(text)
  }
  function cancelAddTask() {
    root.addingTask = false
    root.addTaskText = ""
    root.addTaskError = ""
    addTaskInput.text = ""
  }

  property bool addingTask: false
  property string addTaskText: ""
  property string addTaskError: ""
  property bool cancelDialogOpen: false
  property string cancelError: ""

  function pomsCount(entries) {
    var n = 0
    for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n++
    return n
  }

  readonly property int poms: pomsCount(logEntries)
  readonly property int minutes: Parser.investedMinutes(logEntries)
  readonly property var est: meta ? meta.estimate : undefined
  readonly property var doneBy: meta ? meta.done_by : undefined
  readonly property var tasks: meta ? meta.tasks : []
  readonly property int tasksDone: tasks.filter(function(t) { return t.done }).length
  readonly property bool isOpenGoal: !!meta && meta.status !== "done" && meta.status !== "cancelled"

  // ---- timeline grouping ------------------------------------------------
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

  function dayPoms(entries) {
    var n = 0
    for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n++
    return n
  }
  function dayMinutes(entries) {
    var n = 0
    for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n += entries[i].minutes
    return n
  }
  function formatDayDuration(total) {
    var h = Math.floor(total / 60), m = total % 60
    if (h === 0) return m + " min"
    if (m === 0) return h + " h"
    return h + " h " + (m < 10 ? "0" + m : String(m))
  }

  function entryLabel(e) {
    if (e.type === "pomodoro") return e.minutes + " min"
    if (e.type === "coaching") return "coaching"
    if (e.type === "event") return "event · " + String(e.kind || "") + " · " + Parser.formatHCaption(e.minutes)
    return ""
  }

  TextMetrics {
    id: timeMetrics
    font.family: Theme.fontFamily
    font.pixelSize: Theme.captionSize
    text: "00:00"
  }

  ColumnLayout {
    // The journal's column, on the journal's line (Theme.pageX).
    x: Theme.pageX(root.width, root.leftInset)
    y: Theme.panelPadding
    width: Theme.pageWidth(root.width)
    height: root.height - Theme.panelPadding * 2
    spacing: Theme.sectionGap

    // ---- header ---------------------------------------------------------
    // The title and the buttons own the first row and never move. The back
    // link and the "running" chip can't always fit alongside a long title
    // and two buttons, so they get a row of their own, banded by hairlines
    // the way GoalsScreen's filter row is -- degrading by design instead of
    // clipping off the right edge (layout-rules §1, §7).
    ColumnLayout {
      id: header
      Layout.fillWidth: true
      spacing: 0

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spaceMd

        Text {
          Layout.fillWidth: true
          text: root.meta ? root.meta.title : root.slug
          elide: Text.ElideRight
          font.family: Theme.fontFamily
          font.pixelSize: Theme.headingSize
          font.bold: true
          color: Theme.ink
        }

        Button { label: "Add event"; inert: false; onActivated: root.addEventRequested() }
        Button { label: "Coach this goal"; filled: true; inert: false; onActivated: root.coachRequested() }
      }

      Item { Layout.preferredHeight: Theme.spaceLg; Layout.fillWidth: true }

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: subHeaderRow.implicitHeight + Theme.spaceXl
        color: "transparent"

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 1
          color: Theme.hairline
        }

        RowLayout {
          id: subHeaderRow
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.spaceMd

          // A real control, not a bare Text + MouseArea: sized
          // deterministically (a full control's height as its hit target)
          // so the click always lands, with a hover fill so it reads as a
          // control rather than as receding dim text.
          Rectangle {
            id: backControl
            objectName: "backControl"
            // Its label sits on the column's left edge and the hover fill
            // spills into the margin, not the other way round (layout-rules
            // §2, §3).
            Layout.leftMargin: -Math.round((implicitWidth - backLabel.implicitWidth) / 2)
            implicitWidth: backLabel.implicitWidth + Theme.spaceMd
            implicitHeight: Theme.controlHeight
            color: backArea.containsMouse ? Theme.hoverFill : "transparent"

            Text {
              id: backLabel
              anchors.centerIn: parent
              text: "← Goals"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              color: Theme.dim
            }

            MouseArea {
              id: backArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.back()
            }
          }

          Text {
            visible: !!root.meta && root.meta.status === "active"
            text: "running"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            color: Theme.accentColor
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: 1
          color: Theme.hairline
        }
      }
    }

    // ---- figures row ------------------------------------------------------
    // Independent facts, not a rigid row: each sized to its own content in a
    // Flow so it wraps onto a second line at narrow widths instead of
    // running off the edge. The progress rule always spans the full row
    // width beneath them, wrapped or not.
    Flow {
      Layout.fillWidth: true
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
        visible: root.est !== undefined
        text: "≈ " + (root.est !== undefined ? root.est : 0) + " poms left"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.ink
      }
      Text {
        text: root.tasksDone + " of " + root.tasks.length + " tasks"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.bodySize
        color: Theme.ink
      }
    }

    // A progress rule used to fill by `poms / estimate`. Dropped: once
    // `estimate:` is read correctly as poms remaining (goal-files.md),
    // that fraction has no honest meaning -- it would need a recorded
    // starting estimate this contract doesn't keep, and a bar that
    // silently reinterprets "poms done" as "poms done out of whatever
    // estimate happens to be right now" would just lie in a different way
    // than the subtraction bug it replaced. Nothing here plots progress
    // until there's a real denominator for it.

    // ---- body: timeline + right rail --------------------------------------
    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 0

      // Timeline
      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: timelineColumn.height
        clip: true

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
                  text: { var n = root.dayPoms(dayBlock.modelData.entries); return n + (n === 1 ? " pom · " : " poms · ") + root.formatDayDuration(root.dayMinutes(dayBlock.modelData.entries)) }
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
                delegate: Item {
                  id: entryRow
                  required property var modelData
                  width: dayBlock.width
                  height: contentCol.height + Theme.spaceMd

                  readonly property var e: modelData

                  Text {
                    id: timeText
                    text: entryRow.e.heading.split(" ").pop()
                    // Wide enough for any HH:MM at this size, so every
                    // entry's rule and node sit on one vertical line. A
                    // typed 40 fitted 11px digits and clipped larger ones.
                    width: Math.ceil(timeMetrics.advanceWidth)
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
                    width: 1
                    color: Theme.hairline
                  }

                  Rectangle {
                    id: node
                    // Centred on the rule only. It was also anchored to the
                    // rule's left edge, and with both set Qt sized it to fit
                    // between them: the square came out a 1px sliver.
                    width: 7
                    height: 7
                    anchors.horizontalCenter: rule.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Theme.spaceXs
                    color: entryRow.e.type === "coaching" ? Theme.accentColor : Theme.paper
                    border.color: entryRow.e.type === "coaching" ? Theme.accentColor : Theme.ink
                    border.width: 1
                    radius: 0

                    // Dashed look for events: Quickshell/QtQuick has no
                    // native dashed border, so approximate with a dashed
                    // Canvas outline.
                    Canvas {
                      anchors.fill: parent
                      visible: entryRow.e.type === "event"
                      onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = Theme.ink
                        ctx.lineWidth = 1
                        ctx.setLineDash([2, 1])
                        ctx.strokeRect(0.5, 0.5, width - 1, height - 1)
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
                      text: root.entryLabel(entryRow.e)
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.captionSize
                      font.bold: true
                      color: Theme.dim
                    }
                    Text {
                      visible: entryRow.e.type === "pomodoro" && !!entryRow.e.focus
                      width: contentCol.width
                      text: "focus: " + entryRow.e.focus
                      wrapMode: Text.WordWrap
                      lineHeight: Theme.proseLineHeight
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.bodySize
                      color: Theme.ink
                    }
                    Text {
                      visible: entryRow.e.type === "event" && !!entryRow.e.title
                      width: contentCol.width
                      text: entryRow.e.title ? entryRow.e.title : ""
                      wrapMode: Text.WordWrap
                      lineHeight: Theme.proseLineHeight
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.bodySize
                      color: Theme.ink
                    }
                    Text {
                      visible: entryRow.e.type === "pomodoro" && !!entryRow.e.done
                      width: contentCol.width
                      text: "done: " + entryRow.e.done
                      wrapMode: Text.WordWrap
                      lineHeight: Theme.proseLineHeight
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.bodySmallSize
                      color: Theme.dim
                    }
                    Text {
                      visible: entryRow.e.type === "pomodoro" && !!entryRow.e.left
                      width: contentCol.width
                      text: "left: " + entryRow.e.left
                      wrapMode: Text.WordWrap
                      lineHeight: Theme.proseLineHeight
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.bodySmallSize
                      color: Theme.dim
                    }
                    Text {
                      // goal-files.md §4's "Anything else?" line, written
                      // only when the break's open question was answered.
                      visible: entryRow.e.type === "pomodoro" && !!entryRow.e.other
                      width: contentCol.width
                      text: "else: " + entryRow.e.other
                      wrapMode: Text.WordWrap
                      lineHeight: Theme.proseLineHeight
                      font.family: Theme.fontFamily
                      font.pixelSize: Theme.bodySmallSize
                      color: Theme.dim
                    }
                  }
                }
              }
            }
          }
        }
      }

      // hairline between timeline and right rail
      Rectangle {
        Layout.preferredWidth: 1
        Layout.fillHeight: true
        color: Theme.hairline
      }

      // Right rail. A share of the column rather than a fixed 312px: at full
      // measure that share is the same ~310px, but at the window's minimum
      // a fixed rail left the timeline -- the screen's actual content --
      // about fifteen characters a line. Task names elide instead. Never
      // narrower than its two rows of controls, though, which can't elide
      // and would otherwise draw past the window edge (layout-rules §7).
      //
      // Off the page column's width, not this layout's: a layout reading
      // its own width to size its children feeds back into itself. And off
      // those two rows' implicit widths rather than the whole rail's, whose
      // wrapped hint text reports its unwrapped, full-sentence width.
      Item {
        Layout.preferredWidth: Math.max(Math.round(Theme.pageWidth(root.width) * 3 / 8),
                                        Math.ceil(Math.max(tasksHeader.implicitWidth, closeRow.implicitWidth))
                                        + Theme.spaceLg * 2)
        Layout.fillHeight: true

        ColumnLayout {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          anchors.leftMargin: Theme.spaceLg
          anchors.rightMargin: Theme.spaceLg
          anchors.bottomMargin: Theme.spaceLg
          spacing: Theme.spaceSm

          RowLayout {
            id: tasksHeader
            Layout.fillWidth: true
            spacing: Theme.spaceSm
            Text {
              text: "Tasks"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              font.bold: true
              color: Theme.dim
            }
            Text {
              text: root.tasksDone + " of " + root.tasks.length + " done"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              color: Theme.faint
            }
            Item { Layout.fillWidth: true }
            Button {
              label: "+ task"
              inert: false
              visible: !root.addingTask
              Layout.preferredWidth: implicitWidth
              Layout.preferredHeight: Theme.smallControlHeight
              Layout.alignment: Qt.AlignVCenter
              onActivated: { root.addTaskError = ""; root.addingTask = true }
            }
          }

          // Minimal inline input, not a dialog: Enter commits to "## Tasks",
          // Escape cancels. Stays open with whatever was typed if the write
          // fails, so a rejected add is never silently lost (layout-rules
          // §9: this is a small secondary control, not a modal).
          Column {
            Layout.fillWidth: true
            visible: root.addingTask
            spacing: Theme.spaceXs

            Rectangle {
              width: parent.width
              height: Theme.smallControlHeight
              color: "transparent"
              border.color: Theme.border
              border.width: Theme.borderWidth

              TextInput {
                id: addTaskInput
                anchors.fill: parent
                anchors.leftMargin: Theme.spaceXs
                anchors.rightMargin: Theme.spaceXs
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.ink
                selectByMouse: true

                onVisibleChanged: if (visible) { text = root.addTaskText; forceActiveFocus() }
                onTextChanged: root.addTaskText = text
                Keys.onReturnPressed: root.commitAddTask()
                Keys.onEnterPressed: root.commitAddTask()
                Keys.onEscapePressed: root.cancelAddTask()
              }
            }

            Text {
              visible: root.addTaskError.length > 0
              width: parent.width
              wrapMode: Text.WordWrap
              lineHeight: Theme.proseLineHeight
              text: root.addTaskError
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              color: Theme.red
            }
          }

          Column {
            Layout.fillWidth: true
            Repeater {
              model: root.tasks
              delegate: Column {
                required property var modelData
                required property int index
                width: parent.width

                // Full row width, same edges the row content below sits
                // inside -- every rule starts and ends at the same two
                // points now that the checkbox is no longer bled outside
                // this width (layout-rules §2, §3: one left edge, fills
                // bleed only where the scroller itself is the wide thing,
                // which this rail is not).
                Rectangle {
                  width: parent.width
                  height: 1
                  color: Theme.hairline
                  visible: index > 0
                }

                // The checkbox is the row's leading element and owns the
                // rail's left edge -- the same edge the TASKS heading
                // sits at -- with the label inset a consistent gap to its
                // right. Row height is the control-height token, not a
                // bare text height, so the checkbox and label both have
                // room to breathe; the hit target covers the whole row,
                // not just the checkbox, so ticking a task is easy.
                Item {
                  width: parent.width
                  height: Theme.controlHeight

                  Rectangle {
                    id: taskCheckbox
                    width: 12
                    height: 12
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    border.color: Theme.border
                    border.width: 1
                    color: "transparent"

                    Text {
                      visible: modelData.done
                      anchors.centerIn: parent
                      text: "✓"
                      font.family: Theme.fontFamily
                      font.pixelSize: 9
                      color: Theme.accentColor
                    }
                  }

                  Text {
                    id: taskEstimate
                    visible: modelData.estimate !== undefined
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.estimate !== undefined ? ("≈" + modelData.estimate) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySmallSize
                    color: Theme.dim
                  }

                  Text {
                    anchors.left: taskCheckbox.right
                    anchors.leftMargin: Theme.spaceSm
                    anchors.right: taskEstimate.left
                    anchors.rightMargin: Theme.spaceSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    font.strikeout: modelData.done
                    color: modelData.done ? Theme.faint : Theme.ink
                    elide: Text.ElideRight
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleTask(index)
                  }
                }
              }
            }

            Text {
              visible: root.tasks.length === 0
              text: "No tasks yet."
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySize
              color: Theme.faint
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.tasks.length === 0
            wrapMode: Text.WordWrap
            lineHeight: Theme.proseLineHeight
            text: "Tasks belong to the goal, not to a pomodoro. A finished pom never ticks one off — you do, or the coach does."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            color: Theme.faint
          }

          Item { Layout.preferredHeight: Theme.spaceSm }

          // "NEXT SESSION" (the claude /ompom-coach command + copy button)
          // used to live here too. Removed: CoachingScreen already carries
          // that hand-off with its own working copy button, and the same
          // control in two places is two things to keep in step instead
          // of one.

          Item { Layout.fillHeight: true }

          // Close / cancel. Only offered while the goal is still open --
          // a done or cancelled goal has nothing left to close or cancel.
          ColumnLayout {
            Layout.fillWidth: true
            visible: root.isOpenGoal
            spacing: Theme.spaceSm

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }

            RowLayout {
              id: closeRow
              Layout.fillWidth: true
              spacing: Theme.spaceSm
              Button {
                label: "Close goal · done"
                inert: false
                Layout.preferredWidth: implicitWidth
                Layout.preferredHeight: Theme.controlHeight
                onActivated: root.closeGoal()
              }
              Item { Layout.fillWidth: true }
              Text {
                text: "Cancel"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.red
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.cancelError = ""; root.cancelDialogOpen = true }
                }
              }
            }
          }

          // A cancelled goal keeps its reason/takeaway on screen -- it's
          // the one place this otherwise-invisible "## Cancelled" section
          // (Writer.appendCancelNote) is ever shown back to the user.
          ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.meta && root.meta.status === "cancelled" && !!root.meta.cancelled
            spacing: Theme.spaceXs
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.hairline }
            Text {
              text: "Cancelled"
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              font.bold: true
              color: Theme.red
            }
            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              lineHeight: Theme.proseLineHeight
              visible: !!root.meta && !!root.meta.cancelled && root.meta.cancelled.reason.length > 0
              text: root.meta && root.meta.cancelled ? root.meta.cancelled.reason : ""
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: Theme.ink
            }
            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              lineHeight: Theme.proseLineHeight
              visible: !!root.meta && !!root.meta.cancelled && root.meta.cancelled.takeaway.length > 0
              text: root.meta && root.meta.cancelled ? root.meta.cancelled.takeaway : ""
              font.family: Theme.fontFamily
              font.pixelSize: Theme.bodySmallSize
              color: Theme.dim
            }
          }
        }
      }
    }
  }

  // CancelDialog is no longer instantiated here: nested inside this
  // screen's own Item, it could only ever cover the content area to the
  // right of the sidebar (the Item this screen fills is already narrower
  // than the window, see omvision.qml's `width: parent.width -
  // sidebarSlot.width`), leaving the sidebar itself clickable behind a
  // dialog that is supposed to be fully modal. omvision.qml mounts one
  // shared CancelDialog at the window root instead, the same level
  // EventDialog already lived at, driven by this screen's own
  // cancelDialogOpen/cancelError state and cancelGoal signal.
}
