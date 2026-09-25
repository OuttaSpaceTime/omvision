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
- Type scale, exactly: caption 12, bodySmall 14, body 15, subtitle 16, title 17, heading 24,
  display 32. Sized against the journal's 15pt (≈20px) page, not against a toolbar: body is a
  notch under the journal so the writing stays the largest text in the app, and a screen's
  title is the one large thing on it. Section labels are caption, **bold, sentence case**
  (`What happened`, not `WHAT HAPPENED`), dimmed; captions built from data are lower case too
  (`0 of 3 tasks done`, `event · training · 1 h 30`). Nothing is set in capitals.
- Wrapped prose (break notes, coaching summaries, hints) takes `Theme.proseLineHeight`, 1.4.
  Single-line labels keep the font's own line height, so they stay on the marker or control
  they sit beside.
- Surfaces: fills are the foreground colour at 4% alpha (8% hover, 18% selected); borders are
  1px at 40% alpha. No drop shadows, no gradients.
- **Spacing is a scale, and nothing outside it is allowed.** 4px based, nine steps:
  `spaceXxs` 2, `spaceXs` 4, `spaceSm` 8, `spaceMd` 12, `spaceLg` 16, `spaceXl` 24,
  `space2xl` 32, `space3xl` 48, `space4xl` 64. Four named tokens sit on top of it and are
  what a screen should reach for: `panelPadding` (64, every page's margin, the journal's
  included), `sectionGap` (32, a header to its content and between a page's sections),
  `rowGap` (12), `rowPadding` (24, a list row's text to its hairline). If a value looks wrong somewhere, take the neighbouring step — do not type a
  number. Before the scale the same decision was spelled 2, 4, 6, 8, 10, 12, 14, 16, 18, 20,
  24 and 28 across ten files, which is why rows meant to match sat a pixel or two apart and
  why none of it could be tuned globally. Control height 32, small secondary actions and the
  fields they open 24 (`smallControlHeight`); every dialog card is `dialogWidth` (560) wide,
  padded `spaceXl`.
- **One page column.** Every screen sets its text in the journal's column: `pageMeasure`
  wide (70 characters of the writing font, ≈840px) and on the journal's own vertical line —
  centred on the *window*, not on the area beside the rail (`Theme.pageX`), so switching
  screens changes what is on the page, never where the page is, and the column holds still
  while the rail slides in or out. At narrow widths it shrinks to leave a `panelPadding`
  margin each side. Hairlines stop at the column; hover fills bleed a margin past it.
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

Header row: `Goals` at heading size bold, then `Add event` and `New goal` buttons pushed
right. Under it, a band between two hairlines holding the filter chips (`active N`,
`paused N`, `done N`, `cancelled N`, caption — the selected one underlined in accent), at the
same left edge as the goal titles.

One row per goal, hairline-separated, sized to its text. Each row bleeds a page margin past
the column on both sides, padding restored inside, so a fill runs past the text. Selected or
hovered row: 4% fill plus a 3px accent bar at the fill's own left edge, in the margin.

Row contents: the title at title size bold, an optional status chip (caption, bold —
`running` in accent, a deadline in red), the `why` line at bodySmall in dim, and one caption
line in faint: `N of M tasks done · ≈ N poms left · last session <when>`, eliding. There is
no right-hand column; see TODO.md for why.

## Screen: Goal detail

Header: the title at heading bold (eliding), then `Add event` and `Coach this goal` buttons
pushed right (the second one accent-filled). Under it, a hairline band like the Goals filter
row holding `← Goals` (caption, dim, navigates back; its text on the column edge, its hover
fill in the margin) and a `running` chip. Below, a `Flow` of figures at body size:
`<N> poms · <H>m in`, `≈ <N> poms left`, `<done> of <total> tasks`. No progress rule.

Body splits into the timeline (flexible) and a right rail with a 1px hairline between. The
rail is 3/8 of the page column (≈315px at full measure), but never narrower than its two rows
of controls; task names elide instead.

**Timeline** — caption heading `What happened`, then entries newest first, grouped under day
headers (`Sun 20 Sep` caption bold + a dim `3 poms · 1 h 15` summary beside it). Each entry
is a row of: a right-aligned time in faint caption, as wide as `00:00`, a 7px square node
centred on a 1px vertical rule, then the content. Node styles: 1px bordered square for a
pomodoro, filled accent for a coaching session, 1px **dashed** for an event. Content is a
caption label (`25 min`, `coaching`, `event · training · 1 h 30`), the `focus:` line at body
size, and the `done:`/`left:`/`else:` lines beneath at bodySmall in dim, all wrapped prose.

**Right rail** — caption heading `Tasks` with `N of M done` beside it and a small `+ task`
button; then one row per task, hairline-separated, each a checkbox (checked and struck through
when done) with the task text and an optional `≈N` estimate at the right. When there are no
tasks yet, this line at caption size in faint: "Tasks belong to the goal, not to a pomodoro. A
finished pom never ticks one off — you do, or the coach does." At the bottom, while the goal is open,
`Close goal · done` and a red `Cancel`. The coaching hand-off lives on the Coaching screen
only.

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

The text column is the app's page column (see Tokens): `Theme.writingColumns` (70)
monospace characters wide, measured off the live font, on the same vertical line as every
other screen's text, and still while the sidebar slides in beside it. Type is `Theme.writingPointSize`
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
