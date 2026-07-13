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
    time.sleep(1.0)
    child.sendline("exit")
    child.expect(pexpect.EOF)
    out = child.before or ""
    child.close()
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
