# Ompom.Highlight (native)

> **Status: built, verified working in isolation, but NOT wired into
> Service.qml — it crashed the entire Quickshell compositor process
> once during a plugin hot-reload. Do not wire this in without first
> fixing the lifecycle bug described below.** See "The crash" section.

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
(`~/.config/omarchy/plugins/ompom.engine/native/Ompom/`) — an
`import Ompom.Highlight 1.0` line resolves against whatever
`QML2_IMPORT_PATH` points at, not against its own plugin directory.

## Required: QML2_IMPORT_PATH

`omarchy-shell` (Quickshell) needs `QML2_IMPORT_PATH` to include this
plugin's `native/` directory *before* it loads `ompom.engine`, or
`import Ompom.Highlight 1.0` fails.

For the current session:

```bash
systemctl --user set-environment QML2_IMPORT_PATH="$HOME/.config/omarchy/plugins/ompom.engine/native"
```

Verified this does **not** actually reach `omarchy-shell`: the process is
launched via Hyprland's internal `hl.dsp.exec_cmd` dispatch
(`omarchy-restart-shell`'s mechanism), which inherits Hyprland's own
captured environment, not the systemd user manager's dynamic one — so
`systemctl --user set-environment` has no effect on it. What did work:
adding `export QML2_IMPORT_PATH=...` to `~/.config/uwsm/env-hyprland`
(this machine uses UWSM), which takes effect on the next full
logout/login, since that's when UWSM sources it into the session Hyprland
itself inherits.

## The crash

Once wired in (see git history around commit `c038c08` and the revert
after it), a save-triggered hot-reload of `ompom.engine` crashed the
entire `quickshell` process with SIGSEGV — not a QML error, an actual
native crash taking down the whole compositor shell (bar, lock screen,
idle management, everything) with it. Confirmed via
`coredumpctl gdb <pid>`; the backtrace was a cascade of
`QObjectPrivate::deleteChildren()` / `QObject::~QObject()` frames through
a `QTextDocument::~QTextDocument()` destruction.

Suspected cause: `NoteHighlighter::setDocument()`
(`native/notehighlighter.cpp`) does `delete m_highlighter` manually, but
`MarkdownHighlighter`'s base class `QSyntaxHighlighter(QTextDocument*)`
already parents itself to that document, so Qt's own parent-child
teardown *also* deletes it when the document goes away. During a normal
run this never overlaps. During a hot-reload, the whole old component
tree (old `TextEdit`, old `QQuickTextDocument`, and everything parented
under it) gets torn down by the QML engine at some point that isn't
obviously synchronized with `NoteHighlighter`'s own QML-object
destruction — plausibly a double-delete or use-after-free of the same
`MarkdownHighlighter` instance from two teardown paths at once. Not
confirmed with certainty; would need a debug build of Quickshell/Qt or
targeted logging in `NoteHighlighter`'s destructor (currently doesn't
have one — that's arguably the first thing to add: an explicit
`~NoteHighlighter()` that clears `m_highlighter` to `nullptr` *without*
deleting it, so Qt's parent-child mechanism is the *only* thing that
ever frees it, rather than two mechanisms potentially racing).

Separately from this: a `Loader { source: "NoteHighlighterHost.qml" }`
indirection (rather than importing `Ompom.Highlight` directly in
Service.qml) was built and confirmed to correctly turn a *missing*
native plugin into a graceful `Loader.status === Loader.Error` instead
of a whole-file load failure. That part of the design is sound and
worth keeping whenever this gets re-attempted — it just doesn't help
with a crash that happens *after* successful loading, during teardown.

## Compiled artifact, not portable

`libompomhighlight.so` is compiled against this machine's exact Qt 6.11.2
ABI/architecture. It is not distributable via `omarchy plugin add` the
way the rest of this plugin is — it would need rebuilding on any other
machine.
