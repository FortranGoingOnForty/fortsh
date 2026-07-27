"""Smart quotes and brackets — screen-level tests (AR-11 PAIRS).

test_specs/autopair.yaml proves the EXECUTED line is right; these prove what
the user actually sees, which output cannot: that a guard suppressed pairing
rather than the pair being expanded away, where the cursor landed, and that
nothing got doubled on screen.

Runs against the real renderer (no FORTSH_TEST_MODE), because test mode has no
redraw and echoes only appended bytes — every mid-buffer edit, which is exactly
what an auto-close creates, is invisible there.
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

ROWS, COLS = 24, 90
BS = b"\x7f"
HOME = b"\x01"          # Ctrl-A
LEFT = b"\x1b[D"
RIGHT = b"\x1b[C"


def _line(fortsh_path, tmp_path, chunks, cols=COLS):
    """Type each chunk as a discrete keystroke burst; return the input line
    as rendered, plus the cursor's column."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env.pop("FORTSH_TEST_MODE", None)
    child = pexpect.spawn(fortsh_path, ["--norc"], cwd=str(tmp_path), env=env,
                          encoding=None, timeout=8, dimensions=(ROWS, cols))
    screen = pyte.Screen(cols, ROWS)
    stream = pyte.ByteStream(screen)

    def drain(secs=0.5):
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
    for chunk in chunks:
        child.send(chunk)
        time.sleep(0.15)
    drain(0.6)

    rendered = [r.rstrip() for r in screen.display if r.strip()]
    col = screen.cursor.x
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close(force=True)
    except Exception:
        pass

    prompt_lines = [r for r in rendered if r.startswith(">")]
    assert prompt_lines, f"no input line rendered; screen was {rendered!r}"
    # The autosuggestion is rendered inline after the buffer, so callers match
    # on a prefix rather than the whole line.
    return prompt_lines[-1], col


# ---------------------------------------------------------------- auto-close

@pytest.mark.parametrize("opener,pair", [
    (b"(", "()"),
    (b"[", "[]"),
    (b"{", "{}"),
    (b'"', '""'),
    (b"'", "''"),
    (b"`", "``"),
])
def test_opener_inserts_its_closer(fortsh_path, tmp_path, opener, pair):
    line, col = _line(fortsh_path, tmp_path, [b"echo ", opener])
    assert line.startswith(f"> echo {pair}")
    # Cursor parks BETWEEN the two halves: "> echo (" is 8 columns.
    assert col == 8


def test_typing_continues_inside_the_pair(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo (", b"x"])
    assert line.startswith("> echo (x)")


def test_pairs_nest(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo (", b"["])
    assert line.startswith("> echo ([])")


def test_brace_pairs_inside_double_quotes(fortsh_path, tmp_path):
    """${ is the substitution opener that makes pairing inside "..." worth it."""
    line, _ = _line(fortsh_path, tmp_path, [b'echo "', b"$", b"{"])
    assert line.startswith('> echo "${}"')


# --------------------------------------------------------------- the guards

def test_apostrophe_in_a_word_does_not_pair(fortsh_path, tmp_path):
    """G2: pairing after a word character would turn don't into don''t."""
    line, _ = _line(fortsh_path, tmp_path, [b"echo don't"])
    assert line.startswith("> echo don't")
    assert "don''t" not in line


def test_opener_before_existing_text_inserts_alone(fortsh_path, tmp_path):
    """G1: the character after the cursor is a word char, so no closer."""
    line, _ = _line(fortsh_path, tmp_path, [b"echo foo", HOME, b"("])
    assert line.startswith("> (echo foo")
    assert "()" not in line


def test_backslash_escaped_opener_does_not_pair(fortsh_path, tmp_path):
    r"""\" must insert one literal quote — there is no quoted-insert key."""
    line, _ = _line(fortsh_path, tmp_path, [b"echo ", b"\\", b'"'])
    assert line.startswith('> echo \\"')
    assert '\\""' not in line


def test_single_quotes_suppress_pairing_inside_them(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo '", b"a", b"(", b"b"])
    assert line.startswith("> echo 'a(b'")


def test_third_quote_extends_instead_of_pairing(fortsh_path, tmp_path):
    """Three typed quotes give three quotes: pair, skip over, then literal."""
    line, _ = _line(fortsh_path, tmp_path, [b'echo "', b'"', b'"'])
    assert line.startswith('> echo """')
    assert '""""' not in line


# -------------------------------------------------------------- skip-over

def test_typed_closer_skips_over_ours(fortsh_path, tmp_path):
    line, col = _line(fortsh_path, tmp_path, [b"echo (", b")"])
    assert line.startswith("> echo ()")
    assert col == 9          # past the closer, not before a second one


def test_skip_over_survives_cursor_motion(fortsh_path, tmp_path):
    """Motion moves no bytes, so the tracked position stays valid."""
    line, col = _line(fortsh_path, tmp_path,
                      [b"echo (", HOME, RIGHT * 6, b")"])
    assert line.startswith("> echo ()")
    assert col == 9


def test_untracked_closer_is_inserted_not_skipped(fortsh_path, tmp_path):
    """A hand-typed ')' in front of an unrelated ')' must still insert."""
    line, _ = _line(fortsh_path, tmp_path,
                    [b"echo a)b", HOME, RIGHT * 6, b")"])
    assert line.startswith("> echo a))b")


# --------------------------------------------------------------- backspace

def test_backspace_removes_both_halves(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo (", BS])
    assert line.startswith("> echo")
    assert "(" not in line and ")" not in line


def test_backspace_unwinds_nested_pairs_one_at_a_time(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo (", b"[", BS])
    assert line.startswith("> echo ()")


def test_tracking_survives_a_plain_backspace(fortsh_path, tmp_path):
    """Deleting a byte inside the pair shifts the closer, it does not lose it."""
    line, col = _line(fortsh_path, tmp_path, [b"echo (ab", BS, b")"])
    assert line.startswith("> echo (a)")
    assert col == 10         # skip-over still worked afterwards


def test_backspace_is_plain_once_the_pair_was_skipped(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo (", b")", BS])
    assert line.startswith("> echo (")
    assert "()" not in line


# ------------------------------------------------------------- set -o

def test_set_plus_o_autopair_disables_it(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"set +o autopair\r", b"echo ("])
    assert line.startswith("> echo (")
    assert "()" not in line
