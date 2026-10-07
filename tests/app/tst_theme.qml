import QtQuick

// Regression test: the app kept whatever omarchy theme it started with. It
// must follow a switch -- the theme directory swapped, then the theme-set
// hook's `qs ipc call theme reload` -- and an edit to colors.toml in place
// (see the comment on following a switch in Theme.qml).
//
// The window's colour is Theme.paper, the theme's `background`, so that is
// what is checked: nothing here imports Theme. The fixture HOME has no
// theme, so the app starts on the Flexoki fallback; this file's HOME is its
// own, so installing themes in it touches no other test.
OmvisionTest {
  name: "theme"

  readonly property string current: home + "/.local/state/omarchy/current"

  // The fixture's colors.toml, with another background.
  function themeToml(background) {
    return 'mode = "dark"\n'
         + 'background = "' + background + '"\n'
         + 'foreground = "#e0e0e0"\n'
         + 'accent = "#3264eb"\n'
  }

  // What omarchy-theme-set does, in its order: stage the next theme, swap
  // it in for the current one, then run the theme-set hooks. The hook's
  // call goes to this instance only: $PPID is the app, and a test must not
  // reach the user's own Omvision.
  function setTheme(name, background) {
    var r = run(["/usr/bin/sh", "-c",
                 'set -e; c="$1"; mkdir -p "$c/next-theme"; printf "%s" "$2" > "$c/next-theme/colors.toml"; '
                 + 'rm -rf "$c/theme"; mv "$c/next-theme" "$c/theme"; '
                 + 'qs ipc --pid "$PPID" call theme reload',
                 "sh", current, themeToml(background)])
    compare(r.code, 0, "switched to " + name)
  }

  function expectPaper(background, msg) {
    tryVerify(function() { return Qt.colorEqual(window.color, background) }, 5000,
              msg + ": window is " + window.color + ", want " + background)
  }

  function test_follows_theme_switches() {
    if (!safeHome()) skip("not in a test HOME")

    expectPaper("#FFFCF0", "no theme installed: the Flexoki fallback")

    setTheme("one", "#101820")
    expectPaper("#101820", "the first theme set")

    // The switch that used to be missed: the colors.toml being watched is
    // deleted with the directory it sits in.
    setTheme("two", "#203040")
    expectPaper("#203040", "a switch")

    setTheme("one", "#101820")
    expectPaper("#101820", "switching back")

    // A theme edited in place, with no switch.
    writeFile(current + "/theme/colors.toml", themeToml("#305050"))
    expectPaper("#305050", "an in-place edit")
  }
}
