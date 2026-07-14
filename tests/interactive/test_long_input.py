"""Long interactive input must reach execution, not truncate silently (QUAL-6).

insert_char_impl dropped characters once the line reached MAX_LINE_LEN-1 (1023)
with no feedback, and the truncated command still ran. A 1100-char `echo`
therefore executed with only 1018 a's. The cap is raised (well above normal use)
and overflow now rings the bell instead of dropping silently. This asserts the
audit's repro: a 1100-char command reaches execution in full, like bash.
"""
import os
import time

import pexpect
import pytest

pytestmark = pytest.mark.ci

ROWS, COLS = 24, 80


def _longest_run(data: bytes, ch: int) -> int:
    longest = cur = 0
    for b in data:
        if b == ch:
            cur += 1
            longest = max(longest, cur)
        else:
            cur = 0
    return longest


def test_1100_char_command_reaches_execution(fortsh_path):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], env=env, encoding=None,
                          timeout=12, dimensions=(ROWS, COLS))
    out = bytearray()

    def drain(secs=1.5):
        end = time.time() + secs
        while time.time() < end:
            try:
                out.extend(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    try:
        time.sleep(1.0)
        drain(1.0)
        n = 1100
        child.send(b"echo " + b"a" * n)
        drain(1.5)
        out.clear()
        child.send(b"\r")
        drain(2.0)
        # echo prints all n a's on its own line; the run must be the full n,
        # not the old 1023-5 = 1018 truncation.
        longest = _longest_run(bytes(out), ord("a"))
        assert longest == n, (
            f"echo output's longest a-run was {longest}, expected {n} "
            f"(input truncated before reaching execution)"
        )
    finally:
        try:
            child.send(b"\x03")
            child.sendline(b"exit")
            child.close()
        except Exception:
            pass
