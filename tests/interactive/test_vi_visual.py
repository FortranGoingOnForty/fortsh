"""Vi visual mode tests (AR-05b, stage 1).

`set -o vi`, then drive command-mode keys. Visual mode (v/V) selects a region
that motions extend; d/x/c/s/y operate on the INCLUSIVE selection (the char
under the cursor is part of it, matching vi) and leave visual mode. Checks are
execution-based: apply the edit, run the line, read the echo output.

Also guards the basic vi ops (dw, yy/p) that share the range helpers visual
mode reuses.
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
ESC = b"\x1b"


def _vi(fortsh_path, tmp_path, keys):
    """Enable vi mode, send the key chunks, Enter, return echo output lines."""
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
    # echo output: lines that aren't the prompt/command echo
    return [l.strip() for l in out.split(b"\r\n")
            if l.strip() and b"echo" not in l and b">" not in l
            and b"::" not in l and b"vi_visual" not in l]


def _output(lines):
    return lines[0].decode() if lines else ""


def test_visual_delete_word(fortsh_path, tmp_path):
    """v + e + d deletes the selected word (inclusive)."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo abcde fghij", ESC, b"0", b"w", b"w", b"v", b"e", b"d"])
    assert _output(out) == "abcde", out


def test_visual_change_word(fortsh_path, tmp_path):
    """v + e + c replaces the selection with typed text."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo abcde fghij", ESC, b"0", b"w", b"w", b"v", b"e", b"c",
               b"XX", ESC])
    assert _output(out) == "abcde XX", out


def test_visual_single_char_delete(fortsh_path, tmp_path):
    """v then d with no motion deletes the single char under the cursor."""
    out = _vi(fortsh_path, tmp_path, [b"echo abcZ", ESC, b"v", b"d"])
    assert _output(out) == "abc", out


def test_visual_linewise_change(fortsh_path, tmp_path):
    """V selects the whole line; c clears it and enters insert mode."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo SHOULDVANISH", ESC, b"V", b"c", b"echo survived", ESC])
    assert _output(out) == "survived", out


def test_visual_yank_then_put(fortsh_path, tmp_path):
    """A visual yank feeds the vi put register: y the word, $ to end, p pastes."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo ab cd", ESC, b"0", b"w", b"v", b"e", b"y", b"$", b"p"])
    assert _output(out) == "ab cdab", out


def test_visual_escape_cancels(fortsh_path, tmp_path):
    """Esc leaves visual mode without changing the buffer."""
    out = _vi(fortsh_path, tmp_path,
              [b"echo keepme", ESC, b"0", b"v", b"e", ESC])
    assert _output(out) == "keepme", out


# --- basic-vi regression guard (shared range helpers) ---

def test_basic_dw_still_works(fortsh_path, tmp_path):
    """dw (delete word by motion) still deletes a word — guards the shared
    yank_range/delete_range helpers that visual mode reuses. (yy/p sharing the
    vi put register is covered by test_visual_yank_then_put.)"""
    out = _vi(fortsh_path, tmp_path,
              [b"echo abcde fghij", ESC, b"0", b"w", b"w", b"d", b"w"])
    assert _output(out) == "abcde", out
