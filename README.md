# fortsh

A shell written in Fortran. Because we can.

## Status

**POSIX compliance**: 100%
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
- Arrays (indexed and associative)
- Parameter expansion (`${var#stuff}`, etc.)
- Process substitution (`<(cmd)`, `>(cmd)`)
- Brace expansion (`{1..10}`)
- Regex matching with capture groups (`BASH_REMATCH`)
- Vi mode (if you're into that)

## What Doesn't Work

- Programmable completion (basic completion works fine)
- Some advanced vi mode features (yank/put, marks)
- Nested brace expansion (who uses this?)
- Your expectations, probably

## Building

Requires:
- A Fortran 2018 compiler (gfortran 8+, ifort 19+)
- GNU Make
- POSIX system (Linux, BSD, macOS)
- Realistic expectations

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

First run offers to create default configs. Or don't. I'm not your supervisor.

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
make check
```

Or don't. Live dangerously.

## Built-in Commands

### POSIX Required

All of them: `:`, `.`, `break`, `cd`, `continue`, `echo`, `eval`, `exec`, `exit`, `export`, `getopts`, `hash`, `printf`, `pwd`, `read`, `readonly`, `return`, `set`, `shift`, `test`/`[`, `times`, `trap`, `type`, `ulimit`, `umask`, `unset`, `wait`

### bash Compatible

The useful ones: `[[`, `alias`, `bg`, `command`, `declare`, `fc`, `fg`, `history`, `jobs`, `kill`, `let`, `local`, `printenv`, `shopt`, `source`, `unalias`, `which`

### fortsh Specific

- `config` - manage config files
- `memory` - show memory stats
- `perf` - show performance metrics

Because why not.

## Known Issues

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
