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
any more. This script now owns four things: goal logs, day logs, the
active-goal pointer, and the night overlay's reads and writes of
Omvision's journal.

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
  read-journal <day>      print ~/Notes/Omvision/journal/<day>.md as it
                          is (nothing for a day with no file). Exits 1,
                          printing nothing, for a file it can't read
                          whole -- over MAX_JOURNAL_BYTES, not UTF-8, not
                          a plain file -- since the night page would
                          otherwise save a cut copy back over it.
  write-journal <day>     read {"base", "text"} from stdin and replace the
                          day's journal with `text`, but only if the file
                          still says `base` (what the night page last read
                          or wrote). If it doesn't -- Omvision wrote the
                          day meanwhile -- nothing is written, the file's
                          text goes to stdout, and the exit code is 3, so
                          the engine can merge and try again. A blank
                          `text` deletes the day, as Omvision does with an
                          emptied page. Whole-file and atomic (temp file,
                          rename), not an append: the journal is free
                          text edited anywhere, not a log.

<slug> is validated against a closed character class before it is ever
used as a path component (see SLUG_RE below) -- for append-log that
validation happens before any directory is even opened. <day> likewise
(DAY_RE, and a real calendar date).
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
# A journal day is a few kilobytes; this is far past any real one, and a
# file over it is refused whole rather than read in part (see read-journal).
MAX_JOURNAL_BYTES = 1_000_000
# write-journal's stdin carries the day twice (base and text), JSON-escaped:
# a newline is two bytes there, and a control character six.
MAX_JOURNAL_INPUT_BYTES = 12 * MAX_JOURNAL_BYTES
# write-journal's exit code when the file no longer says `base`.
EXIT_JOURNAL_CHANGED = 3

# The character class alone rules out '/', '.', '..', NUL and uppercase;
# fullmatch pins the check to the whole string, not just a prefix, so
# "ok/../etc" can't sneak past by matching only its first component.
SLUG_RE = re.compile(r"[a-z0-9][a-z0-9-]{0,63}")

ACTIVE_GOAL_NAME = "active-goal"

# Omvision's journal file names (Paths.journalFile): the shape alone keeps
# '/' and '..' out, and valid_day() then wants a real date, so the engine
# can't create a file Omvision's journal would never list.
DAY_RE = re.compile(r"\d{4}-\d\d-\d\d")


def valid_slug(slug):
    return bool(SLUG_RE.fullmatch(slug))


def valid_day(day):
    if not DAY_RE.fullmatch(day):
        return False
    try:
        datetime.date.fromisoformat(day)
    except ValueError:
        return False
    return True


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


def write_atomic(dir_fd, name, data, mode=0o600):
    """Write `data` to `name` under dir_fd via temp-file-then-rename,
    both confined to dir_fd. The destination is never opened for writing
    directly, so a symlink dropped in its place is never followed --
    rename() only ever replaces the directory entry named `name`. The
    file ends up with `mode` exactly (fchmod, not the umask-filtered
    create mode), so a rewrite can keep an existing file's mode."""
    tmp = f".{name}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=dir_fd)
    try:
        os.fchmod(fd, mode)
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
        # §4): a re-save of the same entry -- as the night's notes were,
        # each time their page closed, until the night's page became the
        # journal -- repeats it, and readers keep the last entry
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


class JournalUnreadable(Exception):
    pass


def read_journal_day(journal_fd, name):
    """The day's text, "" for a day with no file. Raises JournalUnreadable
    for anything it can't read whole: the caller would write the page
    back over the file, so a part of it read as all of it would cut the
    rest off for good."""
    data = read_capped(journal_fd, name, MAX_JOURNAL_BYTES)
    if data is None:
        raise JournalUnreadable("not a plain file")
    if len(data) > MAX_JOURNAL_BYTES:
        raise JournalUnreadable(f"over {MAX_JOURNAL_BYTES} bytes")
    try:
        # utf-8-sig: a byte-order mark isn't part of the text. Qt drops it
        # when the engine decodes this output, so a BOM kept here would make
        # every write-journal look like the file changed under it.
        return data.decode("utf-8-sig")
    except UnicodeDecodeError as e:
        raise JournalUnreadable(f"not UTF-8: {e}") from None


