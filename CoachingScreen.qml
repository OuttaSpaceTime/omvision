import QtQuick
import QtQuick.Layouts
import Quickshell.Io

import "Parser.js" as Parser

// Coaching — the hand-off screen, minus anything that writes (plan.md
// Milestone 4 / C2). Goal + method are local UI state only (they pick which
// command is shown, never touch disk). The `copy` control mirrors Goal
// detail's own NEXT SESSION box: it actually copies the command to the
// clipboard, since the ompom-coach skill now exists to receive it.
Item {
  id: root

  property var goalsData: ({})
  property string selectedSlug: ""
  property string selectedMethod: ""

  // Exactly the two the ompom-coach skill accepts. It parses `--method mi|polya`
  // and stops with an error on anything else, so a third chip here would just
  // hand the user a command that refuses to run. If the skill ever learns
  // another method, add it in both places at once.
  readonly property var methods: ["motivational interviewing", "how to solve it"]

  function methodFlag(m) { return m === "how to solve it" ? "polya" : "mi" }

  // One source for the command: the box shows exactly what the button copies.
  readonly property string command:
    "claude /ompom-coach " + root.selectedSlug + " --method " + methodFlag(root.selectedMethod)

  function buildGoalList(data) {
    var out = []
    for (var slug in data) {
      var g = data[slug]
      if (!g || !g.meta) continue
      out.push({ slug: slug, meta: g.meta })
    }
    out.sort(function(a, b) { return a.meta.title < b.meta.title ? -1 : (a.meta.title > b.meta.title ? 1 : 0) })
    return out
  }
  readonly property var goalList: buildGoalList(root.goalsData)

  function findGoal(slug) {
    for (var i = 0; i < goalList.length; i++) if (goalList[i].slug === slug) return goalList[i]
    return null
  }
  readonly property var selectedGoal: findGoal(root.selectedSlug)

  // Keep the selection valid as the goal list changes underneath it (a file
  // appears/disappears on disk) without ever picking on the user's behalf
  // once they've made a real choice that's still valid.
  onGoalListChanged: {
    if (goalList.length === 0) { selectedSlug = ""; return }
    if (!findGoal(selectedSlug)) selectedSlug = goalList[0].slug
  }
  Component.onCompleted: {
    if (selectedMethod === "" && methods.length > 0) selectedMethod = methods[0]
    if (selectedSlug === "" && goalList.length > 0) selectedSlug = goalList[0].slug
  }

  readonly property var sessionsNewestFirst: {
    var s = (root.selectedGoal && root.selectedGoal.meta.coaching) ? root.selectedGoal.meta.coaching : []
    return s.slice().reverse()
  }

  readonly property var readsList: ["The goal file", "Log entries since the last session", "Journal entries", "Events"]

  function sectionLabel(text) {
    return text
  }

  // Feedback lives on the button itself rather than in a floating popup:
  // nothing to position, nothing to dismiss, and it reads where the eye
  // already is.
  TextMetrics {
    id: copiedMetrics
    font.family: Theme.fontFamily
    font.pixelSize: Theme.bodySize
    text: "copied!"
  }

  Timer {
    id: copiedTimer
    interval: 1300
    onTriggered: copyBtn.label = "copy"
  }

  Process { id: copyProc }
  function copyToClipboard(text) {
    copyProc.command = ["wl-copy", text]
    copyProc.running = true
  }

  Column {
    anchors.fill: parent
    anchors.margins: Theme.panelPadding
    spacing: Theme.sectionGap

    Text {
      text: "Coaching"
      font.family: Theme.fontFamily
      font.pixelSize: Theme.headingSize
      font.bold: true
      color: Theme.ink
    }

    Text {
      visible: root.goalList.length === 0
      text: "No goals yet."
      font.family: Theme.fontFamily
      font.pixelSize: Theme.bodySize
      color: Theme.faint
    }

    Flickable {
      visible: root.goalList.length > 0
      width: parent.width
      height: parent.height - y
      contentHeight: bodyColumn.height
      clip: true

      Column {
        id: bodyColumn
        width: parent.width
        spacing: Theme.spaceLg

        // ---- goal chips -----------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          Text {
            text: "GOAL"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: Theme.dim
          }

          Flow {
            width: parent.width
            spacing: Theme.spaceMd
            Repeater {
              model: root.goalList
              delegate: Text {
                required property var modelData
                readonly property bool isSelected: root.selectedSlug === modelData.slug
                text: modelData.meta.title
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: isSelected ? Theme.accentColor : Theme.dim
                font.underline: isSelected

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedSlug = parent.modelData.slug
                }
              }
            }
          }
        }

        // ---- method chips -----------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          Text {
            text: "METHOD"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: Theme.dim
          }

          Flow {
            width: parent.width
            spacing: Theme.spaceMd
            Repeater {
              model: root.methods
              delegate: Text {
                required property string modelData
                readonly property bool isSelected: root.selectedMethod === modelData
                text: modelData
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: isSelected ? Theme.accentColor : Theme.dim
                font.underline: isSelected

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedMethod = parent.modelData
                }
              }
            }
          }
        }

        // ---- command box --------------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          Text {
            text: "COMMAND"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: Theme.dim
          }

          Rectangle {
            width: parent.width
            height: 36
            border.color: Theme.border
            border.width: 1
            color: "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.margins: Theme.spaceSm
              spacing: Theme.spaceSm
              Text {
                Layout.fillWidth: true
                text: root.command
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySmallSize
                color: Theme.ink
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
              }
              // Reserve this control's own width and height rather than
              // letting it size to content alongside the text (layout-rules
              // §4) -- unreserved, it drew past the box's border and
              // stretched to the box's full height instead of the 20px a
              // secondary control gets (§8).
              Button {
                id: copyBtn
                label: "copy"
                inert: false
                // Reserved from the WIDER of the two labels it can show, so
                // the box doesn't twitch when it flips to "copied!".
                Layout.preferredWidth: Math.round(copiedMetrics.width) + 24
                Layout.preferredHeight: 20
                Layout.alignment: Qt.AlignVCenter
                onActivated: {
                  root.copyToClipboard(root.command)
                  copyBtn.label = "copied!"
                  copiedTimer.restart()
                }
              }
            }
          }
        }

        // ---- what a session reads ------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          Text {
            text: "THIS SESSION READS"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: Theme.dim
          }

          Column {
            width: parent.width
            spacing: Theme.spaceXs
            Repeater {
              model: root.readsList
              delegate: RowLayout {
                required property string modelData
                width: parent.width
                spacing: Theme.spaceSm
                Text {
                  text: "-"
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySize
                  color: Theme.dim
                }
                Text {
                  Layout.fillWidth: true
                  text: modelData
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySize
                  color: Theme.ink
                  wrapMode: Text.WordWrap
                }
              }
            }
          }
        }

        // ---- past sessions --------------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          Text {
            text: "PAST SESSIONS"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.captionSize
            font.bold: true
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
            color: Theme.dim
          }

          Text {
            visible: root.sessionsNewestFirst.length === 0
            text: "No coaching sessions yet."
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.faint
          }

          Column {
            width: parent.width
            visible: root.sessionsNewestFirst.length > 0
            Repeater {
              model: root.sessionsNewestFirst
              delegate: Column {
                required property var modelData
                required property int index
                width: parent.width
                spacing: Theme.spaceXxs

                Rectangle {
                  width: parent.width
                  height: 1
                  color: Theme.hairline
                  visible: index > 0
                }

                Item { width: 1; height: index > 0 ? 8 : 0 }

                RowLayout {
                  width: parent.width
                  spacing: Theme.spaceSm
                  Text {
                    text: modelData.date
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    font.bold: true
                    color: Theme.ink
                  }
                  Text {
                    text: modelData.method
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    color: Theme.dim
                  }
                  Item { Layout.fillWidth: true }
                }

                Text {
                  width: parent.width
                  visible: !!modelData.summary
                  text: modelData.summary
                  wrapMode: Text.WordWrap
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySmallSize
                  color: Theme.dim
                }

                Item { width: 1; height: 8 }
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Runs in your own terminal. It reads all of this and rewrites what's next."
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.faint
        }
      }
    }
  }
}
