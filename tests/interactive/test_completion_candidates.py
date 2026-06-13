"""Completion candidate correctness tests (AR-06).

fish hides dotfiles unless the token starts with '.'. The menu candidate text is
plain (pyte renders it), so the bare-pattern case is checked on the display; the
leading-dot case is checked by executing the completed line.
"""
import os
import time

import pexpect
import pytest

try:
    import pyte
except ImportError:  # pragma: no cover
    pyte = None

try:
    import pwd
    _HAS_ROOT = pwd.getpwnam("root") is not None
except Exception:  # pragma: no cover
    _HAS_ROOT = False

pytestmark = pytest.mark.skipif(pyte is None, reason="pyte not installed")


def _tab_raw(fortsh_path, tmp_path, line):
    """Type `line` (ending in Tab), return the raw bytes emitted in response.
    Raw, not pyte: completion menus / inline expansions reposition the cursor in
    ways pyte mistracks, but the candidate text is emitted verbatim first."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
    raw = bytearray()

    def drain(secs=1.0):
        end = time.time() + secs
        while time.time() < end:
            try:
                raw.extend(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    drain(1.0)
    mark = len(raw)
    child.send(line)
    drain(1.2)
    tail = bytes(raw[mark:])
    _cleanup(child)
    return tail

ROWS, COLS = 24, 90


def _spawn(fortsh_path, tmp_path):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
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

    return child, screen, drain


def _cleanup(child):
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass


def test_dotfiles_hidden_on_bare_pattern(fortsh_path, tmp_path):
    """`ls `+Tab lists visible files but not dotfiles. Checked on the raw byte
    stream — pyte mistracks the menu's draw + cursor-reposition + clear (same
    limitation as the AR-03 menu tests), but the candidate names are emitted
    verbatim before the menu is repositioned."""
    (tmp_path / "apple").write_text("")
    (tmp_path / "banana").write_text("")
    (tmp_path / ".hidden").write_text("")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, COLS))
    raw = bytearray()

    def drain(secs=0.8):
        end = time.time() + secs
        while time.time() < end:
            try:
                raw.extend(child.read_nonblocking(65536, timeout=0.2))
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break

    time.sleep(1.0)
    drain(1.0)
    mark = len(raw)
    child.send(b"ls \t")
    drain(1.2)
    tail = bytes(raw[mark:])
    _cleanup(child)
    assert b"apple" in tail and b"banana" in tail
    assert b".hidden" not in tail


def test_dotfile_completes_with_leading_dot(fortsh_path, tmp_path):
    """`echo .h`+Tab completes the unique dotfile `.hidden` (execution-based)."""
    (tmp_path / ".hidden").write_text("")
    child, screen, drain = _spawn(fortsh_path, tmp_path)
    time.sleep(1.0)
    drain(1.0)
    child.send(b"echo .h\t")
    drain(0.8)
    child.send(b"\r")
    drain(0.8)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    _cleanup(child)
    assert ".hidden" in rows


def test_trailing_space_after_unique_file(fortsh_path, tmp_path):
    """A unique file completion gets a trailing space, so a marker typed right
    after Tab is a separate echo arg: `echo readme.txt Z` -> `readme.txt Z`."""
    (tmp_path / "readme.txt").write_text("")
    child, screen, drain = _spawn(fortsh_path, tmp_path)
    time.sleep(1.0)
    drain(1.0)
    child.send(b"echo readme\t")
    drain(0.8)
    child.send(b"Z\r")
    drain(0.8)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    _cleanup(child)
    assert "readme.txt Z" in rows
    assert "readme.txtZ" not in rows


def test_no_trailing_space_after_dir(fortsh_path, tmp_path):
    """A directory completion ends in `/` with no trailing space, so a marker
    typed after Tab abuts the slash: `echo mydir/Z`."""
    (tmp_path / "mydir").mkdir()
    child, screen, drain = _spawn(fortsh_path, tmp_path)
    time.sleep(1.0)
    drain(1.0)
    child.send(b"echo mydi\t")
    drain(0.8)
    child.send(b"Z\r")
    drain(0.8)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    _cleanup(child)
    assert "mydir/Z" in rows


def test_bare_dollar_lists_variables(fortsh_path, tmp_path):
    """A lone `$`+Tab lists variables (AR-06b): previously the >1 guard meant a
    bare `$` completed nothing. PATH is always set, so it must appear."""
    tail = _tab_raw(fortsh_path, tmp_path, b"echo $\t")
    assert b"PATH" in tail


def test_unexported_var_completes(fortsh_path, tmp_path):
    """An unexported shell variable is offered for `$`-completion (AR-06b: the
    shell state is now threaded into the interactive completion backend). Set
    `myvar` without export, complete `$myv`, execute, expect its value."""
    child, screen, drain = _spawn(fortsh_path, tmp_path)
    time.sleep(1.0)
    drain(1.0)
    child.send(b"myvar=localval\r")   # unexported shell variable
    drain(0.7)
    child.send(b"echo $myv\t")        # completes to $myvar via shell%variables
    drain(0.8)
    child.send(b"\r")
    drain(0.8)
    rows = [r.rstrip() for r in screen.display if r.strip()]
    _cleanup(child)
    assert "localval" in rows


@pytest.mark.skipif(not _HAS_ROOT, reason="no 'root' user to complete")
def test_tilde_user_completes(fortsh_path, tmp_path):
    """`~ro`+Tab completes a username via getpwent (AR-06b): `~root` is offered
    (root exists on the test host)."""
    tail = _tab_raw(fortsh_path, tmp_path, b"echo ~ro\t")
    assert b"~root" in tail
