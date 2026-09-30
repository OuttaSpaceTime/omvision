# Omvision — where this stopped

Runs with:

```
~/Code/omvision/bin/omvision
```

(`qs -p ~/Code/omvision/omvision.qml` still runs it, minus the journal's markdown styling --
the launcher exists to put the compiled `MarkdownHighlight` module on the QML import path.)

Milestones 2, 3 and 4 are in: it reads and writes `~/Notes/Omvision/goals/*.md`,
`<slug>.log.md`, `days/*.md` and the per-goal journals, and the `ompom-coach` skill exists at
`~/.claude/skills/ompom-coach/SKILL.md`. The UI spec is `docs/ui-spec.md`, the layout rules are
`docs/layout-rules.md`, and the file contract is `~/Code/ompom-engine/docs/goal-files.md`.

## Landed 2026-09-29

- **Compose (fcitx5) no longer paints a box at the start of a styled line.** The user
  reported the cursor jumping to the line start when typing `ä` with Compose, but only on
  lines with `@` tags. The cursor never moved: the `ä` always landed in place. fcitx5 colours
  its preedit (`·`), QSyntaxHighlighter puts that range first in the layout's format list,
  and Qt Quick's `QQuickTextNodeEngine::mergeFormats` assumes the list is sorted. So the
  highlight was painted on the line's first coloured character. That affects a list's `-`
  and links too, not only tags. The fix is `uncolourPreedit()` in the highlighter: the
  preedit loses its blue background and draws in text colour at the cursor. The comment
  there explains why sorting the list was rejected. Reproduced and verified with a C++
  harness in the session scratchpad (not in the repo). It loads `MarkdownHighlight` with a
  TextEdit offscreen, sends fcitx5-qt's own `QInputMethodEvent`s (preedit `·`, `"`, then
  commit `ä`), grabs the window and prints the layout's format order. Before the fix, a box
  sat on the `@` and on the `-`; after, neither, and a plain line is unchanged. The app
  loads offscreen without errors. It has not yet been checked in the live app (it needs a
  restart to load the rebuilt plugin).

- **The `@` list filters fuzzily**, ignoring case and accents: `filterGoals`, `foldForMatch`,
  `matchScore` in JournalScreen.qml. Tiers are prefix, word start, substring and scattered.
  Scattered matches pick the best placement (a small DP), not the first, so `sa` ranks
  Study Software Architecture above Wall Squat. Checked offscreen with `bin/shot -a mention:`
  `wsq`, `WallSq`, `dia`, `sa` and `e` at 900px, and `wsq` at 420px. The user reported that
  typing had stopped filtering the list. Offscreen, typing filtered fine, and after this
  change it worked for the user too. The cause was never pinned down. Ten `qs -p` instances
  were running at the time, so the user may have been typing in a stale one.

- **The `@` list shows one line per goal**: the title, plus `done`/`cancelled` in caption
  faint at the right of closed goals. The `@slug` line under each title is gone (the tag
  already draws as the title). Checked offscreen with `bin/shot -a mention` at 900 and 420px.

- **Smaller pencil on task rows.** `PencilIcon.qml` has a `small` size: the `+ task` button's
  `smallControlHeight` (24px square) with a caption-size glyph. Task rows use it. At the full
  32px it nearly filled a one-line row. Goals rows and the detail title keep the full size.
  Checked offscreen with the pencil forced visible at 1100 and 720px.

- **Tags show the goal's current title** and follow a rename live, with no write to the
  journal. The file still holds `@slug`. A highlighter can't change characters, so
  `formatMentions()` (highlighter) makes the slug transparent and exactly as wide as the title.
  All the width goes on its first character as letter spacing, and the rest is hidden at 1pt.
  A line break can't split one character, and a slug stretched evenly could break after a
  hyphen. `mentionSpans()` reads each gap's x, baseline, width and font from the layout, and
  JournalScreen's `tagTitles` Repeater draws the titles there (refreshed on text, tag, width
  and height changes). `mentions` is now a slug → title map. This replaces the words-from-slug
  styling (transparent hyphens, AllUppercase capitals), so "Diät" now reads "Diät". Widths are
  capped at the line, the title elides, and a change of column width re-sizes them.
  Verified offscreen against a fixture HOME: body, heading, quote and list tags at 1100 and
  720px, a title changed on disk mid-run (the tag re-rendered and the line reflowed), the
  long-title cap, the `@` picker, and `mentionAt()` at each title's middle, on the `@` and past
  the line end. **Open:** a real click, drag-select and caret placement inside a tag. The caret
  now stops at the `@`, at the end of the title, and at invisible zero-width positions in
  between.

