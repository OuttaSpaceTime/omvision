# Ompom Bar

The bar icon for [Ompom](https://github.com/OuttaSpaceTime/ompom-engine) — an Omarchy shell plugin that shows the pomodoro timer's state in the top bar. Requires **[ompom-engine](https://github.com/OuttaSpaceTime/ompom-engine)** to actually run the timer; this plugin only displays and controls it.

## What it does

- Shows a tomato icon + live countdown (or "paused" / nothing when off).
- **Left-click**: pause/resume the current focus run.
- **Right-click**: cycle Normal → Long Focus → Off.
- Colors follow the active Omarchy theme (drawn SVG icons tinted at runtime, not a fixed-color emoji).

## Install

```bash
omarchy plugin add https://github.com/OuttaSpaceTime/ompom-engine.git --enable --yes
omarchy plugin add https://github.com/OuttaSpaceTime/ompom-bar.git --enable --yes
```

## Icons

See [icons/ATTRIBUTION.md](icons/ATTRIBUTION.md).

## License

MIT — see [LICENSE](LICENSE).
