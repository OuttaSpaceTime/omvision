#!/usr/bin/env bash
# Puts the fixture notes into a test HOME, or puts them back.
#
#   tests/app/seed-home.sh <fixture home> <test home>
#
# bin/test runs it once to seed a fresh temp HOME before starting the app;
# OmvisionTest.qml runs it again before every test to undo what the last
# test wrote. Prints each installed file's path, one per line, so the test
# can read back what the app should now be showing.
#
# Safety: the target must be a directory under the temp dir that carries the
# marker file bin/test creates. This script deletes files there (whatever a
# test added under Notes/Omvision), and it must never be able to do that to
# a real home, whatever HOME a caller hands it.
#
# Files are installed the way the app writes its own: a temp file next to the
# target, then a rename over it. The app's file watchers already have to
# follow that (every goal-file edit lands that way), so a reset looks to the
# app like one more write -- where copying in place would show it a
# truncated file for a moment, and deleting the directory and copying it
# back would hand the watchers new inodes all at once.
#
# A fixture file named TODAY.md is installed under today's date, so the
# journal opens on it. `date +%F` is local time, as Parser.dayKey() is.
set -euo pipefail

fixtures="${1:?fixture home}"
target="${2:?test home}"

tmp_root="$(cd "${TMPDIR:-/tmp}" && pwd -P)"
target_real="$(cd "$target" && pwd -P)"
case "$target_real/" in
  "$tmp_root"/*|/tmp/*) ;;
  *) echo "seed-home: refusing: $target_real is not under $tmp_root" >&2; exit 2 ;;
esac
[ -f "$target_real/.omvision-test-home" ] || {
  echo "seed-home: refusing: $target_real has no .omvision-test-home marker" >&2; exit 2; }

notes="$target_real/Notes/Omvision"
today="$(date +%F)"
declare -A keep=()

while IFS= read -r -d '' src; do
  rel="${src#"$fixtures"/}"
  case "$rel" in
    */TODAY.md) rel="${rel%TODAY.md}$today.md" ;;
  esac
  dst="$target_real/$rel"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst.seed-tmp"
  mv -f "$dst.seed-tmp" "$dst"
  keep["$dst"]=1
  printf '%s\n' "$dst"
done < <(find "$fixtures" -type f -print0 | sort -z)

# Whatever a test created (a new goal, a day file, another journal day).
if [ -d "$notes" ]; then
  while IFS= read -r -d '' f; do
    [ -n "${keep["$f"]:-}" ] || rm -f -- "$f"
  done < <(find "$notes" -type f -print0)
fi
