# Testing

`bin/test` runs everything, offscreen, in about 15 seconds. No window opens and
nothing under `~/Notes` is read or written.

```bash
bin/test                    # both layers
bin/test unit               # Writer.js and Parser.js only (under a second)
bin/test app                # the whole-app tests only
bin/test app tasks          # one file: tests/app/tst_tasks.qml
bin/test app tasks test_add_a_task
bin/test -v                 # the runners' full output
bin/test -k                 # keep every app run's temp dir, not only failed ones
```

It exits non-zero if a test fails, a known failure starts passing, an app run times out
(`OMVISION_TEST_TIMEOUT`, default 120s) or crashes, or the worked-example fixture has
drifted from the file contract.

## Layer 1: `tests/unit`

Plain Qt `TestCase` files that import `Writer.js` and `Parser.js` directly, run by Qt's
own runner: `qmltestrunner -platform offscreen -input tests/unit`.

- `tst_writer.qml` is golden tests of every Writer edit. Each states the whole expected
  file, since Writer promises that everything it was not asked to change survives byte for
  byte. Every edit is run with CRLF endings, unknown front-matter keys and blank lines, and
  on files that are not goal files, where it must return null.
- `tst_parser.qml` covers goal files, tasks, coaching, log entries (`else:`, dedupe, year
  wrap, the `[+time]` marker), `estimate:` as poms *left*, and the small formatters.
- `workedexample.js` is the worked example from `~/Code/ompom-engine/docs/goal-files.md`,
  as JS strings (a test can't read files). bin/test checks it against the contract on
  every run.

## Layer 2: `tests/app`

The real app, driven from inside. `omvision.qml` has a test hook: when `OMVISION_TEST`
names a `.qml` file, a Loader beside the screenshot driver's loads it and hands it `app`,
`journal`, `goalDetail`, `coaching`, `target` (the window's content item) and `window`.
bin/test starts the app once per `tests/app/tst_*.qml` through `bin/omvision`, with a fresh
temp HOME seeded from `tests/fixtures/home`.

A test file is an `OmvisionTest` (`tests/app/OmvisionTest.qml`), which is a Qt `TestCase`
with these helpers. Each one waits by itself and fails with what it last saw:

| helper | does |
|---|---|
| `openGoal(slug)` | clicks the goal's row on the Goals screen, waits for its detail |
| `click(name)` | hovers the item, waits until it can be clicked, clicks its centre |
| `item(name)` | the visible item with that name, once it appears |
| `type(text)`, `key(k, mods)` | real key events to the focused item |
| `readFile(rel)` | a file under `$HOME/Notes/Omvision`, or null |
| `expectFile(rel, want)` | waits until the file says `want` (a string, or a predicate) |
| `expectFileUnchanged(rel, ms)` | the file stays as the fixture left it for `ms` |
| `fixtureText(rel)` | what the fixture put there |

The usual `compare`, `verify`, `tryCompare`, `tryVerify`, `mouseClick`, `mouseMove`,
`keyClick` and `wait` work as in any TestCase.

Before every test the fixture files are put back (`tests/app/seed-home.sh`) and the test
waits until the app shows them again, then goes back to the Goals screen. State the app
keeps in memory across screens is not reset: the journal's open day, for instance. A test
that needs the app exactly as it started gets a file of its own and sets
`resetBeforeEachTest: false` (see `tst_journal_blank.qml`).

Each test prints one line, `PASS`, `FAIL` (with the detail, and a screenshot next to the
log), `XFAIL` or `SKIP`, which bin/test collects. A failed run keeps its temp dir: the
app's log, the screenshots and the HOME as the test left it.

### Fixtures

`tests/fixtures/home` is a HOME: one goal (`write-the-report`, three tasks, the first
done), its log, and a journal entry. `journal/TODAY.md` is installed under today's date,
so the journal opens on it. Nothing in it comes from the real notes. The theme file is
absent, so the app runs on the Flexoki fallback.

`seed-home.sh` refuses any target that is not under the temp dir, or that lacks the
`.omvision-test-home` marker bin/test creates. It deletes whatever a test added under
`Notes/Omvision`, and it must never do that to a real home.

### Finding controls

`click()` and `item()` look items up by `objectName`. These names are meant to sit on
the controls, and a refactor must keep them:

| objectName | control |
|---|---|
| `goalRow:<slug>`, `goalEdit:<slug>` | a Goals row, its pencil |
| `taskRow:<i>`, `taskEdit:<i>`, `taskEditField:<i>` | a task row, its pencil, its inline edit |
| `addTaskButton`, `addTaskField` | `+ task` and its input |
| `closeGoalButton`, `reopenGoalButton`, `cancelGoalButton` | the goal's close, reopen and cancel |
| `addEventButton`, `coachButton`, `editGoalButton` | the detail header's actions |
| `journalEditor` | the journal's page |

Until those `objectName`s are in `GoalDetailScreen.qml` and `GoalsScreen.qml`,
`OmvisionTest.locate()` finds each item by its label or its delegate's properties
instead. Once they land, `locate()` goes unused and can be deleted.

### The `qtest_results` workaround

A `TestCase` reports every assertion through an internal object, `qtest_results`. By
default that is a `TestResult`, which logs through QtTest's C++ logger. qmltestrunner
sets that logger up and `qs` doesn't. `OmvisionTest` points the property at a small
stand-in that records failures, and it runs the test functions itself, since Qt's own
scheduler drives the logger at every step. It borrows the real `TestResult` only for
`wait()`. All of this is private Qt API (`QtTest/TestCase.qml`, Qt 6.11), and it lives in
`OmvisionTest.qml` alone, so a Qt upgrade that changes it breaks only that file.

## Known failures

Bugs a test has found but that aren't fixed yet are pinned with
`expectFailContinue("", "BUG: ...")`. They report as `XFAIL` and don't fail the run. When
one is fixed the assertion passes, which is reported as `XPASS` and fails the run, as a
reminder to remove the `expectFailContinue`. Current ones:

- The Writer task edits (`toggleTask`, `addTask`, `editTask`) ignore missing or
  unterminated front matter. `setStatus` and `updateGoalFields` refuse it.
- `setStatus` edits front matter that Parser rejects (a line that isn't `key: value`).
- `updateGoalFields` can't rename `Fix bug #12` to `Fix bug`: the `# comment` rule meant
  for the coach's estimate applies to every key.
- `buildNewGoalFile` writes an estimate of `0` as `estimate: ` with no value.
- `Parser.parseGoalFile` reads the coach's `estimate: 6   # was 9` as no estimate.

## What the tests don't cover

- How things look: layout, colours, hover fills and the pencil fading in. The tests hover
  only to reach a control. Use `bin/shot` and read the images.
- Compose and input-method typing (fcitx5 preedit). Key events are not the input
  method's events. An offscreen C++ harness reproduced the compose bug. It has not been
  committed yet, and it is out of scope for this suite.
- The journal's kinetic trackpad glide, and anything else about timing and feel.
- Everything that needs a real session: the ompom engine and bar, the live omarchy theme,
  and the user's own notes. Those stay with the user.

## Adding a test

- A change to Writer.js or Parser.js gets a case in `tests/unit`, stated as the whole
  expected file.
- A change to what a click or a key does gets a flow in `tests/app`: act through
  `click`/`type`/`key`, then check the file with `expectFile`, not only the screen.
- Then break the feature on purpose, check that the test fails, and restore it.
