import QtQuick
import QtQuick.Controls

// Left sidebar: mark, wordmark, nav rows, and a collapse toggle.
// Spec §Window, plus the collapsible-sidebar addendum:
//   - `collapsed` drives narrow-rail vs full-width rendering. The rail is
//     never zero-width: mark + toggle + icon-only nav stay reachable.
//   - When used as the narrow-mode overlay, the caller sets `collapsed: false`
//     and positions/sizes this item itself; the sidebar doesn't know it's
//     floating, it just always paints an opaque background + right hairline.
//   - No conditional anchor *lines* anywhere below (anchors.left vs undefined
//     etc.) — only margins/visibility vary with state. Toggling which anchor
//     line is bound turned out to silently fail to lay the item out at all,
//     which is why an earlier version of this file had an invisible toggle
//     control. Margins-only keeps every element's anchor set fixed and valid.
Rectangle {
  id: root

  property string currentScreen: "goals"
  property bool collapsed: false
  signal navigate(string screen)
  signal toggle()

  readonly property int expandedWidth: 176
  readonly property int collapsedWidth: 64

  readonly property var navItems: [
    { id: "today", label: "Today", glyph: "" },
    { id: "goals", label: "Goals", glyph: "" },
    { id: "coaching", label: "Coaching", glyph: "" },
    { id: "journal", label: "Journal", glyph: "" }
  ]

  width: collapsed ? collapsedWidth : expandedWidth
  color: Theme.paper
  clip: true

  Behavior on width {
    NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: Theme.hairline
  }

  // ---- header: mark + wordmark + collapse toggle ---------------------------
  // Expanded, the three share one row: mark, wordmark, toggle at the right.
  // Collapsed, the mark and the toggle become two stacked entries of their
  // own, so the rail reads as a single column of one-purpose rows all the
  // way down rather than cramming two controls onto one line.
  // Only margins and heights vary between the states -- see the note at the
  // top of this file about why anchor *lines* must stay bound either way.
  Item {
    id: header
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 10
    height: root.collapsed ? 60 : 28

    Rectangle {
      id: mark
      width: 26
      height: 26
      anchors.left: parent.left
      // Centred in the rail when collapsed; at the normal inset when not.
      anchors.leftMargin: root.collapsed ? Math.round((root.collapsedWidth - width) / 2) : 6
      anchors.top: parent.top
      // 1 centres a 26px mark in the 28px first row of either state.
      anchors.topMargin: 1
      color: "transparent"
      border.color: Theme.accentColor
      border.width: Theme.borderWidth
      Text {
        anchors.centerIn: parent
        text: "λi"
        font.family: Theme.fontFamily
        font.pixelSize: 13
        color: Theme.accentColor
      }
    }

    Text {
      visible: !root.collapsed
      anchors.left: mark.right
      anchors.leftMargin: 8
      anchors.right: toggleBtn.left
      anchors.verticalCenter: mark.verticalCenter
      elide: Text.ElideRight
      text: "omvision"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.titleSize
      font.bold: true
      font.letterSpacing: 1
      color: Theme.ink
    }

    // Always-visible, always-hittable way back. Secondary ink (not faint —
    // this is a control, not receding text) with a hover fill and a real
    // >=28px hit target. Collapsed, it drops to its own row under the mark
    // and centres in the rail; expanded, it sits at the header's right end.
    Rectangle {
      id: toggleBtn
      width: 28
      height: 28
      anchors.right: parent.right
      anchors.rightMargin: root.collapsed ? Math.round((root.collapsedWidth - width) / 2) : 0
      anchors.top: parent.top
      anchors.topMargin: root.collapsed ? 32 : 0
      color: toggleArea.containsMouse ? Theme.hoverFill : "transparent"

      Text {
        anchors.centerIn: parent
        text: root.collapsed ? "»" : "«"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.subtitleSize
        color: Theme.secondaryInk
      }

      MouseArea {
        id: toggleArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggle()
      }

      ToolTip.visible: toggleArea.containsMouse
      ToolTip.delay: 400
      ToolTip.text: root.collapsed ? "Expand sidebar (Ctrl+B)" : "Collapse sidebar (Ctrl+B)"
    }
  }

  // ---- nav ------------------------------------------------------------------
  // Expanded: full text rows. Collapsed: icon-only — labels are text, not
  // icons, so they're hidden rather than squeezed; a Nerd Font glyph plus a
  // tooltip keeps every screen reachable without expanding.
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: header.bottom
    anchors.topMargin: 14
    spacing: 2

    Repeater {
      model: root.navItems
      delegate: Item {
        id: navRow
        required property var modelData
        width: parent.width
        height: root.collapsed ? 36 : (Theme.bodySize + 12)

        readonly property bool selected: root.currentScreen === modelData.id

        Rectangle {
          visible: navRow.selected
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: 2
          color: Theme.accentColor
        }

        Rectangle {
          visible: navArea.containsMouse
          anchors.fill: parent
          color: Theme.hoverFill
        }

        // Expanded: text label.
        Text {
          visible: !root.collapsed
          anchors.left: parent.left
          anchors.leftMargin: navRow.selected ? 10 : 8
          anchors.verticalCenter: parent.verticalCenter
          text: navRow.modelData.label
          font.family: Theme.fontFamily
          font.pixelSize: Theme.bodySize
          color: navRow.selected ? Theme.accentColor : Theme.dim
        }

        // Collapsed: centered Nerd Font glyph, tooltip carries the label.
        Text {
          visible: root.collapsed
          anchors.centerIn: parent
          text: navRow.modelData.glyph
          font.family: Theme.fontFamily
          font.pixelSize: Theme.subtitleSize
          color: navRow.selected ? Theme.accentColor : Theme.dim
        }

        MouseArea {
          id: navArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.navigate(navRow.modelData.id)
        }

        ToolTip.visible: root.collapsed && navArea.containsMouse
        ToolTip.delay: 400
        ToolTip.text: navRow.modelData.label
      }
    }
  }
}
