#!/usr/bin/python3
"""Ompom Engine notes helper.

Service.qml invokes this as a fixed interpreter/script pair
(["/usr/bin/python3", <this file's own resolved path>, "save-note"]) --
never through a shell, never resolved via PATH. It owns every filesystem
operation for the "save note" flow so it can hold real, validated
directory file descriptors for the whole operation instead of
re-resolving string paths across several separate QML-side FileView/
Process steps -- that gap let an intermediate notes/state directory
swapped for a symlink between two of those steps redirect a read, write,
or rollover move outside ~/Notes/Ompom or ~/.local/state/ompom.

Each directory component from $HOME down is opened with O_NOFOLLOW via
its parent's already-open directory fd (creating it first if missing);
if a component turns out to be anything but a real directory -- a
symlink planted in its place, a stray file -- this aborts rather than
working around it. Every read, write, and rename after that walk is
issued against those fds (dir_fd=), so even if a path component is
replaced by a symlink after the walk, the already-open fd still refers
to the original real directory.

The note text is read from stdin as UTF-8, not argv -- no length or
quoting limit to fight, and no argument for a shell to reinterpret
(there is no shell here regardless). Exit code is purely informational;
the caller treats the save as best-effort either way.
"""
import os
import re
import sys
import time
from contextlib import ExitStack, contextmanager

MAX_NOTE_INPUT_BYTES = 20_000
MAX_TODAY_FILE_BYTES = 2_000_000
MAX_MARKER_BYTES = 32
DAY_MARKER_RE = re.compile(rb"^\d{4}-\d{2}-\d{2}$")

TODAY_NAME = "ompom.md"
MARKER_NAME = "notes-day"


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


def handle_save(today_fd, grave_fd, state_fd, note):
    marker = (read_capped(state_fd, MARKER_NAME, MAX_MARKER_BYTES) or b"").strip()
    today = time.strftime("%Y-%m-%d")

    # Only a marker in the exact format this engine itself ever writes is
    # ever used, and only to pick a filename inside the already-validated
    # grave_fd -- never concatenated into a path string. Anything else
    # (corrupted file, path separators, "..") just skips rollover.
    if marker and marker != today.encode() and DAY_MARKER_RE.match(marker):
        try:
            os.rename(TODAY_NAME, marker.decode() + ".md", src_dir_fd=today_fd, dst_dir_fd=grave_fd)
        except FileNotFoundError:
            pass  # nothing to roll over yet -- harmless, same as before

    existing = read_capped(today_fd, TODAY_NAME, MAX_TODAY_FILE_BYTES)
    if existing is None or len(existing) > MAX_TODAY_FILE_BYTES:
        # Not a plain file where we expect one, or already oversized --
        # leave it completely untouched and drop this note rather than
        # truncate or guess.
        return

    stamp = time.strftime("%Y-%m-%d %H:%M")
    block = f"## {stamp}\n\n{note}\n\n".encode("utf-8")
    write_atomic(today_fd, TODAY_NAME, existing + block)
    write_atomic(state_fd, MARKER_NAME, today.encode())


def main():
    if len(sys.argv) != 2 or sys.argv[1] != "save-note":
        print("usage: notes-helper.py save-note < note-text", file=sys.stderr)
        return 2

    raw = sys.stdin.buffer.read(MAX_NOTE_INPUT_BYTES + 1)
    note = raw[:MAX_NOTE_INPUT_BYTES].decode("utf-8", "replace").strip()
    if not note:
        return 0

    try:
        with ExitStack() as stack:
            home_fd = stack.enter_context(opened(home_dir_fd()))
            notes_fd = stack.enter_context(opened(sub_dir_fd(home_fd, "Notes")))
            ompom_fd = stack.enter_context(opened(sub_dir_fd(notes_fd, "Ompom")))
            today_fd = stack.enter_context(opened(sub_dir_fd(ompom_fd, "today")))
            grave_fd = stack.enter_context(opened(sub_dir_fd(ompom_fd, "grave")))
            local_fd = stack.enter_context(opened(sub_dir_fd(home_fd, ".local")))
            state_root_fd = stack.enter_context(opened(sub_dir_fd(local_fd, "state")))
            state_fd = stack.enter_context(opened(sub_dir_fd(state_root_fd, "ompom")))

            handle_save(today_fd, grave_fd, state_fd, note)
    except OSError as e:
        print(f"notes-helper: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
