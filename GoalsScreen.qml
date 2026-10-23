pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import "Parser.js" as Parser
import "Util.js" as Util

// Spec §Screen: Goals.
Item {
  id: root

  // How far this screen's left edge sits from the window's; see Theme.pageX.
  property int leftInset: 0

  required property App app

  property string filterStatus: "active"

  readonly property var goalList: Util.goalsByTitle(root.app.notes.goalsData)

  // Parser reads a goal with no `status:` as active, so status is always set.
  function countByStatus(status) {
    return goalList.filter(function(g) { return g.meta.status === status }).length
  }

  readonly property var filteredList: goalList.filter(function(g) { return g.meta.status === root.filterStatus })

  function lastSessionLabel(entries) {
    return entries.length > 0 ? entries[entries.length - 1].heading : "never"
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
        width: parent.width
        spacing: Theme.spaceMd

        Text {
          text: "Goals"
          font.family: Theme.fontFamily
          font.pixelSize: Theme.headingSize
          font.bold: true
          color: Theme.ink
        }

        Item { Layout.fillWidth: true }

        Button { label: "Add event"; onActivated: root.app.openDialog("event") }
        Button { label: "New goal"; onActivated: root.app.openDialog("goal") }
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
          height: Theme.hairlineWidth
          color: Theme.hairline
        }

        Row {
          id: filters
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.spaceMd
          Repeater {
            model: ["active", "done", "cancelled"]
            delegate: TextChip {
              id: filterChip
              required property string modelData
              selected: root.filterStatus === modelData
              label: modelData + " " + root.countByStatus(modelData)
              font.pixelSize: Theme.captionSize
              onClicked: root.filterStatus = filterChip.modelData
            }
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Theme.hairlineWidth
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
            objectName: "goalRow:" + modelData.slug
            required property var modelData
            required property int index

            readonly property bool isSelected: root.app.nav.goalSlug === modelData.slug
            // Passive, so the row stays hovered while the pointer is over
            // the edit pencil's own MouseArea.
            HoverHandler { id: rowHover }
            readonly property bool hovered: rowHover.hovered
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
              height: Theme.hairlineWidth
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
              width: Theme.selectionBarWidth
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
                    text: rowItem.modelData.meta.title
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.titleSize
                    font.bold: true
                    color: Theme.ink
                  }
                  CaptionLabel {
                    visible: rowItem.modelData.meta.status === "active"
                    text: "running"
                    color: Theme.accentColor
                  }
                  CaptionLabel {
                    visible: rowItem.modelData.meta.status !== "active" && !!rowItem.modelData.meta.done_by
                    text: rowItem.modelData.meta.done_by ? ("due " + Parser.formatShortDate(rowItem.modelData.meta.done_by)) : ""
                    color: Theme.red
                  }
                }

                Text {
                  Layout.fillWidth: true
                  visible: rowItem.modelData.meta.why.length > 0
                  text: rowItem.modelData.meta.why
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
                  readonly property int doneCount: Parser.doneTaskCount(rowItem.modelData.meta.tasks)
                  readonly property var est: rowItem.modelData.meta.estimate
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                  text: {
                    var parts = [doneCount + " of " + rowItem.modelData.meta.tasks.length + " tasks done"]
                    // `estimate:` is poms REMAINING, not the goal's total
                    // (goal-files.md: the coach rewrites it down each
                    // session, it doesn't start high and get subtracted
                    // from) -- so this is a direct read, never poms - est.
                    // Spelled out as "poms left", not just "left": sitting
                    // right after "N of M tasks done" in the same caption,
                    // a bare number reads as a second fraction over the
                    // same M -- it isn't, it's a different unit entirely.
                    if (est !== undefined) parts.push("≈ " + est + " poms left")
                    parts.push("last session " + root.lastSessionLabel(rowItem.modelData.logEntries))
                    return parts.join(" · ")
                  }
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.captionSize
                  color: Theme.faint
                }
              }

              Item {
                id: goalPencilSlot
                Layout.preferredWidth: goalPencil.implicitWidth
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.app.nav.openGoal(rowItem.modelData.slug, "goals")
            }

            // Overlaid rather than inside rowContent, and declared after the
            // row's MouseArea, so its click wins over "open goal". Its width
            // is held open in rowContent by goalPencilSlot, so the why and
            // caption lines elide short of it and hovering shifts nothing.
            PencilIcon {
              id: goalPencil
              objectName: "goalEdit:" + rowItem.modelData.slug
              visible: rowItem.hovered
              anchors.right: parent.right
              anchors.rightMargin: Theme.panelPadding
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.app.openDialog("goal", rowItem.modelData.slug)
            }
          }
        }

        Item {
          visible: root.filteredList.length === 0
          width: rowsColumn.width
          height: Theme.emptyRowHeight
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
