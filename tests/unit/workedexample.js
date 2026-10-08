.pragma library

// The worked example from docs/goal-files.md, as the
// exact bytes of each file. Kept here as JS strings because qmltestrunner
// can't read files from a test (QML's XMLHttpRequest refuses local files
// unless an environment switch is set, and is asynchronous anyway).
// bin/test checks these against the contract on every run, so a change to
// the contract's example can't leave the golden tests testing an old one.
// One JSON string per line: that is what bin/test parses.

var goal = "---\ntitle: Ship the goal files doc\nwhy: Blocks every other milestone — Omvision and the coach skill can't start without it.\nstatus: active\nestimate: 3\ndone_by: 2026-09-21\n---\n## Tasks\n- [x] Read the plan and notes-helper.py\n- [ ] Write docs/goal-files.md   ≈2\n- [ ] Get it reviewed   ≈1\n\n## Coaching\n### Session 1 · 19 Sep · Pólya\nWhat's the actual blocker? — Nothing's blocked, it just hasn't been written yet.\nSmallest next step: read the plan's Milestone 0 section end to end before writing anything.\n"

var log = "### 19 Sep 16:10 · 25m\nfocus: Read the plan and notes-helper.py\ndone: read both start to finish, understand the two-file split\nleft: haven't started writing yet\n\n### 20 Sep 09:00 · event · training · 1h30\nBouldering — legs dead, head clear\n\n### 20 Sep 14:25 · 25m\nfocus: Write docs/goal-files.md\nleft: still drafting the parsing-rules section\n"
