"""Punctuation-aware word motion / kill tests (AR-05 DIV-3).

fish word boundaries are punctuation-aware: Alt-b/Alt-f/Alt-d/Alt-Backspace
operate on "small words" (a run of alnum OR a run of punctuation), and Ctrl-W is
backward-kill-path-component (splits on '/' and whitespace). Each case builds an
`echo <text>` line, applies an edit, executes it, and checks the echoed output —
the buffer after the edit is observable as the echoed argument.
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


def _edit_run(fortsh_path, tmp_path, line, keys):
    """Type `line`, send the `keys` edit sequence, execute, return the screen
    rows (stripped, non-empty) so the echoed output can be asserted."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
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
    for ch in line:
        child.send(bytes([ch]))
        time.sleep(0.02)
    drain(0.5)
    child.send(keys)
    drain(0.5)
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


def test_ctrl_w_kills_path_component(fortsh_path, tmp_path):
    """Ctrl-W is backward-kill-path-component: two presses on `aa/bb/cc` peel
    `cc` then `bb/`, leaving `aa/` (not `aa/bb` as a small-word kill would)."""
    rows = _edit_run(fortsh_path, tmp_path, b"echo aa/bb/cc", b"\x17\x17")
    assert "aa/" in rows
    assert "aa/bb" not in rows


def test_alt_backspace_kills_small_word(fortsh_path, tmp_path):
    """Alt-Backspace is punctuation-aware backward-kill-word: two presses on
    `aa/bb/cc` peel `cc` then the `/`, leaving `aa/bb`."""
    rows = _edit_run(fortsh_path, tmp_path, b"echo aa/bb/cc", b"\x1b\x7f\x1b\x7f")
    assert "aa/bb" in rows
    assert "aa/" not in rows


def test_alt_b_stops_at_punctuation(fortsh_path, tmp_path):
    """Alt-b lands at the start of the last small word: from end of `aa.bb.cc`
    it moves before `cc`, so Ctrl-K (kill to end) leaves `aa.bb.` — not empty as
    a whitespace-word motion (jump to column 0) would."""
    rows = _edit_run(fortsh_path, tmp_path, b"echo aa.bb.cc", b"\x1bb\x0b")
    assert "aa.bb." in rows


def test_alt_d_kills_small_word_forward(fortsh_path, tmp_path):
    """Alt-d forward-kills one small word: at the start of `aa.bb` (after
    `echo `) it removes `aa`, leaving `.bb` — a whitespace kill would take the
    whole `aa.bb`."""
    # Ctrl-A to start, 5 Rights past "echo " (e,c,h,o,space), then Alt-d.
    rows = _edit_run(fortsh_path, tmp_path, b"echo aa.bb",
                     b"\x01" + b"\x1b[C" * 5 + b"\x1bd")
    assert ".bb" in rows
    assert "aa.bb" not in rows
