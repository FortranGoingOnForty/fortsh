"""Vi text-object tests (AR-05b, stage 3).

After an operator (d/c/y), `i`/`a` + an object char operates on the inner/around
object: word (iw/aw), quote (i"/a", i'), bracket (i(/a(, i[/i{, b/B aliases).
Execution-based; the cursor is positioned with explicit `l` motions (fortsh vi
has no `f<char>`).
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")
ESC = b"\x1b"
L = b"l"


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
        cap(0.2)
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


def test_diw_deletes_inner_word(fortsh_path, tmp_path):
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb cc", ESC, b"0", b"w", b"d", b"i", b"w"])
    assert out == "bb cc", out


def test_ciw_changes_inner_word(fortsh_path, tmp_path):
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb", ESC, b"0", b"w", b"c", b"i", b"w", b"XX", ESC])
    assert out == "XX bb", out


def test_daw_deletes_around_word(fortsh_path, tmp_path):
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb cc", ESC, b"0", b"w", b"d", b"a", b"w"])
    assert out == "bb cc", out


def test_ci_quote_changes_inside_quotes(fortsh_path, tmp_path):
    # echo "abc" z -> cursor to 'a' (pos 6) -> ci" NEW -> echo "NEW" z
    out = _vi(fortsh_path, tmp_path,
              [b'echo "abc" z', ESC, b"0"] + [L] * 6 + [b"c", b"i", b'"', b"NEW", ESC])
    assert out == "NEW z", out


def test_ca_quote_removes_quotes_too(fortsh_path, tmp_path):
    # a" includes the quotes: echo "abc" z -> ca" NEW -> echo NEW z
    out = _vi(fortsh_path, tmp_path,
              [b'echo "abc" z', ESC, b"0"] + [L] * 6 + [b"c", b"a", b'"', b"NEW", ESC])
    assert out == "NEW z", out


def test_ci_bracket_changes_inside(fortsh_path, tmp_path):
    # echo [abc] z (literal in empty dir) -> cursor inside -> ci[ Q -> [Q] z
    out = _vi(fortsh_path, tmp_path,
              [b"echo [abc] z", ESC, b"0"] + [L] * 6 + [b"c", b"i", b"[", b"Q", ESC])
    assert out == "[Q] z", out


def test_yiw_then_put(fortsh_path, tmp_path):
    # yank inner word, jump to end, put it
    out = _vi(fortsh_path, tmp_path,
              [b"echo ab cd", ESC, b"0", b"w", b"y", b"i", b"w", b"$", b"p"])
    assert out == "ab cdab", out


def test_dot_repeats_ciw(fortsh_path, tmp_path):
    # ciwX on one word, then `.` on the next word
    out = _vi(fortsh_path, tmp_path,
              [b"echo aa bb cc", ESC, b"0", b"w", b"c", b"i", b"w", b"X", ESC,
               b"w", b"."])
    assert out == "X X cc", out
