# Handoff: six macOS-ARM64-only interactive pytest failures

**Status:** open. **Platform:** macOS on Apple Silicon (flang-new build). **Blocks:** re-enabling the
interactive pytest suite on the macOS CI job.

## Why this document exists

`tests/interactive/` has two suites. The YAML specs (`test_specs/*.yaml`, run by
`run_tests.py`) have always run in CI on all three platforms. The pytest files
(`test_*.py`) ran **nowhere** — and were in fact broken: `find_fortsh_binary` in
`conftest.py` returned a path relative to pytest's invocation directory, while the
tests spawn fortsh with `cwd=tmp_path`, so every one of them failed to spawn at all.

That was fixed in the v1.10.0 branch, and the suite was wired into CI. On both Linux
runners it is fully green. On macOS ARM64 it exposed **six pre-existing failures**
that have nothing to do with the change that enabled them. Rather than ship a
permanently red job, or mark them `known_failure` (which would blind the Linux
runners too, where they pass), the macOS job was left on YAML-only with a pointer
to this file.

**The goal is to fix these six and add the pytest step back to the macOS job.**

## Getting set up

```bash
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh
git checkout release-1.10.0     # or trunk, once merged

# macOS ARM64 needs flang-new; gfortran has known miscompiles on Apple Silicon.
brew install flang fzf
make release                     # produces bin/fortsh

cd tests/interactive
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt

# Reproduce exactly what CI runs:
./.venv/bin/python -m pytest -q -m "not known_failure"
```

Expected on this machine: `7 failed, 152 passed, 2 skipped, 5 deselected`. One of
those seven (`test_autopair.py::test_set_plus_o_autopair_disables_it`) has since been
fixed — it was a genuine race where a setup command was folded into the keystroke
stream. The remaining six are below.

Run a single case with full output:

```bash
./.venv/bin/python -m pytest test_norc.py::test_rc_loads_by_default -q -s
```

## Ground rules before you "fix" anything

These matter more than usual here, because this suite has a documented history of
tests that passed for the wrong reason.

1. **Decide first whether the bug is in fortsh or in the test.** Both kinds are
   present in this repo. Two POSIX specs were recently found asserting on the
   *echoed input line* rather than on command output — `echo "a"b"c"` prints `abc`,
   but the expectation was `a"b"c`, so they matched the terminal echo and never
   exercised the shell at all. Ask what each assertion would catch if fortsh were
   subtly wrong.
2. **Never assert on text that also appears in the keystrokes.** The PTY stream
   contains the echo of what you typed. Prefer something only execution can
   produce — an arithmetic result (`$((6*7))` → `42`) is the idiom used in
   `test_specs/autopair.yaml`.
3. **Do not reach for `@pytest.mark.known_failure` to make a red test go away.**
   It is for pre-existing debt that is genuinely out of scope, it requires a
   written reason, and it hides the test on *every* platform. See `pytest.ini`.
4. **Check whether the failure is Linux-vs-macOS or fast-vs-slow.** The macOS
   runner is heavily loaded and much slower. Several of the cases below smell like
   timing. A timing fix is legitimate, but fix it by *waiting for the condition*
   (drain until the prompt/marker appears), not by inflating a `sleep`.
5. **Confirm against a pre-feature build before blaming recent work.** The trick
   used during v1.10.0:
   ```bash
   git worktree add /tmp/fortsh-base <older-sha> && cd /tmp/fortsh-base && make release
   FORTSH=/tmp/fortsh-base/bin/fortsh ./.venv/bin/python -m pytest <file> -q
   ```
   All six below were confirmed present before the autopair work.

## The six failures

### 1. `test_norc.py::test_rc_loads_by_default` — TIMEOUT
### 2. `test_norc.py::test_norc_skips_rc_file` — TIMEOUT

Both write a sentinel `~/.fortshrc` into a throwaway `HOME` that echoes
`RC_SENTINEL_LOADED`, spawn fortsh with that `HOME`, and check whether the sentinel
was sourced. Both time out rather than assert-fail, so the shell likely never
reached a usable prompt.

Worth checking, roughly in order of suspicion:

- Does `check_first_run_and_prompt` (`src/scripting/config.f90`) block? It prompts
  interactively on a HOME with no config files, and it is skipped only when
  `FORTSH_TEST_MODE` is set. `test_norc.py` does not set that variable. On Linux the
  sentinel file exists so the first-run branch returns early — verify the file is
  actually landing where fortsh looks on macOS.
