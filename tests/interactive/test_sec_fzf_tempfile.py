"""SEC-2: fzf browsers must not write through fixed, guessable /tmp names.

The four fzf browsers used to redirect fzf's stdout to fixed paths like
/tmp/fortsh_fzf_selection.tmp via a shell `>` (O_CREAT|O_TRUNC, follows a
symlink). A local attacker could pre-plant a symlink at that name pointing at
a victim file; opening the redirect then truncated the victim, and under
umask 022 the temp file leaked selections world-readable. The fix routes each
browser through mkstemp (O_EXCL, 0600, unpredictable name).

This test plants a symlink at the old fixed selection path and drives the
Ctrl-F browser; the victim file must survive intact.
"""
import os
import time

import pexpect
import pytest

FIXED_SELECTION_PATH = "/tmp/fortsh_fzf_selection.tmp"
CTRL_F = "\x06"
ESC = "\x1b"

pytestmark = pytest.mark.skipif(
    not any(os.access(os.path.join(p, "fzf"), os.X_OK)
            for p in os.environ.get("PATH", "").split(os.pathsep)),
    reason="fzf not installed",
)


def test_symlink_at_fixed_name_not_followed(fortsh_path, tmp_path):
    victim = tmp_path / "victim.txt"
    victim.write_text("PRECIOUS DATA\n" * 8)
    original = victim.read_text()

    # Plant the symlink an attacker would use at the old fixed redirect target.
    if os.path.lexists(FIXED_SELECTION_PATH):
        os.remove(FIXED_SELECTION_PATH)
    os.symlink(victim, FIXED_SELECTION_PATH)

    try:
        env = dict(os.environ)
        env["TERM"] = "xterm-256color"
        env["HOME"] = str(tmp_path)
        env["HISTFILE"] = "/dev/null"
        env["FORTSH_TEST_MODE"] = "1"
        env.pop("FORTSH_RC_FILE", None)
        child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                              encoding="utf-8", timeout=8, dimensions=(24, 80))
        time.sleep(1.0)
        child.send(CTRL_F)      # launch fzf file browser -> opens the redirect
        time.sleep(1.5)
        child.send(ESC)         # cancel fzf
        time.sleep(0.4)
        try:
            child.send("\x03")  # Ctrl-C to clear any partial line
            child.sendline("exit")
            child.expect(pexpect.EOF)
        except Exception:
            pass
        finally:
            child.close()

        assert victim.read_text() == original, \
            "victim file was truncated/overwritten through the planted symlink"
    finally:
        if os.path.lexists(FIXED_SELECTION_PATH):
            os.remove(FIXED_SELECTION_PATH)
