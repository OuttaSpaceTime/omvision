#!/usr/bin/env bash
# Runs tests/engine/tst_break.qml against the real ompom engine, offscreen.
#
#   tests/engine/run.sh <out dir> [test file]
#
# `qs` offscreen has no layer-shell backend, so the test's shell.qml puts
# the plugin's own Overlay.qml in a FloatingWindow where Service.qml uses a
# PanelWindow, over the plugin's own Engine.qml: every file but the 30-line
# Service.qml is the one that ships. Not demo mode: the real notes-helper.py
# writes real entries -- into a throwaway HOME under <out dir>, seeded from
# tests/fixtures/home. The test sits inside that window, so its key events
# reach the overlay's fields and shortcuts.
#
# Prints the test's lines (ok / FAIL / DONE) and exits non-zero on a
# failure, a crash or a timeout. bin/test runs this as its `engine` layer.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${1:?out dir}"
src="$ROOT/plugins/ompom.engine"
commons=/usr/share/omarchy/shell/Commons
[ -d "$commons" ] || { echo "FAIL no omarchy-shell Commons at $commons"; exit 1; }

cfg="$out/cfg" home="$out/home"
mkdir -p "$cfg" "$home/.local/state/omvision" "$out/shots"
touch "$home/.omvision-test-home"
"$ROOT/tests/app/seed-home.sh" "$ROOT/tests/fixtures/home" "$home" >/dev/null || { echo "FAIL couldn't seed $home"; exit 1; }
# Goals the break's picker must leave out: one not focusable (goal-files.md
# §6), one done. Here rather than in the shared fixture, which the app tests
# compare file for file.
printf -- '---\ntitle: Train legs\nstatus: active\nfocusable: no\n---\n' >"$home/Notes/Omvision/goals/train-legs.md"
printf -- '---\ntitle: Old milestone\nstatus: done\n---\n' >"$home/Notes/Omvision/goals/old-milestone.md"

# The plugin's files beside shell.qml, as bin/ompom-demo lays them out, so
# its types resolve as same-directory types and `qs.Commons` as the shell's
# own module. The test goes two levels down, as in the repo, so its import
# of the app's Parser.js (the log reader it checks the helper's entries
# with) is "../../Parser.js" in both places, and qmllint can follow it.
ln -s "$commons" "$cfg/Commons"
for f in "$src"/*.qml "$src"/notes-helper.py "$ROOT/Parser.js"; do ln -s "$f" "$cfg/${f##*/}"; done
mkdir -p "$cfg/tests/engine"
cp "${2:-$ROOT/tests/engine/tst_break.qml}" "$cfg/tests/engine/EngineTest.qml"
cat > "$cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "tests/engine"
ShellRoot {
  // Noon today, whenever the test runs: the engine follows the clock into
  // its night at 22:15, and the cycle steps need a day. The test moves it.
  Engine {
    id: engine
    clockOffsetMs: { var d = new Date(); d.setHours(12, 0, 0, 0); return d.getTime() - Date.now() }
  }
  FloatingWindow {
    id: window
    visible: engine.overlayVisible
    implicitWidth: 1280
    implicitHeight: 800
    color: "transparent"
    Overlay { id: overlay; anchors.fill: parent; engine: engine }
    EngineTest { engine: engine; overlayWindow: window; overlay: overlay }
  }
}
QML

# WAYLAND_DISPLAY stays, as in bin/test's app layer: qs's GTK setup aborts
# without one, and offscreen nothing is shown on it.
HOME="$home" QT_QPA_PLATFORM=offscreen QML_XHR_ALLOW_FILE_READ=1 \
  ENGINE_TEST_SHOTS="$out/shots" QML2_IMPORT_PATH="$ROOT${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
  timeout "${ENGINE_TEST_TIMEOUT:-90}" qs -p "$cfg" --no-color >"$out/engine.log" 2>&1
code=$?
lines="$(sed -n 's/.*\[engine-test\] //p' "$out/engine.log")"
printf '%s\n' "$lines"
if [ "$code" = 124 ]; then echo "FAIL timed out"; exit 1; fi
# Checked after the DONE line too: a crash on the way out (a native module's
# teardown, say) is still a crash.
if [ "$code" != 0 ]; then echo "FAIL qs exited $code"; exit 1; fi
printf '%s\n' "$lines" | grep -q '^DONE 0 failed' || exit 1
