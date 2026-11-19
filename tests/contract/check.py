#!/usr/bin/python3 -I
"""Runs tests/contract/cases.json against notes-helper.py.

The same cases run against Parser.js and Writer.js in
tests/unit/tst_contract.qml, so the helper and the app can't drift apart
on goal-files.md without one side failing. The helper is loaded as a
module rather than run as a program: list-goals and the appends only
reach these functions through real files, and what's checked here is the
grammar, not the file handling.

Prints `PASS <section>: <name>` or `FAIL ...` per case, then
`DONE <passed> passed, <failed> failed`, and exits 1 on any failure.
bin/test runs it with the unit layer.
"""
import datetime
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

spec = importlib.util.spec_from_file_location(
    "notes_helper", os.path.join(ROOT, "plugins", "ompom.engine", "notes-helper.py"))
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

with open(os.path.join(HERE, "cases.json"), encoding="utf-8") as f:
    cases = json.load(f)

failed = passed = 0


def check(section, name, got, want):
    global failed, passed
    if got == want:
        passed += 1
        print(f"PASS {section}: {name}")
    else:
        failed += 1
        print(f"FAIL {section}: {name}: got {got!r}, expected {want!r}")


for c in cases["focusable"]:
    check("focusable", c["name"], helper.is_focusable(c["raw"]), c["focusable"])

for c in cases["goalFiles"]:
    fields = helper.parse_front_matter(c["text"])
    got = None if fields is None else {
        "title": fields.get("title"),
        "status": fields.get("status"),
        "focusable": helper.is_focusable(fields.get("focusable")),
    }
    check("goalFiles", c["name"], got, c["goal"])

for section in ("pomodoros", "events"):
    for c in cases[section]:
        check(section, c["name"], helper.build_log_entry(c["payload"]).decode("utf-8"), c["text"])

# The bar's week (notes-helper.py recent) reads back what the helper writes:
# every pomodoro case counted under its id with its minutes, no event, and a
# re-saved id (readers keep the last entry) counted once.
for c in cases["pomodoros"]:
    runs = {}
    helper.runs_in(c["text"], runs)
    check("recent", c["name"], runs, {c["payload"]["started"]: int(c["payload"]["minutes"])})
for c in cases["events"]:
    runs = {}
    helper.runs_in(c["text"], runs)
    check("recent", c["name"], runs, {})
resaved = {}
first, again = ({"started": "2026-11-14T09:00:00", "minutes": m} for m in (25, 65))
helper.runs_in("".join(helper.build_log_entry(p).decode("utf-8") for p in (first, again)), resaved)
check("recent", "a re-saved id counts once, with its last minutes", resaved, {"2026-11-14T09:00:00": 65})

# The week itself: runs bucketed by the day of their id, from a goal log and
# a day file, the window's oldest day first, a run outside it left out.
with tempfile.TemporaryDirectory() as tmp:
    for d in ("goals", "days"):
        os.mkdir(os.path.join(tmp, d))
    def entry(started, minutes):
        return helper.build_log_entry({"started": started, "minutes": minutes})
    with open(os.path.join(tmp, "goals", "g.log.md"), "wb") as f:
        f.write(entry("2026-11-13T09:00:00", 25) + entry("2026-11-19T09:00:00", 50))
    with open(os.path.join(tmp, "days", "2026-11-19.md"), "wb") as f:
        f.write(entry("2026-11-19T14:00:00", 25))
    goals_fd = os.open(os.path.join(tmp, "goals"), os.O_RDONLY | os.O_DIRECTORY)
    days_fd = os.open(os.path.join(tmp, "days"), os.O_RDONLY | os.O_DIRECTORY)
    try:
        week = helper.handle_recent(goals_fd, days_fd, datetime.date(2026, 11, 19))
    finally:
        os.close(goals_fd)
        os.close(days_fd)
    check("recent", "seven days, oldest first", [d["day"] for d in week][::6], ["2026-11-13", "2026-11-19"])
    check("recent", "the first day of the window counted", week[0], {"day": "2026-11-13", "runs": 1, "minutes": 25})
    check("recent", "today sums goal and day runs", week[-1], {"day": "2026-11-19", "runs": 2, "minutes": 75})
    check("recent", "a quiet day is zero", week[3], {"day": "2026-11-16", "runs": 0, "minutes": 0})

print(f"DONE {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
