# Goal files — the ompom / Omvision / coach contract

This is the file contract between three programs that never share a process:
`ompom-engine` (this repo — the timer, runs inside the Omarchy shell), **Omvision**
(a separate goals/tasks/journal app, not built yet), and the `ompom-coach` Claude
Code skill (also not built yet). None of them can call into each other directly —
the shell plugin can't import an app, the coach skill runs in a terminal the shell
never sees — so the filesystem is the only thing all three agree on. This document
is that agreement. It has to be precise enough that a second implementer can write
Omvision or the coach skill against it without opening this repo's source.

`notes-helper.py` in this repo is the reference implementation of the ompom-engine
side of the contract (`list-goals`, `append-log`, `append-day`, `read-active`,
`write-active`). Omvision will read and write these files directly, in its own
language, following the same rules.

A pomodoro note lives in exactly one place: the active goal's log if a goal is
set, or the day file if not. There is no third copy and no daily-notes file with
a rollover — see "Retired paths" at the end of this document.

## 1. Layout

```
~/Notes/Omvision/goals/<slug>.md                    # Omvision + coach only
~/Notes/Omvision/goals/<slug>.log.md                 # ompom-engine + Omvision events, append-only
~/Notes/Omvision/goals/<slug>/journal/YYYY-MM-DD.md  # Omvision only, one file per day
~/Notes/Omvision/days/YYYY-MM-DD.md                  # poms run with no active goal, same grammar, append-only
~/.local/state/omvision/active-goal                  # slug of the goal ompom shows, or empty
```

`<slug>.md` and `<slug>.log.md` are flat files directly under `goals/`, not inside
the goal's own subdirectory — only the journal gets a subdirectory, because it's
the only thing that's naturally one-file-per-day. A goal with slug `deep-work-book`
therefore looks like:

```
~/Notes/Omvision/goals/deep-work-book.md
~/Notes/Omvision/goals/deep-work-book.log.md
~/Notes/Omvision/goals/deep-work-book/journal/2026-09-20.md
```

## 2. Why the log is a separate file

The obvious design is one file per goal, with `ompom` appending to a "Log"
section and the coach/Omvision rewriting the "Tasks" and "Coaching" sections
around it. That design has a lost-update race and no amount of "just don't touch
the other section" discipline fixes it, because the failure isn't about which
section gets touched — it's about *when* a writer's copy of the whole file goes
stale.

Concrete sequence, single-file design:

- **T0** — a coach session starts. It reads the whole goal file into memory to
  plan what to ask and what to rewrite.
- **T1** — you finish a pomodoro. `ompom` appends a log entry: reads the whole
  file (it has to, to append without clobbering), adds the entry, writes the
  whole file back.
- **T2** — the coach session finishes. It writes its in-memory copy — the one
  it read at T0 — back over the file, verbatim except for the sections it meant
  to change.

The T1 write is gone. Not merged, not reported as a conflict — gone, because T2's
write is a normal file write and has no idea T1 ever happened. Nothing in this
sequence is a bug in either writer; it's what read-modify-write *is* when two
writers do it to the same file without coordination, and a coach session and a
25-minute focus timer are exactly the kind of two processes that will overlap in
practice.

**The fix is structural, not a rule to remember.** `notes-helper.py`'s
`write_atomic()` — the function every existing write in this repo goes through —
is itself read-whole-file → temp file → `rename()`. That's a read-modify-write by
construction: it's what makes a single write atomic (the rename can't land a
half-written file), but it does nothing about two *separate* read-modify-write
cycles racing each other, because each one only ever sees the file as it stood
when *that* cycle started reading. Routing the log through `write_atomic()`
would just reproduce the race above with smaller windows.

