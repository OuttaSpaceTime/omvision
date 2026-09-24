# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Omvision is a standalone Quickshell (QML) app: goals, tasks, a daily journal and coaching,
reading and writing files under `~/Notes/Omvision/`. `TODO.md` is the hand-off log: read it
first, and when you stop, record what landed and what is still open.

## Running and verifying

- **Never open the app on the user's desktop to test a change.** Earlier sessions left
  windows piling up there, and `hyprctl` commands landed on the user's terminal.
- Screenshots come from `bin/shot`, which runs the real app offscreen, so no window
  appears. Examples: `bin/shot -s journal -w 720`, `bin/shot -s journal -a sidebar -f 0,40,200`.
  Read every PNG it prints. After a visual change, capture wide and narrow. See
  `docs/layout-rules.md`, "Screenshotting".
- Load check without a screenshot: `QT_QPA_PLATFORM=offscreen timeout 10 bin/omvision`.
- Lint: `/usr/lib/qt6/bin/qmllint <file>` (it is not on PATH). Its `[missing-property]`
  warnings on `Theme.*`, and its `[unqualified]` and `[import]` warnings, are noise: qmllint
  can't resolve Quickshell or the `Theme` singleton.
- There is no test suite. Qt's `qml` and `qmltestrunner` can't load Quickshell's modules,
  which are compiled into the `qs` binary. Clicks can't be simulated on this machine, so
  verify by calling the functions a click would call.
- Launch with `bin/omvision`, not `qs -p omvision.qml`. The journal's markdown styling is a
  compiled module (`highlighter/`). Quickshell ignores directory-relative module imports, so
  the launcher puts the repo on `QML2_IMPORT_PATH`. After changing the C++, run
  `highlighter/build.sh` and restart: Quickshell hot-reloads QML, not plugins.

## Rules

- Before UI work, read `docs/layout-rules.md` (every rule there came from a shipped bug) and
  `docs/ui-spec.md`. Keep `ui-spec.md` in step with behaviour you change. Parts of it are
  stale already, so check claims there against the code.
- Colours, type sizes and spacing come from `Theme.qml` tokens. Spacing uses only the scale's
  steps: never type a pixel number. Don't import `qs.Commons`.
- `~/Notes/Omvision/` holds the user's real notes. Don't write to it to test anything. The
  file contract is `~/Code/ompom-engine/docs/goal-files.md`:
  - `<slug>.log.md` and `days/*.md` are append-only (`tee -a`).
  - Goal files are re-read right before each change and written one at a time through a
    queue.
  - The journal is written only by this app.
- Quickshell's `FileView` fails silently in four ways: see TODO.md, "Four silent-failure bugs
  in this Quickshell build".
- Comments explain *why*, in prose, including alternatives that were rejected. Match that
  style, and update a comment when the behaviour it describes changes.
