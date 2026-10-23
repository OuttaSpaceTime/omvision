pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import "Util.js" as Util

// Coaching — the hand-off screen, minus anything that writes. Goal and
// method are local UI state only (they pick which command is shown, never
// touch disk). `start in kitty` opens the session itself; `copy` stays for
// running it somewhere else (another terminal, a tmux pane), since the
// ompom-coach skill receives it either way.
Item {
  id: root

  // How far this screen's left edge sits from the window's; see Theme.pageX.
  property int leftInset: 0

  required property App app
  // The goal the session is about: the one "Coach this goal" was clicked on,
  // or picked here.
  readonly property string selectedSlug: root.app.nav.coachSlug
  property string selectedMethod: ""

  // Exactly the two the ompom-coach skill accepts. It parses `--method mi|polya`
  // and stops with an error on anything else, so a third chip here would just
  // hand the user a command that refuses to run. If the skill ever learns
  // another method, add it in both places at once.
  readonly property var methods: ["motivational interviewing", "how to solve it"]

  function methodFlag(m) { return m === "how to solve it" ? "polya" : "mi" }

  // One source for the command: the box shows exactly what `copy` copies and
  // `start in kitty` runs. The prompt is one argument, quoted, so claude
  // can't take `--method` for an option of its own and the skill gets the
  // whole line as its ARGUMENTS. The slug needs no escaping: goal slugs are
  // [a-z0-9-] (goal-files.md), and the skill refuses anything else.
  readonly property string prompt:
    "/ompom-coach " + root.selectedSlug + " --method " + methodFlag(root.selectedMethod)
  readonly property string command: "claude '" + root.prompt + "'"

  // kitty, not the omarchy default terminal, because that's where the
  // sessions are run by hand. It starts in the notes directory so the
  // session's project is the notes it reads and rewrites, not wherever
  // Omvision happened to be launched from. No --hold: when the session ends,
  // the window goes with it.
  readonly property var launchArgv: [
    "kitty", "--directory", Paths.notesDir, "--title", "coach · " + root.selectedSlug,
    "claude", root.prompt
  ]

  // Detached, so closing Omvision doesn't take a running session with it.
  // `kitty` by bare name, from PATH: bin/test puts a stub ahead of it.
  function startSession() { Quickshell.execDetached(root.launchArgv) }

  readonly property var goalList: Util.goalsByTitle(root.app.notes.goalsData)

  function findGoal(slug) {
    return goalList.find(function(g) { return g.slug === slug }) || null
  }
  readonly property var selectedGoal: findGoal(root.selectedSlug)

  // Keep the selection valid as the goal list changes underneath it (a file
  // appears/disappears on disk) without ever picking on the user's behalf
  // once they've made a real choice that's still valid.
  onGoalListChanged: {
    if (goalList.length === 0) { root.app.nav.coachSlug = ""; return }
    if (!findGoal(selectedSlug)) root.app.nav.coachSlug = goalList[0].slug
  }
  Component.onCompleted: {
    if (selectedMethod === "" && methods.length > 0) selectedMethod = methods[0]
    if (selectedSlug === "" && goalList.length > 0) root.app.nav.coachSlug = goalList[0].slug
  }

  readonly property var sessionsNewestFirst:
    ((root.selectedGoal && root.selectedGoal.meta.coaching) || []).slice().reverse()

  readonly property var readsList: ["The goal file", "Log entries since the last session", "Journal entries", "Events"]

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
    interval: Theme.copiedFeedbackDuration
    onTriggered: copyBtn.label = "copy"
  }

  Process { id: copyProc }
  function copyToClipboard(text) {
    copyProc.command = ["wl-copy", text]
    copyProc.running = true
  }

  Column {
    // The journal's column, on the journal's line (Theme.pageX).
    x: Theme.pageX(root.width, root.leftInset)
    y: Theme.panelPadding
    width: Theme.pageWidth(root.width)
    height: root.height - Theme.panelPadding * 2
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
        // The same gap as the title's to the first section: one rhythm down
        // the whole page instead of a roomy top over a tight stack.
        spacing: Theme.sectionGap

        // ---- goal chips -----------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          CaptionLabel { text: "Goal" }

          Flow {
            width: parent.width
            spacing: Theme.spaceMd
            Repeater {
              model: root.goalList
              delegate: TextChip {
                id: goalChip
                required property var modelData
                selected: root.selectedSlug === modelData.slug
                label: modelData.meta.title
                onClicked: root.app.nav.coachSlug = goalChip.modelData.slug
              }
            }
          }
        }

        // ---- method chips -----------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          CaptionLabel { text: "Method" }

          Flow {
            width: parent.width
            spacing: Theme.spaceMd
            Repeater {
              model: root.methods
              delegate: TextChip {
                id: methodChip
                required property string modelData
                objectName: "coachMethod:" + root.methodFlag(modelData)
                selected: root.selectedMethod === modelData
                label: modelData
                onClicked: root.selectedMethod = methodChip.modelData
              }
            }
          }
        }

        // ---- command box --------------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          CaptionLabel { text: "Command" }

          Rectangle {
            width: parent.width
            height: Theme.smallControlHeight + Theme.spaceSm * 2
            border.color: Theme.border
            border.width: Theme.borderWidth
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
              // stretched to the box's full height instead of the small
              // height a secondary control gets (§9).
              Button {
                id: copyBtn
                label: "copy"
                // Reserved from the WIDER of the two labels it can show, so
                // the box doesn't twitch when it flips to "copied!".
                Layout.preferredWidth: Math.round(copiedMetrics.width) + Theme.spaceXl
                Layout.preferredHeight: Theme.smallControlHeight
                Layout.alignment: Qt.AlignVCenter
                onActivated: {
                  root.copyToClipboard(root.command)
                  copyBtn.label = "copied!"
                  copiedTimer.restart()
                }
              }
            }
          }

          // Its own row, under the box, at full control height: the screen's one
          // primary action, filled like Goal detail's `Coach this goal` that
          // leads here. In the box beside `copy` it would have had to shrink to
          // the small height, and read as a secondary.
          Button {
            objectName: "coachStartButton"
            label: "start in kitty"
            filled: true
            onActivated: root.startSession()
          }
        }

        // ---- what a session reads ------------------------------------------
        Column {
          width: parent.width
          spacing: Theme.spaceSm

          CaptionLabel { text: "This session reads" }

          Column {
            width: parent.width
            spacing: Theme.spaceXs
            Repeater {
              model: root.readsList
              delegate: RowLayout {
                id: readRow
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
                  text: readRow.modelData
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

          CaptionLabel { text: "Past sessions" }

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
                id: sessionRow
                required property var modelData
                required property int index
                width: parent.width
                spacing: Theme.spaceXxs

                Rectangle {
                  width: parent.width
                  height: Theme.hairlineWidth
                  color: Theme.hairline
                  visible: sessionRow.index > 0
                }

                Item { width: parent.width; height: sessionRow.index > 0 ? Theme.spaceSm : 0 }

                RowLayout {
                  width: parent.width
                  spacing: Theme.spaceSm
                  CaptionLabel {
                    text: sessionRow.modelData.date
                    color: Theme.ink
                  }
                  Text {
                    text: sessionRow.modelData.method
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.captionSize
                    color: Theme.dim
                  }
                  Item { Layout.fillWidth: true }
                }

                Text {
                  width: parent.width
                  visible: !!sessionRow.modelData.summary
                  text: sessionRow.modelData.summary
                  wrapMode: Text.WordWrap
                  lineHeight: Theme.proseLineHeight
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.bodySmallSize
                  color: Theme.dim
                }

                Item { width: parent.width; height: Theme.spaceSm }
              }
            }
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Opens in kitty, in ~/Notes/Omvision. It reads all of this and rewrites what's next."
          font.family: Theme.fontFamily
          font.pixelSize: Theme.captionSize
          color: Theme.faint
        }
      }
    }
  }
}
