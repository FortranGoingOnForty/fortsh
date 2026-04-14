# fortsh
(noun) : something clever never

A shell written in Fortran. Because we can.

## Status

**CI**: All green across x86_64 Linux, ARM64 Linux, and macOS ARM64 (Apple Silicon)
**POSIX compliance**: 3,632+ tests passing across 23 POSIX suites
**Builtin tests**: 850+ passing | **Integration tests**: 482 passing | **Stress tests**: 204 passing
**Interactive PTY tests**: 180+ passing
**bash compatibility**: ~99%
**Chance you'll miss the other 1%**: Low

Turns out you can write a pretty decent shell in Fortran. Who knew.

## Install

**Homebrew** (macOS / Linux):
```bash
brew install FortranGoingOnForty/tap/fortsh
```

**AUR** (Arch Linux):
```bash
yay -S fortsh
```

**From source**:
```bash
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh
make release
sudo make install    # /usr/local/bin
```

Binary lands in `bin/fortsh`. Shocking, I know.

## What Works

Pretty much everything:

- All POSIX required features
- All the bash stuff people actually use
- Job control (fg, bg, jobs, wait)
- History with Ctrl+R and autosuggestions
- Tab completion for commands, paths, and variables
- Syntax highlighting as you type
- Native text selection with Shift+Arrow + system clipboard (pbcopy / xclip / wl-copy / xsel)
- Arrays (indexed and associative)
- Full parameter expansion (`${var#pattern}`, `${var//find/replace}`, `${var^^}`, etc.)
- Process substitution (`<(cmd)`, `>(cmd)`)
- Brace expansion (`{1..10..2}`, `{a,b}{1,2}`)
- C-style for loops (`for ((i=0; i<10; i++))`)
- ANSI-C quoting (`$'\t\n\e[31m'`)
- Indirect expansion (`${!ref}`, `${!ref:-fallback}`)
- Coprocesses (`coproc { cmd; }`)
- Regex matching with capture groups (`BASH_REMATCH`)
- Vi and Emacs editing modes
- Per-builtin help texts (`help cd`, `help export`, etc.)
- fzf integration (file browser, history search, directory jump, git browser)
- Bracketed paste mode (large pastes land atomically)

## What Doesn't Work

- Some advanced vi mode features (yank/put, marks)
- Your expectations, probably
- More?!

## Building

Requires:
- A Fortran 2018 compiler (gfortran 8+, or flang-new for macOS ARM64)
- GNU Make
- A C compiler (gcc or clang)
- POSIX system (Linux, macOS)
- Realistic expectations

```bash
make                # dev build (debug symbols, -O0)
make release        # production build (optimized, stripped)
make debug          # debug build with bounds checking
make clean          # remove build/ and bin/
```

### Platform Matrix

| Platform | Compiler | Notes |
|----------|----------|-------|
| Linux x86_64 | gfortran | Primary target |
| Linux aarch64 | gfortran | Auto-enables C stat helpers for struct layout differences |
| macOS Intel | gfortran | Works with `-frecursive` |
| macOS ARM64 | flang-new (LLVM) | Required -- gfortran has 7+ critical bugs. Auto-enables C string library. Install via `brew install flang`. |

The Makefile auto-detects your platform and selects the right compiler and flags. Just run `make`.

## Using It

```bash
fortsh              # Interactive mode
fortsh script.sh    # Run a script
fortsh -c 'cmd'     # Run a command
```

It works like bash. If it doesn't, that's a bug.

## Configuration

Login shell reads: `/etc/fortsh/profile`, `~/.fortsh_profile`
Interactive shell reads: `/etc/fortsh/fortshrc`, `~/.fortshrc`
Logout runs: `~/.fortsh_logout`

First run offers to create default configs. Or don't. I'm not your boss.

## Modern Shell Features

fish and zsh have some nice things. We have them too now.

### Autosuggestions

Greyed-out suggestions appear as you type:

