"""Syntax-highlight SGR tests (AR-09).

fortsh emits real SGR under a PTY, so we assert exact escape sequences on raw
bytes. Highlighting is OFF in test mode, so these run in normal mode: an rc file
is created (skips the first-run prompt) and PS1 is single-line; FORTSH_TEST_MODE
is unset so the real redraw + highlighter run. The whole line is sent in one
write (no per-keystroke steps) to avoid rapid-fire PTY races.

Scope per the user's AR-09 decision ("parity minus boldest cosmetics"): keep
green commands / gray comments / default args; DO recolor terminators green and
variables bright-cyan, and add error/validation states.
"""
import os
import time

import pexpect


def _spawn(fortsh_path, tmp_path, cols=100):
    (tmp_path / ".fortshrc").write_text("PS1='hl> '\n")
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env["HOME"] = str(tmp_path)
    env.pop("FORTSH_TEST_MODE", None)
    return pexpect.spawn(fortsh_path, [], cwd=str(tmp_path), env=env,
                         encoding=None, timeout=8, dimensions=(24, cols))


def _drain(child, raw, secs):
    end = time.time() + secs
    while time.time() < end:
        try:
            raw.extend(child.read_nonblocking(65536, timeout=0.2))
        except pexpect.TIMEOUT:
            pass
        except pexpect.EOF:
            break


def _type_line(fortsh_path, tmp_path, line, cols=100):
    """Type `line` (no Enter) in normal mode; return the highlighted frame."""
    child = _spawn(fortsh_path, tmp_path, cols)
    raw = bytearray()
    time.sleep(1.0)
    _drain(child, raw, 1.2)
    mark = len(raw)
    child.send(line.encode())
    _drain(child, raw, 0.8)
    frame = bytes(raw[mark:])
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close()
    except Exception:
        pass
    return frame


def test_terminators_green(fortsh_path, tmp_path):
    """HL-06: bare | ; & are green (fish_color_end); && stays operator cyan."""
    frame = _type_line(fortsh_path, tmp_path, "echo a | cat && ls; pwd")
    assert b"\x1b[32m|\x1b[0m" in frame, f"pipe not green: {frame!r}"
    assert b"\x1b[32m;\x1b[0m" in frame, f"semicolon not green: {frame!r}"
    # && must NOT become a terminator — stays operator cyan (kept palette).
    assert b"\x1b[36m&&\x1b[0m" in frame, f"&& not operator-cyan: {frame!r}"


def test_background_amp_green(fortsh_path, tmp_path):
    """HL-06: a trailing background & is a terminator (green)."""
    frame = _type_line(fortsh_path, tmp_path, "sleep 1 &")
    assert b"\x1b[32m&\x1b[0m" in frame, f"background & not green: {frame!r}"


def test_variable_bright_cyan(fortsh_path, tmp_path):
    """HL-07 (color): $name uses the operator role (bright cyan), not magenta."""
    frame = _type_line(fortsh_path, tmp_path, "echo $HOME")
    assert b"\x1b[96m$HOME\x1b[0m" in frame, f"variable not bright-cyan: {frame!r}"
    assert b"\x1b[35m" not in frame, f"magenta still used for variable: {frame!r}"


def test_valid_command_stays_green(fortsh_path, tmp_path):
    """Kept palette (HL-01 opted out): a valid command stays green."""
    frame = _type_line(fortsh_path, tmp_path, "echo hi")
    assert b"\x1b[32mecho\x1b[0m" in frame, f"command no longer green: {frame!r}"


def test_unclosed_single_quote_red(fortsh_path, tmp_path):
    """HL-04: the opening quote of an unterminated string is red; body yellow."""
    frame = _type_line(fortsh_path, tmp_path, "echo 'ab")
    assert b"\x1b[31m'\x1b[0m" in frame, f"unclosed quote not red: {frame!r}"
    assert b"\x1b[33mab\x1b[0m" in frame, f"quote body not yellow: {frame!r}"


def test_bare_dollar_red(fortsh_path, tmp_path):
    """HL-07: a bare `$` is a red error."""
    frame = _type_line(fortsh_path, tmp_path, "echo $")
    assert b"\x1b[31m$\x1b[0m" in frame, f"bare $ not red: {frame!r}"


def test_special_param_not_red(fortsh_path, tmp_path):
    """HL-07: POSIX special params $? $@ are valid bright-cyan, not red."""
    frame = _type_line(fortsh_path, tmp_path, "echo $? $@")
    assert b"\x1b[96m$?\x1b[0m" in frame, f"$? not bright-cyan: {frame!r}"
    assert b"\x1b[96m$@\x1b[0m" in frame, f"$@ not bright-cyan: {frame!r}"


def test_assignment_not_red(fortsh_path, tmp_path):
    """HL-03: a leading VAR=value is an assignment (not a red invalid command),
    and the command after it still highlights as a valid command."""
    frame = _type_line(fortsh_path, tmp_path, "FOO=bar ls")
    assert b"\x1b[31mFOO=bar" not in frame, f"assignment colored red: {frame!r}"
    assert b"\x1b[32mls\x1b[0m" in frame, f"command after assignment not green: {frame!r}"


def test_existing_path_arg_underlined(fortsh_path, tmp_path):
    """HL-02: an argument naming an existing file is underlined; a nonexistent
    one is not (works for plain names, no slash needed)."""
    (tmp_path / "realfile").write_text("x")
    frame = _type_line(fortsh_path, tmp_path, "cat realfile")
    assert b"\x1b[4mrealfile\x1b[0m" in frame, f"existing path not underlined: {frame!r}"
    frame2 = _type_line(fortsh_path, tmp_path, "cat nofilexyz")
    assert b"\x1b[4mnofilexyz" not in frame2, f"nonexistent path underlined: {frame2!r}"


def test_redirect_operator_bold(fortsh_path, tmp_path):
    """HL-08: the redirect operator is bold cyan (fish_color_redirection)."""
    frame = _type_line(fortsh_path, tmp_path, "echo a > out.txt")
    assert b"\x1b[1m\x1b[36m>\x1b[0m" in frame, f"redirect op not bold-cyan: {frame!r}"


def test_redirect_target_missing_dir_red(fortsh_path, tmp_path):
    """HL-08: a redirect target whose parent directory does not exist is red."""
    frame = _type_line(fortsh_path, tmp_path, "echo a > /nope/x")
    assert b"\x1b[31m/nope/x\x1b[0m" in frame, f"impossible target not red: {frame!r}"
