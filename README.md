# Omvision

A goals, tasks and journal viewer/editor for the ompom plain-text file contract
([`docs/goal-files.md`](docs/goal-files.md)), written as a standalone [Quickshell](https://quickshell.org/) QML
config. It reads and writes markdown files on disk directly. The only compiled part is
the journal's markdown highlighter, which is one shell script and no build system.

```
~/Code/omvision/bin/omvision
```

The launcher builds the markdown highlighter if it is missing and puts it on the
QML import path. `qs -p ~/Code/omvision/omvision.qml` still works; the journal is
then plain monospace markdown instead of styled (see **Journal** below).

## What it does

Renders and edits a tree of markdown files under `~/Notes/Omvision`:

- `goals/<slug>.md` — a goal's status, estimate and task list
- `goals/<slug>.log.md` — that goal's append-only event log
- `days/YYYY-MM-DD.md` — the day's pomodoro and event entries
- `journal/YYYY-MM-DD.md` — one free-form entry per day, attached to no goal

Screens: **Today** (the day's entries), **Goals** (list and filters), **Goal detail**
(tasks, figures, timeline), **Coaching** (hand-off to a coaching session) and **Journal**
(a writing surface, below).

## Journal

A journal entry is a day, not a goal — `journal/YYYY-MM-DD.md`, free-form, about
whatever is on your mind. The screen opens straight into today's entry with the
cursor in it: no read mode, no edit mode, no title bar, no buttons. The app's icon rail is
hidden while you write and comes back from one faint control; the list of days opens as an
overlay, so glancing at it never reflows what you are writing.

Markdown is styled live the way omawrite does it. omawrite's binary tells the whole story: `MarkdownHighlighter`,
`QSyntaxHighlighter::setFormat`, `QFont::setPointSizeF`,
`QQuickTextDocument::textDocument` — and no `QTextDocument::toMarkdown`. The
document holds plain markdown and a C++ highlighter formats it in place:
`#`, `-` and `>` stay visible but dimmed, and `**`, `*`, `_` and a link's
brackets shrink to 1pt rather than being deleted, so the text reads as styled
while the file stays byte-for-byte what was typed.

That needs C++: `QQuickTextDocument::textDocument()` is not reachable from QML.
So `highlighter/` builds a small QML module (`MarkdownHighlight`) with moc and
g++ — no cmake, no ninja, no sudo — and `bin/omvision` puts it on the import
path, because Quickshell blackholes directory-relative module imports onto its
own `qs:` scheme. `JournalScreen` loads the styling through a `Loader`, so a
module that is missing or unbuilt costs the journal its styling and nothing else.

The alternative, QML's own `TextEdit.MarkdownText`, was measured and rejected: it
regenerates the markdown from the document on every read, which hard-wraps
paragraphs at ~78 columns, rewrites `---` as `- - -` and drops two-space hard
breaks. It is idempotent, but it is not your file.

## Writing

Writes follow the file contract's two disciplines:

- `<slug>.md` is **read-modify-write** — through `SerialFileWriter.qml`, a queue over
  one `FileView` with `atomicWrites` (temp file + rename): one job at a time, each
  re-reading the file immediately before its change is applied, never from a copy
  taken when the screen opened. `NotesStore.qml` makes these writes; `Writer.js`
  computes the new text.
- `journal/*.md` is written by `JournalStore.qml`, through a `SerialFileWriter` of
  its own, debounced while you type. Each write carries the path it was queued
  with, so switching days mid-write can never file one day's text under another's
  path, and a day is never written before its text on disk is known. The one other
  writer is the ompom overlay's night page, which only replaces a day whose text
  is still what it read (goal-files.md §5, `write-journal`); the Journal screen
  takes such a change in when it has no unsaved edits.
- `.log.md` and `days/*.md` are **append-only** — `Appender.qml`: `tee -a` with the
  entry on stdin, so it is `O_APPEND` at the kernel level with no read step at all
  (after a `mkdir -p` of the folder, which a first goal-less event can need). A
  coaching session rewriting `<slug>.md` concurrently can never cost an event its
  entry.

## Theming

`Theme.qml` is the app's own token singleton — it deliberately does not import `qs.Commons`,
which is the shell's module and unavailable to a standalone config. Colours are read from the
live omarchy theme at `~/.local/state/omarchy/current/theme/colors.toml`, with a Flexoki Light
fallback if that file is missing or unparseable. It never crashes on a missing theme.

## Files

Everything is QML or plain JS in the top directory, which Quickshell loads as one config.

- `omvision.qml` — only the window and its layout.
- `App.qml` — the app as screens and dialogs see it: its data (`notes`), where it is
  (`nav`) and which dialog is open. Screens and dialogs declare `required property App
  app` and call it directly, so a misspelled member fails `bin/check lint`; small widgets
  get only what they show and report clicks by signal.
- `NotesStore.qml` — the app's data: it lists and reads every goal, log, day and journal
  file (each through a `WatchedFile`), keeps the day (`todayKey`, moved on at midnight),
  and makes every write except the journal's. No screen reads or writes a file itself.
- `Navigator.qml` — which screen shows, the open goal and its back link, the sidebar and
  the keys that work everywhere. Plain QML, unit-tested in `tests/unit/tst_navigator.qml`.
- `Theme.qml` (tokens) and `Paths.qml` (where the files live) — singletons. There is
  no `qmldir`: Quickshell synthesizes one for `pragma Singleton` files, and a
  hand-written one would switch that off.
- `Parser.js` reads the files, `Writer.js` computes edits to a goal file, both pure.
  `Util.js` holds small copy helpers for the app's state; `GoalMatch.js` the journal's
  fuzzy `@goal` matching.
- `SerialFileWriter.qml` (whole-file writes, one at a time) and `Appender.qml`
  (`tee -a`) — the two write paths, see **Writing**.
- Screens: `TodayScreen`, `GoalsScreen`, `GoalDetailScreen`, `CoachingScreen` and
  `JournalScreen`, with `Sidebar` (the icon rail). The goal detail's parts are
  `GoalHeader`, `GoalFigures`, `Timeline` (one entry is `TimelineEntry`), `TaskRow` and
  `GoalEndActions`. The journal's are `JournalStore` (its write path), `JournalMentions`
  (the `@` goal tags) and `MentionPopup` (their list), `DayList` (the list of days),
  `CornerButton` (its corner controls), `TrackpadGlide` (kinetic scrolling) and
  `JournalHighlight` (the styling, loaded through a `Loader`).
- The dialogs: `NewGoalDialog.qml` (also Edit goal), `EventDialog.qml` and
  `CancelDialog.qml`, each in a `DialogFrame` (the modal, its card, error line and
  footer). `ErrorBanner` is the window's write-error line.
- Shared pieces, each so that one look is drawn in one place: `Button`, `PencilIcon`,
  `CaptionLabel` (a bold caption: a section's or field's name, a badge), `DialogField` (a dialog's labelled
  input), `CheckOption` and `OptionMark` (a dialog's tick box and radio ring), `TextChip`
  and `BoxChip` (a row of choices, underlined or boxed) and `EntryNotes` (what a log
  entry says, on Today and the timeline).
- `ShotDriver.qml` — loaded only by `bin/shot`, never in a normal launch.
- `highlighter/` — the C++ source of the markdown highlighter; `highlighter/build.sh`
  builds it into `MarkdownHighlight/` (not tracked).
- `plugins/ompom.engine` and `plugins/ompom.bar` — the omarchy-shell plugins that run
  the pomodoro and show it in the bar. They share this repo's file contract and
  highlighter. `bin/omvision-deploy` deploys them without resetting the running timer;
  `bin/ompom-demo` runs the overlay as a throwaway demo, and `bin/ompom-stage` lays out
  the `qs` config both it and the engine tests run in. See `plugins/ompom.engine/CLAUDE.md`.
- `bin/omvision` launches the app, `bin/shot` takes offscreen screenshots, `bin/test`
  runs the tests and `bin/check` runs everything a change should pass: qmllint, the
  no-pixel-numbers and no-scrim rules, the plugins' manifests, an offscreen load and
  `bin/test`. `bin/qmlls` starts the QML language server with the singletons visible.
- `tests/unit` (the pure JS modules, under qmltestrunner), `tests/contract` (the file
  grammar's cases, run against both the app and `notes-helper.py`), `tests/app` (the
  whole app, driven from inside `qs`), `tests/engine` (the engine and its overlay) and
  `tests/fixtures` (the HOMEs they run in). See `docs/testing.md`.
- `.qmllint.ini` and `.qmllint-baseline` — qmllint's settings, and the warnings that
  predate `bin/check`.

## Docs

- [`docs/ui-spec.md`](docs/ui-spec.md) — tokens, window, per-screen layout
- [`docs/layout-rules.md`](docs/layout-rules.md) — QML layout rules, each one learned by
  shipping the bug first, and how to screenshot the app offscreen with `bin/shot`
- [`docs/testing.md`](docs/testing.md) — `bin/test`, `bin/check`, and how to write a test
- [`docs/goal-files.md`](docs/goal-files.md) — the file contract between the engine, the
  app and the coach skill
- [`docs/ompom-highlighter.md`](docs/ompom-highlighter.md) — the engine's use of the
  highlighter, and how a compiled module is deployed into the shell

## Requirements

Quickshell, Qt 6, and a monospace Nerd Font (JetBrainsMono by default). Building the
highlighter needs `g++`, `pkg-config` and Qt's `moc` (`qt6-base`). `bin/test` and
`bin/check` need Python 3 and `qmltestrunner`/`qmllint` from `qt6-declarative`, at
`/usr/lib/qt6/bin`. `bin/check` also needs a checkout of qs-kit beside this repo
(`~/Code/qs-kit`, or `QS_KIT` pointing at one).
