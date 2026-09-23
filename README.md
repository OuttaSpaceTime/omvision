# Omvision

A goals, tasks and journal viewer/editor for the [ompom-engine](https://github.com/OuttaSpaceTime)
plain-text file contract, written as a standalone [Quickshell](https://quickshell.org/) QML
config. No build step — it reads and writes markdown files on disk directly.

```
qs -p ~/Code/omvision/omvision.qml
```

## What it does

Renders and edits a tree of markdown files under `~/Notes/Omvision`:

- `goals/<slug>.md` — a goal's status, estimate and task list
- `goals/<slug>.log.md` — that goal's append-only event log
- `days/YYYY-MM-DD.md` — the day's pomodoro and event entries
- per-goal journal entries

Screens: **Today** (the day's entries), **Goals** (list and filters), **Goal detail**
(tasks, figures, timeline), **Coaching** (hand-off to a coaching session) and **Journal**
(markdown rendered in place).

## Writing

Writes follow the file contract's two disciplines:

- `<slug>.md` is **read-modify-write** — `FileView.setText()` with `atomicWrites`
  (temp file + rename), always re-reading immediately before the mutation is applied,
  never from a copy taken when the screen opened.
- `.log.md` and `days/*.md` are **append-only** — `tee -a` with the entry on stdin, so
  it is `O_APPEND` at the kernel level with no read step at all. A coaching session
  rewriting `<slug>.md` concurrently can never cost an event its entry.

## Theming

`Theme.qml` is the app's own token singleton — it deliberately does not import `qs.Commons`,
which is the shell's module and unavailable to a standalone config. Colours are read from the
live omarchy theme at `~/.local/state/omarchy/current/theme/colors.toml`, with a Flexoki Light
fallback if that file is missing or unparseable. It never crashes on a missing theme.

## Docs

- [`docs/ui-spec.md`](docs/ui-spec.md) — tokens, window, per-screen layout
- [`docs/layout-rules.md`](docs/layout-rules.md) — QML layout rules, each one learned by
  shipping the bug first
- [`TODO.md`](TODO.md) — where development stopped and what is unverified

## Requirements

Quickshell, Qt 6, and a monospace Nerd Font (JetBrainsMono by default).
