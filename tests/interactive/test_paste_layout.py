"""Layout regression tests for the bracketed-paste path.

These assert terminal-cell layout (via pyte screen emulation), which the
YAML substring harness can't express. Regression target: pasting a command
then executing left the next prompt / command output colliding on one row,
because a deferred paste redraw fired AFTER the submit newline. See the
"skip redraw when done" guard in readline.f90.
"""
import time

import pexpect
import pytest

try:
    import pyte
except ImportError:  # pragma: no cover
    pyte = None

pytestmark = pytest.mark.skipif(pyte is None, reason="pyte not installed")

ROWS, COLS = 24, 80


def _run_paste(fortsh_path, payload):
    """Spawn fortsh, bracketed-paste `payload`, press Enter, return the
    pyte screen after execution."""
    import os
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.8):
        end = time.time() + secs
        while time.time() < end:
            try:
                stream.feed(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    drain(1.0)
    child.send(b"\x1b[200~" + payload + b"\x1b[201~")
    drain(0.6)
    child.send(b"\r")
    drain(0.8)
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return [r.rstrip() for r in screen.display]


def test_paste_execute_output_on_own_line(fortsh_path):
    """A pasted echo must leave its output on a row of its own, not fused
    onto the command line or the next prompt."""
    rows = _run_paste(fortsh_path, b"echo PASTEMARK")
    # The command line row contains 'echo PASTEMARK'; the output row is
    # 'PASTEMARK' alone (no prompt, no 'echo'). The corruption produced
    # rows like 'echo PASTEMARKPASTEMARK' or a prompt fused to output.
    output_rows = [r for r in rows if "PASTEMARK" in r
                   and "echo" not in r and ">" not in r]
    assert output_rows, f"output not on its own line; screen={rows!r}"
    # No row may contain the doubled marker (command fused with output)
    assert not any("PASTEMARKPASTEMARK" in r for r in rows), \
        f"command line fused with output; screen={rows!r}"


def test_paste_execute_next_prompt_isolated(fortsh_path):
    """The prompt after a pasted command must not share a row with output."""
    rows = _run_paste(fortsh_path, b"echo ISOLATED")
    fused = [r for r in rows if "ISOLATED" in r and ">" in r and "echo" not in r]
    assert not fused, f"prompt fused with output; screen={rows!r}"
