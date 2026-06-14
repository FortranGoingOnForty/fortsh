"""Command completion richness tests (AR-02b).

CR-2: a command with a bundled subcommand spec completes its subcommands
(`git `+Tab -> subcommands; `git stat`+Tab -> status). CR-3: a '-'-leading
argument completes the command's options (`ls --al`+Tab -> --all/--almost-all),
while a non-dash argument and an unknown command still file-complete.

Read from RAW bytes: completion menus / inline expansions reposition the cursor
in ways pyte mistracks, but the candidate text is emitted verbatim first.
"""
import os
import re
import time

import pexpect

_ANSI = re.compile(rb"\x1b\[[0-9;?]*[A-Za-z]")


def _clean(b):
    """Strip ANSI escapes so a syntax-highlighted line reads as plain text
    (the completed command line is colored: `\\x1b[32mgit\\x1b[0m status`)."""
    return _ANSI.sub(b"", b)


def _tab_raw(fortsh_path, tmp_path, line, settle=1.2):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(24, 90))
    raw = bytearray()

    def drain(secs):
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
    drain(settle)
    tail = bytes(raw[mark:])
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return tail


def test_git_subcommand_menu(fortsh_path, tmp_path):
    """`git `+Tab lists git subcommands (bundled spec, CR-2)."""
    tail = _tab_raw(fortsh_path, tmp_path, b"git \t")
    for sub in (b"commit", b"checkout", b"status", b"branch", b"rebase"):
        assert sub in tail, f"git subcommand {sub!r} missing from menu"


def test_git_subcommand_prefix_filters(fortsh_path, tmp_path):
    """`git che`+Tab narrows to checkout/cherry-pick, not unrelated subcommands."""
    tail = _tab_raw(fortsh_path, tmp_path, b"git che\t")
    assert b"checkout" in tail and b"cherry-pick" in tail
    assert b"commit" not in tail and b"status" not in tail


def test_git_subcommand_unique_completes(fortsh_path, tmp_path):
    """A unique subcommand prefix completes inline: `git stat`+Tab -> status."""
    tail = _tab_raw(fortsh_path, tmp_path, b"git stat\t")
    assert b"git status" in _clean(tail)


def test_option_menu_for_dash_argument(fortsh_path, tmp_path):
    """`ls --al`+Tab offers the matching long options (CR-3)."""
    tail = _tab_raw(fortsh_path, tmp_path, b"ls --al\t")
    assert b"--all" in tail and b"--almost-all" in tail


def test_option_unique_completes(fortsh_path, tmp_path):
    """A unique option prefix completes inline: `grep --col`+Tab -> --color."""
    tail = _tab_raw(fortsh_path, tmp_path, b"grep --col\t")
    assert b"grep --color" in _clean(tail)


def test_non_dash_argument_still_completes_files(fortsh_path, tmp_path):
    """Regression: a non-dash argument file-completes as before (the option
    hook only fires on '-')."""
    (tmp_path / "marker_unique.txt").write_text("")
    tail = _tab_raw(fortsh_path, tmp_path, b"ls marker\t")
    assert b"marker_unique.txt" in tail


def test_unknown_command_dash_falls_through_to_files(fortsh_path, tmp_path):
    """Regression: a command with no option table does NOT invent options; a
    '-'-leading file is still offered (falls through to file completion)."""
    (tmp_path / "-dashfile").write_text("")
    tail = _tab_raw(fortsh_path, tmp_path, b"zzznotacmd -dash\t")
    assert b"-dashfile" in tail
