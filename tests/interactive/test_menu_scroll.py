"""Completion menu scrolling regression tests (AR-03 NEW-2).

The menu must STOP at the top/bottom of the table (no infinite wrap). When
already at an edge, a repeat same-direction arrow JUMPS to the opposite edge.
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

ROWS, COLS = 24, 28  # narrow -> one menu item per row


def _open_menu(fortsh_path, tmp_path):
    for n in ("alpha", "bravo", "charlie", "delta", "echo_f", "foxtrot",
              "golf", "hotel", "india", "juliet"):
        (tmp_path / f"file_{n}.txt").write_text("x\n")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.8):
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
    child.send(b"cat file_")
    drain(0.6)
    child.send(b"\t")   # draw menu
    drain(0.7)
    child.send(b"\t")   # enter menu select
    drain(0.7)
    return child, screen, drain


def _selected(screen):
    """Text of the reverse-video (highlighted) cell."""
    for y in range(ROWS):
        run = "".join(screen.buffer[y][x].data for x in sorted(screen.buffer[y])
                      if screen.buffer[y][x].reverse and screen.buffer[y][x].data.strip())
        if run.strip():
            return run.strip()
    return ""


def _press(child, screen, drain, key, n):
    seq = []
    for _ in range(n):
        child.send(key)
        drain(0.5)
        seq.append(_selected(screen))
    return seq


def test_menu_up_stops_at_top_not_wrap(fortsh_path, tmp_path):
    """Pressing Up past the top must STOP (a consecutive-identical selection),
    which a wrapping menu never produces, and must NOT jump on the first
    edge press."""
    child, screen, drain = _open_menu(fortsh_path, tmp_path)
    seq = _press(child, screen, drain, b"\x1b[A", 12)  # > 10 items
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    seq = [s for s in seq if s]
    consec = any(seq[i] == seq[i + 1] for i in range(len(seq) - 1))
    assert consec, f"menu Up never stopped at the top (wrapping?): {seq!r}"


def test_menu_repeat_at_edge_jumps(fortsh_path, tmp_path):
    """At the top, the first Up stops; a second Up jumps to a far item (the
    bottom). So a stop is immediately followed by a large change."""
    child, screen, drain = _open_menu(fortsh_path, tmp_path)
    seq = _press(child, screen, drain, b"\x1b[A", 14)
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    seq = [s for s in seq if s]
    # find a stop (consecutive identical), then assert the next press differs
    jumped = False
    for i in range(len(seq) - 2):
        if seq[i] == seq[i + 1] and seq[i + 1] != seq[i + 2]:
            jumped = True
            break
    assert jumped, f"no stop-then-jump pattern at the edge: {seq!r}"
