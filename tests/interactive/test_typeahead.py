"""Type-ahead survives a running command.

fortsh restores cooked mode to run a command and re-enters raw mode for the
next prompt. Anything typed in between waits in the tty input queue, and
re-entering raw mode with TCSAFLUSH discarded it — the keystrokes were echoed
by the terminal driver and then silently dropped, so the next prompt came up
empty. Every other shell replays them.

The assertion has to check the text landed in the BUFFER, not merely that it
appears somewhere on screen: the cooked-mode echo puts it on screen either way,
which is exactly how this went unnoticed. Matching the prompt row is what
separates the two.
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

ROWS, COLS = 24, 100
TYPED = "echo TYPED_DURING_SLEEP"


def _prompt_rows(fortsh_path, tmp_path):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HISTFILE"] = "/dev/null"
    env.pop("FORTSH_RC_FILE", None)
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=15, dimensions=(ROWS, COLS))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs):
        end = time.time() + secs
        while time.time() < end:
            try:
                stream.feed(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    drain(1.5)
    child.sendline(b"sleep 2")
    time.sleep(0.6)                      # command running; shell is in cooked mode
    child.send(TYPED.encode())           # type-ahead, deliberately no newline
    drain(4.0)                           # sleep finishes, prompt returns

    rows = [r.rstrip() for r in screen.display if r.strip()]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close(force=True)
    except Exception:
        pass
    return rows


def test_typeahead_during_a_command_reaches_the_buffer(fortsh_path, tmp_path):
    rows = _prompt_rows(fortsh_path, tmp_path)
    # Must be on the PROMPT row, i.e. in the line buffer. The terminal driver
    # echoes the keystrokes while the command runs either way, but that lands
    # on an output row ("echo TYPED_DURING_SLEEPExecuted in 2.0s"), never on a
    # row beginning with the prompt marker. Distinguishing the two is the whole
    # point — matching anywhere on screen passes even when the input was
    # discarded.
    assert any(r.startswith(">") and TYPED in r for r in rows), (
        f"type-ahead discarded on re-entering raw mode: {rows!r}")