- History-based (commands you've run)
- Path-based (file/directory completions)
- Accept with **Right Arrow** or **Ctrl-F**

### cd-less Navigation

Type a directory path, press Enter. That's it.

```bash
/tmp/              # Navigate to /tmp
../                # Go up
~/Documents/       # Go to ~/Documents
```

Works with Tab completion. Valid directories highlight green.

### Keybindings

**Directory navigation:**

| Key | Action |
|-----|--------|
| Alt+Shift+Up | Go to parent directory |
| Alt+Shift+Left | Previous directory |
| Alt+Shift+Right | Next directory |

**Fuzzy search (requires fzf):**

| Key | Action |
|-----|--------|
| Ctrl-F | Search files |
| Alt-J | Search directories |
| Ctrl-H | Search history |
| Alt-G | Search git files |

**Text selection** (live since v1.7.0 — works like a GUI editor in the terminal):

| Key | Action |
|-----|--------|
| Shift+Left / Shift+Right | Extend selection by character |
| Shift+Home / Shift+End | Extend selection to line start / end |
| Shift+Up / Shift+Down | Extend selection line-wise (Home / End on single-line prompt) |
| Ctrl+Shift+Left / Ctrl+Shift+Right | Extend selection by word |
| Alt+Shift+B / Alt+Shift+F | Extend selection by word (emacs-native alias) |
| any plain motion (Left, Home, Alt+b, ...) | Collapse selection — char-motions snap to the appropriate edge |
| Ctrl+W or Ctrl+X | Cut selection (writes to kill buffer + system clipboard) |
| Alt+W | Copy selection (kill buffer + system clipboard, no delete) |
| Ctrl+Y | Paste from kill buffer (deletes selection first if active) |
| Ctrl+V | Paste from system clipboard (falls back to kill buffer if no tool) |
| typing a printable char | Replaces the selection in place (type-over) |
| Backspace / Delete | Removes the entire selection |

System clipboard bridge auto-detects `pbcopy` (macOS), `wl-copy` (Wayland), `xclip` or `xsel` (X11) at startup. If none are installed, cut/copy still work via the in-session kill buffer.

Env flags:
- `FORTSH_DEBUG_SELECTION=1` — dump selection state to stderr on each mutation
- `FORTSH_NO_BRACKETED_PASTE=1` — disable `ESC[?2004h` emit (terminal-compat triage)

### Tab Completion

Works for commands, paths, variables, and command-specific options.

### Syntax Highlighting

Colors update as you type:
- Green = valid commands and directory paths
- Red = invalid commands
- Cyan = numbers
- Yellow = strings
- Grey = comments

### History

Persists across sessions. Only saves interactive commands (not scripts or .fortshrc).

- **Ctrl-R**: search history
- **Up/Down**: navigate history

Configuration in `~/.fortshrc`:
```bash
export HISTFILE=~/.fortsh_history
export HISTSIZE=1000
export HISTFILESIZE=2000
export HISTCONTROL=ignoredups
```

## Examples

### Basic Variables

```bash
name="fortsh"
echo ${name}                    # fortsh
echo ${name:-default}           # fortsh (or default if unset)
echo ${name%sh}                 # fort (remove shortest suffix match)
```

### Parameter Expansion (The Full Monty)

```bash
path="/usr/local/bin/fortsh"

# Length
echo ${#path}                   # 21

# Substring
echo ${path:0:4}                # /usr

# Remove prefix/suffix
echo ${path#*/}                 # usr/local/bin/fortsh
echo ${path##*/}                # fortsh (remove longest prefix)
echo ${path%/*}                 # /usr/local/bin
echo ${path%%/*}                # (remove longest suffix - empty)

# Replace
echo ${path/local/opt}          # /usr/opt/bin/fortsh
echo ${path//o/0}               # /usr/l0cal/bin/f0rtsh (replace all)

# Case conversion
text="Hello World"
echo ${text^^}                  # HELLO WORLD
echo ${text,,}                  # hello world
echo ${text^}                   # Hello World (first char)

# Indirect expansion
ref="path"
echo ${!ref}                    # /usr/local/bin/fortsh (value of $path)
echo ${!ref:-fallback}          # works with modifiers too
```

### Arrays (Both Kinds)

```bash
# Indexed arrays
fruits=(apple banana cherry)
echo ${fruits[0]}               # apple
echo ${fruits[@]}               # apple banana cherry
echo ${#fruits[@]}              # 3
fruits+=(date)                  # append
echo ${fruits[@]:1:2}           # banana cherry (slice)

# Associative arrays (yes, really)
declare -A config
config[host]=localhost
config[port]=8080
config[user]=admin

echo ${config[host]}            # localhost
echo ${!config[@]}              # host port user (keys)
echo ${#config[@]}              # 3 (count)

for key in "${!config[@]}"; do
    echo "$key = ${config[$key]}"
done
```

### Process Substitution (Actually Works)

```bash
# Compare directory listings
diff <(ls dir1) <(ls dir2)

# Multiple inputs
paste <(seq 1 5) <(seq 6 10)

# Output substitution
echo "test" | tee >(wc -c) >(wc -w) >/dev/null
```

### Regex with Capture Groups

```bash
# Email parsing
if [[ "user@example.com" =~ ^([^@]+)@([^.]+)\.(.+)$ ]]; then
    echo "User: ${BASH_REMATCH[1]}"      # user
    echo "Domain: ${BASH_REMATCH[2]}"    # example
    echo "TLD: ${BASH_REMATCH[3]}"       # com
fi

# Version string parsing
version="v3.14.159-beta"
if [[ $version =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)(-(.+))?$ ]]; then
    major=${BASH_REMATCH[1]}    # 3
    minor=${BASH_REMATCH[2]}    # 14
    patch=${BASH_REMATCH[3]}    # 159
    suffix=${BASH_REMATCH[5]}   # beta
fi
```

### Brace Expansion

```bash
echo {1..10}                    # 1 2 3 4 5 6 7 8 9 10
echo {a..z}                     # a b c ... z
echo {1..20..2}                 # 1 3 5 7 9 11 13 15 17 19
echo {10..1..2}                 # 10 8 6 4 2
echo {a,b,c}{1,2}               # a1 a2 b1 b2 c1 c2

# Practical use
mkdir -p project/{src,test,docs}/{main,utils}
touch file{1..100}.txt
```

### ANSI-C Quoting

```bash
echo $'tab:\there'              # tab:	here
echo $'line1\nline2'            # line1 (newline) line2
echo $'it\'s fine'              # it's fine
echo $'\e[31mred\e[0m'          # red (in color)
```

### Arithmetic

```bash
x=5
y=3

echo $((x + y))                 # 8
echo $((x * y))                 # 15
echo $((x ** y))                # 125 (exponentiation)
echo $((x % y))                 # 2 (modulo)

# C-style for loops
for ((i=0; i<5; i++)); do
    echo "Count: $i"
done

# Multi-variable
for ((i=0, j=10; i<j; i++, j--)); do
    echo "$i $j"
done

# Inline increment
count=0
echo $((count++))               # 0 (post-increment)
echo $count                     # 1
```

### Here Documents

```bash
# Basic heredoc
cat <<EOF
Line 1
Line 2 with $variables expanded
EOF

# Quoted delimiter (no expansion)
cat <<'EOF'
$variables not expanded
EOF

# Here string (shorthand)
grep pattern <<<"search this text"

# Indented heredoc
if true; then
    cat <<-EOF
	This leading tab is stripped
	So is this one
	EOF
fi
```

### Command Substitution & Pipes

```bash
# Capture output
current_dir=$(pwd)
file_count=$(ls | wc -l)

# Nested substitution
echo "Found $(grep pattern $(find . -name '*.txt') | wc -l) matches"

# Complex pipelines
ps aux | grep fortsh | grep -v grep | awk '{print $2}' | xargs kill

# Pipeline with error handling
command1 | command2 || echo "Pipeline failed with status $?"
```

### Coprocesses

```bash
# Named coproc
coproc WORKER { while read line; do echo "processed: $line"; done; }
echo "hello" >&${WORKER[1]}
read result <&${WORKER[0]}
echo $result    # processed: hello

# Brace group coproc
coproc { cat -n; }
```

### Job Control

```bash
# Background job
sleep 10 &
bg_pid=$!
echo "Started job $bg_pid"

# List jobs
jobs

# Bring to foreground
fg %1

# Kill job
kill %1

# Wait for completion
wait $bg_pid
echo "Job completed with status $?"
```

### Control Flow (The Tricky Bits)

```bash
# Case with multiple patterns
case $input in
    *.txt|*.md)
        echo "Text file"
        ;;
    [0-9]*)
        echo "Starts with number"
        ;;
    *)
        echo "Something else"
        ;;
esac

# Until loop (less common)
count=0
until [ $count -eq 5 ]; do
    echo $count
    ((count++))
done

# Nested loops with break/continue
for i in {1..3}; do
    for j in {1..3}; do
        [ $i -eq 2 ] && [ $j -eq 2 ] && continue
        echo "$i,$j"
    done
done
```

### Functions with Local Scope

```bash
outer_var="global"

my_function() {
    local outer_var="local"    # Shadows global
    local inner_var="only here"

    echo $outer_var            # local
    return 42
}

my_function
exit_code=$?                   # 42
echo $outer_var                # global
echo $inner_var                # (empty - not in scope)
```

### Signal Handling

```bash
# Trap signals
trap 'echo "Cleaning up..."; rm -f /tmp/tempfile; exit' INT TERM

# Trap ERR (on command failure)
trap 'echo "Command failed with exit code $?"' ERR

# Trap EXIT (always runs)
trap 'echo "Script finished"' EXIT

# Remove trap
trap - INT
```

### Advanced Test Conditions

```bash
# File tests
[ -f file ]                    # Regular file
[ -d dir ]                     # Directory
[ -L link ]                    # Symbolic link
[ -r file ]                    # Readable
[ -w file ]                    # Writable
[ -x file ]                    # Executable
[ file1 -nt file2 ]            # file1 newer than file2

# String tests with [[ ]]
[[ $str =~ pattern ]]          # Regex match
[[ $str == *substring* ]]      # Glob match
[[ -n $str ]]                  # Non-empty
[[ -z $str ]]                  # Empty

# Numeric comparisons
[ $a -eq $b ]                  # Equal
[ $a -lt $b ]                  # Less than
[ $a -ge $b ]                  # Greater or equal

# Logical operators
[[ $a == "x" && $b == "y" ]]   # And
[[ $a == "x" || $b == "y" ]]   # Or
[[ ! $a == "x" ]]              # Not
```

## Testing

```bash
make test-posix         # POSIX compliance (~1 min)
make test-posix-full    # all POSIX suites (~3 min)
make test-posix-quick   # fast POSIX, skip coverage (~30s)
make test-bench         # unit bench tests (memory pool, lexer, executor, C strings)
make test-all           # everything including memory pool tests
make check              # comprehensive build checks
```

Individual test suites:
```bash
./tests/builtins/run_builtin_tests.sh --verbose
./tests/builtins/integration/run_integration_tests.sh --verbose
./tests/builtins/test_stress.sh
```

Interactive PTY tests (Python/pexpect):
```bash
cd tests/interactive
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python run_tests.py
```

Or don't. Live dangerously.

## Built-in Commands

### POSIX Required

All of them: `:`, `.`, `break`, `cd`, `continue`, `echo`, `eval`, `exec`, `exit`, `export`, `getopts`, `hash`, `printf`, `pwd`, `read`, `readonly`, `return`, `set`, `shift`, `test`/`[`, `times`, `trap`, `type`, `ulimit`, `umask`, `unset`, `wait`

### bash Compatible

The useful ones: `[[`, `alias`, `bg`, `command`, `compgen`, `complete`, `coproc`, `declare`, `fc`, `fg`, `history`, `jobs`, `kill`, `let`, `local`, `printenv`, `shopt`, `source`, `unalias`, `which`

### fortsh Specific

- `config` - manage config files
- `memory` - show memory stats
- `perf` - show performance metrics
- `help <builtin>` - detailed help for any builtin
- `defun` - function definition helper

Every builtin has detailed help: `help cd`, `help export`, `help trap`, etc.

## macOS ARM64 Notes

Both Fortran compilers have issues on Apple Silicon. fortsh uses flang-new (LLVM) with C interop workarounds. The Makefile handles everything automatically.

Install flang-new via `brew install flang`. See `COMPILER_NOTES.md` for the full story on compiler bugs and workarounds.

Key differences from Linux builds:
- C string library auto-enabled (works around flang-new string buffer limitations)
- Platform-specific constants for signals, terminal I/O, file flags, and resource limits
- Builtin output uses C-level `write()` to respect fd redirections (flang-new's Fortran I/O caches file descriptors)

## Known Issues

- Slower than bash for large scripts (it's Fortran, not a miracle worker)
- Unicode support varies by system locale
- Will not make you coffee

## Project Structure

```
src/
├── common/          # Types, errors, string pool, perf monitoring
├── system/          # OS interface (POSIX syscalls), signals
├── parsing/         # Lexer, grammar parser, AST, glob
├── execution/       # AST executor, builtins, job control, pipelines
├── scripting/       # Variables, expansion, control flow, completion
├── io/              # Readline (~9000 lines), heredoc, fd redirection
├── c_interop/       # C FFI: string ops, fd wrapper, terminal size
└── fortsh.f90       # Main REPL loop
```

~70,000 lines of Fortran, fully self-contained with no external Fortran library dependencies.

## Why?

Why not?

More seriously: started as "can you even do this in Fortran?" Turns out yes. Then it became "how far can this go?" Turns out pretty far.

It's actually usable now. We're as surprised as you are.

## Standards

POSIX.1-2017 (IEEE Std 1003.1-2017)
bash 5.x for extensions

## Contributing

Found a bug? Cool, file an issue.
Want to add a feature? Check it's not already there (spoiler: it might be).
Want to make it faster? Please do.

## License

GPL-3.0. See LICENSE file.

## Links

Repository: https://github.com/FortranGoingOnForty/fortsh
Issues: https://github.com/FortranGoingOnForty/fortsh/issues
POSIX Shell Spec: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html

---

*Yes, it's really written in Fortran. Yes, it really works. No, we don't know why either.*
