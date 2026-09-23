# Omvision UI spec (from the approved mockups)

A Quickshell QML app: `qs -p ~/Code/omvision/omvision.qml`, one `FloatingWindow`, no build step.
Milestone 2 is **read-only** — it renders what ompom and a hand-written goal file put on disk.

## Tokens

Do not import `qs.Commons` — that is the shell's own module and is not available to a
standalone config. Omvision carries its own `Theme.qml` singleton with the same values,
read where possible from the live omarchy theme at
`~/.local/state/omarchy/current/theme/colors.toml` (keys `background`, `foreground`,
`accent`, `muted`, plus `mode = "light"|"dark"`), with the hardcoded fallback below if the
file is missing or unparseable. Never crash on a missing theme.

- Corners: **0 radius everywhere.** Hyprland's `decoration:rounding` is 0 on this machine.
- Font: `monospace` (resolves to JetBrainsMono Nerd Font). One family for the whole app.
- Type scale, exactly: caption 10, bodySmall 11, body 12, subtitle 13, title 14, heading 16,
  display 24. Section labels are caption, **bold, uppercase, letterSpacing 1.2**, dimmed.
- Surfaces: fills are the foreground colour at 4% alpha (8% hover, 18% selected); borders are
  1px at 40% alpha. No drop shadows, no gradients.
- Spacing: panel padding 18, row gap 8, control height 28.
- Fallback palette (Flexoki Light): paper `#FFFCF0`, ink `#100F0F`, secondary ink `#403E3C`,
  dim `#6F6E69`, faint `#878580`, hairline `#DAD8CC`, border `#B7B5AC`, fill `#F6F3E8`,
  accent `#205EA6`, accent fill `#E8EDF4`, red `#AF3029`.

## Window

1440×900 default, resizable, title "Omvision". Left sidebar 176px wide, 1px hairline on its
right edge. Sidebar contents, top to bottom: a 18px square outlined in accent containing the
text `λi`, then the word `omvision` at title size, bold, letterSpacing 1; then the nav rows at
body size, 6px vertical padding — **Today, Goals, Coaching, Journal**. The selected row is
accent-coloured with a 2px accent bar on its left edge; the others are dim. No "Archive" row.
Only Goals and the goal detail need to work in M2; the others may render an empty state.

## Screen: Goals

Header row: `Goals` at heading size bold, then a caption-styled summary
(`TODAY · 3 POMS · 1 H 15`) computed from today's entries across all logs, then filter chips
pushed right (`active N`, `paused N`, `done N`, `cancelled N` — the selected one underlined in
accent), then `Add event` and `New goal` buttons (28px, 1px border; inert in M2).

One row per goal, hairline-separated, each row bleeding to both panel edges (negative side
margins, padding restored inside) so the rules run full width. Selected/hovered row: 4% fill
plus a 3px accent bar that is the row's own left edge, with the text inset 30px from it —
the bar must touch the fill, never float in the padding.

Row contents, left column: the title at title size bold, an optional status chip
(caption, bold, uppercase — `running` in accent, a deadline in red), the `why` line at
bodySmall in dim, and a caption line reading `N OF M TASKS DONE · LAST SESSION <when>`.
Right column, 240px: `<poms> / ≈<estimate>` at title size beside `≈ N left · <done_by>` in
dim, and under them a 2px progress rule — accent for the selected goal, border colour
otherwise.

## Screen: Goal detail

Header: `← Goals` (caption, dim, navigates back), the title at heading bold, a `running`
chip, then `Add event` and `Coach this goal` buttons pushed right (the second one accent-
filled; both inert in M2). Below, a single row of figures separated by 28px:
`<N> poms · <H> h in`, `≈ <N> left`, `<done> of <total> tasks`, `done by <date>`, then a 2px
progress rule taking the remaining width.

Body splits into the timeline (flexible) and a 312px right rail with a 1px hairline between.

**Timeline** — caption heading `WHAT HAPPENED`, then entries newest first, grouped under day
headers (`SUN 20 SEP` caption + a dim `3 poms · 1 h 15` summary). Each entry is a row of:
a 40px right-aligned time in faint, a 7px square node centred in a 1px vertical rule that runs
through the whole column, then the content. Node styles: 1px bordered square for a pomodoro,
filled accent for a coaching session, 1px **dashed** for an event. Content is a caption type
label (`25 MIN`, `COACHING`, `EVENT · TRAINING · 1 H 30`), the `focus:` line at body size, and
the `done:`/`left:` lines beneath at bodySmall in dim.

**Right rail** — caption heading `TASKS` with `N of M done` beside it and an inert `+ task`
button; then one row per task, hairline-separated, each a checkbox (checked and struck through
when done) with the task text and an optional `≈N` estimate at the right. Under the list, this
line at caption size in faint: "Tasks belong to the goal, not to a pomodoro. A finished pom
never ticks one off — you do, or the coach does." Then a caption heading `NEXT SESSION` over a
bordered box holding `claude /ompom-coach <slug>` with a small `copy` button, and under it, in
faint: "Runs in your own terminal. It reads all of this and rewrites what's next."

## Data

Read the files directly, in QML, without shelling out to ompom's helper:

- `~/Notes/Omvision/goals/*.md` — front-matter is a flat `key: value` subset between `---`
  fences; `## Tasks` holds `- [ ]` / `- [x]` lines with an optional trailing `≈N`.
- `~/Notes/Omvision/goals/<slug>.log.md` — entries headed
  `### <D Mon HH:MM> · <N>m` or `### <D Mon HH:MM> · event · <kind> · <dur>`, then
  `focus:` / `done:` / `left:` lines, or a free line for an event.
- `~/Notes/Omvision/days/YYYY-MM-DD.md` — same entry grammar, for runs with no goal.
- The full contract, including every tolerance rule, is
  `~/Code/ompom-engine/docs/goal-files.md`. **Read it before writing a parser.**

Anything that fails to parse is skipped, never fatal — a broken file must not blank the app.
Watch the goals directory so edits appear without a restart.
