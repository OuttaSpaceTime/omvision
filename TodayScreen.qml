import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// Spec: Today — what happened today across everything. Read-only, like
// GoalsScreen: same header shape, same full-bleed row list, same shared left
// edge. Not in docs/ui-spec.md yet (M2 shipped it as an empty state); the
// detailed shape comes from the coordinator's hand-off brief instead.
Item {
  id: root

  // How far this screen's left edge sits from the window's; see Theme.pageX.
  property int leftInset: 0

  property var goalsData: ({})
  property var dayEntries: []
  // slug -> entries, for `<slug>.log.md` files whose goal file is gone. They
  // are real pomodoros and belong in today's account of what happened; they
  // just have a slug where a title would be. See omvision.qml's
  // applyGoalsList() for how they are found.
  property var orphanLogs: ({})

  function typeLabel(e) {
    if (e.type === "pomodoro") return "pomodoro"
    if (e.type === "coaching") return "coaching"
    if (e.type === "event") return "event" + (e.kind ? (" · " + String(e.kind)) : "")
    return String(e.type || "")
  }

  // Every log entry (goal logs + the day file) whose timestamp is today,
  // newest first. Day-file entries carry no goal.
  function buildTodayList(data, dayList, orphans) {
    var now = new Date()
    var todayKey = Parser.dayKey(now)
    var out = []

    for (var slug in data) {
      var g = data[slug]
      if (!g) continue
      var title = g.meta ? g.meta.title : slug
      var entries = g.logEntries || []
      for (var i = 0; i < entries.length; i++) {
        var e = entries[i]
        if (Parser.dayKey(e.date) !== todayKey) continue
        out.push({
          date: e.date, type: e.type, time: e.heading.split(" ").pop(),
          focus: e.focus || "", done: e.done || "", left: e.left || "",
          other: e.other || "", kind: e.kind || "", title2: e.title || "",
          minutes: e.minutes || 0, goalTitle: title, goalSlug: slug
        })
      }
    }

    var orph = orphans || ({})
    for (var oslug in orph) {
      var oentries = orph[oslug] || []
      for (var o = 0; o < oentries.length; o++) {
        var eo = oentries[o]
        if (Parser.dayKey(eo.date) !== todayKey) continue
        out.push({
          date: eo.date, type: eo.type, time: eo.heading.split(" ").pop(),
          focus: eo.focus || "", done: eo.done || "", left: eo.left || "",
          other: eo.other || "", kind: eo.kind || "", title2: eo.title || "",
          minutes: eo.minutes || 0, goalTitle: oslug, goalSlug: oslug
        })
      }
    }

    var dl = dayList || []
    for (var j = 0; j < dl.length; j++) {
      var e2 = dl[j]
      if (Parser.dayKey(e2.date) !== todayKey) continue
      out.push({
        date: e2.date, type: e2.type, time: e2.heading.split(" ").pop(),
        focus: e2.focus || "", done: e2.done || "", left: e2.left || "",
        other: e2.other || "", kind: e2.kind || "", title2: e2.title || "",
        minutes: e2.minutes || 0, goalTitle: "", goalSlug: ""
      })
    }

    out.sort(function(a, b) { return b.date.getTime() - a.date.getTime() })
    return out
  }

  readonly property var todayList: buildTodayList(root.goalsData, root.dayEntries, root.orphanLogs)

  function totalMinutes(list) {
    var n = 0
    for (var i = 0; i < list.length; i++) n += list[i].minutes
    return n
  }
  readonly property int todayCount: todayList.length
  readonly property int todayMinutesTotal: totalMinutes(todayList)

  Column {
    // The journal's column, on the journal's line (Theme.pageX).
    x: Theme.pageX(root.width, root.leftInset)
    y: Theme.panelPadding
    width: Theme.pageWidth(root.width)
    height: root.height - Theme.panelPadding * 2
    spacing: Theme.sectionGap

    // Header. Title + the count/time summary share the first row, per the
    // hand-off brief; a hairline bands it off from the list below, same
    // shape as GoalsScreen's header band.
    Column {
      id: header
      width: parent.width
      spacing: Theme.spaceMd

      RowLayout {
        width: parent.width
        spacing: Theme.spaceMd

        Text {
          text: "Today"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.headingSize
          font.bold: true
          color: Theme.ink
        }

        Text {
          Layout.fillWidth: true
          elide: Text.ElideRight
          text: root.todayCount + (root.todayCount === 1 ? " entry · " : " entries · ") + Parser.formatHCaption(root.todayMinutesTotal)
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.dim
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: Theme.hairline
      }
    }

    // ---- entries --------------------------------------------------------
    // Same bleed idiom as GoalsScreen: the scroller is the wide thing so its
    // hairlines run edge to edge; row content is inset back to the shared
    // left edge. No hover/selection here -- these rows aren't clickable.
    Flickable {
      x: -Theme.panelPadding
      width: parent.width + Theme.panelPadding * 2
      height: parent.height - y
      contentHeight: rowsColumn.height
      clip: true

      Column {
        id: rowsColumn
        width: parent.width

        Repeater {
          model: root.todayList
          delegate: Item {
            id: rowItem
            required property var modelData
            required property int index

            width: rowsColumn.width
            // The row's padding, top and bottom, so its text sits centred
            // between its hairlines rather than riding the top.
            height: contentCol.height + Theme.rowPadding * 2

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: 1
              color: Theme.hairline
              visible: rowItem.index > 0
            }

            Column {
              id: contentCol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: Theme.panelPadding
              anchors.rightMargin: Theme.panelPadding
              anchors.topMargin: Theme.rowPadding
              spacing: Theme.spaceXs

              RowLayout {
                width: parent.width
                spacing: Theme.spaceSm

                Text {
                  text: rowItem.modelData.time
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySize
                  font.bold: true
                  color: Theme.ink
                }
                Text {
                  text: root.typeLabel(rowItem.modelData)
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.captionSize
                  font.bold: true
                  color: Theme.dim
                }
                // The surplus width needs an explicit home. Without this
                // spacer, a row whose goal label is hidden -- an entry with no
                // goal -- has no fillWidth item at all, so the layout spreads
                // the leftover width across the remaining cells and the type
                // label drifts into the middle of the row, while rows that do
                // have a goal keep it tight against the time. Same row, two
                // different alignments, depending on the data.
                Item { Layout.fillWidth: true }

                Text {
                  Layout.maximumWidth: Math.round(parent.width * 0.4)
                  visible: !!rowItem.modelData.goalTitle
                  text: rowItem.modelData.goalTitle
                  elide: Text.ElideRight
                  horizontalAlignment: Text.AlignRight
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.captionSize
                  color: Theme.accentColor
                }
              }

              Text {
                visible: rowItem.modelData.type === "pomodoro" && !!rowItem.modelData.focus
                width: parent.width
                text: "focus: " + rowItem.modelData.focus
                wrapMode: Text.WordWrap
                lineHeight: Theme.proseLineHeight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.ink
              }
              Text {
                visible: rowItem.modelData.type === "event" && !!rowItem.modelData.title2
                width: parent.width
                text: rowItem.modelData.title2
                wrapMode: Text.WordWrap
                lineHeight: Theme.proseLineHeight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.ink
              }
              // What the break actually recorded. Same three lines, same
              // styling, as the goal-detail timeline -- a run logged with no
              // `focus:` used to render as a bare timestamp here, with every
              // word the user wrote about it dropped on the floor.
              Text {
                visible: rowItem.modelData.type === "pomodoro" && !!rowItem.modelData.done
                width: parent.width
                text: "done: " + rowItem.modelData.done
                wrapMode: Text.WordWrap
                lineHeight: Theme.proseLineHeight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.dim
              }
              Text {
                visible: rowItem.modelData.type === "pomodoro" && !!rowItem.modelData.left
                width: parent.width
                text: "left: " + rowItem.modelData.left
                wrapMode: Text.WordWrap
                lineHeight: Theme.proseLineHeight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.dim
              }
              Text {
                visible: rowItem.modelData.type === "pomodoro" && !!rowItem.modelData.other
                width: parent.width
                text: "else: " + rowItem.modelData.other
                wrapMode: Text.WordWrap
                lineHeight: Theme.proseLineHeight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.dim
              }
            }
          }
        }

        Item {
          visible: root.todayList.length === 0
          width: rowsColumn.width
          height: 60
          Text {
            anchors.centerIn: parent
            text: "Nothing logged today."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.faint
          }
        }
      }
    }
  }
}
