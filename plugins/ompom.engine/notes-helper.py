#!/usr/bin/python3
"""Ompom Engine notes helper.

Engine.qml invokes this as a fixed interpreter/script pair
(["/usr/bin/python3", <this file's own resolved path>, <subcommand>, ...])
-- never through a shell, never resolved via PATH. It owns every
filesystem operation for ompom's notes so it can hold real, validated
directory file descriptors for the whole operation instead of
re-resolving string paths across several separate QML-side FileView/
Process steps -- that gap let an intermediate notes/state directory
swapped for a symlink between two of those steps redirect a read or
write outside ~/Notes/Omvision or ~/.local/state/omvision.

A pomodoro note lives in exactly one place: the active goal's log if a
goal is set (`append-log`), or a day file if not (`append-day`). There
is no daily-notes file with a rollover any more -- that mechanism
(~/Notes/Ompom/today/ompom.md, the ~/Notes/Ompom/grave/ rollover, and
the ~/.local/state/ompom/notes-day marker) has been retired along with
the `save-note` subcommand that owned it. Existing files under those
paths are left on disk as history; nothing here reads or writes them
any more. This script now owns three things: goal logs, day logs, and
the active-goal pointer.

Each directory component from $HOME down is opened with O_NOFOLLOW via
its parent's already-open directory fd (creating it first if missing);
if a component turns out to be anything but a real directory -- a
symlink planted in its place, a stray file -- this aborts rather than
working around it. Every read, write, and rename after that walk is
issued against those fds (dir_fd=), so even if a path component is
replaced by a symlink after the walk, the already-open fd still refers
to the original real directory.

Note and entry text is read from stdin as UTF-8, not argv -- no length
or quoting limit to fight, and no argument for a shell to reinterpret
(there is no shell here regardless).

Subcommands:
  list-goals              walk ~/Notes/Omvision/goals/, print a JSON array
                          of {slug, title, status, focusable} parsed from each goal
                          file's front matter. Runs behind a fullscreen
                          overlay, so a single unparseable/unreadable/
                          non-file entry is skipped, never fatal.
  append-log <slug>       read one JSON entry from stdin, append it to
                          ~/Notes/Omvision/goals/<slug>.log.md. This is
                          deliberately NOT fd-safe-atomic-via-rename: it
                          opens O_APPEND and never reads the file first,
                          because a coaching session may be rewriting
                          <slug>.md concurrently and a read-modify-write
                          here is exactly how a logged pomodoro goes
                          missing.
  append-day              read one JSON entry from stdin, same shapes as
                          append-log, append it to
                          ~/Notes/Omvision/days/YYYY-MM-DD.md -- the date
                          taken from the entry's own `started` field, not
                          wall-clock "now", so a pomodoro that ends after
                          midnight is filed under the day it started.
                          Same O_APPEND, no-read-back discipline as
                          append-log, for the same reason.
  read-active/write-active  the single-line slug (or empty) at
                          ~/.local/state/omvision/active-goal.

<slug> is validated against a closed character class before it is ever
used as a path component (see SLUG_RE below) -- for append-log that
validation happens before any directory is even opened.
"""
import datetime
import json
import os
import re
import stat
import sys
from contextlib import ExitStack, contextmanager

MAX_NOTE_INPUT_BYTES = 20_000
MAX_GOAL_FILE_BYTES = 200_000
MAX_SLUG_BYTES = 128

# The character class alone rules out '/', '.', '..', NUL and uppercase;
# fullmatch pins the check to the whole string, not just a prefix, so
# "ok/../etc" can't sneak past by matching only its first component.
SLUG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")

ACTIVE_GOAL_NAME = "active-goal"


def valid_slug(slug):
    return bool(SLUG_RE.fullmatch(slug))


@contextmanager
def opened(fd):
    try:
        yield fd
    finally:
        os.close(fd)


def home_dir_fd():
    home = os.environ["HOME"]
    return os.open(home, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)


def sub_dir_fd(parent_fd, name):
    """Open `name` under parent_fd as a directory, creating it first if
    missing, and refusing to follow it if it's a symlink. mkdir fails
    with FileExistsError on a pre-planted symlink same as it would on a
    real directory; the O_NOFOLLOW open below is what actually rejects
    the symlink case rather than silently walking into it."""
    try:
        os.mkdir(name, dir_fd=parent_fd)
    except FileExistsError:
        pass
    return os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)


