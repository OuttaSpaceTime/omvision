# Omvision — where this stopped

Runs with:

```
qs -p ~/Code/omvision/omvision.qml
```

Milestones 2, 3 and 4 are in: it reads and writes `~/Notes/Omvision/goals/*.md`,
`<slug>.log.md`, `days/*.md` and the per-goal journals, and the `ompom-coach` skill exists at
`~/.claude/skills/ompom-coach/SKILL.md`. The UI spec is `docs/ui-spec.md`, the layout rules are
`docs/layout-rules.md`, and the file contract is `~/Code/ompom-engine/docs/goal-files.md`.

## Open

1. **Nothing mouse-driven has ever been clicked.** There is no click-simulation tool on this
   machine (no ydotool/wlrctl/xdotool, and installing one needs sudo), so every agent has
   verified its work by calling the same functions a click would — over IPC, from a test
   harness, or by keyboard. The wiring is there in each case. A pass with an actual mouse over
   ticking a task, the back control, the filter chips and every dialog (including the newer
   New goal modal and `Coach this goal`) would close this out.
2. **Two write-failure paths have never been seen to fire**: the journal's `Theme.red` line on
   `saveFailed`, and the goal-file queue's failure branch. Forcing them needs a read-only
   directory, which the sandbox blocked.

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

States that must be captured every round:

| State | How |
|---|---|
| Goals list, wide | default window, ~1440 |
| Goals list, half width | ~700, the width where the top bar broke |
| Goals list, narrow | below the collapse breakpoint |
| Goal detail, wide | open a goal with log entries |
| Goal detail, narrow | same goal, narrow window |
| Sidebar collapsed | rail only, check the toggle is visible and hittable |
| Sidebar floating | expanded while below the breakpoint, over the content |

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
