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


def _line(fortsh_path, tmp_path, chunks, cols=COLS, setup=None):
    """Type each chunk as a discrete keystroke burst; return the input line
    as rendered, plus the cursor's column.

    `setup` is a command run to completion BEFORE typing begins. Folding it
    into `chunks` as "cmd\r" only allowed the inter-chunk 0.15s gap for the
    shell to execute it and repaint, which is not enough on a loaded macOS
    runner — the following keystrokes then landed before the setting applied.
    """
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env.pop("FORTSH_TEST_MODE", None)
    # Pin HOME/HISTFILE so the developer's real history cannot supply a
    # different autosuggestion than the one these assertions expect.
    env["HOME"] = str(tmp_path)
    env["HISTFILE"] = "/dev/null"
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
    if setup is not None:
        child.send(setup + b"\r")
        drain(1.5)
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


def test_multibyte_inside_a_pair_keeps_the_closer(fortsh_path, tmp_path):
    """Regression: a multi-byte insert must shift the pending closer, not
    forfeit it, or the trailing quote opens a second string instead of
    skipping over the one already there."""
    line, _ = _line(fortsh_path, tmp_path,
                    [b"echo '", "\u4e16\u754c".encode("utf-8"), b"'"])
    assert line.startswith("> echo '\u4e16\u754c'")
    assert "''" not in line


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
    line, _ = _line(fortsh_path, tmp_path, [b"echo ("],
                    setup=b"set +o autopair")
    assert line.startswith("> echo (")
    assert "()" not in line


# ------------------------------------------------------- selection wrapping

SHIFT_LEFT = b"\x1b[1;2D"


def test_opener_wraps_a_selection(fortsh_path, tmp_path):
    """An opener typed over a shift-selection surrounds it instead of
    replacing it; every other character still types over."""
    line, _ = _line(fortsh_path, tmp_path, [b"echo abc", SHIFT_LEFT * 3, b"("])
    assert line.startswith("> echo (abc)")


def test_wrapping_can_be_repeated(fortsh_path, tmp_path):
    """The selection is kept over the original text, so a second opener wraps
    around the first pair."""
    line, _ = _line(fortsh_path, tmp_path,
                    [b"echo abc", SHIFT_LEFT * 3, b"(", b'"'])
    assert line.startswith('> echo ("abc")')


def test_non_opener_still_types_over_a_selection(fortsh_path, tmp_path):
    line, _ = _line(fortsh_path, tmp_path, [b"echo abc", SHIFT_LEFT * 3, b"X"])
    assert line.startswith("> echo X")
    assert "abc" not in line


# ------------------------------------------- autosuggestions inside a pair

SUGGEST_FG = "brightblack"     # what fortsh's ESC[90m shadow text reads as


def _cells(fortsh_path, tmp_path, chunks, seed, cols=COLS):
    """Like _line, but seeds history first and returns (text, dim_text) for the
    input row — dim_text being the shadow-rendered autosuggestion. Screen text
    alone cannot tell a suggestion from accepted text; the colour can."""
    env = dict(os.environ)
    env["TERM"] = "xterm-256color"
    env.pop("FORTSH_TEST_MODE", None)
    # Pin HOME/HISTFILE so the developer's real history cannot supply a
    # different autosuggestion than the one these assertions expect.
    env["HOME"] = str(tmp_path)
    env["HISTFILE"] = "/dev/null"
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
    child.sendline(seed)
    time.sleep(0.5)
    drain(0.5)
    for chunk in chunks:
        child.send(chunk)
        time.sleep(0.25)
    drain(0.6)

    rows = [r.rstrip() for r in screen.display]
    idx = [i for i, r in enumerate(rows) if r.startswith(">")]
    assert idx, f"no input line rendered; screen was {[r for r in rows if r]!r}"
    y = idx[-1]
    row = screen.buffer[y]
    text = rows[y]
    dim = "".join(row[x].data for x in range(cols) if row[x].fg == SUGGEST_FG)
    try:
        child.send(b"\x03")
        child.sendline(b"exit")
        child.close(force=True)
    except Exception:
        pass
    return text, dim


SEED = b'echo "quoted hello there"'


def test_suggestion_shows_inside_a_pair(fortsh_path, tmp_path):
    """The pending closer is hidden behind the suggestion, which carries its
    own closing quote — so the line reads right instead of `echo "quo"ted...`."""
    text, dim = _cells(fortsh_path, tmp_path, [b'echo "', b"quo"], SEED)
    assert text.startswith('> echo "quoted hello there"')
    assert dim == 'ted hello there"'


def test_right_accepts_and_consumes_the_pending_closer(fortsh_path, tmp_path):
    """A full accept drops the pending closers: exactly one trailing quote,
    and nothing left rendered as shadow text."""
    text, dim = _cells(fortsh_path, tmp_path,
                       [b'echo "', b"quo", RIGHT], SEED)
    assert text.startswith('> echo "quoted hello there"')
    assert dim == ""
    assert not text.startswith('> echo "quoted hello there""')


def test_word_accept_keeps_the_pair_open(fortsh_path, tmp_path):
    """A PARTIAL accept stays inside the pair, so the closing quote is still
    waiting and is not shadow text."""
    ALT_F = b"\x1bf"
    text, dim = _cells(fortsh_path, tmp_path,
                       [b'echo "', b"quo", ALT_F], SEED)
    assert text.startswith('> echo "quoted "')
    assert '"' not in dim


def test_no_suggestion_leaves_the_closer_visible(fortsh_path, tmp_path):
    """With nothing to suggest, the pending closer renders normally."""
    text, dim = _cells(fortsh_path, tmp_path, [b'echo "', b"zzq"], SEED)
    assert text.startswith('> echo "zzq"')
    assert dim == ""