So the log **never goes through `write_atomic()`, and never goes through a
read step at all.** `ompom` and Omvision append to `<slug>.log.md` with
`O_APPEND` and nothing else — no read, no rewrite, no temp file. `O_APPEND`'s
atomicity is a kernel guarantee on the write() syscall itself: the kernel
seeks to end-of-file and writes in one operation, so two concurrent appenders
can interleave their *writes* but neither can ever observe or undo the other's
already-committed bytes. There is no copy of the file sitting in either
process's memory to go stale, so there is nothing for a second writer to
clobber. This is also why `<slug>.log.md` is a *separate file* rather than a
section: `<slug>.md` still goes through ordinary read-modify-write (the coach
and Omvision need to edit `## Tasks` and `## Coaching` freely, which append-only
can't do), but because the log isn't inside that file, a stale-copy rewrite of
`<slug>.md` can never lose a log entry — there's no log entry in it to lose.

## 3. Slugs

A slug is derived from a goal's title once, when the goal is created, and then
fixed for the life of the goal — it's a filename, not a display value, so it
must not change out from under the log and journal paths that were derived from
it.

Derivation:

1. Lowercase the title.
2. Replace every run of characters outside `[a-z0-9]` with a single `-`.
3. Strip leading and trailing `-`.

`"Ship the goal files doc"` → `ship-the-goal-files-doc`. `"λi: rethink Q3"` →
`i-rethink-q3` (the leading `λ` and the `:` both collapse into the surrounding
dash run, which then gets stripped).

If step 3 leaves nothing — a title that's all punctuation or non-ASCII, e.g.
`"???"` — fall back to `goal`.

**Collisions.** Before writing a new goal, the creator (Omvision, or the coach
when it creates a goal) checks whether `<slug>.md` already exists. If it does
and its `title:` front-matter matches the title being created, treat it as the
same goal (no collision — this makes goal creation idempotent under retries).
If it exists with a *different* title, the slug is taken by someone else's
goal: append `-2`, then `-3`, and so on, to the derived slug until an unused one
is found. `"Deep work"` and a later, unrelated `"Deep work"` become
`deep-work` and `deep-work-2`.

## 4. Log entry grammar

`<slug>.log.md` is a flat sequence of entries, newest at the bottom (append-only
means append at the end, not sorted). Two entry shapes, both headed by a `###`
line starting with the same timestamp format and separated from the previous
entry by a blank line.

**Pomodoro entry** — written by `ompom` when a focus run ends:

```
### 20 Sep 14:25 · 25m
focus: Wire the goal picker into the IPC
done: status call wired through the IPC
left: picker still caches the list on load
else: kept getting pulled into Slack, worth guarding the next run
```

Heading: `### <D Mon HH:MM> · <N>m` — day of month with no leading zero,
three-letter month, 24-hour clock, then the pomodoro's length in minutes.
Body: a `focus:` line (what the run was for, captured at `intent`), then
`done:`, `left:` and `else:` lines captured at break time. `done:` and `left:`
are each optional — omit the line entirely if the field was left blank, don't
write it empty.

`else:` is the break screen's open question ("What else?"), and is written
**only when it was answered**. Every entry written before this line existed is
still valid, and a reader that doesn't know the key sees the three-line body it
always saw. Like `done:` and `left:`, it is a note and never task state.

**`done:` and `left:` are notes, not task state.** Finishing a pomodoro never
ticks a task off in `<slug>.md`. A reader that auto-completes a task because its
text showed up next to `done:` is misreading the contract — task completion is
an explicit action in Omvision's `## Tasks` UI (M3/O3), never a side effect of
the timer. The log is a diary; `<slug>.md` is the state.

**Event entry** — written by `ompom` or, later, Omvision for anything logged
outside the timer (training, a meeting, a reading session):

```
### 20 Sep 09:00 · event · training · 1h30
Bouldering — legs dead, head clear
```

Heading: `### <D Mon HH:MM> · event · <kind> · <duration>` — same timestamp,
then the literal word `event`, a free-text `kind`, then a duration. Body: one
free-text line, no `key:` prefix.

**Duration formatting**, used in both the pomodoro heading's `<N>m` and the
event heading's `<duration>`: minutes under 60 are `<n>m` (`25m`); 60 and over
are `<h>h` (`1h`) or `<h>h<mm>` with the leftover minutes zero-padded to two
digits and no trailing `m` (`1h30`, not `1h30m`). Ninety minutes is `1h30`;
exactly two hours is `2h`. This rule isn't spelled out anywhere upstream of this
doc — it's read off the one worked example in the plan (`1h30` for 90 minutes)
and generalized; any log writer should reuse it as-is so headings don't diverge
in style across writers.

## 5. `notes-helper.py` CLI contract

Same invocation discipline as today: `["/usr/bin/python3", <resolved path>,
<subcommand>, ...]`, called directly, never through a shell. Same fd walk —
every directory from `$HOME` down is opened `O_NOFOLLOW` via its already-open
parent, and every read/write/rename after that walk goes through those fds. Same
20 000-byte input ceiling on anything read from stdin.

Exit codes are uniform across every subcommand: **2** for a usage error (wrong
argv shape, an invalid slug, or an entry that cannot be parsed into the
grammar above — the caller's bug, and nothing is written); **1** for an
`OSError` raised while walking or opening the fixed directories
(`~/Notes/Omvision/goals`, `~/Notes/Omvision/days`, `~/.local/state/omvision`)
— something is wrong with the machine, not the input; **0** otherwise.

A malformed entry deliberately does **not** collapse into success. A pomodoro's
worth of writing is real content, not nothing — a dropped entry that reports
success is the same class of silent loss the two-file split above exists to
prevent, so `append-log` and `append-day` refuse loudly and write nothing on a
bad entry. **A note now has only one home.** There is no second copy anywhere
else it might have landed instead, so a refused append means the text only
ever existed in the caller's memory: the caller (ompom's overlay) must hold
onto what the user typed and let them retry or copy it out by hand, because
this helper will not have written it anywhere.

A goal slug that arrives as an argument (`append-log <slug>`) is validated
against the same `[a-z0-9-]+` pattern slugs are derived under (§3) before it
touches the filesystem. This isn't just tidiness — it's the same discipline the
rest of the script applies to every path component: a slug is about to become a
filename opened relative to an already-validated directory fd, so a slug that
doesn't match the pattern (empty, containing `/` or `..`, whatever) is rejected
outright — exit 2, nothing opened, nothing written. It can never be used to
escape `goals/` the way a symlink component could, because it's never allowed
to look like anything but a bare filename fragment.

### `list-goals`

No stdin. Walks `~/Notes/Omvision/goals/`, opening only `*.md` files that are
not `*.log.md`, and parses each one's front matter (§6). Prints one JSON array
to stdout, sorted by slug:

```json
[
  {"slug": "deep-work-book", "title": "Finish the deep work book"},
  {"slug": "ship-goal-files-doc", "title": "Ship the goal files doc"}
]
```

A file that fails to parse (§6) is left out of the array, not treated as an
error — `list-goals` always exits 0 and prints `[]` if the directory doesn't
exist yet or nothing parses. Only a directory-fd-walk failure (e.g. `Notes` is
a file, not a directory) is a 1.

### `append-log <slug>`

Stdin: one JSON object, UTF-8, under the same 20 000-byte cap used throughout
this contract. Two shapes, told apart by which of `focus`/`kind` is present —
an object with both or neither is malformed and dropped.

Pomodoro shape:

```json
{"started": "2026-09-20T14:25:00", "minutes": 25,
 "focus": "Wire the goal picker into the IPC",
 "done": "status call wired through the IPC",
 "left": "picker still caches the list on load"}
```

`started`, `minutes`, and `focus` are required; `done` and `left` are optional
strings (omit the key, or send `""`, and the corresponding line is left out of
the written entry — see §4). `started` is a local-time ISO-8601 timestamp; the
helper reformats it into the heading's `<D Mon HH:MM>`, it does not use
wall-clock "now", so a delayed write (e.g. the process was slow to spawn)
doesn't skew the logged time.

Event shape:

```json
{"started": "2026-09-20T09:00:00", "minutes": 90,
 "kind": "training", "title": "Bouldering — legs dead, head clear"}
```

`started`, `minutes`, `kind` are required; `title` is the event's one free-text
body line (§4) — the name is inherited from the plan's own field list and reads
oddly next to a goal's `title:`, but it means the same thing "a `## Coaching`
entry's prose" means: the text a human wrote, not a structured field.

Writes with `O_APPEND` directly to `<slug>.log.md` under the goals directory fd
— no read-back (§2). If `<slug>.log.md` doesn't exist yet it's created
(`O_CREAT`); the file is otherwise never truncated or rewritten by this
subcommand.

### `append-day`

Stdin: one JSON object, exactly the same two shapes, same 20 000-byte cap, and
same required/optional fields as `append-log` (above) — `append-day` reuses
the same entry parser and the same formatted-block builder, so a pomodoro or
event logged with no active goal reads identically to one logged against a
goal. The only difference is where it lands and how that destination is
chosen.

No `<slug>` argument. Instead, the destination filename is derived from the
entry's own `started` field: reformat it to `YYYY-MM-DD` and append `.md`. This
is a **local-day** computation on the timestamp the caller sent, never on
wall-clock "now" — a pomodoro started at 23:50 and logged a few seconds after
midnight still lands in *that day's* file, not the next one, because the run
belongs to the day it was started, not the day the helper process happened to
run.

Writes with `O_APPEND` directly to `~/Notes/Omvision/days/<that day>.md` under
a directory fd for `~/Notes/Omvision/days/` — no read-back, same discipline as
`append-log`, for the same reason: nothing else in this contract ever rewrites
a day file wholesale, so there is no concurrent read-modify-write for an
append to lose a race against, but the append-only discipline is applied
uniformly rather than relied on as an accident of there being only one writer
today. If `<that day>.md` doesn't exist yet it's created (`O_CREAT`); the file
is otherwise never truncated or rewritten by this subcommand.

### `read-active` / `write-active`

Back `~/.local/state/omvision/active-goal`: a tiny marker file under the state
dir fd, read with `read_capped()`.

`read-active` — no stdin. Prints the active slug as a bare line to stdout, no
JSON wrapper (it's a single scalar). Prints nothing (empty stdout) if the file
doesn't exist or is empty — "no active goal" and "file missing" are the same
state, not an error. Always exits 0.

`write-active` — reads the new slug from stdin rather than argv (no shell to
reinterpret an argument, no length limit to negotiate). An empty stdin clears
the active goal (writes an empty file — this is the "slug, or empty" state the
plan's layout comment calls out). A non-empty value is validated against the
slug pattern (§3) before being written; anything that fails validation is
dropped as a no-op, same as a malformed `append-log` entry. Written with
`write_atomic()` — this file has exactly one writer class (the goal picker,
whether that's ompom's overlay or Omvision), so the ordinary RMW pattern is
fine here; §2's argument is specifically about two *independent* writers on the
same file, which doesn't apply to a marker only ever set by "the user picked a
goal."

## 6. Parsing rules

Every reader of these files — `list-goals`, Omvision, the coach skill — has to
tolerate the same set of imperfections, because any of the three writers can
leave a file in a slightly-off state (a half-finished manual edit, a tool that
normalizes line endings, a goal created before its first task) and none of that
should be fatal.

- **No front matter, or front matter that doesn't parse → skip the whole
  file.** Front matter here is intentionally a restricted subset of YAML: a
  `---` line, one `key: value` pair per line, a closing `---` line, no nested
  structures, no multi-line values. That restriction is what lets every reader
  parse it with plain string splitting instead of pulling in a YAML library —
  consistent with `notes-helper.py` having zero non-stdlib imports today. A
  file that doesn't fit this shape (front matter never closes, a value spans
  multiple lines, no `---` at all) is not a goal file as far as this contract
  is concerned; skip it and move on. This is the same posture `write_atomic()`
  and friends already take toward anything that isn't a plain file where one is
  expected — leave it alone, drop the operation, don't guess.
- **Missing `title` → skip the file.** `list-goals` can't report a goal with no
  name, and nothing downstream should either.
- **Missing `status` → treat as `active`.** A goal file hand-written for
  testing (as M1's acceptance step does) won't necessarily set every field.
- **Missing `estimate` / `done_by` → simply absent**, not an error and not a
  zero. Downstream JSON just omits the key.
- **`estimate` is poms *remaining*, not the goal's total.** It answers "how much
  is still left", it shrinks as the work is done, and it should equal the sum of
  the open tasks' `≈N` markers. The coach rewrites it at the end of a session —
  that is what `estimate: 6   # was 9 — session 2` means. A reader therefore
  **displays it directly** and must never subtract completed pomodoros from it:
  doing that double-counts the work and reports a goal as nearly finished the
  moment it is started. This was ambiguous in the first draft of this contract
  and the two apps implemented it differently; if you find code doing
  `estimate - pomsDone`, that code is wrong, not this line.
- **Unknown front-matter keys → preserved, ignored.** A future Omvision field
  a reader doesn't know about yet must not make the file unparseable — this is
  what lets the two apps ship out of step with each other.
- **CRLF line endings → normalize before matching.** Front-matter delimiters,
  `## Tasks`/`## Coaching` headings, and log entry `###` headings are all
  matched against line content; a reader must strip a trailing `\r` (or
  normalize `\r\n` → `\n` up front) before comparing, since any editor touching
  these files on a non-Linux machine can introduce CRLF.
- **Trailing whitespace → ignore.** Don't let trailing spaces on a heading or
  key line break a match.
- **No `## Tasks` section yet → zero tasks, not an error.** A goal the coach
  just created before its first session, or one hand-written for testing, may
  have front matter and nothing else. Same for `## Coaching` before any
  session has run.
- **Log file missing or empty → zero entries**, not an error. A brand-new goal
  has no `<slug>.log.md` until the first pomodoro or event lands. The same
  applies to a day file — a day with no pom run with no active goal has no
  `days/YYYY-MM-DD.md` at all.

## 7. Conventions Omvision adds

These are not part of the grammar above. They are things Omvision writes that a
reader will meet in the wild, recorded here so nobody treats them as corruption or
"helpfully" strips them. Both rely on §6's tolerance rule: an unrecognised token in
free text is just text, and an unknown `##` section is left alone.

- **`[+time] ` prefixing an event's body line.** Set when the user ticked "counts
  toward goal time" on an event, so a meeting or a reading session can be folded
  into the goal's invested-time figure. There is no field for this in the grammar
  and it deliberately stays out of it: a reader that doesn't know the marker shows
  it as part of the line, which is untidy but harmless, and it never touches the
  pomodoro count or the estimate. Omvision strips it for display.
- **A `## Cancelled` section** appended to `<slug>.md` when a goal is cancelled,
  holding the reason and the "what do you take from it" line. It is its own heading
  rather than an entry under `## Coaching`, because it is not a coaching session and
  must not be parsed as one.

The mockups showed a cancelled goal moving to `goals/archive/`. That is **not**
implemented and is not part of this contract: `status: cancelled` in place is what
the status filters already read, and a second location would mean two places to look
for the same goal. If archiving is ever wanted, it needs a contract change here
first, not a directory someone invents at write time.

## 8. Retired paths

Earlier drafts of ompom-engine wrote notes to a single fixed daily file with a
rollover: `~/Notes/Ompom/today/ompom.md` held the running day, and a
`save-note` subcommand rolled the previous day's file into
`~/Notes/Ompom/grave/YYYY-MM-DD.md` when a marker at
`~/.local/state/ompom/notes-day` showed the date had changed. That mechanism,
and the `save-note` subcommand that owned it, are **retired** now that a
pomodoro note has exactly one home (§1): the goal's log if a goal is set,
`~/Notes/Omvision/days/YYYY-MM-DD.md` if not. `notes-helper.py` no longer
reads or writes any of `~/Notes/Ompom/today/`, `~/Notes/Ompom/grave/`, or
`~/.local/state/ompom/` — those paths, and whatever they still contain, are
left exactly as they were. This is deliberate: existing `today/ompom.md` and
`grave/*.md` files are the user's real notes history and stay on disk
untouched, they're just no longer written to or read by this contract. Nothing
in Omvision or the coach skill should read them either — they predate the
goals layer and have nothing to do with it.

## Worked example

A goal two pomodoros and one training session into its life:

`~/Notes/Omvision/goals/ship-goal-files-doc.md`:

```markdown
---
title: Ship the goal files doc
why: Blocks every other milestone — Omvision and the coach skill can't start without it.
status: active
estimate: 3
done_by: 2026-09-21
---
## Tasks
- [x] Read the plan and notes-helper.py
- [ ] Write docs/goal-files.md   ≈2
- [ ] Get it reviewed   ≈1

## Coaching
### Session 1 · 19 Sep · Pólya
What's the actual blocker? — Nothing's blocked, it just hasn't been written yet.
Smallest next step: read the plan's Milestone 0 section end to end before writing anything.
```

`~/Notes/Omvision/goals/ship-goal-files-doc.log.md`:

```markdown
### 19 Sep 16:10 · 25m
focus: Read the plan and notes-helper.py
done: read both start to finish, understand the two-file split
left: haven't started writing yet

### 20 Sep 09:00 · event · training · 1h30
Bouldering — legs dead, head clear

### 20 Sep 14:25 · 25m
focus: Write docs/goal-files.md
left: still drafting the parsing-rules section
```

`~/Notes/Omvision/goals/ship-goal-files-doc/journal/2026-09-20.md` — free-form,
owned entirely by Omvision (M3/O5, not built yet); this contract fixes only its
path, one file per calendar day under the goal's own `journal/` subdirectory.
The coach reads whatever's in it for the date range since its last session and
must tolerate arbitrary markdown, same as any other reader here.

`~/.local/state/omvision/active-goal`:

```
ship-goal-files-doc
```
