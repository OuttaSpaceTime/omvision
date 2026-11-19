# Ompom Bar

The bar icon for Ompom — an Omarchy shell plugin that shows the pomodoro timer's state in the top bar. Requires **[ompom.engine](../ompom.engine)** to actually run the timer; this plugin only displays and controls it.

## What it does

- Shows the Omvision mark (a λ seal) + live countdown (or "paused" / nothing when off).
- **Left-click**: a popup with the timer's state (countdown, mode, run in the set, goal), an on/off switch, Normal 25/5 / Long 50/10, **Pause** and **Restart run**, and the last 7 days (pomodoros per day, today and week totals) read from the Omvision logs.
- **Right-click**: switch the timer on (in the last mode used) or off.
- **Middle-click**: pause/resume the current focus run.
- Colors follow the active Omarchy theme (drawn SVG icons tinted at runtime, not a fixed-color emoji).

## Install

Installed together with the engine: see [ompom.engine's README](../ompom.engine/README.md#install).

## Icons

See [icons/ATTRIBUTION.md](icons/ATTRIBUTION.md).

## License

MIT — see [LICENSE](../../LICENSE).
