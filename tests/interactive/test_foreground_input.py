"""Foreground-child terminal handoff regressions.

Package managers such as pacman/Paru read confirmations from a canonical TTY.
The child must own the foreground process group and receive the user's line
unchanged, both directly and through a sudo-like nested PTY relay.
"""

from pathlib import Path
import os
import shlex
import shutil
import sys

import pexpect
import pytest


_HELPER = Path(__file__).with_name("confirmation_child.py").resolve()
_COOKED_STATE = b"TTY_STATE foreground=1 canonical=1 echo=1"


def _spawn(fortsh_path, tmp_path):
    fortsh_path = str(Path(fortsh_path).resolve())
    env = dict(os.environ)
    env.update(
        TERM="xterm-256color",
        FORTSH_RC_FILE="/dev/null",
        FORTSH_TEST_MODE="1",
        FORTSH_MINIMAL_ECHO="1",
        HISTFILE="/dev/null",
    )
    child = pexpect.spawn(
        fortsh_path,
        cwd=str(tmp_path),
        env=env,
        encoding=None,
        timeout=8,
        dimensions=(24, 80),
    )
    child.expect_exact(b"> ")
    return child


def _cleanup(child):
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close(force=True)
    except Exception:
        pass


def _assert_confirmation_round_trip(child, command):
    child.sendline(command)

    # This marker is emitted after readline restores the terminal and before
    # the foreground program starts. Waiting for it avoids matching text in
    # fortsh's echoed command line.
    child.expect_exact(b"\x1b[?2004l")
    child.expect_exact(_COOKED_STATE)
    child.expect_exact(b"CONFIRM [Y/n]:")

    child.send(b"y")
    child.expect_exact(b"y")  # canonical TTY echo: the byte reached the child
    with pytest.raises(pexpect.TIMEOUT):
        child.expect_exact(b"ANSWER=", timeout=0.2)

    # pacman/Paru confirmations are line-buffered: y/Y/n is submitted by Enter.
    child.send(b"\r")
    child.expect_exact(b"ANSWER=y")
    child.expect_exact(b"> ")


@pytest.mark.job_control
def test_foreground_child_receives_confirmation_line(fortsh_path, tmp_path):
    child = _spawn(fortsh_path, tmp_path)
    try:
        command = f"python3 {shlex.quote(str(_HELPER))}".encode()
        _assert_confirmation_round_trip(child, command)
    finally:
        _cleanup(child)


@pytest.mark.job_control
@pytest.mark.skipif(
    sys.platform != "linux" or shutil.which("script") is None,
    reason="util-linux script not installed",
)
def test_nested_pty_receives_confirmation_line(fortsh_path, tmp_path):
    child = _spawn(fortsh_path, tmp_path)
    try:
        inner = f"python3 {shlex.quote(str(_HELPER))}"
        command = f"script -qefc {shlex.quote(inner)} /dev/null".encode()
        _assert_confirmation_round_trip(child, command)
    finally:
        _cleanup(child)
