# Layout rules for this app

Every one of these was learned by shipping the bug first. They are not style
preferences — breaking them produces the exact failures listed.

## 1. Look at it. Every time.

QML fails silently where CSS fails loudly: a child too wide for its parent simply
draws past it, with no clipping, wrapping or ellipsis unless you ask for them.
Layout written without looking at the result has been wrong every single time in
this repo. After any visual change, screenshot it and **read the image**, at both a
wide and a narrow window. See "Screenshotting" below: `bin/shot`, offscreen.

## 2. Text aligns at one left edge — across the whole app

The screen title, any filter chips and every list row's first character share one
left edge. Do not indent row content to make room for a selection marker — that is
what broke it before. A control whose label is inset in its own box (`← Goals`) is
pulled left so the *label* sits on the edge and its hover fill hangs in the margin.

That edge is the same on every screen: each one sets its text in the journal's
column with `Theme.pageX` / `Theme.pageWidth`, centred on the window rather than on
the area beside the rail. Don't position a screen's content with `anchors.margins`
on the full area; the text would jump when you switch to or from the journal.

## 3. Fills bleed, text does not

A hover or selected fill runs the full width of the content area, edge to edge. The
text inside is inset back to the shared left edge. Because the list scroller has
`clip: true`, a row **cannot** bleed by drawing at negative `x` — it gets clipped.
The *scroller* is the wide thing:

```qml
Flickable {
  x: -Theme.panelPadding
  width: parent.width + Theme.panelPadding * 2
  clip: true
  // rows fill this width; row content uses anchors.leftMargin: Theme.panelPadding
}
```

The selection bar sits at the bled row's own left edge, in the margin, so the
padding between it and the text is what gives the fill breathing room.

## 4. Reserve width for controls; never let two things both size to content

A button beside a text field must have its width reserved in the layout, with the
text taking the remainder and eliding. Letting both size to their content is how the
`copy` button ended up drawn outside its own container's border.

## 5. `Layout.*` only works inside a `Layout`, and spreads upward inside one

`Layout.fillWidth` on a child of a plain `Item`, `Column` or `Row` silently does
nothing. If you need it, the parent must be a `RowLayout`/`ColumnLayout`/`GridLayout`.

Inside one, a nested layout inherits `fillWidth` from any child that has it. The
event dialog's 120px `How long` column had a `fillWidth` field in it, so the whole
column filled too and squeezed `When` until it clipped its own value. A column meant
to stay fixed says `Layout.fillWidth: false`.

A layout's child must not size itself from that layout's `width` either: the width
feeds back into the layout's own sizing. Size it from something outside the layout
(the goal detail rail uses `Theme.pageWidth(root.width)`).

## 6. Never switch which anchor *lines* are bound between states

Binding `anchors.left` in one state and leaving it undefined in another makes the
item silently fail to lay out at all — this is why the sidebar toggle was invisible.
Vary margins, sizes, `x`, `visible` and `parent`; keep the anchor set constant. To
place one item differently in two containers, bind `parent` and use an `x`
expression that is correct in both.

Also never bind two anchors on the same axis *and* a size: `left` plus
`horizontalCenter` makes Qt fit the item between them and ignore its `width`. The
timeline's 7px node was anchored both ways and rendered as a 1px sliver, unnoticed
until a screenshot with log entries was read.

## 7. Degrade by design, never by clipping

Nothing may draw past the window edge at any width. Decide what gives way first and
implement it: on the Goals header, the summary was deleted outright and the filter
chips moved to a row of their own. Elide text rather than overflow it.

## 8. Secondary text is defined by contrast, not by a colour

Never draw text in the omarchy theme's `muted` colour. That key is for muted UI
*elements* — inactive marks, borders — and on a light theme it sits close to the
background: Rosé Pine Dawn's `#cecacd` on `#faf4ed` rendered body text at 1.48:1.
A fixed alpha on the foreground is no better, because what 50% buys depends on how
far apart that theme's foreground and background happen to be.