def read_capped(dir_fd, name, cap):
    """Read at most cap+1 bytes of `name` under dir_fd, refusing to
    follow a symlink. A single bounded os.read() call means this never
    pulls more than cap+1 bytes into memory no matter how large the
    underlying file actually is. Returns None if `name` exists but isn't
    a plain file we can open (e.g. a symlink)."""
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=dir_fd)
    except FileNotFoundError:
        return b""
    except OSError:
        return None
    try:
        return os.read(fd, cap + 1)
    finally:
        os.close(fd)


def write_atomic(dir_fd, name, data):
    """Write `data` to `name` under dir_fd via temp-file-then-rename,
    both confined to dir_fd. The destination is never opened for writing
    directly, so a symlink dropped in its place is never followed --
    rename() only ever replaces the directory entry named `name`."""
    tmp = f".{name}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.rename(tmp, name, src_dir_fd=dir_fd, dst_dir_fd=dir_fd)
    except BaseException:
        try:
            os.unlink(tmp, dir_fd=dir_fd)
        except OSError:
            pass
        raise


FRONT_MATTER_LINE = re.compile(r"([A-Za-z0-9_-]+):\s?(.*)")


def parse_front_matter(text):
    """Parse goal-files.md §6's front matter into a flat {key: value}
    dict, or None for a file that isn't a goal file. The rule is
    Parser.js's goalFrontMatter(), line for line, so the break's picker
    lists exactly the goals Omvision's Goals screen does
    (tests/contract/cases.json holds both to it): blank lines may come
    before the opening fence; every line up to the closing one is
    `key: value`, and any other line makes it not a goal file; a repeated
    key's last line wins; and there has to be a non-empty title. A value
    is what follows the colon and at most one space, with trailing
    whitespace dropped."""
    lines = [line.rstrip() for line in text.splitlines()]
    i = 0
    while i < len(lines) and lines[i] == "":
        i += 1
    if i == len(lines) or lines[i] != "---":
        return None
    fields = {}
    for line in lines[i + 1:]:
        if line == "---":
            return fields if fields.get("title") else None
        m = FRONT_MATTER_LINE.fullmatch(line)
        if not m:
            return None
        fields[m.group(1)] = m.group(2)
    return None


def handle_list_goals(goals_fd):
    out = []
    try:
        names = os.listdir(goals_fd)
    except OSError:
        names = []

    for name in sorted(names):
        # Each entry is handled in its own try -- one vanished file, one
        # permission error, one directory sitting where a goal file
        # should be, must never take the rest of the listing down with
        # it. This runs behind a fullscreen overlay with no fallback UI.
        try:
            if not name.endswith(".md"):
                continue
            slug = name[:-len(".md")]
            if not valid_slug(slug):
                continue  # also filters out "<slug>.log.md" -- its "slug"
                          # part contains a literal '.' and never matches
            st = os.stat(name, dir_fd=goals_fd, follow_symlinks=False)
            if not stat.S_ISREG(st.st_mode):
                continue
            content = read_capped(goals_fd, name, MAX_GOAL_FILE_BYTES)
            if content is None or len(content) > MAX_GOAL_FILE_BYTES:
                continue
            fields = parse_front_matter(content.decode("utf-8", "replace"))
            if fields is None:
                continue
            out.append({
                "slug": slug,
                "title": fields.get("title"),
                "status": fields.get("status"),
                "focusable": is_focusable(fields.get("focusable")),
            })
        except OSError:
            continue

    print(json.dumps(out))


def is_focusable(raw):
    # goal-files.md §6: only an explicit no hides a goal from the break's
    # picker, so a missing key or a typo leaves it in. Parser.js's
    # isFocusable() reads it the same way.
    return (raw or "").strip().lower() not in ("no", "false", "off")


def format_duration(minutes):
    """Writer.js's formatDuration(): under an hour `<n>m`, else `<h>h`, or
    `<h>h<mm>` with the minutes padded to two digits, the only form
    Parser.js reads back (`1h1` would be a heading it skips)."""
    minutes = int(minutes)
    if minutes < 60:
        return f"{minutes}m"
    hours, rem = divmod(minutes, 60)
    return f"{hours}h{rem:02d}" if rem else f"{hours}h"


