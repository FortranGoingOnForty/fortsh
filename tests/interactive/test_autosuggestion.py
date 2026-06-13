"""Autosuggestion (shadow text) regression tests (AR-04).

Verified by executing the line and checking the output, since the ghost text
renders as plain characters in the pyte display (can't tell accepted-vs-ghost
from the display text alone).
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


def _accept_and_run(fortsh_path, tmp_path, accept_key):
    """Seed history with `echo suggested_command_xyz`, type `echo sug` to
    surface the suggestion, press accept_key, execute, return the echoed text."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=1.0):
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
    child.send(b"echo suggested_command_xyz\r")
    drain(0.7)
    for ch in b"echo sug":
        child.send(bytes([ch]))
        time.sleep(0.03)
    drain(0.8)
    child.send(accept_key)
    drain(0.7)
    child.send(b"\r")
    drain(1.0)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    # the executed echo printed either the full suggestion or just "sug"
    hits = [r for r in rows if r in ("suggested_command_xyz", "sug")]
    return hits[-1] if hits else "(none)"


def test_end_accepts_autosuggestion(fortsh_path, tmp_path):
    """End at end-of-line accepts the whole autosuggestion (AS-1)."""
    assert _accept_and_run(fortsh_path, tmp_path, b"\x1b[F") == "suggested_command_xyz"


def test_ctrl_e_accepts_autosuggestion(fortsh_path, tmp_path):
    """Ctrl-E accepts the whole autosuggestion (AS-1)."""
    assert _accept_and_run(fortsh_path, tmp_path, b"\x05") == "suggested_command_xyz"
