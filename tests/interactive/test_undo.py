"""Undo / redo tests (AR-05 DIV-1).

Ctrl-/ (0x1f) undoes the last edit group; Alt-/ redoes. Consecutive single-char
inserts coalesce into one group, so undo removes a whole typed run. A cursor
motion breaks the run (its own group boundary). Each case edits an `echo ` line,
applies undo/redo, executes, and checks the echoed output.
"""
import os
import time

import pexpect
import pytest

try:
    import pyte
except ImportError:  # pragma: no cover
    pyte = None

pytestmark = pytest.mark.skipif(pyte is None, reason="pyte not installed")

ROWS, COLS = 24, 90
CTRL_U = b"\x15"
UNDO = b"\x1f"        # Ctrl-/
REDO = b"\x1b/"       # Alt-/
LEFT = b"\x1b[D"
RIGHT = b"\x1b[C"


def _run_keys(fortsh_path, tmp_path, chunks):
    """Send each chunk as a discrete keystroke burst, execute, return rows."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.5):
        end = time.time() + secs
        while time.time() < end:
            try:
                stream.feed(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    drain(1.0)
    for ch in chunks:
        child.send(ch)
        time.sleep(0.15)
    drain(0.6)
    child.send(b"\r")
    drain(0.9)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return rows


def test_undo_restores_killed_line(fortsh_path, tmp_path):
    """Ctrl-U wipes the line; Ctrl-/ brings it back (PROBE-5)."""
    rows = _run_keys(fortsh_path, tmp_path, [b"echo hello", CTRL_U, UNDO])
    assert "hello" in rows


def test_undo_removes_whole_typed_run(fortsh_path, tmp_path):
    """A coalesced insert run undoes as one unit: typing `XYZ` (after a motion
    boundary) then one Ctrl-/ removes all of `XYZ`, leaving `echo hello`."""
    rows = _run_keys(fortsh_path, tmp_path,
                     [b"echo hello", LEFT, RIGHT, b"XYZ", UNDO])
    assert "hello" in rows
    assert "helloXYZ" not in rows


def test_redo_replays_undone_edit(fortsh_path, tmp_path):
    """Alt-/ replays an undone insert: type `hello` (after a motion boundary),
    undo it back to `echo `, then redo to get `echo hello` again."""
    rows = _run_keys(fortsh_path, tmp_path,
                     [b"echo ", LEFT, RIGHT, b"hello", UNDO, REDO])
    assert "hello" in rows
