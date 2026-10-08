# Ompom Engine

The pomodoro timer engine behind Ompom — an Omarchy shell plugin that runs the focus/break state machine and renders the fullscreen block overlay. Pair it with **[ompom.bar](../ompom.bar)** for the bar icon; this plugin alone has no visible controls.

## What it does

- Starts automatically with the Omarchy shell (every login), always in **Normal** mode by default.
- **Normal**: 25 min focus / 5 min break. **Long Focus**: 50 min focus / 10 min break. **Off**: disabled.
- When focus ends, a fullscreen popup blocks input and offers **+1 minute** (up to 3 times) or **Start break** — the extension minutes are blocked too, same as the break itself.
- **Take notes** is available any time the popup is up. It opens a blank box (Save/Discard); Save appends a timestamped entry to `~/Notes/Ompom/today/ompom.md`. The first save of a new day archives the previous day's file into `~/Notes/Ompom/grave/YYYY-MM-DD.md` first.
- No settings screen — mode and pause are controlled entirely from the bar icon (see [ompom.bar](../ompom.bar)).

## Install

The engine and the bar live in the [omvision](https://github.com/OuttaSpaceTime/omvision)
repo, under `plugins/`. `omarchy plugin add` can't install them from there (it wants
`manifest.json` at a repo's root); `bin/ompom-deploy` copies both into place:

```bash
git clone https://github.com/OuttaSpaceTime/omvision.git ~/Code/omvision
~/Code/omvision/bin/ompom-deploy
omarchy plugin enable ompom.engine
omarchy plugin enable ompom.bar
```

Run `bin/ompom-deploy` again for later changes: it keeps a running pomodoro.

## IPC

Exposes an `ompom` IPC target for the bar widget (and anything else) to use:

```bash
omarchy-shell ompom status        # JSON: mode, phase, remaining, paused, extensionsUsed
omarchy-shell ompom togglePause    # pause/resume the current focus run
omarchy-shell ompom cycleMode      # Normal -> Long Focus -> Off -> Normal
```

## License

MIT — see [LICENSE](../../LICENSE).
