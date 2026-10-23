pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// Spec §Screen: Today — what happened today across everything. Read-only,
// like GoalsScreen: same header shape, same full-bleed row list, same shared
// left edge.
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
    if (e.type === "event") return "event" + (e.kind ? (" · " + String(e.kind)) : "")
    return String(e.type || "")
  }

  // Every log entry (goal logs + the day file) whose timestamp is today,
  // newest first, each as { entry, goalTitle }: the entry as Parser read it,
  // and the goal it was logged against, "" for the day file's.
  function buildTodayList(data, dayList, orphans) {
    var todayKey = Parser.dayKey(new Date())
    var out = []
    function collect(entries, goalTitle) {
      for (let i = 0; i < entries.length; i++) {
        if (Parser.dayKey(entries[i].date) === todayKey) out.push({ entry: entries[i], goalTitle: goalTitle })
      }
    }
    for (let slug in data) {
      const g = data[slug]
      if (g) collect(g.logEntries || [], g.meta ? g.meta.title : slug)
    }
    for (let oslug in (orphans || {})) collect(orphans[oslug] || [], oslug)
    collect(dayList || [], "")
    out.sort(function(a, b) { return b.entry.date.getTime() - a.entry.date.getTime() })
    return out
  }

  readonly property var todayList: buildTodayList(root.goalsData, root.dayEntries, root.orphanLogs)

  readonly property int todayCount: todayList.length
  readonly property int todayMinutesTotal: todayList.reduce(function(n, r) { return n + r.entry.minutes }, 0)

  Column {
    // The journal's column, on the journal's line (Theme.pageX).
    x: Theme.pageX(root.width, root.leftInset)
    y: Theme.panelPadding
    width: Theme.pageWidth(root.width)
    height: root.height - Theme.panelPadding * 2
    spacing: Theme.sectionGap

    // Header. Title + the count/time summary share the first row; a
    // hairline bands it off from the list below, same shape as GoalsScreen's
    // header band.
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
          text: root.todayCount + (root.todayCount === 1 ? " entry · " : " entries · ") + Parser.durationLabel(root.todayMinutesTotal)
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.dim
        }
      }

      Rectangle {
        width: parent.width
        height: Theme.hairlineWidth
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
              height: Theme.hairlineWidth
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
                  text: Parser.entryTime(rowItem.modelData.entry)
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySize
                  font.bold: true
                  color: Theme.ink
                }
                CaptionLabel { text: root.typeLabel(rowItem.modelData.entry) }
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

              EntryNotes {
                width: parent.width
                spacing: Theme.spaceXs
                entry: rowItem.modelData.entry
              }
            }
          }
        }

        Item {
          visible: root.todayList.length === 0
          width: rowsColumn.width
          height: Theme.emptyRowHeight
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
