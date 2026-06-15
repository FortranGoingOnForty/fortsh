"""Completion menu description column (AR-03c).

fish renders a dim description to the right of each completion: a variable's
value, a builtin's one-line summary. Plain file/dir menus get no description
and keep the AR-03b column-major name-only layout.

Read from raw bytes: pyte renders ESC[90m (dim) as the default color and
collapses the menu's cursor moves, so the description column is invisible to it.
The candidate + description text is emitted verbatim in the draw.
"""
import os
import re
import time

import pexpect

DIM = b"\x1b[90m"


def _menu_raw(fortsh_path, tmp_path, setup, line):
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
    child.send(line)
    drain(1.2)
    tail = bytes(raw[mark:])
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return tail


def test_variable_menu_shows_values(fortsh_path, tmp_path):
    """`$ZZ`+Tab lists matching variables with their values as descriptions."""
    tail = _menu_raw(fortsh_path, tmp_path,
                     [b"ZZALPHA=valuealpha\r", b"ZZBETA=valuebeta\r"],
                     b"echo $ZZ\t")
    assert b"$ZZALPHA" in tail and b"$ZZBETA" in tail
    assert b"valuealpha" in tail and b"valuebeta" in tail
    assert DIM in tail, "description column not rendered dim"
    # value follows its name on the same line
    assert re.search(rb"\$ZZBETA\s+(?:\x1b\[90m)?valuebeta", tail), tail[:200]


def test_builtin_menu_shows_summary(fortsh_path, tmp_path):
    """A command-position menu describes builtins with a one-line summary.
    `e`+Tab matches several commands (a menu), among them the echo builtin."""
    tail = _menu_raw(fortsh_path, tmp_path, [], b"e\t")
    assert b"echo" in tail
    assert b"write arguments to standard output" in tail
    assert DIM in tail


def test_file_menu_has_no_descriptions(fortsh_path, tmp_path):
    """A plain file menu keeps the AR-03b name-only layout: no dim description
    column, names shown as before."""
    (tmp_path / "apple.txt").write_text("")
    (tmp_path / "apricot.txt").write_text("")
    tail = _menu_raw(fortsh_path, tmp_path, [], b"cat ap\t")
    assert b"apple.txt" in tail and b"apricot.txt" in tail
    assert DIM not in tail, "file menu should have no description column"


def test_option_menu_shows_help(fortsh_path, tmp_path):
    """`ls -`+Tab describes each option flag (MDESC_OPT, #88)."""
    tail = _menu_raw(fortsh_path, tmp_path, [], b"ls -\t")
    assert b"-l" in tail
    assert b"long listing format" in tail
    assert b"reverse sort order" in tail   # -r: command-specific (not 'recursive')
    assert DIM in tail


def test_git_subcommand_menu_shows_help(fortsh_path, tmp_path):
    """`git `+Tab describes each subcommand (MDESC_SUB, #88). The full list
    pages, so assert on entries in the first visible page (add..clean)."""
    tail = _menu_raw(fortsh_path, tmp_path, [], b"git \t")
    assert b"add file contents to the index" in tail
    assert b"list, create, or delete branches" in tail   # branch
    assert DIM in tail
