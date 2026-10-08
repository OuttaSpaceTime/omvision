# The ompom overlay's markdown highlighter

The overlay's two writing surfaces (the intent line and the break notes) are
styled by `MarkdownHighlight`, the module built from this repo's `highlighter/`,
so writing there looks exactly like writing in the journal.
`plugins/ompom.engine/NoteHighlighterHost.qml` loads it.

The engine once had its own module, `Ompom.Highlight` (a `NoteHighlighter`
wrapping a `MarkdownHighlighter` copied from
[omacom-io/omawrite](https://github.com/omacom-io/omawrite)). It drew markdown
differently from the journal and was retired on 2026-09-24. Its sources were
removed when the plugin moved into this repo and are in the git history. The
deployed plugin's `native/Ompom/` still holds its build, which nothing imports.

## Deploying it

`bin/ompom-deploy` does not ship the module. Build it with
`highlighter/build.sh`, then copy `MarkdownHighlight/` into the deployed
plugin's `native/MarkdownHighlight/`, replacing every file atomically (see "The
crash" below), and restart the whole shell rather than relying on a hot reload:
the retired library also exports a class named `MarkdownHighlighter`, and a
fresh process never has both loaded. A restart loses the running pomodoro
unless you take `omarchy-shell ompom snapshot` first and `restore` it after, as
`bin/ompom-deploy` does.

## Why a compiled module needs QML2_IMPORT_PATH

Quickshell's third-party plugin model is "drop a folder of `.qml` files,
they're interpreted directly, no build step" — that's how `omarchy plugin
add` works (a plain `git clone`). `MarkdownHighlight` breaks that model:
it's a compiled Qt/C++ QML extension module, built by
`highlighter/build.sh`, and only works because Quickshell's underlying `QQmlApplicationEngine` honors the
standard `QML2_IMPORT_PATH` environment variable like any Qt app.

## Required: QML2_IMPORT_PATH

`omarchy-shell` (Quickshell) needs `QML2_IMPORT_PATH` to include the
deployed plugin's `native/` directory *before* it loads `ompom.engine`, or
`import MarkdownHighlight` fails.

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

While developing this, a hot-reload of `ompom.engine` crashed the entire
`quickshell` process with SIGSEGV — not a QML error, an actual native
crash taking down the whole compositor shell (bar, lock screen, idle
management, everything) with it. Confirmed via `coredumpctl gdb <pid>`;
the backtrace was a generic cascade of `QObjectPrivate::deleteChildren()`
/ `QObject::~QObject()` frames through a `QTextDocument::~QTextDocument()`
destruction — no frame named anything in this plugin's own code.

That last detail pointed away from the first theory (a double-free
between `NoteHighlighter::setDocument()`'s manual `delete m_highlighter`
and `QSyntaxHighlighter`'s own parent-child teardown — a real
double-management issue, fixed anyway as cheap defense in depth, but not
what actually crashed it) and toward the real cause: **the installed
`.so` was being deployed with a plain `cp` while the running process
already had it mapped.** `cp` opens, truncates, and writes the
destination file in place — it is not atomic. A process that dlopen'd
the old file keeps a private, file-backed mapping of it; any page not
yet faulted in at the time of the overwrite can, on a later access, read
back bytes from the *new* file content instead of the one that was
actually mapped when the library was loaded. That's silent code/vtable
corruption, exactly consistent with a crash whose backtrace looks
generic rather than pointing at any specific logic bug — and it fit the
timeline exactly: the `cp` of a rebuilt `.so` landed seconds before a
"Local plugin changed, reloading" hot-reload, which is when the process
next touched pages of that file.

Fix: **deploy the installed `.so` (and, for consistency, every file)
via atomic rename** — write to a temp file in the same directory, then
`mv` it over the real path. `rename(2)` on the same filesystem swaps the
directory entry without touching the old inode's contents, so a process
with the old file still mapped keeps a fully consistent view of it
indefinitely, while anything that opens the path afterward gets the
complete new file. Verified by redeploying the `.so` four times in a row
while `omarchy-shell` was running live (`ompom.engine`'s timer kept
ticking correctly throughout, single process, no crash) — see the git
history around the second wiring-in commit for the exact commands.

Separately: the `Loader { source: "NoteHighlighterHost.qml" }`
indirection (rather than importing the module directly in
Service.qml) is still worth keeping regardless of the above — it turns
a *missing* native plugin (e.g. `QML2_IMPORT_PATH` not set yet) into a
graceful `Loader.status === Loader.Error` instead of a whole-file load
failure. That's a different failure mode than the crash and this fix
doesn't substitute for it; both are needed.

## Compiled artifact, not portable

`libmarkdownhighlight.so` is compiled against this machine's exact Qt
ABI/architecture. It can't travel with the plugin's QML the way plain
files do — it needs rebuilding on any other machine.
