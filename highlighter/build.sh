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

# clangd reads its flags from here (there is no compile_commands.json without
# cmake); written from the same pkg-config call the build uses, so the editor
# and the compiler never disagree about the Qt headers.
{ echo "-std=c++17"; echo "-I."; pkg-config --cflags Qt6Quick Qt6Qml Qt6Gui Qt6Core | tr ' ' '\n' | grep -v '^$'; } > compile_flags.txt

"$MOC" markdownhighlighter.h -o "$BUILD/moc_markdownhighlighter.cpp"
"$MOC" plugin.h -o "$BUILD/moc_plugin.cpp"

# Hidden visibility: only the plugin's entry points (Q_PLUGIN_METADATA marks
# them exported) leave the library. The ompom overlay loads this same module
# inside omarchy-shell, and ompom's own older plugin also defines a class named
# MarkdownHighlighter; with default visibility two such libraries in one
# process can bind to each other's symbols, which is a native crash of the
# whole shell, not a QML error.
#
# Linked to a temporary name and renamed into place: a running app has the old
# .so mapped, and overwriting that file in place can hand it pages of the new
# one (docs/ompom-highlighter.md, "The crash"). A rename leaves the
# mapped file untouched.
#
# pkg-config's flags are left unquoted on purpose: each one has to reach g++
# as a word of its own.
# shellcheck disable=SC2046
g++ -std=c++17 -fPIC -shared -O2 -Wall \
  -fvisibility=hidden -fvisibility-inlines-hidden \
  $(pkg-config --cflags Qt6Quick Qt6Qml Qt6Gui Qt6Core) \
  -I. \
  markdownhighlighter.cpp plugin.cpp \
  "$BUILD/moc_markdownhighlighter.cpp" "$BUILD/moc_plugin.cpp" \
  $(pkg-config --libs Qt6Quick Qt6Qml Qt6Gui Qt6Core) \
  -o "$OUT/.libmarkdownhighlight.so.new"
mv -f "$OUT/.libmarkdownhighlight.so.new" "$OUT/libmarkdownhighlight.so"

cat > "$OUT/qmldir" <<QMLDIR
module MarkdownHighlight
plugin markdownhighlight
QMLDIR

echo "built $OUT/libmarkdownhighlight.so"
