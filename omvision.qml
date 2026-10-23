pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// Omvision -- goals, tasks, a daily journal and coaching, over the ompom
// engine's file contract (docs/goal-files.md). A standalone Quickshell
// config, launched with bin/omvision rather than `qs -p` by hand: the
// launcher puts the journal's compiled markdown highlighter on the import
// path (see bin/omvision for why it has to).
//
// This file is only the window and its layout. The app is App.qml: its data
// (NotesStore), where it is (Navigator) and which dialog is open. Each
// screen and dialog is handed the App and works through it.
ShellRoot {
  id: root

  readonly property App app: App {}

  // Hiding a screen does not take the keyboard from it: the journal's
  // editor or a task field keeps active focus while invisible, and typing
  // on Today would go into the hidden day and be saved there. So every
  // change of screen hands the keyboard back to the window's content, where
  // the shortcuts are handled. The journal takes it again itself when it is
  // shown (its onVisibleChanged).
  Connections {
    target: root.app.nav
    function onScreenChanged() { if (root.app.nav.screen !== "journal") contentRoot.forceActiveFocus() }
  }

  // A goal edit that fails with no field or dialog to show it in.
  Connections {
    target: root.app.notes
    function onWriteFailed(message) { writeErrorBanner.show(message) }
  }

  // Closing the window ends the app. Quickshell is built for shells, which
  // outlive their windows, so it keeps running with none, and each launch
  // would leave another windowless Omvision behind. Quitting here is what
  // its docs give for an app that should end with its window.
  Connections {
    target: Quickshell
    function onLastWindowClosed() { Qt.quit() }
  }

  FloatingWindow {
    id: window
    title: "Omvision"
    // bin/shot sets these to capture at other sizes; unset, they are 0.
    implicitWidth: parseInt(Quickshell.env("OMVISION_SHOT_WIDTH") || "0") || Theme.windowWidth
    implicitHeight: parseInt(Quickshell.env("OMVISION_SHOT_HEIGHT") || "0") || Theme.windowHeight
    minimumSize: Qt.size(Theme.windowMinWidth, Theme.windowMinHeight)
    color: Theme.paper

    Item {
      id: contentRoot
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()
      // Keys the focused item leaves unaccepted bubble up to here.
      Keys.onPressed: function(event) { event.accepted = root.app.nav.handleKey(event.key, event.modifiers) }

      // Offscreen screenshots for bin/shot; inactive (nothing loaded) in a
      // normal launch. Behind everything, since it also paints the paper
      // the grab needs -- see ShotDriver.qml.
      Loader {
        anchors.fill: parent
        z: -1
        active: Quickshell.env("OMVISION_SHOT_DIR") !== null
                && Quickshell.env("OMVISION_SHOT_DIR") !== ""
        source: "ShotDriver.qml"
        onLoaded: {
          const driver = item as ShotDriver
          driver.app = root.app
          driver.journal = journalScreen
          driver.goalDetail = goalDetailScreen
          driver.target = contentRoot
        }
      }

      // Test hook: OMVISION_TEST names a .qml file (an absolute path, or one
      // relative to this directory) that drives the real app from inside,
      // the way ShotDriver does for screenshots. Qt's qmltestrunner can't
      // load Quickshell's modules, so a test that needs the real screens,
      // FileViews and write paths has to run inside `qs` like this. The file
      // must declare every property passed below. Unset or empty, nothing is
      // loaded -- a normal launch never sees it. Behind everything for the
      // same reason as the driver: anything it draws must not cover the app.
      //
      // The properties go in as setSource()'s initial properties, not as
      // assignments in onLoaded the way the driver gets them: the test's
      // type lives under tests/ and the app can't name it, so `item` would
      // be a plain QObject to qmllint, with none of these members. Initial
      // properties still fire their change handlers, in the order listed,
      // as the properties are set -- before the test file's own bindings
      // and Component.onCompleted, which works because a read evaluates a
      // pending binding, so started() still sees `today`.
      Loader {
        anchors.fill: parent
        z: -1
        readonly property string testFile: Quickshell.env("OMVISION_TEST") || ""
        Component.onCompleted: {
          if (testFile === "") return
          setSource(testFile.charAt(0) === "/" ? "file://" + testFile : Qt.resolvedUrl(testFile), {
            app: root.app,
            journal: journalScreen,
            goalDetail: goalDetailScreen,
            coaching: coachingScreen,
            target: contentRoot,
            window: window
          })
        }
      }

      Row {
        anchors.fill: parent
        spacing: 0

        // Showing and hiding the sidebar animates the room it takes, not the
        // sidebar itself: this slot opens from 0 to the rail's width, the
        // rail (always its full width, so nothing inside it squeezes) slides
        // in along with it, and the content beside it narrows in step
        // instead of jumping sideways.
        Item {
          id: sidebarSlot
          height: parent.height
          width: root.app.nav.sidebarHidden ? 0 : inFlowSidebar.railWidth
          visible: width > 0
          clip: true

          Behavior on width {
            NumberAnimation { duration: Theme.slideDuration; easing.type: Theme.slideEasing }
          }

          Sidebar {
            id: inFlowSidebar
            height: parent.height
            x: sidebarSlot.width - width
            currentScreen: root.app.nav.railScreen
            onNavigate: function(screen) { root.app.nav.screen = screen }
          }
        }

        // The screens. Each is told how far this area sits from the window's
        // left edge -- the rail's width, animated -- so it can centre its
        // text column on the window rather than on this area (Theme.pageX),
        // and the column stays put while the rail slides in or out.
        Item {
          width: parent.width - sidebarSlot.width
          height: parent.height

          GoalsScreen {
            app: root.app
            anchors.fill: parent
            leftInset: sidebarSlot.width
            visible: root.app.nav.screen === "goals"
          }

          GoalDetailScreen {
            id: goalDetailScreen
            app: root.app
            anchors.fill: parent
            leftInset: sidebarSlot.width
            visible: root.app.nav.screen === "goalDetail"
          }

          TodayScreen {
            app: root.app
            anchors.fill: parent
            leftInset: sidebarSlot.width
            visible: root.app.nav.screen === "today"
          }

          CoachingScreen {
            id: coachingScreen
            app: root.app
            anchors.fill: parent
            leftInset: sidebarSlot.width
            visible: root.app.nav.screen === "coaching"
          }

          JournalScreen {
            id: journalScreen
            app: root.app
            anchors.fill: parent
            leftInset: sidebarSlot.width
            visible: root.app.nav.screen === "journal"
          }
        }
      }

      // At the window root, above the sidebar too, so nothing behind a
      // dialog can be clicked. Each shows itself while app.dialog names it.
      EventDialog { app: root.app; anchors.fill: parent; z: 900 }
      CancelDialog { app: root.app; anchors.fill: parent; z: 900 }
      NewGoalDialog { app: root.app; anchors.fill: parent; z: 900 }

      ErrorBanner {
        id: writeErrorBanner
        z: 1000
      }
    }
  }
}
