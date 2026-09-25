# Omvision + ompom overlay — implementation plan (draft 2, after advisor review)

## What exists today
`ompom-engine` is an omarchy shell plugin (Quickshell/QML, `keepLoaded`), `Service.qml`:
- phases `focus | prompt | extend | break`; `overlayVisible = mode !== "off" && (phase === "prompt" || phase === "break")`
- `tick()` decrements `remaining` on every phase (only `mode === "off"` or `paused` stop it); the phase branch fires at zero
- `togglePause()` returns early unless `phase === "focus"`; `cycleMode()` refuses during `extend`/`break`
- `resetRun()` hardcodes `phase = "focus"`; `tick()`'s break-timeout branch does the same
- at focus end: prompt with `+1 minute (n left)` (3 × 60 s) then `Start break`; `Take notes` only during `break`
- notes view = plain `TextEdit` at `Style.font.display`, floating header with `←`
- `notes-helper.py` owns all filesystem work: fd-safe O_NOFOLLOW walk, day rollover, and `write_atomic()` = read-whole-file → temp file → `rename()`. **There is no O_APPEND path and no lock.**
- IPC target `ompom`: `status`, `togglePause`, `cycleMode`. `ompom-bar` (separate repo) draws the icon.

## Decisions already made
- Goals/tasks/journal live in a **separate app, Omvision** (mark `λi`). ompom stays the timer.
- ompom's bar widget and styling **do not change at all**. Only the overlays change.
- Overlay order: focus note → **the existing `+1 minute` / `Start break` prompt, untouched, before anything else** → break → "What's done? What's left?" in two sections.
- Tasks belong to a goal, never to a pomodoro. A finished pom ticks nothing off.
- Coaching is not in the UI: Omvision shows a command to paste into the user's own Claude Code terminal, and reads back what the session wrote.
- Two repos: `ompom-engine` (overlay-only change) and a new `omvision`.
- Chrome follows omarchy shell tokens; writing surfaces follow omawrite.
- Mockups: https://claude.ai/artifact/MHYF5Dr3yhQX6zRBeTRTU2

## Milestone 0 — the file contract (blocks everything else)

**Two files per goal, so the two writers never touch the same one.** This replaces
"strict section ownership", which does not survive interleaved read-modify-write cycles:
a coach session reads at T0, ompom logs a pomodoro at T1, the coach writes its T0 copy
back at T2 and the pomodoro is gone, silently.

```
~/Notes/Omvision/goals/<slug>.md        # Omvision + coach only
---
title: Goals layer
why: ...
status: active | done | cancelled
estimate: 6            # poms, set by coaching
done_by: 2026-09-24
---
## Tasks               # yours; coach may add/close
- [ ] Picker reads live goals   ≈2
- [x] Overlay blocks input
## Coaching            # appended by the coach skill
### Session 2 · 18 Sep · motivational interviewing
...

~/Notes/Omvision/goals/<slug>.log.md    # ompom appends, nobody rewrites
### 20 Sep 14:25 · 25m
focus: Wire the goal picker into the IPC
done: status call wired through the IPC
left: picker still caches the list on load

### 20 Sep 09:00 · event · training · 1h30
Bouldering — legs dead, head clear

~/Notes/Omvision/days/YYYY-MM-DD.md     # poms run with no goal, same grammar
~/Notes/Omvision/goals/<slug>/journal/YYYY-MM-DD.md
~/.local/state/omvision/active-goal     # slug, or empty
```

**The old daily file is retired.** `~/Notes/Ompom/today/ompom.md`, the `grave/`
rollover and the `notes-day` marker exist only because the day file had a fixed
name; writing `days/YYYY-MM-DD.md` directly removes all three. Existing files stay
on disk as history, untouched. A note therefore lives in exactly one place: the
goal's log if a goal is set, the day file if not.

Rules:
- ompom writes **only** `<slug>.log.md`, and only with `O_APPEND` and no read-back, so a
  concurrent writer can never cost it an entry.
- The coach and Omvision may rewrite `<slug>.md`, but must re-read it immediately before
  writing, never from a copy taken at the start of a session.
- Anything that fails to parse (missing front-matter, junk) is **skipped**, never fatal.

Deliverable: `docs/goal-files.md` in ompom-engine, with the grammar, a worked example, and
the helper CLI below.

## Milestone 1 — ompom overlay (this repo, overlay-only)

**E1 — `intent` phase, and the goal is remembered.**
A new phase `intent` runs before `focus`; `overlayVisible` gains it.
- **The first run after the shell starts has no intent and no goal.** `phase` still defaults
  to `"focus"`, so logging in never puts an overlay on screen. The intent screen appears only
  on the `break → intent` transition, i.e. at the start of a cycle you chose to continue.
