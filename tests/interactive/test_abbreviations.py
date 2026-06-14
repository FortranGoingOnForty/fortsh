"""Abbreviation tests (AR-07).

fish-style abbreviations: defined with `abbr -a name expansion`, they expand at
command position when a separator (space, `;`, ...) or Enter follows, and stay
literal in argument position. Execution-based: define, type, run, read output.
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")


def _run(fortsh_path, tmp_path, setup, keys):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(24, 90))
    raw = bytearray()

    def drain(secs):
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
    for cmd in setup:
        child.send(cmd)
        drain(0.5)
    mark = len(raw)
    for k in keys:
        child.send(k)
        drain(0.35)
    drain(0.5)
    out = _ANSI.sub(b"", bytes(raw[mark:]))
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    # command-output lines (exclude the prompt and the echoed command line)
    return [l.strip() for l in out.split(b"\r\n")
            if l.strip() and b">" not in l and b"::" not in l]


ADD = [b"abbr -a gco 'echo EXPANDED'\r"]


def test_add_and_expand_on_enter(fortsh_path, tmp_path):
    """`abbr -a name expansion` (fish CLI) + Enter expands and runs it."""
    out = _run(fortsh_path, tmp_path, ADD, [b"gco", b"\r"])
    assert any(l == b"EXPANDED" for l in out), out


def test_not_expanded_in_argument_position(fortsh_path, tmp_path):
    """An abbreviation in argument position stays literal (command-position only)."""
    out = _run(fortsh_path, tmp_path, ADD, [b"echo gco", b"\r"])
    assert any(l == b"gco" for l in out), out
    assert not any(l == b"EXPANDED" for l in out), out


def test_expand_on_space_with_args(fortsh_path, tmp_path):
    """Space expands the command-position word; args after it are kept."""
    out = _run(fortsh_path, tmp_path, ADD, [b"gco", b" ", b"hi", b"\r"])
    assert any(l == b"EXPANDED hi" for l in out), out


def test_expand_after_separator(fortsh_path, tmp_path):
    """A word at command position after `;` expands."""
    out = _run(fortsh_path, tmp_path, ADD, [b"true; gco", b"\r"])
    assert any(l == b"EXPANDED" for l in out), out


def test_name_value_syntax_still_works(fortsh_path, tmp_path):
    """The legacy `abbr name=value` syntax still defines an abbreviation."""
    out = _run(fortsh_path, tmp_path, [b"abbr gx='echo GXVAL'\r"], [b"gx", b"\r"])
    assert any(l == b"GXVAL" for l in out), out


def test_add_joins_bare_words(fortsh_path, tmp_path):
    """`abbr -a name w1 w2` joins the bare words into the expansion."""
    out = _run(fortsh_path, tmp_path, [b"abbr -a ge echo BAREWORDS\r"],
               [b"ge", b"\r"])
    assert any(l == b"BAREWORDS" for l in out), out


def _isolated_session(fortsh_path, home, cmds, keys):
    """A session with HOME pinned to `home` (so ~/.fortsh_abbreviations is the
    isolated file) and the first-run prompt suppressed."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HOME"] = str(home)
    env["FORTSH_TEST_MODE"] = "1"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(home), env=env,
                          encoding=None, timeout=8, dimensions=(24, 90))
    raw = bytearray()

    def drain(secs):
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
    for cmd in cmds:
        child.send(cmd)
        drain(0.5)
    mark = len(raw)
    for k in keys:
        child.send(k)
        drain(0.35)
    drain(0.4)
    out = _ANSI.sub(b"", bytes(raw[mark:]))
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return [l.strip() for l in out.split(b"\r\n")
            if l.strip() and b">" not in l and b"::" not in l]


def test_abbreviations_persist_across_restart(fortsh_path, tmp_path):
    """An abbreviation defined in one session is restored in the next process
    (ABBR-PERSIST): define + exit, then a fresh shell expands it."""
    _isolated_session(fortsh_path, tmp_path,
                      [b"abbr -a gco 'echo PERSISTED'\r"], [])
    assert (tmp_path / ".fortsh_abbreviations").exists()
    out = _isolated_session(fortsh_path, tmp_path, [], [b"gco", b"\r"])
    assert any(l == b"PERSISTED" for l in out), out
