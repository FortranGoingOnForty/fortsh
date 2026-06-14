"""Terminal-resize redraw regression (the "staircase" bug).

After narrowing the terminal so the prompt wraps, typing must keep redrawing the
command on one line — not drift one row down (and one column right) per keystroke.
Root cause was the redraw computing the cursor's row two different (both wrong)
ways: the nav-up undercounted a wrapped prompt's height while the diff-down
(content_byte_to_row_col) counted it correctly, so they no longer cancelled.

Rendered through pyte (a real VT emulator) since the bug is purely about where
escape sequences land on screen.
"""
import os
import time

import pexpect
import pytest

try:
    import pyte
except ImportError:  # pragma: no cover
    pyte = None

pytestmark = pytest.mark.skipif(pyte is None, reason="pyte not installed")


def test_typing_after_narrow_resize_does_not_staircase(fortsh_path, tmp_path):
    # A file whose name yields a path autosuggestion ending in .txt.
    (tmp_path / "zzfile_marker.txt").write_text("")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(24, 80))
    raw = bytearray()

    def drain(secs):
        end = time.time() + secs
        while time.time() < end:
            try:
                raw.extend(child.read_nonblocking(65536, timeout=0.15))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    drain(1.0)
    child.send(b"cat zz")          # path suggestion "file_marker.txt" appears
    drain(0.7)
    child.setwinsize(24, 28)       # narrow -> the prompt's first line wraps
    drain(0.9)
    for ch in (b"f", b"i", b"l"):  # type into the suggestion, one char at a time
        child.send(ch)
        drain(0.4)

    screen = pyte.Screen(28, 24)
    stream = pyte.ByteStream(screen)
    stream.feed(bytes(raw))
    rows = [r.rstrip() for r in screen.display]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass

    # The suggestion ends in ".txt". With the staircase bug it was redrawn on a
    # new row per keystroke, so ".txt" appeared on several rows; fixed, it sits
    # on exactly one (the command line).
    txt_rows = [r for r in rows if ".txt" in r]
    assert len(txt_rows) == 1, (
        f"command staircased across rows after resize:\n" +
        "\n".join(f"  {r!r}" for r in rows if r.strip()))
    # And the typed text is contiguous on that row (not one char per row).
    assert "cat zzfil" in txt_rows[0], txt_rows