def format_timestamp(started):
    dt = datetime.datetime.fromisoformat(started)
    day = dt.strftime("%d").lstrip("0") or "0"
    return f"{day} {dt.strftime('%b %H:%M')}"


def note_line(key, value):
    """One `key: value` line of a pomodoro body, or "" for a blank answer.
    The break's notes are multi-line (its sections continue lists on
    Return), and a raw newline would end the value: the next line would
    read as body text, or as a key or a `###` heading of its own. So every
    line after the first is indented two spaces, which is how readers know
    it continues the key above (goal-files.md §4). A blank line inside the
    value stays blank: a reader keeps it when an indented line follows."""
    lines = [line.rstrip() for line in str(value).replace("\r\n", "\n").split("\n")]
    while lines and not lines[-1]:
        lines.pop()
    while lines and not lines[0]:
        lines.pop(0)
    if not lines:
        return ""
    rest = "".join("\n" + ("  " + line if line else "") for line in lines[1:])
    return f"{key}: {lines[0]}{rest}\n"


def build_log_entry(payload):
    """Turn one JSON object (a pomodoro or a standalone event) into the
    formatted block append_log_entry() writes. A missing or wrong-typed
    required field raises -- the caller turns that into a clean non-zero
    exit before any file is touched, rather than writing a half-formed
    entry that's worse than no entry at all."""
    ts = format_timestamp(payload["started"])
    dur = format_duration(payload["minutes"])

    kind = payload.get("kind")
    if kind is not None:
        # One body line, as Writer.formatEventEntry() makes it: a newline
        # in the title would start a line §4 doesn't have.
        title = re.sub(r"[\r\n]+", " ", str(payload["title"])).strip()
        header = f"### {ts} · event · {kind} · {dur}\n"
        body = f"{title}\n"
    else:
        # The entry's id is its `started`, to the second (goal-files.md
        # §4): a re-save of the same entry -- the night's notes, every time
        # the page is closed -- repeats it, and readers keep the last entry
        # per id. A key whose answer was left blank is left out, as §4 has
        # always said. `focus` only comes from older engines, which asked
        # for it before every run.
        header = f"### {ts} · {dur}\n"
        body = f"id: {payload['started']}\n" + "".join(
            note_line(key, payload.get(key, "")) for key in ("focus", "done", "left", "else"))

    return (header + body + "\n").encode("utf-8")


def append_entry(dir_fd, name, entry):
    """Append-only, no read-back. O_APPEND set at open time makes each
    write atomic at the kernel level relative to any other appender, so
    two pomodoros logged at the same moment interleave whole entries
    rather than corrupting each other -- and unlike write_atomic() there
    is no read here for a concurrent rewrite of a sibling file (e.g. a
    coaching rewrite of <slug>.md) to race against, so this can never
    lose an entry to that race. Shared by append-log (goal logs) and
    append-day (day logs); both write only under this discipline."""
    fd = os.open(
        name,
        os.O_APPEND | os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW,
        0o600,
        dir_fd=dir_fd,
    )
    with os.fdopen(fd, "ab") as f:
        f.write(entry)
        f.flush()
        os.fsync(f.fileno())


def append_log_entry(goals_fd, slug, entry):
    append_entry(goals_fd, f"{slug}.log.md", entry)


def day_file_name(payload):
    """Derive the day file's name from the entry's own `started` field,
    never from wall-clock "now" -- a pomodoro that ends after midnight
    still belongs to the day it started, the same reasoning
    build_log_entry() already applies to the entry's timestamp."""
    dt = datetime.datetime.fromisoformat(payload["started"])
    return dt.strftime("%Y-%m-%d") + ".md"


def handle_read_active(state_fd):
    content = read_capped(state_fd, ACTIVE_GOAL_NAME, MAX_SLUG_BYTES)
    slug = (content or b"")[:MAX_SLUG_BYTES].decode("utf-8", "replace").strip()
    print(slug)


USAGE = """\
usage: notes-helper.py list-goals
       notes-helper.py append-log <slug> < entry.json
       notes-helper.py append-day < entry.json
       notes-helper.py read-active
       notes-helper.py write-active < slug
"""


def cmd_list_goals():
    try:
        with ExitStack() as stack:
            home_fd = stack.enter_context(opened(home_dir_fd()))
            notes_fd = stack.enter_context(opened(sub_dir_fd(home_fd, "Notes")))
            omvision_fd = stack.enter_context(opened(sub_dir_fd(notes_fd, "Omvision")))
            goals_fd = stack.enter_context(opened(sub_dir_fd(omvision_fd, "goals")))

            handle_list_goals(goals_fd)
    except OSError as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    return 0


