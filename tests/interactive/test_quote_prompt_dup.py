"""Regression: typing shell metacharacters must not duplicate the prompt.

Class of bug (previously hit by #51, fixed in 6d85f03): a per-keystroke code
path built a /bin/sh command string by concatenating the *typed word* into a
double-quoted argument, e.g.

    ls_command = 'ls -1aF "' // trim(expanded_dir) // '/" 2>/dev/null | grep -i "^' &
                 // trim(pattern) // '"'

An unbalanced `"` (or a backtick, or `$(`) in the buffer therefore made the
child shell fail to parse its own command line and print

    sh: -c: line 1: unexpected EOF while looking for matching `"'

straight to the tty. That stray line + newline scrolls the display out from
under readline, whose redraw tracks the prompt origin by row count — so the
next redraw repaints the whole prompt one row lower. Typing `"` repeatedly
walked a fresh copy of the prompt down the screen.

The fix was to stop shelling out for directory enumeration at all (native
opendir/readdir). This test locks the *behaviour*, not the implementation:
while a line is being edited, nothing but readline may write to the terminal,
so the prompt must appear exactly once no matter what metacharacters are typed.
"""
import os
import time

import pexpect
import pytest

try:
    import pyte
except ImportError:  # pragma: no cover
    pyte = None

pytestmark = [
    pytest.mark.ci,
    pytest.mark.prompt,
    pytest.mark.skipif(pyte is None, reason="pyte not installed"),
]

ROWS, COLS = 24, 80

# Distinctive first prompt line so counting occurrences is unambiguous, plus a
# second line ('> ') and an RPROMPT — the two-line + right-prompt layout the
# duplication was reported against. No \w: the prompt must render identically
# whatever directory the suite runs from.
PROMPT_MARK = "FORTSH-PROMPT-MARK"
RC_TEXT = "PS1='" + PROMPT_MARK + "\n> '\nRPROMPT='rp'\n"

# Metacharacters that are inert inside single quotes but break out of a
# double-quoted shell word — exactly the ones that exposed the old shell-out.
# ("'" is included as the control: it never triggered the bug.)
METACHARS = ['"', '`', '$(', "'"]


def _spawn(fortsh_path, home):
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    # Own HOME, holding the rc: without a ~/.fortshrc (or ~/.fortsh_profile)
    # fortsh treats the session as a first run and blocks on
    # "Create default configs? [Y/n]:", so the prompt never renders. A CI
    # runner has no config; a developer's machine does. Pinning HOME makes the
    # test behave the same on both. FORTSH_TEST_MODE would also skip that
    # prompt, but it disables the redraw this test exists to exercise.
    env["HOME"] = str(home)
    env["FORTSH_RC_FILE"] = str(home / ".fortshrc")
    env["HISTFILE"] = "/dev/null"
    return pexpect.spawn(fortsh_path, [], env=env, encoding=None,
                         timeout=8, dimensions=(ROWS, COLS))


@pytest.mark.parametrize("meta", METACHARS)
def test_metachar_typing_does_not_duplicate_prompt(fortsh_path, tmp_path, meta):
    (tmp_path / ".fortshrc").write_text(RC_TEXT)

    child = _spawn(fortsh_path, tmp_path)
    screen = pyte.Screen(COLS, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.3):
        chunk = bytearray()
        end = time.time() + secs
        while time.time() < end:
            try:
                data = child.read_nonblocking(65536, timeout=0.1)
                chunk.extend(data)
                stream.feed(data)
            except pexpect.TIMEOUT:
                pass
            except pexpect.EOF:
                break
        return bytes(chunk)

    try:
        time.sleep(1.0)
        drain(0.8)
        child.send(b"\x0c")  # Ctrl-L: start from a clean screen
        drain(0.5)

        assert sum(1 for line in screen.display if PROMPT_MARK in line) == 1, (
            "prompt did not render exactly once before typing"
        )

        emitted = bytearray()
        for _ in range(6):
            child.send(meta.encode())
            emitted.extend(drain(0.3))

        text = emitted.decode("utf-8", "replace")
        # Nothing but readline may write while a line is being edited.
        assert "sh:" not in text and "unexpected EOF" not in text, (
            "a subprocess wrote to the tty while editing: " + repr(text[:400])
        )

        copies = sum(1 for line in screen.display if PROMPT_MARK in line)
        assert copies == 1, (
            "prompt duplicated %d times after typing %r:\n%s"
            % (copies, meta,
               "\n".join(l.rstrip() for l in screen.display if l.strip()))
        )
    finally:
        child.terminate(force=True)
