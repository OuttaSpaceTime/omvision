# Ompom Engine

The pomodoro timer engine behind Ompom — an Omarchy shell plugin that runs the focus/break state machine and renders the fullscreen block overlay. Pair it with **[ompom.bar](../ompom.bar)** for the bar icon; this plugin alone has no visible controls.

## What it does

- Starts automatically with the Omarchy shell (every login), always in **Normal** mode by default.
- **Normal**: 25 min focus / 5 min break, and every fourth break is a long one of 15 min (the count starts over each day and on a mode switch). **Long Focus**: 50 min focus / 10 min break. **Off**: disabled.
- When focus ends, a fullscreen popup blocks input and offers **+1 minute** (up to 3 times) or **Start break** — the extension minutes are blocked too, same as the break itself.
- The break shows its countdown with **+1 / +2 / +3 min** to lengthen it, **Take notes**, and **Ctrl+G** to pick the next run's goal (done, cancelled and `focusable: no` goals aren't offered).
- In a break, **Take notes** opens one page with three sections, *Done*, *Next* and *Notes*, each headed like a markdown heading; click a heading to fold it. The arrows move through the page as through one markdown file, stopping on the headings, where Return folds and unfolds. Esc or ← goes back to the countdown, and the notes stay as written until the break ends.
- When the break ends, the run is logged with its notes — to the goal's `<slug>.log.md`, or `~/Notes/Omvision/days/<date>.md` without a goal — and the next focus run starts straight away. If the write is refused, the break holds at 0:00 with **Try again** and **Skip**.
- **Bedtime**: at 22:15 whatever is running stops (a finished run is logged, a focus run cut off part-way isn't) and **Time to sleep** comes up, with **+1 minute** (up to 3 times) and **Good night**. From 22:20 until 05:30 the laptop shows only the night's screen: a countdown to 05:30, in hours, minutes and seconds, and **Take notes**. Logging in during that time lands straight on it. At 05:30 a fresh run starts. This holds in every mode, Off too, and with the timer paused.
- At night **Take notes** opens the day's journal, `~/Notes/Omvision/journal/<date>.md`, the same file Omvision's Journal screen shows, set the same way but without the app around it: free writing, no questions. It opens on the day's text with the caret at the end and saves as you type. If Omvision saved the day meanwhile, nothing it wrote is lost: what you typed goes after it.
- No settings screen — mode and pause are controlled entirely from the bar icon (see [ompom.bar](../ompom.bar)).

## Install

The engine and the bar live in the [omvision](https://github.com/OuttaSpaceTime/omvision)
repo, under `plugins/`. `omarchy plugin add` can't install them from there (it wants
`manifest.json` at a repo's root); `bin/omvision-deploy` copies both into place:

```bash
git clone https://github.com/OuttaSpaceTime/omvision.git ~/Code/omvision
~/Code/omvision/bin/omvision-deploy
omarchy plugin enable ompom.engine
omarchy plugin enable ompom.bar
```

Run `bin/omvision-deploy` again for later changes: it keeps a running pomodoro.

## IPC

Exposes an `ompom` IPC target for the bar widget (and anything else) to use:

```bash
omarchy-shell ompom status        # JSON: mode, phase, remaining, remainingLabel, label (the bar's), paused, ...
omarchy-shell ompom togglePause    # pause/resume the current focus run
omarchy-shell ompom cycleMode      # Normal -> Long Focus -> Off -> Normal
omarchy-shell ompom skipSleep      # ends tonight's bedtime screen, for when the laptop is really needed
```

`skipSleep` is the only way out of the night, and nothing on the overlay offers it.
It works at any hour of the night's span, before bedtime included: run at 21:57, it keeps
the 22:15 prompt and the 22:20 night screen away, and the run in progress carries on. It lasts
the rest of this night only (until 05:30); the next night's 22:15 is as usual. It is kept in
the engine's state, so a deploy carries it over, but a plain shell restart starts a fresh
engine and the night comes back: run it again.
With the overlay up, run it from a TTY (Ctrl+Alt+F3, log in).

## License

MIT — see [LICENSE](../../LICENSE).
