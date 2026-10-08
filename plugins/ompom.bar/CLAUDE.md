# CLAUDE.md

The bar icon for Ompom. It holds no state of its own: it polls the engine
(`plugins/ompom.engine`) over IPC once a second.

## Deploying

Deploy only with omvision's `bin/omvision-deploy` (the `omvision-deploy`
skill), never by copying into `~/.config/omarchy/plugins/ompom.bar` by hand.
A bar-only change just hot-reloads, and the running pomodoro is untouched. See
`plugins/ompom.engine/CLAUDE.md`, "Deploying".