- Is it `~/.fortshrc` vs `~/.fortsh_profile` and login-vs-interactive detection?
  `load_config_file` branches on `is_login_shell` / `is_interactive`; a PTY spawned
  differently on macOS could take the login path and read `.fortsh_profile` instead.
- Note this failure is *self-referential*: every other pytest in the suite spawns
  `--norc` and assumes rc isolation. If `--norc` is genuinely broken on macOS, some
  of the other four failures below may be downstream of it. **Fix these two first**
  and re-run the whole suite before investigating the rest.

### 3. `test_command_completion.py::test_cmd_path_tab_offers_executables_and_dirs`

> `AssertionError: executable dropped from command completion`

The rendered line at failure was `> ./sub/` with the executable missing from the
candidate list. Two leads:

- The prompt in the captured screen is enormously long
  (`runner@sjc22-bm213-52751a63-…-3EBF8260FBD3 :: /p/v/f/p/2/T/p/p/test_cmd_path_tab_off`)
  and wrapped across two rows, with the path aggressively abbreviated. The
  assertion reads rendered rows, so this may be a **capture** problem — the
  candidate scrolled off or was split across the wrap — rather than a completion
  problem. Re-run with a wider `COLS` and a pinned short `PS1` to separate the two.
- If it is real: macOS `/private/var/folders/...` temp paths are symlinked from
  `/var`. Check whether the executable-detection path in
  `readline_completion_backend.f90` resolves symlinks consistently, and whether the
  `x` permission test is applied to the resolved or unresolved path.

### 4. `test_menu_scroll.py::test_menu_up_stops_at_top_not_wrap`
### 5. `test_menu_scroll.py::test_menu_repeat_at_edge_jumps`

These cover AR-03 NEW-2 edge behaviour: Up at the top of the completion menu must
**stop** (producing two consecutive identical selections), and only the *next*
press jumps to the opposite edge. The state lives in `menu_edge_armed`
(`src/io/readline_state.f90`), reset whenever a menu opens/closes or another nav key
moves the selection.

The captured sequences show the selection moving continuously with no repeat, i.e.
it looks like wrapping. Leads:

- The tests detect a stop by sampling the *rendered* selection after each keypress.
  If the macOS redraw coalesces frames — or the drain window is too short for this
  slower machine — two distinct frames can be missed and a genuine stop looks like
  continuous motion. Instrument first: dump the sampled sequence and compare against
  the same run on Linux before touching `menu_edge_armed`.
- If it reproduces with generous drains, then the edge latch really is not arming.
  Check that nothing on the macOS path resets `menu_edge_armed` between presses.

### 6. `test_sec_process_menu.py::test_benign_user_populates_menu`

> `AssertionError: process menu did not populate for a benign username`

Ctrl-X opens a process menu built from `ps`. The test asserts the header appears,
since `ps` always lists at least the shell itself. `get_process_list`
(`src/io/readline.f90`) was hardened to invoke `ps` via `execvp` with an argv array
rather than `popen` — check the **argv it builds is valid on BSD `ps`**. macOS `ps`
is BSD-flavoured and rejects some GNU-style option spellings, so a flag that works
on Linux may make `ps` exit non-zero and yield an empty list. Run the exact argv by
hand on this machine and look at the exit status.

This is a security-relevant path (it was hardened deliberately). **Do not "fix" it
by going back to a shell string** — keep the argv form and correct the flags.

## Definition of done

1. All six pass on macOS ARM64, with the cause of each identified as either a fortsh
   bug or a test bug, and stated in the commit message.
2. Nothing newly marked `known_failure`.
3. The full suite still passes on Linux — a macOS-motivated change must not regress
   it:
   ```bash
   ./.venv/bin/python -m pytest -q -m "not known_failure"
   ```
4. The YAML specs still pass on both platforms:
   ```bash
   ./.venv/bin/python run_tests.py
   ```
5. Re-add the pytest step to the `macos-arm64-interactive` job in
   `.github/workflows/test.yml`, and delete the NOTE comment that points here.
   The step is already present in the two Linux jobs — copy it verbatim:
   ```yaml
   - name: Run interactive pytest suite
     run: |
       cd tests/interactive
       source .venv/bin/activate
       python -m pytest -q -m "not known_failure"
   ```
6. Delete this file in the same PR.

## Repo conventions

- Commit often, in small chunks; terse imperative subject under ~250 chars.
- No co-author trailers, no "Generated with" trailers.
- Tests and CI are first-class — a fix without a test that would have caught it is
  not finished.
