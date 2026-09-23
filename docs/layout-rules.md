# Layout rules for this app

Every one of these was learned by shipping the bug first. They are not style
preferences — breaking them produces the exact failures listed.

## 1. Look at it. Every time.

QML fails silently where CSS fails loudly: a child too wide for its parent simply
draws past it, with no clipping, wrapping or ellipsis unless you ask for them.
Layout written without looking at the result has been wrong every single time in
this repo. After any visual change, screenshot it and **read the image**, at both a
wide and a narrow window. See "Screenshotting" below for the recipe that works.

## 2. Text aligns at one left edge, per screen

The screen title, any filter chips and every list row's first character share one
left edge. Do not indent row content to make room for a selection marker — that is
what broke it before.

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

## 5. `Layout.*` only works inside a `Layout`

`Layout.fillWidth` on a child of a plain `Item`, `Column` or `Row` silently does
nothing. If you need it, the parent must be a `RowLayout`/`ColumnLayout`/`GridLayout`.

## 6. Never switch which anchor *lines* are bound between states

Binding `anchors.left` in one state and leaving it undefined in another makes the
item silently fail to lay out at all — this is why the sidebar toggle was invisible.
Vary margins, sizes, `x`, `visible` and `parent`; keep the anchor set constant. To
place one item differently in two containers, bind `parent` and use an `x`
expression that is correct in both.

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
contrast target (7, 5.5, 4.5). Every one of them is used at 10–13px, so none may go
below the 4.5:1 AA floor for small text. Use those tokens; do not invent a new grey.

## 9. Controls are quiet

Control height 28, small secondary actions 20. A control must not be the loudest
thing on its screen: `+ task` at twice its height and a solid accent checkbox both
had to be pulled back. Square corners, 1px hairlines, no shadows.

## Screenshotting

```bash
# 1. launch (setsid so it survives the shell)
pkill -x qs            # NOT pkill -f, which matches and kills your own shell
(setsid qs -p ~/Code/omvision/omvision.qml > /tmp/omvision.log 2>&1 &)
sleep 6

# 2. find it — it may not be on the visible workspace
hyprctl clients -j | python3 -c "
import json,sys
for c in json.load(sys.stdin):
    if c['class']=='org.quickshell': print(c['workspace']['id'], c['at'], c['size'])"

# 3. if it is on another workspace, switch there, capture, switch back
hyprctl dispatch workspace <n>; sleep 2
grim -g "<x>,<y> <w>x<h>" /tmp/shot.png
hyprctl dispatch workspace <original>

# 4. READ the png
```

`pkill -x qs` kills **every** instance, including one another person or agent is
running. If someone else may have the app open, kill your own by PID instead.

Hyprland on this machine is a Lua-scripted fork: `hyprctl --batch "dispatch a ; dispatch b"`
fails with a Lua parse error, and dispatchers behave differently from the documented
`hyprctl dispatch <name> <args>`. The working form targets a window explicitly by address:

```bash
hyprctl dispatch 'hl.dsp.window.<action>({window="address:0x...", ...})'
```

**An untargeted dispatch acts on whatever Hyprland considers focused**, which is not the
window you just launched — it has hit the user's terminal three separate times in this
project, floating it, resizing it, or moving it to another workspace. Get the address from
`hyprctl clients -j` and pass it, or better, launch the window at the size you want to test
and don't drive the compositor at all.

Do not use `hyprctl dispatch movecursor` or `resizeactive` to set up a shot: they
act on whatever is focused, which has twice turned out to be the user's terminal.
Omarchy shows a "screenshot saved" toast over the top-right of the screen for a few
seconds after each `grim` call — take a throwaway shot, wait ~7s, then take the real
one, or your capture will have the toast in it.
