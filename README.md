# Omvision

A goals, tasks and journal viewer/editor for the [ompom-engine](https://github.com/OuttaSpaceTime)
plain-text file contract, written as a standalone [Quickshell](https://quickshell.org/) QML
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
  taken when the screen opened. `omvision.qml` makes these writes; `Writer.js`
  computes the new text.
- `journal/*.md` is Omvision's alone — `JournalStore.qml`, through a
  `SerialFileWriter` of its own, debounced while you type. Each write carries the
  path it was queued with, so switching days mid-write can never file one day's
  text under another's path, and a day is never written before its text on disk is
  known.
- `.log.md` and `days/*.md` are **append-only** — `Appender.qml`: `tee -a` with the
  entry on stdin, so it is `O_APPEND` at the kernel level with no read step at all. A
  coaching session rewriting `<slug>.md` concurrently can never cost an event its
  entry.

## Theming

`Theme.qml` is the app's own token singleton — it deliberately does not import `qs.Commons`,
which is the shell's module and unavailable to a standalone config. Colours are read from the
live omarchy theme at `~/.local/state/omarchy/current/theme/colors.toml`, with a Flexoki Light
fallback if that file is missing or unparseable. It never crashes on a missing theme.

## Files

Everything is QML or plain JS in the top directory, which Quickshell loads as one config.

- `omvision.qml` — the window, navigation and the app's data: it lists and loads
  every goal, log, day and journal file, hands the screens parsed results, and makes
  every write except the journal's.
- `Theme.qml` (tokens) and `Paths.qml` (where the files live) — singletons. There is
  no `qmldir`: Quickshell synthesizes one for `pragma Singleton` files, and a
  hand-written one would switch that off.
- `Parser.js` reads the files, `Writer.js` computes edits to a goal file, both pure.
  `Util.js` holds small copy helpers for the app's state; `GoalMatch.js` the journal's
  fuzzy `@goal` matching.
- `SerialFileWriter.qml` (whole-file writes, one at a time) and `Appender.qml`
  (`tee -a`) — the two write paths, see **Writing**.
- Screens: `TodayScreen`, `GoalsScreen`, `GoalDetailScreen`, `CoachingScreen` and
  `JournalScreen`, with `Sidebar` (the icon rail). The goal detail's larger parts live
  in files of their own beside it. The journal's are `JournalStore` (its write path),
  `DayList` (the list of days), `MentionPopup` (the `@` goal list), `CornerButton`
  (its two corner controls) and `JournalHighlight` (the styling, loaded through a
  `Loader`).
- `Button.qml`, `PencilIcon.qml`, and the dialogs `NewGoalDialog.qml` (also Edit
  goal), `EventDialog.qml` and `CancelDialog.qml`.
- `ShotDriver.qml` — loaded only by `bin/shot`, never in a normal launch.
- `highlighter/` — the C++ source of the markdown highlighter; `highlighter/build.sh`
  builds it into `MarkdownHighlight/` (not tracked).
- `bin/omvision` launches the app, `bin/shot` takes offscreen screenshots, `bin/test`
  runs the tests and `bin/check` runs everything a change should pass: qmllint, the
  no-pixel-numbers rule, an offscreen load and `bin/test`.
- `tests/unit` (Writer and Parser, under qmltestrunner), `tests/app` (the whole app,
  driven from inside `qs`) and `tests/fixtures/home` (the HOME the app tests run in).
- `.qmllint.ini` and `.qmllint-baseline` — qmllint's settings, and the warnings that
  predate `bin/check`.

## Docs

- [`docs/ui-spec.md`](docs/ui-spec.md) — tokens, window, per-screen layout
- [`docs/layout-rules.md`](docs/layout-rules.md) — QML layout rules, each one learned by
  shipping the bug first, and how to screenshot the app offscreen with `bin/shot`
- [`docs/testing.md`](docs/testing.md) — `bin/test`, `bin/check`, and how to write a test

## Requirements

Quickshell, Qt 6, and a monospace Nerd Font (JetBrainsMono by default). Building the
highlighter needs `g++`, `pkg-config` and Qt's `moc` (`qt6-base`). `bin/test` and
`bin/check` need Python 3 and `qmltestrunner`/`qmllint` from `qt6-declarative`, at
`/usr/lib/qt6/bin`.
