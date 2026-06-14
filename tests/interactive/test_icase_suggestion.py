"""Case-insensitive path autosuggestion tests (AR-04b, AS-8).

fish offers a path autosuggestion when the typed prefix matches a filename only
case-insensitively, and its forward-char accept case-corrects the prefix so the
result is a valid path (`read` -> README, not readME). fortsh matches that on
accept, and additionally keeps End/Ctrl-E valid too (fish's End appends the raw
suffix, yielding a broken `readME`).

Behavioral checks via execution: accept the ghost, run the echo line, read the
token the shell actually produced.
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
KEY_RIGHT = b"\x1b[C"
KEY_END = b"\x05"  # Ctrl-E


def _run(fortsh_path, tmp_path, files, typed, accept):
    for fn in files:
        (tmp_path / fn).write_text("")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(24, 90))
    raw = bytearray()

    def cap(secs):
        end = time.time() + secs
        while time.time() < end:
            try:
                raw.extend(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    cap(1.0)
    gmark = len(raw)
    child.send(typed)
    cap(0.8)
    ghost_frame = bytes(raw[gmark:])
    child.send(accept)
    cap(0.4)
    mark = len(raw)
    child.send(b"\r")
    cap(0.8)
    out = _ANSI.sub(b"", bytes(raw[mark:]))
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    # the echo output: a bare token on its own line
    m = re.search(rb"\n([A-Za-z0-9._/]+)", out)
    accepted = m.group(1).decode() if m else None
    return ghost_frame, accepted


def test_icase_suggestion_appears_and_accepts_valid_path(fortsh_path, tmp_path):
    """`echo read` with only README present shows a ghost; Right accepts it as
    README (a valid path), not readME."""
    ghost, accepted = _run(fortsh_path, tmp_path, ["README"], b"echo read", KEY_RIGHT)
    assert b"\x1b[90m" in ghost, "no autosuggestion ghost shown for icase match"
    assert accepted == "README", f"icase accept gave {accepted!r}, expected README"


def test_icase_end_key_also_case_corrects(fortsh_path, tmp_path):
    """End/Ctrl-E also yields the valid README (fortsh keeps every accept key
    valid; fish's End quirk would give readME)."""
    _, accepted = _run(fortsh_path, tmp_path, ["README"], b"echo read", KEY_END)
    assert accepted == "README", f"End accept gave {accepted!r}, expected README"


def test_exact_case_suggestion_appends(fortsh_path, tmp_path):
    """An exact-case match appends as before (no recase): read -> readme."""
    _, accepted = _run(fortsh_path, tmp_path, ["readme"], b"echo read", KEY_RIGHT)
    assert accepted == "readme", f"exact accept gave {accepted!r}, expected readme"


def test_exact_case_preferred_over_icase(fortsh_path, tmp_path):
    """When both an exact-case and an icase candidate exist, the exact one wins."""
    _, accepted = _run(fortsh_path, tmp_path, ["readme", "README"],
                       b"echo read", KEY_RIGHT)
    assert accepted == "readme", f"expected exact-case readme, got {accepted!r}"
