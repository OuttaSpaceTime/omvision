# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Omvision is a standalone Quickshell (QML) app: goals, tasks, a daily journal and coaching,
reading and writing files under `~/Notes/Omvision/`.

## Running and verifying

- **Never open the app on the user's desktop to test a change.** Earlier sessions left
  windows piling up there, and `hyprctl` commands landed on the user's terminal.
- Screenshots come from `bin/shot`, which runs the real app offscreen, so no window
  appears. Examples: `bin/shot -s journal -w 720`, `bin/shot -s journal -a sidebar -f 0,40,200`.
  Read every PNG it prints. After a visual change, capture wide and narrow. See
  `docs/layout-rules.md`, "Screenshotting".
- Load check without a screenshot: `bin/check load` (the app offscreen against a fixture
  HOME, failing on any QML warning).
- Lint: `bin/check lint`, not a bare `/usr/lib/qt6/bin/qmllint <file>`. Run on the repo,
  qmllint can't see the `Theme`/`Paths` singletons (Quickshell synthesizes their qmldir),
  so every `Theme.*` reads as `[missing-property]`; `bin/check` lints a copy that fixes
  that, and fails only on warnings not in `.qmllint-baseline`.
- `bin/check` runs everything a change should pass: lint, the no-pixel-numbers rule, the
  no-scrim rule, the load check and `bin/test`. Run it before you stop. See `docs/testing.md`.
- Tests: `bin/test` runs every layer offscreen in about a minute. Run it before and after
  a change. `tests/unit` (qmltestrunner) covers Writer.js, Parser.js and the engine's
  Cycle.js, and `tests/contract` holds goal-files.md as cases the app and
  notes-helper.py both run. `tests/app` runs the real app inside `qs` with a throwaway
  HOME, clicks and types through `OmvisionTest.qml`'s helpers, and checks the bytes on
  disk. `tests/engine` does the same for the ompom engine and its overlay; both share
  `tests/lib/QsTestCase.qml`. `bin/test app tasks` runs one file. See `docs/testing.md`.
- A change to the write path, or to what a click or key does, comes with a test: a
  whole-file Writer/Parser case in `tests/unit`, a contract case for the file grammar, a
  rule's case in `tests/unit/tst_cycle.qml`, or a flow in `tests/app` or `tests/engine`.
  Pin a bug you
  aren't fixing with `expectFailContinue("", "BUG: …")`. Keep the objectNames listed in
  `docs/testing.md` through refactors.
- Launch with `bin/omvision`, not `qs -p omvision.qml`. The journal's markdown styling is a
  compiled module (`highlighter/`). Quickshell ignores directory-relative module imports, so
  the launcher puts the repo on `QML2_IMPORT_PATH`. After changing the C++, run
  `highlighter/build.sh` and restart: Quickshell hot-reloads QML, not plugins.

## Rules

- Before UI work, read `docs/layout-rules.md` (every rule there came from a shipped bug) and
  `docs/ui-spec.md`. Keep `ui-spec.md` in step with behaviour you change. Parts of it are
  stale already, so check claims there against the code.
- Colours, type sizes and spacing come from `Theme.qml` tokens. Spacing uses only the scale's
  steps: never type a pixel number (`bin/check px` enforces it; a number that must stay
  takes `// check: allow-px <reason>` on its line). Don't import `qs.Commons`.
- No dialog dims the window behind it: no scrim, no translucent layer (`docs/layout-rules.md`
  rule 10; `bin/check noscrim` enforces it).
- `~/Notes/Omvision/` holds the user's real notes. Don't write to it to test anything. The
  file contract is `docs/goal-files.md`:
  - `<slug>.log.md` and `days/*.md` are append-only (`tee -a`).
  - Goal files are re-read right before each change and written one at a time through a
    queue.
  - The journal is written by this app, and at night by the ompom overlay's journal page
    (`notes-helper.py write-journal`, which won't write over a save it didn't read).
- `plugins/ompom.engine` and `plugins/ompom.bar` are the omarchy-shell plugins that run the
  user's live pomodoro. Deploy them only with `bin/omvision-deploy` (the `omvision-deploy` skill):
  it keeps the running timer. See `plugins/ompom.engine/CLAUDE.md`. They live here rather
  than in repos of their own, so they can't be installed with `omarchy plugin add` (it wants
  `manifest.json` at a repo's root). `bin/check` validates their manifests instead of linting them.
- A change to either plugin isn't done until it's deployed: once `bin/check` passes, run
  `bin/omvision-deploy` without waiting to be asked, and confirm with `--dry-run` that
  nothing differs. A fix once sat undeployed, and the user tested the old engine all
  night thinking it was the new one. One exception: between 22:15 and 05:30 a deploy lands
  straight on the bedtime or night screen, so ask first then.
- Quickshell's `FileView` fails silently in four ways in this build:
  1. `setText()` called synchronously inside `onLoaded` writes the file but drops
     `onSaved`/`onSaveFailed`, stalling any queue waiting on it. Defer it with a
     zero-interval `Timer`.
  2. `setText("")` on a path never loaded is a no-op. Create empty files with `touch`.
  3. `writeAdapter()` only works with a `JsonAdapter`; on a plain-text `FileView` it warns
     and does nothing.
  4. `reload()` called synchronously inside the same `FileView`'s `onSaved`/`onLoaded`
     stalls the same way as 1. Same fix.
- Comments explain *why*, in prose, including alternatives that were rejected. Match that
  style, and update a comment when the behaviour it describes changes.