- **Edit a goal from its detail screen.** Hovering the title shows the pencil right after it
  (`titleGroup` in GoalDetailScreen.qml, sized to the title so the pencil follows the words;
  slot reserved, so the title never re-elides). It opens the same Edit goal dialog
  (`editGoalRequested` → `openEditGoalDialog`).
- **The pencil is a button now.** `PencilIcon.qml` is a 32px square drawn like `Button.qml`
  (border, 8% hover fill, ink glyph) with its own MouseArea and `clicked` signal; the three
  callers (Goals rows, task rows, detail title) dropped their MouseAreas. The bare dim glyph
  didn't read as clickable: on a Goals row the whole row already shows a hand cursor.
  Verified offscreen with hover forced on in a scratch copy (goals list, goal detail wide
  and 720px). **Open:** the real hover and click, which can't be driven here.

- **`@` goal tags in the journal.** Typing `@` opens a list of every goal under the `@`,
  and the letters after it filter the list. Up/Down/Return/Tab/Escape or a click writes
  `@<slug>`. It works in headings and list items, and never after a word character, so
  e-mail addresses don't trigger it. Known tags are styled by the highlighter: a new
  `mentions` property on `MarkdownHighlighter`, empty by default, so the ompom overlay is
  unaffected. A plain click on a tag opens the goal (`TapHandler` with a passive grab, next
  to the TextEdit's own mouse handling), and its back link reads `← Journal`
  (`goalBackScreen` in omvision.qml). Tags show the goal's title (see the entry above; this first version read the
  slug as words). The pattern lives only in `mentionRe` (C++): clicks, hover and
  `-a opentag` hit-test the spans it produced (`tagSpans`), so a tag in a link or code span,
  which the highlighter leaves plain, isn't clickable either. The spec is in ui-spec.md,
  Journal, "Goal tags".
  Verified offscreen against a fixture HOME: the list, filtering, flip-above and no-match
  shots (`bin/shot -a mention[:query]`, `-a opentag`); and, calling the functions directly,
  accept, word-end replacement, space/email/Escape closing, hit-testing (known, unknown,
  in code, past the line end), and journal → goal → back. The day's file was unchanged
  afterwards (`writesDisabled`).
  **Open:** a real mouse click and hover on a tag were not tried (they can't be simulated
  here). What needs a hand check: the click opens the goal, dragging across a tag still
  selects, and the pointer turns into a hand. The deployed ompom copy of the highlighter was
  not redeployed; it doesn't need `mentions`. The coach skill doesn't look for `@slug` yet;
  it could grep all journal days for a goal's tag instead of only overlapping dates.

## Landed 2026-09-25

- **Journal trackpad glide** (`JournalScreen.qml`, the `trackpadGlide` WheelHandler). Qt Quick
  on Wayland has no kinetic trackpad scrolling: the compositor sends ScrollEnd, no momentum,
  and Flickable stops dead. A passive (`blocking: false`) WheelHandler measures finger speed
  over the last 80 ms and flicks on at 1.5× that on ScrollEnd; friction is
  `flickDeceleration: 1250`. It must list `PointerDevice.TouchPad`: Qt's Wayland backend marks
  trackpad scrolls synthesized, and a default WheelHandler ignores them. (An earlier attempt
  missed that and never saw a trackpad event.) Mouse wheel is stock Qt. **Open:** the tuning
  (`boost`, `flickDeceleration`) was never felt on hardware. Real scroll input can't be
  produced here. Sign and glide distance were checked with a standalone `qml` test.
- **Tasks wrap** instead of eliding; checkbox and `≈N` sit on the first line.
- **Edit a task**: hover pencil (always-reserved slot, so no reflow), inline wrapping field,
  cursor at the end. `Writer.editTask` keeps `[x]` and `≈N`; saving it empty deletes the task.
