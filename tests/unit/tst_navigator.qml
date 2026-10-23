import QtQuick
import QtTest

// Navigator.qml's rules on their own: which screen a key or a goal opens,
// where back goes, and when the sidebar shows. tests/app/tst_shortcuts.qml
// checks the same keys reach it from inside the running app.
TestCase {
  name: "Navigator"

  // By its URL, not `import "../.."`: importing the repo's directory would
  // pull in JournalHighlight, whose compiled module qmllint can't see.
  readonly property Component navigator: Qt.createComponent(Qt.resolvedUrl("../../Navigator.qml"))

  function make() { return createTemporaryObject(navigator, null) }

  function test_starts_on_goals_with_the_rail_shown() {
    var nav = make()
    compare(nav.screen, "goals")
    verify(!nav.sidebarHidden)
  }

  function test_screen_keys() {
    var nav = make()
    var keys = [[Qt.Key_T, "today"], [Qt.Key_G, "goals"], [Qt.Key_J, "journal"],
                [Qt.Key_1, "today"], [Qt.Key_2, "goals"], [Qt.Key_3, "coaching"], [Qt.Key_4, "journal"]]
    for (let i = 0; i < keys.length; i++) {
      verify(nav.handleKey(keys[i][0], Qt.ControlModifier))
      compare(nav.screen, keys[i][1])
    }
  }

  function test_keys_without_ctrl_are_left_alone() {
    var nav = make()
    verify(!nav.handleKey(Qt.Key_T, Qt.NoModifier))
    verify(!nav.handleKey(Qt.Key_K, Qt.ControlModifier))
    compare(nav.screen, "goals")
  }

  function test_a_dialog_blocks_the_screen_keys_but_takes_them() {
    var nav = make()
    nav.blocked = true
    verify(nav.handleKey(Qt.Key_T, Qt.ControlModifier), "taken, so a dialog field doesn't get it")
    compare(nav.screen, "goals")
  }

  function test_a_goal_goes_back_where_it_was_opened_from() {
    var nav = make()
    nav.openGoal("a", "journal")
    compare(nav.screen, "goalDetail")
    compare(nav.goalSlug, "a")
    compare(nav.railScreen, "journal", "the rail marks where it came from")
    nav.back()
    compare(nav.screen, "journal")
    nav.openGoal("b", "goals")
    nav.back()
    compare(nav.screen, "goals")
  }

  function test_coach_opens_coaching_on_the_goal() {
    var nav = make()
    nav.coach("a")
    compare(nav.screen, "coaching")
    compare(nav.coachSlug, "a")
  }

  function test_the_journal_hides_the_sidebar_and_ctrl_b_brings_it_back() {
    var nav = make()
    nav.screen = "journal"
    verify(nav.sidebarHidden)
    verify(nav.handleKey(Qt.Key_B, Qt.ControlModifier))
    verify(!nav.sidebarHidden)
    nav.toggleSidebar()
    verify(nav.sidebarHidden)
  }

  function test_writing_puts_a_brought_back_sidebar_away() {
    var nav = make()
    nav.screen = "journal"
    nav.toggleSidebar()
    nav.hideSidebar()
    verify(nav.sidebarHidden)
  }

  function test_entering_the_journal_hides_it_however_it_was_left() {
    var nav = make()
    nav.screen = "journal"
    nav.toggleSidebar()
    nav.screen = "today"
    verify(!nav.sidebarHidden)
    nav.screen = "journal"
    verify(nav.sidebarHidden)
  }

  function test_ctrl_b_does_nothing_outside_the_journal() {
    var nav = make()
    nav.toggleSidebar()
    verify(!nav.sidebarRevealed)
    verify(!nav.sidebarHidden)
  }
}
