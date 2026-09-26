# CLAUDE.md

Ompom's pomodoro engine: a `keepLoaded` omarchy-shell service (`Service.qml`) with a
fullscreen overlay. The bar icon lives in `~/Code/ompom-bar`.

## Deploying: never reset the running timer

- The user's real pomodoro runs in the deployed copy under
  `~/.config/omarchy/plugins/ompom.engine`. Deploy only with `bin/ompom-deploy`
  (the `ompom-deploy` skill). Never copy files into the plugin folder by hand, and
  never run `omarchy-restart-shell` on its own: either one loses the running cycle.
- How it works: bar-only changes hot-reload, and `keepLoaded` keeps the engine
  untouched through that. A new `Service.qml` only loads on a shell restart, so
  the script saves the engine's `snapshot` IPC, restarts the shell, and `restore`s
  it into the new engine.
- A new piece of cycle state (a property that must outlive a restart) goes into
  both `snapshotJson()` and `restore()`. Otherwise the next deploy drops it.
- Replace live files atomically (temp file, then rename), never with `cp` in
  place: see `native/README.md`, "The crash".

## Testing

- Try the overlay with `bin/ompom-demo` (the `ompom-demo` skill). It runs on its
  own IPC target, `ompom-demo`, and never writes notes.
- `qs` offscreen has no `PanelWindow` backend. To test the logic offscreen, run a
  scratch copy with `PanelWindow` swapped for `FloatingWindow` (drop the
  `WlrLayershell.*`, `anchors` and `exclusionMode` lines), load it with
  `demo: true`, and drive it with `qs -p <dir> ipc call ompom-demo <method>`.
