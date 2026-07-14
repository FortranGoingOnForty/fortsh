"""Redraw regression test for an exact-width paste followed by a keystroke (RL-1).

When a batch insert fills a row to exactly the terminal width, the terminal
leaves the cursor in deferred (pending) wrap — still on the filled row. But
cursor_get_row_col treated an exactly-filled row as advanced (its wrap test used
'>='), so module_cursor_screen_row was one greater than the physical row and the
next keystroke's move-up emitted one too many ESC[A, scrolling the screen. The
fix treats an exact fill as pending-wrap. Verified via pyte cursor tracking and
the emitted byte stream (the extra leading ESC[A must be gone).
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

ROWS, COLS = 24, 80


def test_exact_width_paste_then_key_no_extra_cursor_up(fortsh_path):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], env=env, encoding=None,
                          timeout=8, dimensions=(ROWS, COLS))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.6):
        end = time.time() + secs
        while time.time() < end:
            try:
                stream.feed(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    try:
        time.sleep(1.0)
        drain(1.0)

        # The input-line prompt is '> ' (2 cols), so COLS-2 'a's fill the row to
        # exactly the terminal width, leaving the cursor in pending wrap.
        child.send(b"\x1b[200~" + b"a" * (COLS - 2) + b"\x1b[201~")
        drain(0.6)

        # Precondition: exact fill — cursor at the last column, still on the
        # prompt's physical row (pending wrap, not advanced to the next row).
        assert screen.cursor.x == COLS, (
            f"expected exact-width fill (cursor.x == {COLS}), got "
            f"cursor.x={screen.cursor.x}; prompt width may differ here"
        )
        fill_row = screen.cursor.y

        # Type one char and capture exactly what the redraw emits.
        raw = bytearray()
        end = time.time() + 0.6
        child.send(b"b")
        while time.time() < end:
            try:
                raw.extend(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

        # The bug emitted the move-up first: the stream began with two ESC[A
        # (one too many) before any content, because the exact-fill row was
        # counted as advanced. The fix keeps the cursor on the filled row
        # (pending wrap), so the redraw echoes the char and wraps normally.
        assert not bytes(raw).startswith(b"\x1b[A\x1b[A"), (
            "exact-width paste + keystroke emitted a leading double ESC[A "
            "(over-counted move-up that scrolls the screen)"
        )

        # The typed char rendered on screen (buffer not corrupted by the redraw).
        stream.feed(bytes(raw))
        assert any("b" in r for r in screen.display), "typed char lost after redraw"
    finally:
        try:
            child.send(b"\x03")
            child.sendline(b"exit")
            child.close()
        except Exception:
            pass