- **Edit a goal**: hover pencil on Goals rows opens NewGoalDialog in edit mode (`editSlug`,
  `initial`). `Writer.updateGoalFields` rewrites only changed front-matter keys, so a coach's
  `# was 9` note survives; the slug never changes.
- **Reopen goal** button on done goals (`status: active`). Not offered on cancelled goals: their
  `## Cancelled` note would stay and a second cancel would append another.
- **No paused status**: filter chip removed (no goal used it; the pomodoro pause is unrelated).
- The "Tasks belong to the goal…" caption only shows when there are no tasks.
- Both pencils are `PencilIcon.qml` (U+F040, 16px; tried upright, looked strange), centred vertically on
  their row. Hover can't be driven offscreen; they were checked by shooting a scratch copy
  with the hover conditions forced true.
- `bin/shot -a editgoal|edittask` added. Verified offscreen with fixture data.

## Landed 2026-09-24 (ompom-engine, deployed, not committed)

- **Overlay buttons match Omvision's `Button.qml`**: square, 1px border at 40% foreground,
  transparent with an 8% hover fill, 28px tall; `primary` is Omvision's `filled`.
- **Break notes**: order is now What's done? → What's left? → **What else?** (renamed from
  "Anything else?", still saved as `else:`). The header is a slim 22px `←` and a
  `BREAK NOTES` caption, 32px from the top edge with 32px before the first heading.
- **Esc after collapsing a section works.** A hidden TextEdit drops keyboard focus, so
  collapsing the section with the caret left nothing focused and Esc did nothing (verified
  offscreen). `notesPage.toggleSection()` now hands focus to the next open section, or to
  the page, which also takes Esc.
- Deployed by copying `Service.qml`, `OverlayButton.qml` and `notes-helper.py` into
  `~/.config/omarchy/plugins/ompom.engine/` (a plain copy, not chezmoi-managed); the shell
  reloads the plugin on save, which resets the running pomodoro.

- **Live demo**: `~/Code/ompom-engine/bin/ompom-demo` (skill `/ompom-demo`, chezmoi-managed
  in `~/Code/system`) runs the real `Service.qml` with `demo: true` in its own `qs`: 5s
  timers, no writes, IPC target `ompom-demo`, Ctrl+Q quits. Verified live: the real engine
  kept its own timer and nothing under `~/Notes/Omvision` or `~/.local/state/omvision`
  changed. `qs` offscreen can't load it (no PanelWindow backend). The demo flag is in the
  repo only; the deployed copy predates it, so `--live` refuses until the next deploy.

- **Overlay writing = journal writing.** The intent line and all three break-note fields
  load omvision's `MarkdownHighlight` (via ompom's `NoteHighlighterHost.qml`) with
  `JournalHighlight.qml`'s settings: 15pt, 135% line height, markers solved at 2:1 contrast,
  quotes at 4.5:1, 4% code fill, accent selection. Checked offscreen with markdown in every
  field. ompom's own `Ompom.Highlight` is no longer imported (its sources are still there).
- **`highlighter/build.sh` builds with hidden visibility and renames into place.** Both
  libraries export a C++ class named `MarkdownHighlighter`; loaded into one process they
  could bind to each other's symbols. Now only `qt_plugin_*` is exported (checked with
  `nm -D`), and the journal still styles (`bin/shot -s journal`).
- **Deployed 22:22** (with omvision-25's cycleMode() logging change): `MarkdownHighlight/`
  installed-then-renamed into `~/.config/omarchy/plugins/ompom.engine/native/`, QML the
  same way, then `omarchy restart shell`. Checked in `/proc/<pid>/maps`: the new shell
  maps only `native/MarkdownHighlight/libmarkdownhighlight.so`, not `libompomhighlight`.
  The engine came back in a fresh focus run. Deploy the omvision highlighter again after
  any change to `highlighter/`.

Open from this round: the intent screen ("What's your focus?") still has the old large
header, and its goal line and every `NORMAL` mode label use `Color.muted`, which is
barely readable on light themes.

## Landed 2026-09-24

- **The whole app is set like the journal's page** (the user picked "Journal page" from
  three variants, each screenshotted from a throwaway copy of the repo). Type went up to
  caption 12 / body 15 / title 17 / heading 24, page margins 32 → 64, section gaps 24 → 32,
  controls 28 → 32 and small controls 20 → 24. Labels are in sentence case throughout,
  dialogs included, and wrapped prose gets 1.4 leading (`Theme.proseLineHeight`).
