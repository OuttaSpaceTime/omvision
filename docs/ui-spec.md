# Omvision UI spec (from the approved mockups)

A Quickshell QML app: `~/Code/omvision/bin/omvision`, one `FloatingWindow`. The journal's
markdown highlighter is the one compiled part (`highlighter/build.sh`); everything else is QML.
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
- **Spacing is a scale, and nothing outside it is allowed.** 4px based, nine steps:
  `spaceXxs` 2, `spaceXs` 4, `spaceSm` 8, `spaceMd` 12, `spaceLg` 16, `spaceXl` 24,
  `space2xl` 32, `space3xl` 48, `space4xl` 64. Four named tokens sit on top of it and are
  what a screen should reach for: `panelPadding` (32, every page's margin), `sectionGap`
  (24, a header to its content), `rowGap` (12), `rowPadding` (24, a list row's text to its
  hairline). If a value looks wrong somewhere, take the neighbouring step — do not type a
  number. Before the scale the same decision was spelled 2, 4, 6, 8, 10, 12, 14, 16, 18, 20,
  24 and 28 across ten files, which is why rows meant to match sat a pixel or two apart and
  why none of it could be tuned globally. Control height stays 28, small actions 20.
- Fallback palette (Flexoki Light): paper `#FFFCF0`, ink `#100F0F`, secondary ink `#403E3C`,
  dim `#6F6E69`, faint `#878580`, hairline `#DAD8CC`, border `#B7B5AC`, fill `#F6F3E8`,
  accent `#205EA6`, accent fill `#E8EDF4`, red `#AF3029`.

## Window

1440×900 default, resizable, title "Omvision". One sidebar, one state: a **64px icon rail**,
1px hairline on its right edge. Top to bottom: the 26px Omvision mark (`assets/mark.svg`, a λ
in a double seal with four gate ticks) tinted to the accent, then one 36px row per screen — **Today, Goals, Coaching, Journal** — each a centred
Nerd Font glyph with the label carried by a tooltip. The selected row is accent-coloured with
a 2px accent bar on its left edge; the others are dim. No wordmark, no labelled variant, no
width breakpoint and no collapse toggle: a second layout was never worth the state it needed,
and switching between the two was behind every sidebar bug this app has had. No "Archive" row.

The only screen that changes this is the Journal, which hides the rail entirely while you
write and brings it back from its own control — see **Screen: Journal**.

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

## Screen: Journal

The one screen that is not a list. It is a writing surface, and the spec's ordinary chrome
rules are suspended here on purpose — no screen title, no buttons, no section labels.

Entering the Journal **is** entering writing mode:

- The app sidebar is **hidden**, so the page has nothing down its side. The `»` control
  brings the ordinary rail back in flow while you look around; leaving the Journal
  restores it, and coming back hides it again, so writing always starts clear.
- The list of days starts collapsed and opens as an overlay from the left edge, 260px, over
  the text, so opening it never reflows the text column. It slides out from the edge of the
  journal's own area (clipped there), never across the sidebar.
- Starting to write puts both away: a click on the paper, or any keystroke that edits the
  text, closes the day list and hides the sidebar again. Arrows and Escape don't count.
- The screen's own chrome is two 24px controls, `»` (sidebar, hidden while the sidebar is
  out) and `≡` (days), in `faint` with no border and no fill until hovered. Ctrl+O opens the
  days, Ctrl+N jumps to today, Ctrl+B toggles the sidebar (handled here because the editor
  would otherwise swallow it).

The text column is centred and `Theme.writingColumns` (70) monospace characters wide,
measured off the live font, regardless of window width. Type is `Theme.writingPointSize`
(15pt ≈ 20px) — the only *point* size in the app, because the highlighter's character formats
are point-sized (see README) — on a 185% line height. A sticky 44px header floats over the
text, opaque in `paper`, holding both controls and the day's label (`Today`, else
`Tue 23 Sep`) on one line; the text scrolls behind it. Bottom right, on its own opaque patch
for the same reason, the word count in caption faint, and above it in red the one write error
this screen can raise.

The text is always live: no read mode, no edit mode, no click-to-edit. Markdown is styled in
place by the `MarkdownHighlight` module, matching omawrite line for line:

- `#`, `##`, `-`, `>` and `---` stay **visible** in `faint`.
- `**`, `*`, `_` and a link's `[`/`](url)` are drawn at 1pt, transparent, with their advance
  width cancelled by negative letter-spacing — gone from the eye, still in the document and
  the file.
- Headings are **bold and not bigger**, at every level.
- Quotes italic in `faint`; inline code in `fill`, backticks included and undimmed; links
  accent + underline. `~~` and ``` ``` ``` are not markers here — omawrite has no rule for
  either, so neither does this.
- Blocks sit on a 185% proportional line height.

Nothing is deleted or rewritten: the file keeps every byte that was typed.

One file per day, `journal/YYYY-MM-DD.md`, attached to no goal. Today always has a row in the
day list whether or not its file exists — typing is what creates it.

## Data

Read the files directly, in QML, without shelling out to ompom's helper:

- `~/Notes/Omvision/goals/*.md` — front-matter is a flat `key: value` subset between `---`
  fences; `## Tasks` holds `- [ ]` / `- [x]` lines with an optional trailing `≈N`.
- `~/Notes/Omvision/goals/<slug>.log.md` — entries headed
  `### <D Mon HH:MM> · <N>m` or `### <D Mon HH:MM> · event · <kind> · <dur>`, then
  `focus:` / `done:` / `left:` lines, or a free line for an event.
- `~/Notes/Omvision/days/YYYY-MM-DD.md` — same entry grammar, for runs with no goal.
- `~/Notes/Omvision/journal/YYYY-MM-DD.md` — free-form markdown, one file per calendar day,
  no grammar to fail to parse. Omvision is its only writer.
- The full contract, including every tolerance rule, is
  `~/Code/ompom-engine/docs/goal-files.md`. **Read it before writing a parser.**

Anything that fails to parse is skipped, never fatal — a broken file must not blank the app.
Watch the goals directory so edits appear without a restart.
