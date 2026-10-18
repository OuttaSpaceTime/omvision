# CLAUDE.md

Ompom's pomodoro engine: a `keepLoaded` omarchy-shell service with a fullscreen
overlay. `Service.qml` is only the entry point. Every rule of the cycle is in
`Cycle.js`, plain functions over a plain state with no I/O; `Engine.qml` holds that
state as properties, runs each event through it with the clock, and carries out the
effects it returns (helper writes, the goal list, the active-goal file). The screens are
`Overlay.qml` (with `NoteSection.qml` and `OverlayButton.qml`), which only read the
engine and call its functions. `ListContinue.js` is Return in a list, shared with the
journal. The bar icon lives in `plugins/ompom.bar`, and only shows what the engine's
`status` says. Paths are from the omvision repo root.

- A rule goes in `Cycle.js`, never in `Engine.qml` or the overlay, with a case in
  `tests/unit/tst_cycle.qml`.

## Deploying: never reset the running timer

- The user's real pomodoro runs in the deployed copy under
  `~/.config/omarchy/plugins/ompom.engine`. Deploy only with `bin/omvision-deploy`
  (the `omvision-deploy` skill). Never copy files into the plugin folder by hand, and
  never run `omarchy-restart-shell` on its own: either one loses the running cycle.
- How it works: bar-only changes hot-reload, and `keepLoaded` keeps the engine
  untouched through that. A changed engine file only loads on a shell restart, so
  the script saves the engine's `snapshot` IPC, restarts the shell, and `restore`s
  it into the new engine.
- A new piece of cycle state is a key in `Cycle.fresh()` and a property of the same name
  in `Engine.qml`. If it must outlive a restart it is also a row in `Cycle.FIELDS`, with
  its check. Otherwise the next deploy drops it.
  Mark the row `optional: true` for the deploy that adds it (the engine handing off
  doesn't send it yet), and drop the flag in the commit after.
- Replace live files atomically (temp file, then rename), never with `cp` in
  place: see `docs/ompom-highlighter.md`, "The crash".

## Testing

- `bin/test unit` runs `tests/unit/tst_cycle.qml`: the cycle's rules on a clock that only
  moves when the test moves it, in a few milliseconds.
- `bin/test engine` runs the real `Engine.qml` and `Overlay.qml` offscreen (in a
  `FloatingWindow`, where `Service.qml` uses a layer-shell `PanelWindow` that offscreen
  `qs` can't show) and clicks and types through them in `tests/engine/tst_*.qml`,
  checking the log entries the real helper writes into a throwaway HOME. A change to the
  overlay, or to what reaches the helper, gets a test there; controls are found by the
  objectNames `docs/testing.md` lists. Its failures keep screenshots.
- Try the overlay live with `bin/ompom-demo` (the `ompom-demo` skill). It runs on its
  own IPC target, `ompom-demo`, and never writes notes.