- **One page column.** Every screen's text sits in the journal's 70-character column on the
  journal's own vertical line (`Theme.pageMeasure`, `Theme.pageX`, `Theme.pageWidth`).
  It's centred on the window, so the journal's text no longer shifts 32px when the sidebar
  slides in. Measured across the animation frames with `bin/shot -a sidebar`.
- **Bugs this surfaced, all fixed:** the timeline node was a 1px sliver (two horizontal
  anchors); the timeline's day summary drifted to mid-row (no fill item); the event
  dialog's `When` field was squeezed until it clipped (inherited `fillWidth`); the fixed
  312px task rail left the timeline ~15 characters a line at 720px, then overflowed the
  window once made proportional (floored at its control rows now); goal rows had a fixed
  78px height.
- **Everything mouse-driven has now been clicked**, by the user, closing the old open item
  that no agent could (there is no click-simulation tool on this machine). That covers
  ticking a task, the back control, the filter chips and every dialog, including New goal
  and `Coach this goal`.
- `bin/shot -a event|newgoal|cancel` opens a dialog for a screenshot. Fixture data goes
  through `HOME=<scratch dir>` (docs/layout-rules.md, "Screenshotting"), which is how the
  timeline was checked: the real notes have no goal with log entries.
- Not checked by eye: a done/cancelled goal's detail rail, a coaching screen with past
  sessions, and a Goals row while hovered or selected. Nothing in them changed except
  tokens.

## Landed 2026-09-23

- **The journal is off goals.** An entry is a day, not a goal:
  `~/Notes/Omvision/journal/YYYY-MM-DD.md`, free-form, about whatever is on your mind. The
  goal picker is gone from the flow (`JournalGoalPicker.qml` is now unreferenced). Discovery
  is a flat `find` over one directory.
- **Writing mode.** Opening Journal opens today's entry with the cursor in it. No screen
  title, no `+ entry`, no read/edit modes. 15pt type, a 70-character measure, 185% line
  height, a sticky opaque header carrying both controls and the date on one line. The app
  sidebar is hidden and the day list collapsed; `»` and `≡` (24px, `faint`) bring them
  back — Ctrl+B, Ctrl+O, and Ctrl+N for today.
- **One sidebar, one state.** The labelled 176px variant, the width breakpoint, the manual
  override and the narrow-mode floating overlay are all deleted; what is left is the 64px
  icon rail. That removed the class of bug where a sidebar choice made on one screen
  followed you to the next. Page margins went 18 → 32 and rows opened up to match the
  journal's air (`Theme.panelPadding`, `Theme.sectionGap`).
