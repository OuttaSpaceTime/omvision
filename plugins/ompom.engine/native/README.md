# Ompom.Highlight (native)

A native QML plugin providing `NoteHighlighter`, a thin wrapper around
`MarkdownHighlighter` (copied from
[omacom-io/omawrite](https://github.com/omacom-io/omawrite), MIT — see
`../THIRD_PARTY_NOTICES.md`) that attaches to a `TextEdit`'s
`textDocument` and applies real live markdown syntax highlighting as you
type — headings, bold, italic, blockquotes, list markers, inline code.

This exists because QML's own `TextEdit.MarkdownText` format only
converts markdown to rich text when its `text` property is assigned
wholesale; it does not re-parse as you type into it, so it never
actually renders live (verified by hand — see the Service.qml git
history for the failed pure-QML attempts).

## Why this is here instead of in the plugin root

Quickshell's third-party plugin model is "drop a folder of `.qml` files,
they're interpreted directly, no build step" — that's how `omarchy plugin
add` works (a plain `git clone`). This directory breaks that model: it's
a compiled Qt/C++ QML extension plugin, built with `qmake`, and only
works because Quickshell's underlying `QQmlApplicationEngine` honors the
standard `QML2_IMPORT_PATH` environment variable like any Qt app.

## Building

```bash
cd native
qmake6 ompomhighlight.pro
make
```

Produces `native/Ompom/Highlight/{libompomhighlight.so,qmldir,plugins.qmltypes}`.
Copy that `Ompom/` directory into the *installed* plugin's own directory
(`~/.config/omarchy/plugins/ompom.engine/native/Ompom/`) — Service.qml's
`import Ompom.Highlight 1.0` resolves against whatever `QML2_IMPORT_PATH`
points at, not against its own plugin directory.

## Required: QML2_IMPORT_PATH

`omarchy-shell` (Quickshell) needs `QML2_IMPORT_PATH` to include this
plugin's `native/` directory *before* it loads `ompom.engine`, or the
`import Ompom.Highlight 1.0` line in Service.qml fails outright — and
because a missing QML import is a hard, whole-file load failure, that
takes down the *entire* pomodoro engine, not just the notes highlighting.

For the current session:

```bash
systemctl --user set-environment QML2_IMPORT_PATH="$HOME/.config/omarchy/plugins/ompom.engine/native"
```

This does **not** survive logout/reboot. For that, the environment
variable needs to be added wherever this session's persistent env is
configured (this machine uses UWSM — see `~/.config/uwsm/env-hyprland`
or `~/.config/uwsm/env`) so it's present before Hyprland launches
`omarchy-launch-shell`.

## Wiring it into Service.qml

Not currently wired in (see the git history around this commit for the
attempt and why it was reverted: the import path can't yet be persisted
for this session without a disruptive full compositor/session restart,
and a missing `import` is a hard failure for the *entire* Service.qml,
not just the notes view — better to ship working plain text than a
timer that silently doesn't run). To re-enable once `QML2_IMPORT_PATH`
is actually in place before `omarchy-shell` starts:

1. Add near the top of Service.qml, after the existing imports:
   ```qml
   import Ompom.Highlight 1.0
   ```
2. Inside the notes view, as a sibling of the `noteEdit` `TextEdit`:
   ```qml
   NoteHighlighter {
     id: noteHighlighter
     document: noteEdit.textDocument
   }

   Connections {
     target: root
     function onNotesOpenChanged() {
       if (root.notesOpen) {
         noteHighlighter.setColors(Color.popups.background.toString(),
                                   Color.popups.text.toString(),
                                   Color.accent.toString())
       }
     }
   }
   ```

## Compiled artifact, not portable

`libompomhighlight.so` is compiled against this machine's exact Qt 6.11.2
ABI/architecture. It is not distributable via `omarchy plugin add` the
way the rest of this plugin is — it would need rebuilding on any other
machine.
