# Ompom Bar

The bar icon for Ompom — an Omarchy shell plugin that shows the pomodoro timer's state in the top bar. Requires **[ompom.engine](../ompom.engine)** to actually run the timer; this plugin only displays and controls it.

## What it does

- Shows the Omvision mark (a λ seal) + live countdown (or "paused" / nothing when off).
- **Left-click**: pause/resume the current focus run.
- **Right-click**: cycle Normal → Long Focus → Off.
- Colors follow the active Omarchy theme (drawn SVG icons tinted at runtime, not a fixed-color emoji).

## Install

The engine and the bar live in the [omvision](https://github.com/OuttaSpaceTime/omvision)
repo, under `plugins/`. `omarchy plugin add` can't install them from there (it wants
`manifest.json` at a repo's root), so copy them into place and enable them:

```bash
git clone https://github.com/OuttaSpaceTime/omvision.git ~/Code/omvision
cp -r ~/Code/omvision/plugins/ompom.engine ~/Code/omvision/plugins/ompom.bar ~/.config/omarchy/plugins/
omarchy plugin enable ompom.engine
omarchy plugin enable ompom.bar
```

Later changes go in with `bin/ompom-deploy`, which keeps a running pomodoro.

## Icons

See [icons/ATTRIBUTION.md](icons/ATTRIBUTION.md).

## License

MIT — see [LICENSE](LICENSE).
