"""Kill-ring tests (AR-05 DIV-2).

fish keeps a multi-slot kill ring: every kill op feeds it, consecutive kills
merge into one entry, and Alt-y (yank-pop) rotates through older entries. Each
case edits an `echo ` line, yanks, executes, and checks the echoed output.

Positioning: Ctrl-A to start, then Right x5 to land after "echo " (e,c,h,o,SP).
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
HOME = b"\x01"          # Ctrl-A
END = b"\x1b[F"
RIGHT5 = b"\x1b[C" * 5
ALT_D = b"\x1bd"
ALT_Y = b"\x1by"
CTRL_Y = b"\x19"


def _run_keys(fortsh_path, tmp_path, chunks):
    """Send each chunk as a discrete keystroke burst (separate reads so the
    consecutive-kill flag rotates between them), execute, return screen rows."""
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


def test_alt_d_feeds_kill_ring(fortsh_path, tmp_path):
    """Alt-d's killed text is yankable (PROBE-3: it used to be discarded, so
    Ctrl-Y pasted a stale kill / nothing)."""
    # type `echo target`, home, past "echo ", Alt-d kills `target`, End, Ctrl-Y.
    rows = _run_keys(fortsh_path, tmp_path,
                     [b"echo target", HOME, RIGHT5, ALT_D, END, CTRL_Y])
    assert "target" in rows


def test_consecutive_alt_d_accumulate(fortsh_path, tmp_path):
    """Two consecutive Alt-d kills merge into one ring entry, so a single Ctrl-Y
    yanks both words (`aa bb`), not just the last (`bb`)."""
    rows = _run_keys(fortsh_path, tmp_path,
                     [b"echo aa bb", HOME, RIGHT5, ALT_D, ALT_D, END, CTRL_Y])
    assert "aa bb" in rows
    assert "bb" not in rows  # the single-slot bug would yank only the last kill


def test_alt_y_yank_pop_rotates(fortsh_path, tmp_path):
    """Alt-y after Ctrl-Y replaces the yank with the next-older ring entry.
    Kill `first`, type `second` (breaks the kill chain), kill `second` ->
    ring = [second, first]. Ctrl-Y yanks `second`; Alt-y rotates to `first`."""
    rows = _run_keys(fortsh_path, tmp_path,
                     [b"echo first", HOME, RIGHT5, ALT_D,        # ring=[first]
                      b"second",                                  # buffer `echo second`
                      HOME, RIGHT5, ALT_D,                        # ring=[second, first]
                      END, CTRL_Y, ALT_Y])                        # yank second, pop to first
    assert "first" in rows
    assert "second" not in rows
