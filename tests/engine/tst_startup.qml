import QtQuick

// The engine as a login brings it up, before any test resets it: a file of
// its own, since every other file's reset switches the timer on. The state
// lives in Engine.qml's property defaults, so Cycle.fresh() coming up off
// (tst_cycle.qml) didn't stop a "normal" default there from starting the
// timer at every login.
EngineTest {
  name: "startup"
  resetBeforeEachTest: false

  function test_a_login_leaves_the_timer_off() {
    compare(engine.mode, "off")
    verify(!engine.countdownRunning, "nothing counts down until the bar switches it on")
    verify(!engine.overlayVisible)
    advance(3600)
    verify(engine.atNight || engine.phase === "focus", "an hour later, no run has ended")
    compare(engine.mode, "off")
  }
}
