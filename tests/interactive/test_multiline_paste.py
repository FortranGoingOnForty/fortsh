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
