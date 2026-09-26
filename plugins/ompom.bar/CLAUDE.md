# CLAUDE.md

The bar icon for Ompom. It holds no state of its own: it polls the engine
(`~/Code/ompom-engine`) over IPC once a second.

## Deploying

Deploy only with `~/Code/ompom-engine/bin/ompom-deploy` (the `ompom-deploy`
skill), never by copying into `~/.config/omarchy/plugins/ompom.bar` by hand.
A bar-only change just hot-reloads, and the running pomodoro is untouched. See
`~/Code/ompom-engine/CLAUDE.md`, "Deploying".
