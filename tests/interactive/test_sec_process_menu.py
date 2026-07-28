"""SEC-1: the Ctrl-X process-kill menu must not run $USER through a shell.

get_process_list used to concatenate $USER into `ps -u <USER> ...` and pass it
to popen (/bin/sh -c ...), so a $USER of `; touch MARKER #` executed the touch.
The fix runs ps via execvp with an argv vector, so $USER is one inert argument.
"""
import os
import time

import pexpect

CTRL_X = "\x18"
ESC = "\x1b"


def _spawn(fortsh_path, tmp_path, user_value):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HOME"] = str(tmp_path)
    env["HISTFILE"] = "/dev/null"
    env["FORTSH_TEST_MODE"] = "1"
    env["USER"] = user_value
    env.pop("FORTSH_RC_FILE", None)
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding="utf-8", timeout=8, dimensions=(24, 80))
    _drain_startup(child)
    return child


def _drain_startup(child):
    """Consume the banner before typing.

    Sleeping is not sufficient on macOS: its pty output queues are small, so
    with nobody reading, fortsh blocks part-way through writing the banner and
    never reaches readline. Anything typed meanwhile waits in the tty input
    queue until that read unblocks it, and is then discarded when fortsh enters
    raw mode with TCSAFLUSH — so the Ctrl-X never arrived. Linux's much larger
    pty buffer hides this.
    """
    seen = ""
    deadline = time.time() + 8.0
    while time.time() < deadline:
        try:
            seen += child.read_nonblocking(65536, timeout=0.3)
        except pexpect.TIMEOUT:
            if seen:
                return
        except pexpect.EOF:
            return


def test_malicious_user_does_not_inject(fortsh_path, tmp_path):
    marker = tmp_path / "PWNED"
    child = _spawn(fortsh_path, tmp_path, f"; touch {marker} #")
    child.send(CTRL_X)      # open the process menu -> get_process_list runs ps
    time.sleep(1.0)
    child.send(ESC)         # cancel the menu
    time.sleep(0.3)
    try:
        child.sendline("exit")
        child.expect(pexpect.EOF)
    except Exception:
        pass
    finally:
        child.close()
    assert not marker.exists(), "shell injection via $USER created the marker file"


def test_benign_user_populates_menu(fortsh_path, tmp_path):
    child = _spawn(fortsh_path, tmp_path, os.environ.get("LOGNAME", "root"))
    child.send(CTRL_X)
    # ps always lists at least this shell, so the menu header must appear.
    idx = child.expect(["Select process to signal", "No processes found", pexpect.TIMEOUT])
    child.send(ESC)
    try:
        child.sendline("exit")
        child.expect(pexpect.EOF)
    except Exception:
        pass
    finally:
        child.close()
    assert idx == 0, "process menu did not populate for a benign username"
