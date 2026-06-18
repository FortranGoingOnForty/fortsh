"""Multi-line line editing / faithful multi-line paste (AR-10).

A bracketed paste with newlines becomes a real multi-line editable buffer: it
renders one logical line per row, Up/Down move between lines, a trailing newline
is stripped (so it never auto-executes), and Enter runs the whole buffer.

Rendered with pyte (multi-line static layout is faithful under pyte; only resize
reflow is not). Normal mode (rc sets a single-line PS1) so the real redraw runs.
"""
import os
import time

import pexpect
import pyte


def _session(tmp_path, cols=90, rows=24):
    (tmp_path / ".fortshrc").write_text("PS1='ml> '\n")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HOME"] = str(tmp_path)
    env.pop("FORTSH_TEST_MODE", None)
    fortsh = _bin()
    child = pexpect.spawn(fortsh, [], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(rows, cols))
    screen = pyte.Screen(cols, rows)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.7):
        end = time.time() + secs
        while time.time() < end:
            try:
                stream.feed(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(0.9)
    drain(1.0)
    return child, screen, drain


def _bin():
    for p in (os.environ.get("FORTSH"), "./bin/fortsh"):
        if p and os.path.isfile(p):
            return os.path.abspath(p)
    return "./bin/fortsh"


def _rows(screen):
    return [r.rstrip() for r in screen.display if r.strip()]


def _paste(content):
    return b"\x1b[200~" + content + b"\x1b[201~"


def _cleanup(child):
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass


def test_multiline_paste_renders_each_line(fortsh_path, tmp_path):
    child, screen, drain = _session(tmp_path)
    child.send(_paste(b"echo aaa\necho bbb\necho ccc"))
    drain(0.7)
    rows = _rows(screen)
    _cleanup(child)
    # Three logical lines, each on its own row; the first carries the prompt.
    assert any(r.endswith("echo aaa") for r in rows), rows
    assert "echo bbb" in rows, rows
    assert "echo ccc" in rows, rows


def test_multiline_paste_no_autoexec(fortsh_path, tmp_path):
    """A multi-line paste does NOT run until Enter (no auto-execute)."""
    child, screen, drain = _session(tmp_path)
    child.send(_paste(b"echo aaa\necho bbb"))
    drain(0.7)
    rows = _rows(screen)
    _cleanup(child)
    # The command text is shown, but its OUTPUT (a bare "aaa" line) is not.
    assert "aaa" not in rows, f"paste auto-executed: {rows}"


def test_multiline_paste_runs_on_enter(fortsh_path, tmp_path):
    child, screen, drain = _session(tmp_path)
    child.send(_paste(b"echo aaa\necho bbb\necho ccc"))
    drain(0.7)
    child.send(b"\r")
    drain(1.0)
    rows = _rows(screen)
    _cleanup(child)
    # Each echo ran, producing its own output line.
    assert "aaa" in rows and "bbb" in rows and "ccc" in rows, rows


def test_trailing_newline_stripped(fortsh_path, tmp_path):
    """Pasting "cmd\\n" yields a ready-to-run single line, not a trailing blank
    line; the cursor ends at the end of the command."""
    child, screen, drain = _session(tmp_path)
    child.send(_paste(b"echo solo\n"))
    drain(0.7)
    cy = screen.cursor.y
    rows = _rows(screen)
    _cleanup(child)
    assert any(r.endswith("echo solo") for r in rows), rows
    # Cursor on the same row as the command (no extra blank line below it).
    prompt_row = next(i for i, r in enumerate(screen.display) if r.rstrip().endswith("echo solo"))
    assert cy == prompt_row, f"cursor on a trailing blank line: cy={cy} prompt_row={prompt_row}"


def test_submit_from_interior_line_no_corruption(fortsh_path, tmp_path):
    """Submitting with the cursor on an INTERIOR line of a multi-line buffer
    must run output BELOW the whole block, not overwrite the lines beneath the
    cursor (AR-10 regression: 'echo CC' became 'echo CCAA')."""
    child, screen, drain = _session(tmp_path)
    child.send(_paste(b"echo AA\necho BB\necho CC"))
    drain(0.7)
    child.send(b"\x1b[A")        # cursor onto the middle line (echo BB)
    drain(0.5)
    child.send(b"\r")
    drain(1.0)
    rows = _rows(screen)
    _cleanup(child)
    # The last command line stays an intact row (the bug fused output into it,
    # e.g. "echo CCAA"), and each output is its own clean line.
    assert "echo CC" in rows, f"command line corrupted by output: {rows}"
    assert "AA" in rows and "BB" in rows and "CC" in rows, rows


def test_wrapped_input_under_multiline_prompt_no_dup(fortsh_path, tmp_path):
    """Editing a WRAPPING line under a MULTI-LINE prompt must not duplicate a
    wrapped segment (the Phase 2/3 diff mis-navigated rows; forced full rebuild).
    Single logical line (no newline) — exercises the pre-existing diff bug."""
    (tmp_path / ".fortshrc").write_text("PS1='topline-here\\n> '\n")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HOME"] = str(tmp_path)
    env.pop("FORTSH_TEST_MODE", None)
    child = pexpect.spawn(_bin(), [], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(24, 52))
    screen = pyte.Screen(52, 24)
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

    time.sleep(0.9)
    drain(1.0)
    child.send(_paste(b"echo aaaa bbbb cccc dddd eeee ffff gggg hhhh "
                      b"iiii jjjj kkkk llll mmmm"))
    drain(0.7)
    for _ in range(20):
        child.send(b"\x1b[D")
    drain(0.5)
    child.send(b"\x7f\x7f\x7f")
    drain(0.5)
    rows = _rows(screen)
    _cleanup(child)
    # The unique tail token must appear exactly once (the bug duplicated it).
    n = sum(r.count("mmmm") for r in rows)
    assert n == 1, f"wrapped segment duplicated ({n}x 'mmmm'): {rows}"


def test_up_arrow_moves_between_lines(fortsh_path, tmp_path):
    """Up in a multi-line buffer moves the cursor up a logical line (not history)."""
    child, screen, drain = _session(tmp_path)
    child.send(_paste(b"echo aaa\necho bbb\necho ccc"))
    drain(0.7)
    y0 = screen.cursor.y
    child.send(b"\x1b[A")
    drain(0.5)
    y1 = screen.cursor.y
    child.send(b"\x1b[B")
    drain(0.5)
    y2 = screen.cursor.y
    _cleanup(child)
    assert y1 == y0 - 1, f"Up did not move up a line: {y0}->{y1}"
    assert y2 == y0, f"Down did not return: {y1}->{y2}"