- **ompom, in `~/Code/ompom-engine` and deployed**: break notes gained an "Anything else?"
  section (first, above the other two) saved as its own optional `else:` line — helper,
  `goal-files.md` §4, `Parser.js` and the coach skill all know it. Both writing surfaces
  are centred on the same 70-character measure at 185% line height (a `NoteHighlighter`
  property, since QML's TextEdit has no `lineHeight` — verified), and the break/focus-end
  overlays were re-tiered: uppercase caption mode label, bold state, the countdown as the
  one large thing on screen.
- **Live markdown styling, omawrite's way.** `highlighter/` builds a `MarkdownHighlight` QML
  module: a C++ `QSyntaxHighlighter` on the TextEdit's own `QTextDocument`, syntax markers
  shrunk to 1pt rather than deleted, so the file keeps every byte that was typed. Built with
  moc + g++ alone -- no cmake, no ninja, no sudo.

  The alternative was measured and rejected: QML's `TextEdit.MarkdownText` regenerates the
  markdown from the document on every read, hard-wrapping paragraphs at ~78 columns,
  rewriting `---` as `- - -` and dropping two-space hard breaks. Idempotent, but not the
  user's file.

  Two things worth knowing next time: Quickshell **blackholes directory-relative module
  imports** (`Blackholed import URL QUrl("qs:@/MarkdownHighlight/qmldir")`), so the module
  has to arrive via `QML2_IMPORT_PATH` -- that is the whole reason `bin/omvision` exists.
  And the styling is loaded through a `Loader` (`JournalHighlight.qml`) so a missing or
  unbuilt module costs the journal its styling instead of failing the app's load.

## Open

1. **`~/.claude/skills/ompom-coach/SKILL.md` is still not chezmoi-managed.** It was edited
   in place (journal path, and the new `else:` line), so that edit lives only on this
   machine. Adding it to `~/Code/system` is still open.
2. **`~/Code/ompom-engine/docs/goal-files.md` is untracked** in that repo (`?? docs/`), so
   the `else:` documentation is not under version control there either.
3. **Two write-failure paths have never been seen to fire**: the journal's `Theme.red` line on
   `saveFailed`, and the goal-file queue's failure branch. Forcing them needs a read-only
   directory, which the sandbox blocked.
4. **A journal opened before its files have loaded stays blank over a non-empty day.** Found
   2026-09-24 with `bin/shot`, which then switched to the journal at startup. The page showed
   empty with "0 words" while today's file held 20 bytes. Logged state: `syncBufferFromDisk()`
   does run when `journalContents` changes, but (a) at that moment `entries` hasn't been
   recomputed yet, so `findEntry()` still returns the old empty content, and (b)
   `writeDebounce` is already running, which makes it return early anyway. Nothing calls it
   again afterwards. Also calling it from `onEntriesChanged` did not fix it, because (b)
   still blocks. Normal use rarely hits this: the app opens on Goals and the journal is
   clicked after loading has finished. But typing into that blank page within the first
   second or two would save the new text *over* the day's file. `flushWrite` only refuses
   to save an *empty* buffer over existing text. Not fixed yet.
5. **Omvision processes outlive their windows.** On 2026-09-29, ten `qs -p …/omvision.qml`
   processes were running, but only the newest had a window. The other nine were ended
   with the user's OK. Probably closing the window doesn't quit Quickshell, so every launch
   leaves one behind. That has not been verified. Stale instances still poll, and could
   write, the journal.

## Fixed and verified on screen (2026-09-20)

- The goal row's right-hand column is **gone**. A fixed 240px column of count + estimate could
  not be aligned against rows of varying height — it read ragged at every window size and
  clipped the date. The estimate now rides in the row's caption line, left-aligned and eliding.
  Do not reintroduce a second column here without solving the alignment first.
- The `λi` mark is its own row in the collapsed rail, at 26px, with the `»` toggle on its own
  row beneath it. Collapse/expand behaves.
- Goal detail: header degrades like the Goals one (the unbounded title was the real overflow
  cause — it elides now), figures wrap in a `Flow`, `done by` removed, `copy` sits inside its
  box, `+ task` is 20px, the checkbox is a light tick, task text aligns to the `TASKS` heading.
  The sidebar is present here at 1416px — verified on screen.
- Today, Coaching and Journal exist and read real files. Journal renders markdown omawrite-style
  (headings bold at body size, markers hidden).
- Two bugs found by screenshotting after the agents reported done, both now fixed: the detail
  figures line floored to whole hours, so two pomodoros read `0 h in` instead of `50m in`; and
  Today's rows had no `fillWidth` item when a goal label was hidden, so the layout spread the
  surplus and the type label drifted to the middle of the row on goal-less entries only.
- The Goals header no longer overflows. The `TODAY · N POMS · H` summary was removed outright
  (not degraded — it was never worth the space), and the filter chips now reparent between an
  inline slot and a second row depending on whether they fit, so the title and the buttons keep
  the first row at every width. Wrapped, they right-align to the buttons' edge — bound as `x`,
  not a conditional anchor, so one expression serves both slots. Verified at 701px (one row)
  and 601px (chips wrapped and right-aligned).
  The `filtersInline` test compares intrinsic widths only; comparing against anything the
  layout produces would be a binding loop.

## How the next round should be run

Test-driven, with the implementer taking and reading its own screenshots rather than
reasoning about layout in code. Every one of the bugs above was visible in the first
screenshot taken of that screen, and every one was caught by the user instead.

For each change: state the expected result, capture the states below, compare each against
`docs/ui-spec.md`, and only then report — naming what was checked and what it looked like.

States that must be captured every round, with `bin/shot` (offscreen, see
`docs/layout-rules.md`, "Screenshotting"):

| State | How |
|---|---|
| Goals list, wide | `bin/shot` |
| Goals list, half width | `bin/shot -w 720` (the window's minimum; the top bar broke near here) |
| Goal detail, wide | `bin/shot -s goal:<slug>`, a goal with log entries |
| Goal detail, narrow | `bin/shot -s goal:<slug> -w 720` |
| Journal, writing | `bin/shot -s journal` |
| Journal, sidebar in | `bin/shot -s journal -a sidebar -f 0,40,200` (animation frames) |
| Journal, day list | `bin/shot -s journal -a days -f 0,40,200` |

Fixture data already on disk under `~/Notes/Omvision/` covers goals with and without
estimates, a goal with no sessions, and a day file.

## Landed 2026-09-21

- **Writes**: ticking and adding tasks, closing and cancelling goals, logging events to a goal
  log or the day file. Goal files go through `FileView.setText` with `atomicWrites`, re-read
  immediately before each mutation, one job at a time through a queue, edited as surgical line
  replacements so unknown keys, section order, blank lines and CRLF all survive. Event logs go
  through `tee -a` — a true append, matching `notes-helper.py`'s discipline from the other side.
- **Journal**: create an entry, edit it, debounced writes, plain monospace while editing and
  rendered when not. The writer is a serial queue where each job carries its own captured path
  and text — proven by typing into entry A, switching to B mid-debounce, and confirming neither
  file got the other's text.
- **Coaching**: the `copy` button sits inside its box and copies; the `ompom-coach` skill reads
  the goal file, the log since the last session and overlapping journal entries, and writes back
  `## Tasks`, `estimate:` and a dated `## Coaching` entry.
- **`estimate` semantics corrected**: it is poms *remaining*, not a total. Both screens display
  it directly instead of subtracting pomodoros from it, and the goal-detail progress bar was
  removed rather than given an invented denominator.

- **New goal**: the last inert control. Title (required), `why`, estimate and deadline; the
  slug is derived per the file contract's §3 rules, including collisions — same title is a
  no-op, a different title that would derive the same slug gets `-2`, `-3`, ... Verified by
  driving `handleCreateGoal()` directly against the real files: create, create again with the
  same title (no-op), create a title that derives the same base slug (`-2`).
- **Real modals**: `EventDialog`, `CancelDialog` and `NewGoalDialog` all dim and block the
  screen behind them, `Esc` closes, and clicking the scrim dismisses Add event but not Cancel
  goal (destructive, so it needs an explicit press). The "not modal" report turned out to be
  two bugs: the dialog card had no `height` binding and rendered as a zero-height box with no
  background behind the content, and `CancelDialog` was mounted inside `GoalDetailScreen`
  (which only covers the area right of the sidebar) instead of at the window root.
- **Coaching command adapts to the method chip** (`claude /ompom-coach <slug> --method mi` or
  `--method polya`), box and button read from one property so what's shown is always what's
  copied, and `copy` now flips to `copied!` for 1.3s instead of a floating popup. The third
  "quick check-in" chip was removed — the skill only parses `mi|polya` and would refuse that
  command; it needs teaching before a chip can offer it.
- **Goal detail's task rail** was fixed to one left edge (checkbox, label, `≈N` right-aligned,
  equal-length rules) instead of three, and the redundant `NEXT SESSION` block was deleted
  outright now that Coaching owns that hand-off.
- **`Coach this goal`** now works: it selects the current goal in Coaching and switches there,
  instead of sitting inert.

### Four silent-failure bugs in this Quickshell build, worth knowing

1. `FileView.setText()` called synchronously from inside `onLoaded` writes the file but drops
   the `onSaved`/`onSaveFailed` signal — stalling any queue that waits on it. Defer with a
   zero-interval `Timer`.
2. `FileView.setText("")` on a path that was never loaded is a no-op: it compares against its
   empty internal buffer and skips the write. Create empty files with `touch` instead.
3. `writeAdapter()` is JsonAdapter-only; calling it on a plain-text `FileView` warns and does
   nothing.
4. `reload()` called synchronously from inside a `FileView`'s own `onSaved`/`onLoaded` stalls
   the same way `setText()` does — same fix, a zero-interval `Timer`. Found in the New goal
   collision probe, which chains `reload()` calls across several candidate slugs.
