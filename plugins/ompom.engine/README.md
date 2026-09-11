# Ompom Engine

The pomodoro timer engine behind [Ompom](https://github.com/OuttaSpaceTime/ompom-bar) — an Omarchy shell plugin that runs the focus/break state machine and renders the fullscreen block overlay. Pair it with **[ompom-bar](https://github.com/OuttaSpaceTime/ompom-bar)** for the bar icon; this plugin alone has no visible controls.

## What it does

- Starts automatically with the Omarchy shell (every login), always in **Normal** mode by default.
- **Normal**: 25 min focus / 5 min break. **Long Focus**: 50 min focus / 10 min break. **Off**: disabled.
- When focus ends, a fullscreen popup blocks input and offers **+1 minute** (up to 3 times) or **Start break** — the extension minutes are blocked too, same as the break itself.
- **Take notes** is available any time the popup is up. It opens a blank box (Save/Discard); Save appends a timestamped entry to `~/Notes/Ompom/today/ompom.md`. The first save of a new day archives the previous day's file into `~/Notes/Ompom/grave/YYYY-MM-DD.md` first.
- No settings screen — mode and pause are controlled entirely from the bar icon (see ompom-bar).

## Install

```bash
omarchy plugin add https://github.com/OuttaSpaceTime/ompom-engine.git --enable --yes
omarchy plugin add https://github.com/OuttaSpaceTime/ompom-bar.git --enable --yes
```

## IPC

Exposes an `ompom` IPC target for the bar widget (and anything else) to use:

```bash
omarchy-shell ompom status        # JSON: mode, phase, remaining, paused, extensionsUsed
omarchy-shell ompom togglePause    # pause/resume the current focus run
omarchy-shell ompom cycleMode      # Normal -> Long Focus -> Off -> Normal
```

## License

MIT — see [LICENSE](LICENSE).
