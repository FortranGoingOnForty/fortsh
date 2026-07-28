"""Completion menu under a prompt that WRAPS (AR-03 / live-preview row math).

update_live_preview rewrites the command line in place, which means moving the
cursor up past the drawn menu to the first prompt row. It counted the prompt's
NEWLINES to decide how far, but a prompt longer than the terminal is wide
occupies more rows than it has lines. The up-move then stopped short and the
rewrite repainted the prompt on top of the table: the command line appeared
twice and the menu vanished.

Nothing pins the prompt here on purpose — the point is to exercise fortsh's
real `user@host :: cwd` prompt in a terminal too narrow to hold it. The other
layout tests pin PS1 so they measure completion behaviour rather than prompt
geometry; this one measures the geometry.

Reproduced on Linux and macOS alike, and present in 1.9.0. CI met it first on
the macOS runner only because runner hostnames are ~60 characters.
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

ROWS = 24
# Deep enough that even fortsh's abbreviated path keeps the prompt wider than
# the narrowest terminal below.
DEEP = "a/b/c/d/e/f/g/completion_menu_under_a_wrapped_prompt"


def _run(fortsh_path, tmp_path, cols):
    work = tmp_path / DEEP
    work.mkdir(parents=True)
    (work / "sub").mkdir()
    runme = work / "runme"
    runme.write_text("#!/bin/sh\necho hi\n")
    os.chmod(runme, 0o755)

    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HISTFILE"] = "/dev/null"
    env.pop("FORTSH_RC_FILE", None)
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(work), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, cols))
    screen = pyte.Screen(cols, ROWS)
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

    time.sleep(1.0)
    drain(1.0)
    for key in (b"./", b"\t", b"\t"):   # second Tab enters menu-select
        child.send(key)
        drain(1.2)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close(force=True)
    except Exception:
        pass
    return rows


@pytest.mark.parametrize("cols", [40, 60, 80])
def test_menu_survives_a_wrapping_prompt(fortsh_path, tmp_path, cols):
    rows = _run(fortsh_path, tmp_path, cols)
    blob = "\n".join(rows)
    assert "runme" in blob, f"menu lost under a wrapped prompt at {cols} cols: {rows!r}"
    assert "sub" in blob, f"menu lost under a wrapped prompt at {cols} cols: {rows!r}"


@pytest.mark.parametrize("cols", [40, 60, 80])
def test_wrapping_prompt_is_not_duplicated(fortsh_path, tmp_path, cols):
    """The give-away symptom: the same prompt row rendered twice, because the
    rewrite landed one row too low."""
    rows = _run(fortsh_path, tmp_path, cols)
    # The prompt's first row is whatever line carries the "@host ::" marker.
    prompt_rows = [r for r in rows if "@" in r and "::" in r]
    assert len(prompt_rows) <= 1, (
        f"prompt row repeated at {cols} cols (live-preview up-move short): {rows!r}")
