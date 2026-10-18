#!/usr/bin/env bash
# The engine layer's launcher, as bin/omvision is the app layer's: bin/test
# runs it once per tests/engine/tst_*.qml, with HOME already seeded and the
# test file in OMVISION_TEST, and reads the PASS/FAIL lines QsTestCase
# prints. Any arguments go on to qs.
#
# `qs` offscreen has no layer-shell backend, so the shell.qml here puts the
# plugin's own Overlay.qml in a FloatingWindow where Service.qml uses a
# PanelWindow, over the plugin's own Engine.qml: every file but the 30-line
# Service.qml is the one that ships. Not demo mode: the real notes-helper.py
# writes real entries, into the throwaway HOME. The test file is loaded in
# that window, so its key events reach the overlay's fields and shortcuts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${OMVISION_TEST:?the test file to run}"
out="${OMVISION_TEST_OUT:-${TMPDIR:-/tmp}}"

# The active-goal file's directory, so the engine's FileView has somewhere
# to watch before the helper first writes there.
mkdir -p "$HOME/.local/state/omvision"

# The plugin's files beside shell.qml, laid out as for bin/ompom-demo.
cfg="$(mktemp -d "$out/cfg.XXXXXX")"
"$ROOT/bin/ompom-stage" "$ROOT/plugins/ompom.engine" "$cfg"
cat > "$cfg/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
  Engine { id: engine }
  FloatingWindow {
    id: window
    visible: engine.overlayVisible
    implicitWidth: 1280
    implicitHeight: 800
    color: "transparent"
    Overlay { id: overlay; anchors.fill: parent; engine: engine }
    // Behind the overlay, which takes every click that misses a control.
    Loader {
      anchors.fill: parent
      z: -1
      source: "file://" + Quickshell.env("OMVISION_TEST")
      onLoaded: {
        item.engine = engine
        item.overlay = overlay
        item.window = window
        item.target = overlay
      }
    }
  }
}
QML

# The writing surfaces use omvision's MarkdownHighlight module, which
# resolves through QML2_IMPORT_PATH (see docs/ompom-highlighter.md).
QML2_IMPORT_PATH="$ROOT${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" exec qs -p "$cfg" "$@"
