"""Interactive niceties tests (AR-08).

Stage 1a: Ctrl-C on an empty line is silent (fish), and Up/Down during a Ctrl-R
search step through matches instead of cancelling. Raw-byte capture.
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")


def _spawn(fortsh_path, tmp_path):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    return pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                         encoding=None, timeout=8, dimensions=(24, 90))


def _drain(child, raw, secs):
    end = time.time() + secs
    while time.time() < end:
        try:
            raw.extend(child.read_nonblocking(65536, timeout=0.2))
        except pexpect.TIMEOUT:
            pass
        except pexpect.EOF:
            break


def _cleanup(child):
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass


def test_ctrlc_empty_is_silent(fortsh_path, tmp_path):
    """Ctrl-C on an empty line emits no `^C` (fish behavior)."""
    child = _spawn(fortsh_path, tmp_path)
    raw = bytearray()
    time.sleep(1.0)
    _drain(child, raw, 1.0)
    mark = len(raw)
    child.send(b"\x03")
    _drain(child, raw, 0.6)
    tail = bytes(raw[mark:])
    _cleanup(child)
    assert b"^C" not in tail, f"empty Ctrl-C printed ^C: {tail!r}"


def test_ctrlc_nonempty_shows_caret(fortsh_path, tmp_path):
    """Ctrl-C with text on the line still shows `^C` (abandons the line)."""
    child = _spawn(fortsh_path, tmp_path)
    raw = bytearray()
    time.sleep(1.0)
    _drain(child, raw, 1.0)
    child.send(b"abc")
    _drain(child, raw, 0.4)
    mark = len(raw)
    child.send(b"\x03")
    _drain(child, raw, 0.6)
    tail = bytes(raw[mark:])
    _cleanup(child)
    assert b"^C" in tail, f"non-empty Ctrl-C did not show ^C: {tail!r}"


def test_isearch_arrows_step_matches(fortsh_path, tmp_path):
    """Up/Down during Ctrl-R step to the older/newer match instead of cancelling
    the search and restoring the original line."""
    child = _spawn(fortsh_path, tmp_path)
    raw = bytearray()
    time.sleep(1.0)
    _drain(child, raw, 1.0)
    child.send(b"echo MATCHAAA\r")
    _drain(child, raw, 0.5)
    child.send(b"echo MATCHBBB\r")
    _drain(child, raw, 0.5)
    child.send(b"\x12")            # Ctrl-R: reverse search
    _drain(child, raw, 0.4)
    child.send(b"MATCH")
    _drain(child, raw, 0.5)
    mark = len(raw)
    child.send(b"\x1b[A")          # Up: older match
    _drain(child, raw, 0.5)
    up_frame = _ANSI.sub(b"", bytes(raw[mark:]))
    mark = len(raw)
    child.send(b"\x1b[B")          # Down: newer match
    _drain(child, raw, 0.5)
    down_frame = _ANSI.sub(b"", bytes(raw[mark:]))
    _cleanup(child)
    # Up moved to the older match (the search is still active, line not restored)
    assert b"MATCHAAA" in up_frame, f"Up did not step to older match: {up_frame!r}"
    # Down moved back to the newer match
    assert b"MATCHBBB" in down_frame, f"Down did not step to newer match: {down_frame!r}"
