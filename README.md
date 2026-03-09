# fortsh
(noun) : something clever never

A shell written in Fortran. Because we can.

> **Warning - macOS ARM64 Users**: Due to compiler limitations on apple silicon, command lines are limited to 127 characters. All features work (history, tab completion, syntax highlighting, etc.), but you can't type commands longer than 127 bytes. This is a fundamental limitation of both available compilers: gfortran has 7+ critical bugs (stack corruption, heap corruption, segfaults), while flang-new has a 127-byte string operation limit to prevent heap corruption. We see flang-new as the lesser evil. For details, see COMPILER_NOTES.md.

## Status

**POSIX compliance**: 3,776/3,776 tests passing across 25 test suites
**bash compatibility**: ~99%
**Chance you'll miss the other 1%**: Low

Turns out you can write a pretty decent shell in Fortran. Who knew.

## What Works

Pretty much everything:

- All POSIX required features
- All the bash stuff people actually use
- Job control
- History with Ctrl+R
- Tab completion
- History suggestions a la fish
- fuzzy matching a la fish
- Arrays (indexed and associative)
- Parameter expansion (`${var#stuff}`, etc.)
- Process substitution (`<(cmd)`, `>(cmd)`)
- Brace expansion (`{1..10}`)
- Regex matching with capture groups (`BASH_REMATCH`)
- Vi mode (if you're into that)

## What Doesn't Work

- Some advanced vi mode features (yank/put, marks)
- Nested brace expansion (who uses this?)
- Your expectations, probably
- More?!

## Building

Requires:
- A Fortran 2018 compiler (gfortran 8+, or LLVM flang-new for macOS ARM64)
- GNU Make
- POSIX system (Linux, BSD, macOS)
- Realistic expectations

**macOS ARM64 Note**: Use `brew install llvm` to get flang-new. See the warning at the top or COMPILER_NOTES.md for details.

```bash
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh
make
```

Binary lands in `bin/fortsh`. Shocking, I know.

```bash
sudo make install    # /usr/local/bin
make dev-install    # ~/.local/bin
```

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

Works with Tab completion.

### Keybindings

**Directory navigation:**

| Key | Action |
|-----|--------|
| Alt+Shift+Up | Go to parent directory |
| Alt+Shift+Left | Previous directory |
| Alt+Shift+Right | Next directory |

**Fuzzy search:**

| Key | Action |
|-----|--------|
| Ctrl-F | Search files |
| Alt-J | Search directories |
| Ctrl-H | Search history |
| Alt-G | Search git files |

### Tab Completion

Works for commands, paths, variables, and command-specific options.

### Syntax Highlighting

Colors update as you type:
- Green = valid commands
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
# C-style for loop with multiple vars
for ((i=0, j=10; i<j; i++, j--)); do
    echo "$i $j"
done

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
make test-all           # everything (integration + parity + POSIX)
make test-posix         # POSIX compliance suite (3,776 tests)
make test-parity        # bash parity tests
make test-integration   # integration tests
make check              # comprehensive build checks
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

The useful ones: `[[`, `alias`, `bg`, `command`, `compgen`, `complete`, `declare`, `fc`, `fg`, `history`, `jobs`, `kill`, `let`, `local`, `printenv`, `shopt`, `source`, `unalias`, `which`

### fortsh Specific

- `config` - manage config files
- `memory` - show memory stats
- `perf` - show performance metrics

Because why not.

## macOS & Apple Silicon

Apple Silicon has been an adventure. Both available Fortran compilers have serious issues on ARM64, so fortsh uses a combination of compiler selection, C interop workarounds, and platform-specific code paths to produce a functional shell. For the full story, see `COMPILER_NOTES.md`.

### The Compiler Situation

| Platform | Compiler | Status |
|----------|----------|--------|
| Linux | gfortran | Primary target, no issues |
| macOS Intel | gfortran | Works with `-frecursive` |
| macOS ARM64 | flang-new (LLVM) | Required — gfortran has 7+ critical bugs |

**Why not gfortran on Apple Silicon?** It has at least 8 confirmed bugs that make it unusable:

1. Stack corruption on arrays >600KB
2. Deferred-length allocatable strings lose their length descriptor
3. `intent(out)` subroutine return epilogue segfaults
4. Allocatable string assignment corrupts the heap
5. Automatic finalization crashes
6. Substring slicing (`buffer(:length)`) segfaults
7. Empty string assignment (`buffer = ''`) corrupts the heap
8. `flush()` in tight loops corrupts the heap

Install flang-new via `brew install llvm`. The Makefile auto-detects ARM64 and switches compilers.

### The flang-new 128-Byte Limit

flang-new is far more stable, but has one glaring limitation: string buffers larger than 128 bytes cause heap corruption on substring operations and direct assignments. This means **command lines are limited to 127 characters** on Apple Silicon.

Allocating strings >128 bytes works fine. Operating on them doesn't. We tried a "shadow buffer" pattern (1024-byte storage, 128-byte working buffer) — still limited to 128 effective bytes.

### C String Library Workaround

To mitigate flang-new's string bugs, fortsh includes a C string library (`src/c_interop/fortsh_strings.c`) that performs string operations outside the Fortran runtime. This is **auto-enabled on macOS ARM64** and provides:

- Safe substring extraction (the operation that crashes flang-new)
- Buffer manipulation (insert, delete, append) without heap corruption
- Fortran-to-C string conversion with proper indexing translation

The `buffer_ops.f90` abstraction layer routes string operations through either native Fortran (Linux) or the C library (macOS ARM64) transparently.

Build flags:
```bash
make                    # auto-enables C strings on ARM64
make NO_C_STRINGS=1     # force native Fortran strings (will crash on ARM64)
```

### Platform-Specific Code Paths

Beyond the compiler, macOS differs from Linux in ways that required workarounds throughout the codebase:

**Terminal I/O:**
- `termios_t` struct is 72 bytes on macOS vs 60 on Linux (8-byte vs 4-byte `tcflag_t`)
- Control character array (`NCCS`) is 20 on macOS vs 32 on Linux
- `TIOCGWINSZ` ioctl constant differs (`0x40087468` vs `0x5413`)
- Terminal size detection uses `tput` on macOS (direct ioctl crashes flang-new) vs ioctl on Linux

**Signal numbers:**
- `SIGTSTP`: 18 on macOS, 20 on Linux
- `SIGCHLD`: 20 on macOS, 17 on Linux
- `SIGCONT`: 19 on macOS, 18 on Linux
- macOS does NOT ignore `SIGTSTP` (breaks `waitpid` by auto-reaping children)

**File system:**
- `stat_t` is 96 bytes on macOS vs 144 on Linux, with different field ordering
- macOS has `st_birthtimespec` (birth time) — Linux does not
- `open()` flags differ: `O_CREAT` is `0x200` on macOS vs `0x40` on Linux

**Other:**
- BSD `ps` doesn't support `--no-headers` (macOS uses `pid= -o comm=` format instead)
- Fortran `block` constructs crash flang-new — variables hoisted to subroutine scope
- Substring temporaries on allocatable strings trigger heap corruption — char-by-char copy used instead
- `mode_t` not passed correctly through Fortran C binding — C wrapper (`fd_wrapper.c`) casts explicitly

### macOS ARM64 Build

```bash
brew install llvm
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh
make            # auto-detects ARM64, uses flang-new + C string library
```

You'll see:
```
Using flang-new on macOS ARM64
C string library ENABLED - workaround for flang-new >128 byte bug
```

## Known Issues

- **macOS ARM64**: 127-character command line limit (flang-new string bug, see above)
- Slower than bash for large scripts (it's Fortran, not a miracle worker)
- Some regex patterns with spaces need escaping (affects ~0.1% of use cases)
- Unicode support varies by system locale
- Will not make you coffee

## Why?

Why not?

More seriously: started as "can you even do this in Fortran?" Turns out yes. Then it became "how far can this go?" Turns out pretty far.

It's actually usable now. We're as surprised as you are.

## Project Structure

```
src/
├── common/          # Types, errors, perf monitoring
├── system/          # OS interface, signals, jobs
├── parsing/         # Lexer, parser, glob
├── execution/       # Command execution, builtins
├── scripting/       # Variables, control flow, expansion
├── io/              # Readline, redirection
└── fortsh.f90       # Main REPL loop
```

## Documentation

See `docs/` for:
- `SHELL_PARITY_STATUS_2025_10_12.md` - current feature status
- Implementation docs for specific features
- POSIX compliance tracking

Or just run `help` in the shell.

## Contributing

Found a bug? Cool, file an issue.
Want to add a feature? Check it's not already there (spoiler: it might be).
Want to make it faster? Please do.

This started as a research project and somehow became production-ready. Contributions welcome.

## Standards

POSIX.1-2017 (IEEE Std 1003.1-2017)
bash 5.x for extensions

## License

MIT. See LICENSE file.

## Links

Repository: https://github.com/FortranGoingOnForty/fortsh
Issues: https://github.com/FortranGoingOnForty/fortsh/issues
POSIX Shell Spec: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html

---

*Yes, it's really written in Fortran. Yes, it really works. No, we don't know why either.*
