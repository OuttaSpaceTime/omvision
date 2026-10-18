# CLAUDE.md

Ompom's pomodoro engine: a `keepLoaded` omarchy-shell service with a fullscreen
overlay. `Service.qml` is only the entry point: the cycle is `Engine.qml`, the screens
are `Overlay.qml` (with `NoteSection.qml` and `OverlayButton.qml`), and the overlay only
reads the engine and calls its functions. The bar icon lives in `plugins/ompom.bar`.
Paths are from the omvision repo root.

## Deploying: never reset the running timer

- The user's real pomodoro runs in the deployed copy under
  `~/.config/omarchy/plugins/ompom.engine`. Deploy only with `bin/omvision-deploy`
  (the `omvision-deploy` skill). Never copy files into the plugin folder by hand, and
  never run `omarchy-restart-shell` on its own: either one loses the running cycle.
- How it works: bar-only changes hot-reload, and `keepLoaded` keeps the engine
  untouched through that. A changed engine file only loads on a shell restart, so
  the script saves the engine's `snapshot` IPC, restarts the shell, and `restore`s
  it into the new engine.
- A new piece of cycle state (a property that must outlive a restart) is a row in
  `cycleFields` in `Engine.qml`, with its check. Otherwise the next deploy drops it.
  Mark the row `optional: true` for the deploy that adds it (the engine handing off
  doesn't send it yet), and drop the flag in the commit after.
- Replace live files atomically (temp file, then rename), never with `cp` in
  place: see `docs/ompom-highlighter.md`, "The crash".

## Testing

- `bin/test engine` runs the real `Engine.qml` and `Overlay.qml` offscreen (in a
  `FloatingWindow`, where `Service.qml` uses a layer-shell `PanelWindow` that offscreen
  `qs` can't show) and clicks and types through a whole cycle in `tests/engine/tst_break.qml`, checking the log entries the
  real helper writes into a throwaway HOME. A change to the cycle or the overlay gets a
  step there. Its failures keep screenshots; see `docs/testing.md`.
- Try the overlay live with `bin/ompom-demo` (the `ompom-demo` skill). It runs on its
  own IPC target, `ompom-demo`, and never writes notes.
