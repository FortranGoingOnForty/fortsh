"""Vi dot-repeat tests (AR-05b, stage 2).

`.` replays the last buffer-changing command. Stage 2a covers the non-insert
family (x/X/p/P, d<motion>, r<char>); stage 2b adds insert/change capture.
Execution-based: apply the edits, run the line, read the echo output.
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
ESC = b"\x1b"


def _vi(fortsh_path, tmp_path, keys):
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
    child.send(b"set -o vi\r")
    cap(0.6)
    mark = len(raw)
    for chunk in keys:
        child.send(chunk)
        cap(0.25)
    child.send(b"\r")
    cap(0.7)
    out = _ANSI.sub(b"", bytes(raw[mark:]))
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    lines = [l.strip() for l in out.split(b"\r\n")
             if l.strip() and b"echo" not in l and b">" not in l and b"::" not in l]
    return lines[0].decode() if lines else ""


def test_dot_repeats_dw(fortsh_path, tmp_path):
    """`.` after dw deletes another word (DOT_MOTION)."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb cc dd", ESC, b"0", b"w", b"d", b"w", b"."])
    assert out == "cc dd", out


def test_dot_repeats_x(fortsh_path, tmp_path):
    """`.` after x deletes another char (DOT_SIMPLE)."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo XXabc", ESC, b"0", b"w", b"x", b"."])
    assert out == "abc", out


def test_dot_repeats_replace(fortsh_path, tmp_path):
    """`.` after r<char> replaces the char under the cursor again (DOT_REPLACE)."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo abcde", ESC, b"0", b"w", b"r", b"Z", b"l", b"."])
    assert out == "ZZcde", out


def test_dot_noop_without_prior_change(fortsh_path, tmp_path):
    """`.` with no recorded change is a safe no-op."""
    out = _vi(fortsh_path, tmp_path, [b"echo hi", ESC, b"."])
    assert out == "hi", out


# --- stage 2b: insert/change with captured text ---

def test_dot_repeats_change_word(fortsh_path, tmp_path):
    """`.` replays cw + the typed replacement on the next word (DOTK_INSERT)."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb cc", ESC, b"0", b"w", b"c", b"w", b"XX", ESC, b"w", b"."])
    assert out == "XX XX cc", out


def test_dot_repeats_insert(fortsh_path, tmp_path):
    """`.` replays an i<text> insert at the cursor."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo abc", ESC, b"0", b"w", b"i", b"Z", ESC, b"."])
    assert out == "ZZabc", out


def test_dot_repeats_append(fortsh_path, tmp_path):
    """`.` replays an A<text> append at end of line."""
    out = _vi(fortsh_path, tmp_path, [b"echo ab", ESC, b"A", b"Z", ESC, b"."])
    assert out == "abZZ", out


def test_command_works_after_change_word(fortsh_path, tmp_path):
    """Regression: after cw<text><esc>, a following command-mode key acts as a
    command (the pending operator is cleared), not as another change motion."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb cc", ESC, b"0", b"w", b"c", b"w", b"ZZ", ESC,
               b"w", b"d", b"w"])
    assert out == "ZZ cc", out