def cmd_append_log(slug):
    # Validated before any directory is opened, let alone one named with
    # it -- an invalid slug must never reach the filesystem at all.
    if not valid_slug(slug):
        print(f"notes-helper: bad slug {slug!r}", file=sys.stderr)
        return 2

    raw = sys.stdin.buffer.read(MAX_NOTE_INPUT_BYTES + 1)
    try:
        payload = json.loads(raw[:MAX_NOTE_INPUT_BYTES].decode("utf-8", "replace"))
        entry = build_log_entry(payload)
    except (ValueError, KeyError, TypeError) as e:
        print(f"notes-helper: bad entry: {e}", file=sys.stderr)
        return 2

    try:
        with ExitStack() as stack:
            home_fd = stack.enter_context(opened(home_dir_fd()))
            notes_fd = stack.enter_context(opened(sub_dir_fd(home_fd, "Notes")))
            omvision_fd = stack.enter_context(opened(sub_dir_fd(notes_fd, "Omvision")))
            goals_fd = stack.enter_context(opened(sub_dir_fd(omvision_fd, "goals")))

            append_log_entry(goals_fd, slug, entry)
    except OSError as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    return 0


def cmd_append_day():
    raw = sys.stdin.buffer.read(MAX_NOTE_INPUT_BYTES + 1)
    try:
        payload = json.loads(raw[:MAX_NOTE_INPUT_BYTES].decode("utf-8", "replace"))
        entry = build_log_entry(payload)
        name = day_file_name(payload)
    except (ValueError, KeyError, TypeError) as e:
        print(f"notes-helper: bad entry: {e}", file=sys.stderr)
        return 2

    try:
        with ExitStack() as stack:
            home_fd = stack.enter_context(opened(home_dir_fd()))
            notes_fd = stack.enter_context(opened(sub_dir_fd(home_fd, "Notes")))
            omvision_fd = stack.enter_context(opened(sub_dir_fd(notes_fd, "Omvision")))
            days_fd = stack.enter_context(opened(sub_dir_fd(omvision_fd, "days")))

            append_entry(days_fd, name, entry)
    except OSError as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    return 0


def cmd_read_active():
    try:
        with ExitStack() as stack:
            home_fd = stack.enter_context(opened(home_dir_fd()))
            local_fd = stack.enter_context(opened(sub_dir_fd(home_fd, ".local")))
            state_root_fd = stack.enter_context(opened(sub_dir_fd(local_fd, "state")))
            omvision_state_fd = stack.enter_context(opened(sub_dir_fd(state_root_fd, "omvision")))

            handle_read_active(omvision_state_fd)
    except OSError as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    return 0


def cmd_write_active():
    raw = sys.stdin.buffer.read(MAX_SLUG_BYTES + 1)
    slug = raw[:MAX_SLUG_BYTES].decode("utf-8", "replace").strip()
    if slug and not valid_slug(slug):
        print(f"notes-helper: bad slug {slug!r}", file=sys.stderr)
        return 2

    try:
        with ExitStack() as stack:
            home_fd = stack.enter_context(opened(home_dir_fd()))
            local_fd = stack.enter_context(opened(sub_dir_fd(home_fd, ".local")))
            state_root_fd = stack.enter_context(opened(sub_dir_fd(local_fd, "state")))
            omvision_state_fd = stack.enter_context(opened(sub_dir_fd(state_root_fd, "omvision")))

            write_atomic(omvision_state_fd, ACTIVE_GOAL_NAME, (slug + "\n").encode("utf-8"))
    except OSError as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    return 0


def main():
    argv = sys.argv[1:]

    if len(argv) == 1 and argv[0] == "list-goals":
        return cmd_list_goals()
    if len(argv) == 2 and argv[0] == "append-log":
        return cmd_append_log(argv[1])
    if len(argv) == 1 and argv[0] == "append-day":
        return cmd_append_day()
    if len(argv) == 1 and argv[0] == "read-active":
        return cmd_read_active()
    if len(argv) == 1 and argv[0] == "write-active":
        return cmd_write_active()

    print(USAGE, file=sys.stderr, end="")
    return 2


if __name__ == "__main__":
    sys.exit(main())
