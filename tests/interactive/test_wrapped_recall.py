"""Redraw regression tests for history recall / Ctrl-U over a wrapped line (RL-2).

When a wrapped multi-row line is replaced by shorter content, the differential
redraw used to reposition the cursor by the model row (current_row) instead of
the physical row (module_cursor_screen_row). The move-up under-shot, ESC[J
cleared from a stale wrapped row, and the new tail was spliced onto old content:
recalling `echo short` over a wrapped z-line displayed `echo zzz...zzzshort`
while Enter still executed `echo short`. The fix repositions by the physical row.

These assert terminal-cell layout via pyte, which the YAML/byte harness can't
express — the bug is that the rendered screen diverges from the executed buffer.
"""
import os
import time

import pexpect
import pytest

try:
    import pyte
except ImportError:  # pragma: no cover
    pyte = None

pytestmark = [
    pytest.mark.ci,
    pytest.mark.skipif(pyte is None, reason="pyte not installed"),
]

ROWS, COLS = 24, 80


def _spawn(fortsh_path):
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

    time.sleep(1.0)
    drain(1.0)
    return child, screen, drain


def _active_input_row(screen):
    """Return the command text on the active input line: the last row whose
    prompt marker is '>' (the default prompt's final physical row is
    '> <command>'). Handles the empty case where the row rstrips to just '>'.
    Earlier '>' rows are scrollback prompts, so the last one is the live line."""
    rows = [r.rstrip() for r in screen.display]
    for r in reversed(rows):
        if r.startswith(">"):
            rest = r[1:]
            if rest.startswith(" "):
                rest = rest[1:]
            return rest
    return None


def _close(child):
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass


def test_recall_short_line_over_wrapped_matches_buffer(fortsh_path):
    """Recall `echo short` over a wrapped z-line: the displayed input line must
    read `echo short`, not the z-run with `short` spliced on."""
    child, screen, drain = _spawn(fortsh_path)
    try:
        child.send(b"echo short\r")
        drain(0.5)
        child.send(b"echo " + b"z" * 90 + b"\r")   # 95 cols -> wraps
        drain(0.6)
        child.send(b"\x1b[A")   # Up -> wrapped z-line
        drain(0.5)
        child.send(b"\x1b[A")   # Up -> echo short
        drain(0.6)

        active = _active_input_row(screen)
        assert active == "echo short", (
            f"displayed input line was {active!r}, expected 'echo short' "
            f"(display diverged from the recalled buffer)"
        )
        assert "zz" not in active, "stale wrapped content spliced into recall"
    finally:
        _close(child)


def test_ctrl_u_on_wrapped_recall_clears_line(fortsh_path):
    """Recall the wrapped z-line, then Ctrl-U: the input line must clear to
    empty rather than leaving stale wrapped content on screen."""
    child, screen, drain = _spawn(fortsh_path)
    try:
        child.send(b"echo " + b"z" * 90 + b"\r")
        drain(0.6)
        child.send(b"\x1b[A")   # Up -> wrapped z-line
        drain(0.6)
        child.send(b"\x15")     # Ctrl-U -> kill whole line
        drain(0.6)

        active = _active_input_row(screen)
        assert active == "", (
            f"input line after Ctrl-U was {active!r}, expected empty "
            f"(stale wrapped content not cleared)"
        )
    finally:
        _close(child)
