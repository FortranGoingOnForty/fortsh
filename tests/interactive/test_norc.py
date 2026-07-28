"""--norc startup-file isolation (DOC-5).

Every pytest in this suite spawns `fortsh --norc` and assumes the user's real
~/.fortshrc is not sourced. Before DOC-5 the option was silently ignored, so
the whole suite ran against whatever the host rc file configured. These tests
pin the contract with a sentinel rc file in a throwaway HOME.
"""
import os
import time

import pexpect


def _spawn(fortsh_path, home, args):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HOME"] = str(home)
    env["HISTFILE"] = "/dev/null"
    env["FORTSH_TEST_MODE"] = "1"
    env.pop("FORTSH_RC_FILE", None)
    child = pexpect.spawn(fortsh_path, args, env=env, encoding="utf-8",
                          timeout=8, dimensions=(24, 80))

    # Drain startup output BEFORE typing anything. Sleeping instead is not
    # enough on macOS, and not because the shell is slow — the prompt is up in
    # ~30ms. macOS pty output queues are small, so with nobody reading, fortsh
    # blocks part-way through writing its banner and never reaches readline.
    # Whatever we typed then sits in the tty input queue until the read
    # unblocks it, at which point fortsh enters raw mode with TCSAFLUSH
    # (system/interface.f90) and discards it. The `exit` was echoed in cooked
    # mode and dropped, so the shell sat at a prompt forever. Linux's much
    # larger pty buffer hides all of this.
    out = ""
    deadline = time.time() + 8.0
    while time.time() < deadline:
        try:
            out += child.read_nonblocking(65536, timeout=0.3)
        except pexpect.TIMEOUT:
            if out:
                break          # output started and then went quiet: prompt is up
        except pexpect.EOF:
            break

    child.sendline("exit")
    try:
        child.expect(pexpect.EOF, timeout=8)
        out += child.before or ""
    except pexpect.TIMEOUT:
        pass
    child.close(force=True)
    return out


def _write_sentinel(home):
    home.mkdir(exist_ok=True)
    (home / ".fortshrc").write_text("echo RC_SENTINEL_LOADED\n")


def test_rc_loads_by_default(fortsh_path, tmp_path):
    """Sanity check: without --norc the sentinel rc is sourced, proving the
    sentinel setup works and the skip below is --norc's doing."""
    home = tmp_path / "home"
    _write_sentinel(home)
    out = _spawn(fortsh_path, home, [])
    assert "RC_SENTINEL_LOADED" in out


def test_norc_skips_rc_file(fortsh_path, tmp_path):
    home = tmp_path / "home"
    _write_sentinel(home)
    out = _spawn(fortsh_path, home, ["--norc"])
    assert "RC_SENTINEL_LOADED" not in out


def test_unknown_option_exits_2(fortsh_path, tmp_path):
    child = pexpect.spawn(fortsh_path, ["--badopt", "-c", "echo hi"],
                          encoding="utf-8", timeout=8)
    child.expect(pexpect.EOF)
    out = child.before or ""
    child.close()
    assert "invalid option" in out
    assert "hi" not in out.splitlines()
    assert child.exitstatus == 2
