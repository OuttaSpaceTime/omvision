import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser

// Spec §Screen: Goals.
Item {
  id: root

  // How far this screen's left edge sits from the window's; see Theme.pageX.
  property int leftInset: 0

  property var goalsData: ({})
  property var todaySummary: ({ poms: 0, minutes: 0 })
  property string selectedSlug: ""
  signal openGoal(string slug)
  signal addEventRequested()
  signal newGoalRequested()

  property string filterStatus: "active"

  function buildGoalList(data) {
    var out = []
    for (var slug in data) {
      var g = data[slug]
      if (!g || !g.meta) continue
      out.push({ slug: slug, meta: g.meta, logEntries: g.logEntries || [] })
    }
    out.sort(function(a, b) { return a.meta.title < b.meta.title ? -1 : (a.meta.title > b.meta.title ? 1 : 0) })
    return out
  }

  readonly property var goalList: buildGoalList(goalsData)

  function statusOf(g) { return g.meta.status || "active" }

  function countByStatus(status) {
    var n = 0
    for (var i = 0; i < goalList.length; i++) if (statusOf(goalList[i]) === status) n++
    return n
  }

  readonly property var filteredList: goalList.filter(function(g) { return statusOf(g) === root.filterStatus })

  function pomsCount(entries) {
    var n = 0
    for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n++
    return n
  }

  function pomsMinutes(entries) {
    var n = 0
    for (var i = 0; i < entries.length; i++) if (entries[i].type === "pomodoro") n += entries[i].minutes
    return n
  }

  function lastSessionLabel(entries) {
    if (entries.length === 0) return "never"
    var latest = entries[entries.length - 1]
    return latest.heading
  }

  Column {
    // The journal's column, on the journal's line (Theme.pageX).
    x: Theme.pageX(root.width, root.leftInset)
    y: Theme.panelPadding
    width: Theme.pageWidth(root.width)
    height: root.height - Theme.panelPadding * 2
    spacing: Theme.sectionGap

    // Header. The title and the buttons own the first row and never move.
    // The filter chips join them there when they fit and drop to a row of
    // their own when they don't, instead of pushing the buttons off the
    // right edge. The old "TODAY · N POMS · H" summary is gone: it was the
    // first thing to crowd the row and the least worth the space.
    Column {
      id: header
      width: parent.width
      spacing: 0

      RowLayout {
        id: headerRow
        width: parent.width
        spacing: Theme.spaceMd

        Text {
          id: titleText
          text: "Goals"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.headingSize
          font.bold: true
          color: Theme.ink
        }

        Item { Layout.fillWidth: true }

        Button { id: addEventBtn; label: "Add event"; inert: false; onActivated: root.addEventRequested() }
        Button { id: newGoalBtn; label: "New goal"; inert: false; onActivated: root.newGoalRequested() }
      }

      // The filters are always their own row, never sharing the title's.
      // A hairline above and below makes it read as a band belonging to the
      // list beneath it rather than as a second line of the header -- which
      // is also why the chips sit at the same left edge as the goal titles.
      Item {
        width: parent.width
        height: Theme.spaceLg
      }

      Rectangle {
        width: parent.width
        height: filters.implicitHeight + Theme.spaceXl
        color: "transparent"

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 1
          color: Theme.hairline
        }

        Row {
          id: filters
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.spaceMd
          Repeater {
            model: ["active", "paused", "done", "cancelled"]
            delegate: Text {
              required property string modelData
              readonly property bool isSelected: root.filterStatus === modelData
              text: modelData + " " + root.countByStatus(modelData)
              font.family: Theme.fontFamily
              font.pixelSize: Theme.captionSize
              color: isSelected ? Theme.accentColor : Theme.dim
              font.underline: isSelected

              MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.filterStatus = parent.modelData
              }
            }
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

    // ---- goal rows -----------------------------------------------------
    // The list is wider than the column it sits in, by a page margin on each
    // side, so a row's fill runs past the text into the margin. It clips, so
    // a row cannot bleed by drawing at negative x -- the scroller itself has
    // to be the wide thing. The row content is inset back to the column.
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
          model: root.filteredList
          delegate: Rectangle {
            id: rowItem
            required property var modelData
            required property int index

            readonly property var g: modelData
            readonly property bool isSelected: root.selectedSlug === g.slug
            property bool hovered: false
            readonly property bool highlighted: hovered || isSelected

            // Full width of the (already bled) scroller, so the hover and
            // selected fill runs edge to edge while the text inside is inset
            // back to the same left edge as the title and the filter chips.
            // That inset is what gives the fill breathing room around the
            // text without indenting the text itself.
            // Sized to its text, not a fixed height: a fixed 78px row was
            // only ever right for one type size and clipped the caption line
            // as soon as the type grew.
            width: rowsColumn.width
            height: rowContent.implicitHeight + Theme.rowPadding * 2
            color: highlighted ? Theme.fill : "transparent"

            Rectangle {
              // hairline separator, full row width
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: 1
              color: Theme.hairline
              visible: rowItem.index > 0
            }

            // Sits at the bled row's own left edge, so it reads as a marker in
            // the margin with the padding between it and the text.
            Rectangle {
              visible: rowItem.highlighted
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 3
              color: Theme.accentColor
            }

            // Undoes the bleed for the content: the text lines up with the
            // header above, the fill around it does not.
            RowLayout {
              id: rowContent
              anchors.fill: parent
              anchors.leftMargin: Theme.panelPadding
              anchors.rightMargin: Theme.panelPadding
              anchors.topMargin: Theme.rowPadding
              anchors.bottomMargin: Theme.rowPadding
              spacing: Theme.spaceLg

              ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: Theme.spaceXs

                RowLayout {
                  spacing: Theme.spaceSm
                  Text {
                    text: rowItem.g.meta.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.bold: true
                    color: Theme.ink
                  }
                  Text {
                    visible: rowItem.g.meta.status === "active"
                    text: "running"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.bold: true
                    color: Theme.accentColor
                  }
                  Text {
                    visible: rowItem.g.meta.status !== "active" && !!rowItem.g.meta.done_by
                    text: rowItem.g.meta.done_by ? ("due " + Parser.formatShortDate(rowItem.g.meta.done_by)) : ""
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.bold: true
                    color: Theme.red
                  }
                }

                Text {
                  Layout.fillWidth: true
                  visible: rowItem.g.meta.why.length > 0
                  text: rowItem.g.meta.why
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySmallSize
                  color: Theme.dim
                  elide: Text.ElideRight
                }

                // One left-aligned caption now carries what the right-hand
                // column used to. The pomodoro count and the estimate lived
                // in a fixed 240px column that could never be made to align
                // against rows of varying height -- and the task count
                // already says how far along a goal is. What is still worth
                // knowing from the estimate rides along here, where it
                // elides cleanly instead of clipping at the window edge.
                Text {
                  readonly property int doneCount: rowItem.g.meta.tasks.filter(function(t) { return t.done }).length
                  readonly property int poms: root.pomsCount(rowItem.g.logEntries)
                  readonly property var est: rowItem.g.meta.estimate
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: {
                    var parts = [doneCount + " of " + rowItem.g.meta.tasks.length + " tasks done"]
                    // `estimate:` is poms REMAINING, not the goal's total
                    // (goal-files.md: the coach rewrites it down each
                    // session, it doesn't start high and get subtracted
                    // from) -- so this is a direct read, never poms - est.
                    // Spelled out as "poms left", not just "left": sitting
                    // right after "N of M tasks done" in the same caption,
                    // a bare number reads as a second fraction over the
                    // same M -- it isn't, it's a different unit entirely.
                    if (est !== undefined) parts.push("≈ " + est + " poms left")
                    parts.push("last session " + root.lastSessionLabel(rowItem.g.logEntries))
                    return parts.join(" · ")
                  }
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.captionSize
                  color: Theme.faint
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onEntered: rowItem.hovered = true
              onExited: rowItem.hovered = false
              onClicked: root.openGoal(rowItem.g.slug)
            }
          }
        }

        Item {
          visible: root.filteredList.length === 0
          width: rowsColumn.width
          height: 60
          Text {
            anchors.centerIn: parent
            text: "No " + root.filterStatus + " goals."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.faint
          }
        }
      }
    }
  }
}
