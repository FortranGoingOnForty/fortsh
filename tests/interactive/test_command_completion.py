"""Command-position completion regression tests (AR-02).

A command must be runnable, so completing a path in command position must offer
executables + directories only — never plain data files. cand-2: `./`+Tab used
to collapse to dirs-only (dropping executables). cand-3: `./r`+Tab used to offer
non-executable files alongside executables.
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

ROWS, COLS = 24, 110


def _mkdir(tmp_path):
    (tmp_path / "sub").mkdir()
    runme = tmp_path / "runme"
    runme.write_text("#!/bin/sh\necho hi\n")
    os.chmod(runme, 0o755)
    (tmp_path / "data.txt").write_text("data\n")
    (tmp_path / "readme.txt").write_text("readme\n")  # shares 'r' prefix, NOT +x


def _drive(tmp_path, keys, settle=1.2):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(os.path.expanduser(
        os.environ.get("FORTSH", "./bin/fortsh")), ["--norc"],
        cwd=str(tmp_path), env=env, encoding=None, timeout=8,
        dimensions=(ROWS, COLS))
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

    time.sleep(1.0)
    drain(1.0)
    for k in keys:
        child.send(k)
        drain(settle)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return rows


def test_cmd_path_tab_offers_executables_and_dirs(fortsh_path, tmp_path):
    """cand-2: `./`+Tab (open menu) offers the executable and the directory,
    not the plain data files."""
    os.environ["FORTSH"] = fortsh_path
    _mkdir(tmp_path)
    rows = _drive(tmp_path, [b"./", b"\t", b"\t"])
    blob = "\n".join(rows)
    assert "runme" in blob, f"executable dropped from command completion: {rows!r}"
    assert "sub" in blob, f"directory dropped from command completion: {rows!r}"
    assert "data.txt" not in blob, f"non-executable data file offered as command: {rows!r}"
    assert "readme.txt" not in blob, f"non-executable file offered as command: {rows!r}"


def test_cmd_path_pattern_excludes_nonexecutables(fortsh_path, tmp_path):
    """cand-3: `./r`+Tab resolves to the executable `runme` only — the
    non-executable `readme.txt` (same prefix) is excluded, so it's a unique
    match and completes."""
    os.environ["FORTSH"] = fortsh_path
    _mkdir(tmp_path)
    rows = _drive(tmp_path, [b"./r", b"\t"])
    cmd = next((r for r in rows if "./r" in r and r.lstrip().startswith(">")), "")
    assert "runme" in cmd, f"executable not completed: {rows!r}"
    assert "readme" not in cmd, f"non-executable offered in command position: {rows!r}"


def test_path_command_scan(fortsh_path, tmp_path):
    """cand-1: a bare command-position prefix completes executables found on
    $PATH (not just the ~35 hardcoded names). Uses a synthetic PATH dir so the
    test doesn't depend on which system binaries exist."""
    bindir = tmp_path / "bin"
    bindir.mkdir()
    exe = bindir / "zzcustomcmd"
    exe.write_text("#!/bin/sh\n")
    os.chmod(exe, 0o755)
    (bindir / "zzcustomdata").write_text("data\n")  # present but NOT executable

    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["PATH"] = str(bindir) + ":" + env.get("PATH", "")
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
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

    time.sleep(1.0)
    drain(1.0)
    for ch in b"zzcustom":
        child.send(bytes([ch]))
        time.sleep(0.03)
    drain(0.4)
    child.send(b"\t")  # unique executable match -> completes
    drain(1.2)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    blob = "\n".join(rows)
    assert "zzcustomcmd" in blob, f"PATH executable not completed: {rows!r}"
    cmd = next((r for r in rows if r.lstrip().startswith(">")), "")
    assert "zzcustomdata" not in cmd, f"non-executable PATH entry completed: {rows!r}"
