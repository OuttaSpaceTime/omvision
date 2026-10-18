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
import importlib.util
import json
import os
import sys

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

print(f"DONE {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
