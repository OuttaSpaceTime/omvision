import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// Left sidebar: the mark, then one icon per screen. 64px, always.
//
// There used to be two variants -- a labelled sidebar and this rail -- with a
// width breakpoint choosing between them, a manual override pinning that
// choice, and a floating overlay for "expanded while narrow". All of it is
// gone: four screens with four icons and four tooltips never needed a second
// layout, and the machinery that chose between them was behind every sidebar
// bug this app has had -- a choice made on one screen following you to the
// next, an overlay opening underneath another overlay.
//
// One consequence worth keeping in mind: the rail is the only state, so
// nothing here toggles anything. The Journal hides it outright while you
// write and brings it back from its own control; that is the app's single
// remaining sidebar question, and it lives there, not here.
//
// No conditional anchor *lines* anywhere below -- only margins and
// visibility vary. Toggling which anchor line is bound turned out to
// silently fail to lay the item out at all, which is why an earlier version
// of this file had an invisible toggle control.
Rectangle {
  id: root

  property string currentScreen: "goals"
  signal navigate(string screen)

  readonly property int railWidth: 64

  readonly property var navItems: [
    { id: "today", label: "Today", glyph: "" },
    { id: "goals", label: "Goals", glyph: "" },
    { id: "coaching", label: "Coaching", glyph: "" },
    { id: "journal", label: "Journal", glyph: "" }
  ]

  width: railWidth
  color: Theme.paper
  clip: true

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: 1
    color: Theme.hairline
  }

  // The mark is black-on-transparent (assets/mark.svg) and tinted to the
  // accent here, the same way the ompom bar widget tints its copy of it.
  Item {
    id: mark
    width: 26
    height: 26
    anchors.left: parent.left
    anchors.leftMargin: Math.round((root.railWidth - width) / 2)
    anchors.top: parent.top
    anchors.topMargin: Theme.spaceMd

    Image {
      id: markSvg
      anchors.fill: parent
      source: Qt.resolvedUrl("assets/mark.svg")
      sourceSize.width: mark.width
      sourceSize.height: mark.height
      smooth: true
      visible: false
    }

    MultiEffect {
      anchors.fill: parent
      source: markSvg
      colorization: 1.0
      colorizationColor: Theme.accentColor
      brightness: 1.0
    }
  }

  // ---- nav ------------------------------------------------------------------
  // Icon-only, with the label carried by a tooltip. The labels are text, not
  // icons, so beside a 64px rail they are not squeezed -- they are simply not
  // drawn.
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: mark.bottom
    anchors.topMargin: Theme.spaceXl
    spacing: Theme.spaceXxs

    Repeater {
      model: root.navItems
      delegate: Item {
        id: navRow
        required property var modelData
        width: parent.width
        height: 36

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

        Text {
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

        ToolTip.visible: navArea.containsMouse
        ToolTip.delay: 400
        ToolTip.text: navRow.modelData.label
      }
    }
  }
}