- **A goal can be chosen mid-run, and only the remaining time counts to it.** Omvision writes
  `active-goal` while a run is in progress; the engine watches that file and attributes
  `Math.round(remainingAtSelection / 60)` minutes, not the whole run — the earlier minutes
  were not spent on that goal. Cleared mid-run → the entry goes to the day file at full length.
- A run with no intent simply has no `focus:` line. Nothing is invented to fill it.
- A break that times out with the notes view open **saves** the entry rather than discarding it.
- It shows the focus-note screen only. The goal is whatever `active-goal` says, shown as a
  quiet line; a key opens the picker to change it. No goal list every 25 minutes.
- With no goal files, the goal line is simply absent.
- `tick()` returns early during `intent`: **intent time is not focus time**, and `remaining`
  is set to `focusSecFor` on the way out, not on the way in.
- `togglePause()` needs no change — it already refuses anything but `focus`.
- `resetRun()` and `tick()`'s break-timeout branch both move to `phase = "intent"`.
- `cycleMode()` during `intent` must **keep** the typed focus line (it names what you are about
  to do — unlike break notes, discarding it is a real loss). So `resetRun()` cannot route the
  focus line through `clearNotes()`.
- Esc skips straight to `focus`.

**E2 — the prompt is untouched.** `phase === "prompt"` renders exactly what it renders today.
`startBreak()` additionally opens the notes view, now with two collapsible sections,
"What's done?" and "What's left?", caret in the first. `Take notes` reopens the same view.

**E3 — `notes-helper.py` subcommands**, same fd discipline, same 20 000-byte ceiling:
- `list-goals` → JSON array of `{slug, title}`, skipping anything unparseable
- `append-log <slug>` → entry as JSON on stdin `{started, minutes, focus, done, left}` or
  `{started, minutes, kind, title}` for events; written with **O_APPEND**, no read-modify-write
- `read-active` / `write-active` → `~/.local/state/omvision/active-goal`
- `append-day` → same JSON shape as `append-log`, appended to `~/Notes/Omvision/days/YYYY-MM-DD.md`, also O_APPEND. Replaces `save-note`, which is removed along with the rollover and marker machinery.

Because a note now has only one home, **the overlay must keep the text when a write
is refused** (`append-log`/`append-day` exit non-zero and write nothing on a malformed
entry). There is no second copy to fall back on any more.

**Acceptance (M1 ships on its own):** goal files do not exist yet — Omvision is M2 — so the
check starts by **hand-writing one `~/Notes/Omvision/goals/test-goal.md`**. Then: start a run,
see the goal line, type a focus note, 25 min, `+1 minute` still works 3×, `Start break`, write
done/left, and `test-goal.log.md` has the entry. Repeat with no active goal and check
`~/Notes/Omvision/days/<today>.md` instead. Verified through a real `omarchy plugin add` + shell restart — the last crash was
deployment, not code, so the deploy is part of the task.

**E4 — live markdown via the native `NoteHighlighter`** is explicitly **not** in M1's acceptance
path. It is the thing that took down the compositor twice; it lands after M1 is running.

## Milestone 2 — Omvision skeleton, read-only
New repo, Qt Quick (same stack as omawrite), follows system light/dark.
- **O1** window + sidebar (`λi omvision`; Today, Goals, Coaching, Journal), tokens, no writes.
- **O2** goals list + goal detail: header numbers, timeline rendered from `<slug>.log.md`,
  tasks from `## Tasks`, read-only.
- Acceptance: everything M1 wrote shows up correctly.

## Milestone 3 — Omvision writes
- **O3** tasks: tick, add, reorder; goal create / close / cancel (reason + takeaway → `status`).
- **O4** events outside the timer, appended to `<slug>.log.md` through the same helper path.
- **O5** journal: omawrite-style live markdown, one file per day.

## Milestone 4 — coaching
- **C1** `ompom-coach` skill: reads `<slug>.md`, the log since the last session, and overlapping
  journal entries; asks 3–6 questions (MI or Pólya); re-reads, then rewrites `## Tasks` and
  `estimate` and appends `## Coaching`. Never touches `.log.md`.
- **C2** Omvision coaching screen: goal + method, the command to copy, what it will read, and the
  sessions list where each row opens what came back.

## Risks
1. **Deployment, not code.** Every M1 task ends with a verified `omarchy plugin add` + restart.
2. The `intent` phase touching a working state machine — `resetRun()`, the break branch, the tick
   loop and the notes lifecycle all have to move together. Prompt/extend behaviour gets a
   regression pass before anything else lands.
3. Silent data loss between two writers — structurally removed by the two-file split, not by
   convention.
4. Scope. Nothing past M1 starts until M1 runs on the machine.
