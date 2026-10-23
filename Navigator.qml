import QtQuick

// Where the app is: which screen shows, which goal is open and where its
// back link goes, which goal the Coaching screen is on, and whether the
// sidebar is out. Plain state and rules, no Quickshell and no Theme, so
// tests/unit/tst_navigator.qml runs it under qmltestrunner on its own.
QtObject {
  id: nav

  property string screen: "goals" // today | goals | coaching | journal | goalDetail
  property string goalSlug: ""
  // Where the goal's back link returns to: the Goals list, or the journal
  // when the goal was opened from an `@` tag there, so reading up on a goal
  // mid-sentence puts you back in the sentence.
  property string goalBack: "goals"
  property string coachSlug: ""
  // A dialog is open over the screen it was opened from: the screen keys
  // must not leave it from under the dialog. App binds this.
  property bool blocked: false

  // The rail marks the screen a goal was opened from while the goal shows.
  readonly property string railScreen: nav.screen === "goalDetail" ? nav.goalBack : nav.screen

  function openGoal(slug, from) {
    nav.goalSlug = slug
    nav.goalBack = from
    nav.screen = "goalDetail"
  }

  function back() { nav.screen = nav.goalBack }

  function coach(slug) {
    nav.coachSlug = slug
    nav.screen = "coaching"
  }

  // ---- sidebar -------------------------------------------------------------
  // There is one sidebar and one state for it: the icon rail. The only
  // question is whether it is on screen at all, and only the Journal ever
  // answers no: writing mode hides it, and the journal's own faint control
  // brings it back for as long as you want it. Leaving the journal restores
  // it, and entering the journal hides it again however it was left --
  // writing always starts with nothing down the side of the page.
  readonly property bool writingMode: nav.screen === "journal"
  property bool sidebarRevealed: false
  readonly property bool sidebarHidden: nav.writingMode && !nav.sidebarRevealed
  onWritingModeChanged: if (nav.writingMode) nav.sidebarRevealed = false

  function toggleSidebar() {
    if (nav.writingMode) nav.sidebarRevealed = !nav.sidebarRevealed
  }

  // Starting to write in the journal puts a brought-back sidebar away.
  function hideSidebar() { nav.sidebarRevealed = false }

  // ---- keys ----------------------------------------------------------------
  // The keys that work on every screen, the journal's editor and the task
  // fields included: neither does anything with Ctrl+B/T/G/J/1-4. Ctrl+K
  // would have been the obvious letter for Coaching, but a text field takes
  // it as "delete to the end of the line", so Coaching is Ctrl+3 only.
  readonly property var screenKeys: ({
    [Qt.Key_T]: "today", [Qt.Key_G]: "goals", [Qt.Key_J]: "journal",
    [Qt.Key_1]: "today", [Qt.Key_2]: "goals", [Qt.Key_3]: "coaching", [Qt.Key_4]: "journal"
  })

  // Returns whether the key was one of them. A screen key is taken even
  // while blocked, so it doesn't reach a field in the dialog either.
  function handleKey(key, modifiers) {
    if (!(modifiers & Qt.ControlModifier)) return false
    if (key === Qt.Key_B) { nav.toggleSidebar(); return true }
    var screen = nav.screenKeys[key]
    if (screen === undefined) return false
    if (!nav.blocked) nav.screen = screen
    return true
  }
}
