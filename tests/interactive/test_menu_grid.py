"""Completion menu grid layout tests (AR-03b).

fish fills the completion grid column-major: consecutive candidates run DOWN
each column, not across each row. The internal candidate order is whatever the
directory scan yields (not sorted), so these tests first capture that order
from a one-item-per-row menu, then assert the wide grid is the same sequence
read column-by-column. Navigation follows from the layout: Up/Down move within
a column (+/-1 in the sequence), Left/Right move between columns (+/-num_rows).

pyte mistracks the menu's cursor-reposition + ESC[J + reverse-video, so the
fill order is read from RAW bytes and the selection is read back by accepting
it (Enter) and executing the resulting `echo` line.
"""
import os
import re
import time

import pexpect

ROWS = 40
CAND = re.compile(rb"cand_\d\d\.txt")


def _make_files(tmp_path, count):
    for i in range(1, count + 1):
        (tmp_path / f"cand_{i:02d}.txt").write_text("")


def _spawn(fortsh_path, tmp_path, cols):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    return pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                         encoding=None, timeout=8, dimensions=(ROWS, cols))


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


def _capture_grid(fortsh_path, tmp_path, cols):
    """Type `echo cand_`+Tab, return the rendered grid as a list of rows, each
    a list of candidate names (raw bytes, ANSI stripped)."""
    child = _spawn(fortsh_path, tmp_path, cols)
    raw = bytearray()
    time.sleep(1.0)
    _drain(child, raw, 1.0)
    mark = len(raw)
    child.send(b"echo cand_\t")
    _drain(child, raw, 1.2)
    tail = bytes(raw[mark:])
    _cleanup(child)
    clean = re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]", b"", tail)
    grid = []
    for ln in clean.split(b"\r\n"):
        toks = [m.decode() for m in CAND.findall(ln)]
        if toks:
            grid.append(toks)
    return grid


def _internal_order(fortsh_path, tmp_path):
    """One-item-per-row menu (narrow terminal): rows top-to-bottom are the
    internal candidate order."""
    grid = _capture_grid(fortsh_path, tmp_path, 20)
    return [r[0] for r in grid if len(r) == 1]


def _select_and_run(fortsh_path, tmp_path, cols, arrows):
    """Open the menu (Tab Tab -> selection on item 1), send `arrows`, accept
    (Enter), execute (Enter), return the echoed candidate name."""
    child = _spawn(fortsh_path, tmp_path, cols)
    raw = bytearray()
    time.sleep(1.0)
    _drain(child, raw, 1.0)
    child.send(b"echo cand_\t")   # draw menu
    _drain(child, raw, 0.7)
    child.send(b"\t")             # enter menu-select (selection = item 1)
    _drain(child, raw, 0.7)
    for a in arrows:
        child.send(a)
        _drain(child, raw, 0.5)
    mark = len(raw)
    child.send(b"\r")             # accept selection into the line
    _drain(child, raw, 0.5)
    child.send(b"\r")             # execute the echo
    _drain(child, raw, 0.8)
    out = bytes(raw[mark:])
    _cleanup(child)
    # The echo output is a candidate name alone on a line (no `echo`, no `>`).
    names = [m.decode() for m in CAND.findall(out)]
    # Last match is the executed echo output (earlier ones are the redrawn line).
    return names[-1] if names else None


KEY_DOWN = b"\x1b[B"
KEY_UP = b"\x1b[A"
KEY_RIGHT = b"\x1b[C"
KEY_LEFT = b"\x1b[D"


def test_fill_is_column_major(fortsh_path, tmp_path):
    """The wide grid, read column-by-column, reproduces the internal order
    (column-major). Row-major would interleave differently."""
    _make_files(tmp_path, 15)
    internal = _internal_order(fortsh_path, tmp_path)
    assert len(internal) == 15, f"internal order incomplete: {internal!r}"

    wide = _capture_grid(fortsh_path, tmp_path, 80)
    num_rows = len(wide)
    assert num_rows >= 2, f"need a multi-row grid, got {wide!r}"

    flat = []
    maxcols = max(len(r) for r in wide)
    for c in range(maxcols):
        for r in range(num_rows):
            if c < len(wide[r]):
                flat.append(wide[r][c])
    assert flat == internal, (
        f"grid is not column-major:\n  column-major flatten={flat!r}\n"
        f"  internal order      ={internal!r}\n  grid={wide!r}")


def test_down_moves_within_column(fortsh_path, tmp_path):
    """Down from the first item selects the SECOND internal item (column-major:
    consecutive items run down a column). Row-major would jump a full row."""
    _make_files(tmp_path, 15)
    internal = _internal_order(fortsh_path, tmp_path)
    got = _select_and_run(fortsh_path, tmp_path, 80, [KEY_DOWN])
    assert got == internal[1], (
        f"Down landed on {got!r}, expected the 2nd internal item "
        f"{internal[1]!r} (column-major)")


def test_right_moves_across_columns(fortsh_path, tmp_path):
    """Right from the first item skips a whole column: it selects internal item
    #(num_rows) (0-based num_rows), the top of column 2."""
    _make_files(tmp_path, 15)
    internal = _internal_order(fortsh_path, tmp_path)
    wide = _capture_grid(fortsh_path, tmp_path, 80)
    num_rows = len(wide)
    assert num_rows >= 2
    got = _select_and_run(fortsh_path, tmp_path, 80, [KEY_RIGHT])
    assert got == internal[num_rows], (
        f"Right landed on {got!r}, expected internal item #{num_rows} "
        f"{internal[num_rows]!r} (top of column 2, column-major)")