def journal_dir_fd(stack):
    home_fd = stack.enter_context(opened(home_dir_fd()))
    notes_fd = stack.enter_context(opened(sub_dir_fd(home_fd, "Notes")))
    omvision_fd = stack.enter_context(opened(sub_dir_fd(notes_fd, "Omvision")))
    return stack.enter_context(opened(sub_dir_fd(omvision_fd, "journal")))


USAGE = """\
usage: notes-helper.py list-goals
       notes-helper.py append-log <slug> < entry.json
       notes-helper.py append-day < entry.json
       notes-helper.py read-active
       notes-helper.py write-active < slug
       notes-helper.py read-journal <YYYY-MM-DD>
       notes-helper.py write-journal <YYYY-MM-DD> < {"base": ..., "text": ...}
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


def cmd_read_journal(day):
    if not valid_day(day):
        print(f"notes-helper: bad day {day!r}", file=sys.stderr)
        return 2

    try:
        with ExitStack() as stack:
            text = read_journal_day(journal_dir_fd(stack), day + ".md")
    except (OSError, JournalUnreadable) as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    sys.stdout.buffer.write(text.encode("utf-8"))
    return 0


# Compare-and-swap rather than a plain overwrite: the night page writes the
# text it was editing, and if Omvision saved the same day in between, that
# save must not vanish under it. The read and the rename aren't one atomic
# step, but the night overlay covers the screen, so Omvision has no one
# typing into it while this runs; the check is for the save it had already
# queued, or a change made from another machine through a synced folder.
def cmd_write_journal(day):
    if not valid_day(day):
        print(f"notes-helper: bad day {day!r}", file=sys.stderr)
        return 2

    raw = sys.stdin.buffer.read(MAX_JOURNAL_INPUT_BYTES + 1)
    try:
        if len(raw) > MAX_JOURNAL_INPUT_BYTES:
            raise ValueError("input too long")
        payload = json.loads(raw.decode("utf-8"))
        base, text = payload["base"], payload["text"]
        if not isinstance(base, str) or not isinstance(text, str):
            raise TypeError("base and text must be strings")
        data = text.encode("utf-8")
        if len(data) > MAX_JOURNAL_BYTES:
            raise ValueError(f"text over {MAX_JOURNAL_BYTES} bytes")
    except (ValueError, KeyError, TypeError) as e:
        print(f"notes-helper: bad journal write: {e}", file=sys.stderr)
        return 2

    name = day + ".md"
    try:
        with ExitStack() as stack:
            journal_fd = journal_dir_fd(stack)
            current = read_journal_day(journal_fd, name)
            if current != base:
                sys.stdout.buffer.write(current.encode("utf-8"))
                return EXIT_JOURNAL_CHANGED
            if text.strip() == "":
                # An emptied page deletes the day, as JournalStore.save()
                # does, so it drops out of Omvision's day list.
                try:
                    os.unlink(name, dir_fd=journal_fd)
                except FileNotFoundError:
                    pass
                return 0
            try:
                mode = stat.S_IMODE(os.stat(name, dir_fd=journal_fd, follow_symlinks=False).st_mode)
            except FileNotFoundError:
                mode = 0o600
            write_atomic(journal_fd, name, data, mode)
    except (OSError, JournalUnreadable) as e:
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
    if len(argv) == 2 and argv[0] == "read-journal":
        return cmd_read_journal(argv[1])
    if len(argv) == 2 and argv[0] == "write-journal":
        return cmd_write_journal(argv[1])

    print(USAGE, file=sys.stderr, end="")
    return 2


if __name__ == "__main__":
    sys.exit(main())