`Theme.secondaryInk`, `Theme.dim` and `Theme.faint` are solved for at runtime:
each is the lightest blend of foreground toward background that still meets a
contrast target (7, 5.5, 4.5). Every one of them is used at 12–15px, so none may go
below the 4.5:1 AA floor for small text. Use those tokens; do not invent a new grey.

## 9. Controls are quiet

Control height 32, small secondary actions 24 (`Theme.controlHeight`,
`Theme.smallControlHeight`; they were 28 and 20 until the type grew to 15px, when
labels touched their borders). A control must not be the loudest
thing on its screen: `+ task` at twice its height and a solid accent checkbox both
had to be pulled back. Square corners, 1px hairlines, no shadows.

## Screenshotting

Use `bin/shot`. It runs the real app with real data from `~/Notes/Omvision/`, but
**offscreen** (`QT_QPA_PLATFORM=offscreen`). Qt draws into memory, so no window ever
appears on the desktop. The app switches to the requested screen, takes its own
screenshots and quits. One run takes about 2–3 seconds.

```bash
bin/shot                                   # goals, 1440x900
bin/shot -w 720                            # narrow (720 is the window's minimum)
bin/shot -s goal:<slug>                    # a goal's detail screen
bin/shot -s journal -a sidebar -f 0,40,200 # toggle the sidebar, grab 3 frames
bin/shot -s journal -a days    -f 0,40,200 # open the day list, grab 3 frames
bin/shot -a event                          # a dialog: event | newgoal | cancel (on goal:<slug>)
bin/shot -s goal:<slug> -a editgoal        # also: edittask (first task's inline edit)
bin/shot -o <dir>                          # default dir: $TMPDIR/omvision-shots
```

It prints each PNG path. **Read every image.** That is the point of rule 1.

How it works: `bin/shot` sets `OMVISION_SHOT_*` environment variables and runs
`bin/omvision` offscreen, so the compiled highlighter is loaded too. `omvision.qml`
loads `ShotDriver.qml` only when `OMVISION_SHOT_DIR` is set, and a normal launch never
loads it. The driver:
1. waits `-t` ms (default 1500) for files to load,
2. switches screens the way a click would,
3. runs the `-a` action,
4. grabs the window with `grabToImage`, once per `-f` time.

Things to know:
- **`-f` times are when the grab starts, not exact.** The first grab after a change
  takes about 50–80ms, so a 40ms frame may really land at 80ms. The driver logs the
  actual time next to each file.
- **Switch screens late, never at startup.** A journal opened before its files have
  loaded stays blank (TODO.md, Open 4). The driver switches only after `-t` for this
  reason. If a screen looks empty, suspect that before suspecting the layout.
- **It only reads.** It never types, so nothing under `~/Notes` changes. Keep it that way
  if you add actions: the data is the user's real data. The dialog actions only open a
  dialog, the way its button does.
- **Your notes may not exercise a screen.** The real data has, for instance, no goal
  with log entries, so the timeline never appears in a real-data shot. The notes live
  under `$HOME`, so point `HOME` at a fixture instead of adding test data to `~/Notes`:
  copy `~/Notes/Omvision` into a scratch dir, add the files you need (the worked
  example in `goal-files.md` covers tasks, pomodoros, an event and coaching), and
  symlink `.local/state/omarchy/current` so the live theme still loads. Then run
  `HOME=<scratch> bin/shot …`.
- **Mouse input can't be simulated offscreen either.** Drive state through the same
  functions a click would call (see `runAction()` in `ShotDriver.qml`).

**Never screenshot by launching a real window.** The recipe that used to be here did
that (`setsid qs …`, then `hyprctl` to find the window and `grim` to capture it). It
left Omvision windows piling up on the user's desktop. `pkill -x qs` killed the user's
own instances. Untargeted `hyprctl dispatch` commands (this Hyprland is a Lua-scripted
fork) landed on the user's terminal three times, floating it, resizing it or moving it
to another workspace. Omarchy's "screenshot saved" toast also got into the captures.
None of that happens offscreen.

To check that a change still **loads**, without a screenshot:
`QT_QPA_PLATFORM=offscreen timeout 10 bin/omvision`. QML warnings print to stderr.
Ignore Quickshell's warning that WAYLAND_DISPLAY is set.
