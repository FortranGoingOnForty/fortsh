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


def _word_accept_and_run(fortsh_path, tmp_path, accept_key):
    """Seed history with `echo foo bar baz`, type `echo f` to surface the
    suggestion `oo bar baz`, press accept_key (word-accept), execute, and
    return the echoed line. One-word accept -> 'foo'; whole -> 'foo bar baz';
    no-op -> 'f'."""
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
    child.send(b"echo foo bar baz\r")
    drain(0.7)
    for ch in b"echo f":
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
    hits = [r for r in rows if r in ("foo", "foo bar baz", "f")]
    return hits[-1] if hits else "(none)"


def test_alt_right_accepts_one_word(fortsh_path, tmp_path):
    """Alt-Right accepts one word of the autosuggestion at EOL (AS-6)."""
    assert _word_accept_and_run(fortsh_path, tmp_path, b"\x1b[1;3C") == "foo"


def test_alt_f_accepts_one_word(fortsh_path, tmp_path):
    """Alt-f accepts one word of the autosuggestion at EOL (AS-6)."""
    assert _word_accept_and_run(fortsh_path, tmp_path, b"\x1bf") == "foo"


def test_ctrl_right_accepts_one_word(fortsh_path, tmp_path):
    """Ctrl-Right accepts one word of the autosuggestion at EOL (AS-6)."""
    assert _word_accept_and_run(fortsh_path, tmp_path, b"\x1b[1;5C") == "foo"


def test_suggestion_renders_on_wrapped_line(fortsh_path, tmp_path):
    """AS-2: the autosuggestion still renders once the input wraps past row 0.

    Raw-byte check (pyte mistracks the bright-black ghost): force a wrap with a
    narrow terminal, then assert the keystroke that redraws in the wrapped state
    emits ESC[90m (the ghost SGR). Before the fix the `current_row == 0` gate
    suppressed the suggestion on any wrapped line, so no ESC[90m appeared.
    """
    cols = 40
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, cols))
    raw = bytearray()

    def drain(secs=0.8):
        end = time.time() + secs
        while time.time() < end:
            try:
                raw.extend(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    drain(1.0)
    child.send(b"echo " + b"q" * 60 + b"\r")  # history entry
    drain(0.7)
    prefix = b"echo " + b"q" * 50  # 55 chars: wraps at cols=40 regardless of prompt
    for ch in prefix[:-1]:
        child.send(bytes([ch]))
        time.sleep(0.02)
    drain(0.6)
    mark = len(raw)
    child.send(bytes([prefix[-1]]))  # final keystroke redraws in the wrapped state
    drain(0.6)
    tail = bytes(raw[mark:])
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    assert b"\x1b[90m" in tail, "no bright-black ghost emitted on the wrapped line"
