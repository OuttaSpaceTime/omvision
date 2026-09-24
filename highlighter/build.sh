#!/usr/bin/env bash
# Builds the MarkdownHighlight QML module next to omvision.qml.
#
# No cmake, no ninja, no sudo: moc + g++ against the system Qt6, straight into
# ../MarkdownHighlight/, which is where `import MarkdownHighlight` looks when
# the importing file sits in ~/Code/omvision. Rebuild after any change here,
# then restart the app -- a running Quickshell hot-reloads QML, not plugins.
set -euo pipefail

cd "$(dirname "$0")"

MOC=/usr/lib/qt6/moc
OUT=../MarkdownHighlight
BUILD=build

command -v g++ >/dev/null || { echo "g++ not found" >&2; exit 1; }
[ -x "$MOC" ] || { echo "$MOC not found (install qt6-base)" >&2; exit 1; }

mkdir -p "$BUILD" "$OUT"

"$MOC" markdownhighlighter.h -o "$BUILD/moc_markdownhighlighter.cpp"
"$MOC" plugin.h -o "$BUILD/moc_plugin.cpp"

g++ -std=c++17 -fPIC -shared -O2 -Wall \
  $(pkg-config --cflags Qt6Quick Qt6Qml Qt6Gui Qt6Core) \
  -I. \
  markdownhighlighter.cpp plugin.cpp \
  "$BUILD/moc_markdownhighlighter.cpp" "$BUILD/moc_plugin.cpp" \
  $(pkg-config --libs Qt6Quick Qt6Qml Qt6Gui Qt6Core) \
  -o "$OUT/libmarkdownhighlight.so"

cat > "$OUT/qmldir" <<QMLDIR
module MarkdownHighlight
plugin markdownhighlight
QMLDIR

echo "built $OUT/libmarkdownhighlight.so"
