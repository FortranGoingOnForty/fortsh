# fortsh

A POSIX-compliant shell implementation written in Fortran 2018.

## Features

### POSIX Built-ins

| Command | Status | Notes |
|---------|--------|-------|
| `cd` | ✓ | Change directory |
| `pwd` | ✓ | Print working directory |
| `echo` | ✓ | Display text |
| `printf` | ✓ | Formatted output |
| `read` | ✓ | Read input |
| `test` / `[` | ✓ | Test conditions |
| `export` | ✓ | Export variables |
| `unset` | ✓ | Remove variables |
| `set` | ✓ | Shell options |
| `shift` | ✓ | Shift parameters |
| `type` | ✓ | Command type |
| `readonly` | ✓ | Read-only variables |
| `break` | ✓ | Loop control |
| `continue` | ✓ | Loop control |
| `return` | ✓ | Function return |
| `exec` | ✓ | Replace process |
| `eval` | ✓ | Evaluate string |
| `hash` | ✓ | Command hashing |
| `umask` | ✓ | File mode mask |
| `ulimit` | ✓ | Resource limits |
| `times` | ✓ | Process times |

## Building

```bash
# Prerequisites
sudo dnf install gfortran make gcc git    # RHEL/Fedora
sudo apt install gfortran make gcc git    # Debian/Ubuntu
sudo pacman -S gcc-fortran make gcc git   # Arch

# Build
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh
make

# Install
make install        # System-wide (/usr/local/bin)
make dev-install    # User only (~/.local/bin)
```

## Basic Usage

### Running fortsh

```bash
fortsh                      # Interactive shell
fortsh script.sh            # Execute script
fortsh -c 'echo Hello'      # Execute command
```

### Variables and Parameter Expansion

```bash
# Variable assignment
name="value"
export PATH="/usr/bin:/bin"

# Parameter expansion
echo ${var:-default}        # Use default if unset
echo ${var:=default}        # Assign default if unset
echo ${var:?error}          # Error if unset
echo ${var:+alternate}      # Use alternate if set

# String manipulation
echo ${var%suffix}          # Remove suffix
echo ${var#prefix}          # Remove prefix
echo ${#var}                # String length

# Positional parameters
echo $1 $2 $3               # Script arguments
echo $#                     # Number of arguments
echo $*                     # All arguments (single string)
echo $@                     # All arguments (separate)
echo $$                     # Process ID
echo $?                     # Last exit status
```

### Control Flow

```bash
# If statement
if [ -f "$file" ]; then
    echo "File exists"
elif [ -d "$file" ]; then
    echo "Directory"
else
    echo "Not found"
fi

# Case statement
case "$var" in
    pattern1) echo "Match 1" ;;
    pattern*) echo "Pattern" ;;
    *) echo "Default" ;;
esac

# For loop
for file in *.txt; do
    echo "$file"
done

# While loop
while read line; do
    echo "$line"
done < input.txt

# Until loop
until [ $count -eq 10 ]; do
    ((count++))
done
```

### Functions

```bash
# Function definition
my_function() {
    local var="$1"
    echo "Argument: $var"
    return 0
}

# Function call
my_function "test"
result=$(my_function "test")
```

### I/O Redirection

```bash
# Basic redirection
command > file              # Redirect stdout
command < file              # Redirect stdin
command >> file             # Append
command 2> errors           # Redirect stderr
command 2>&1                # Stderr to stdout

# File descriptors
command 3< input            # Custom fd
command 5>&-                # Close fd

# Process substitution
diff <(sort file1) <(sort file2)
```

### Job Control

```bash
command &                   # Background job
jobs                        # List jobs
fg %1                       # Foreground job 1
bg %2                       # Background job 2
kill %3                     # Kill job 3
wait                        # Wait for all jobs
```

### Test Operators

```bash
# File tests
[ -f file ]                 # Regular file
[ -d dir ]                  # Directory
[ -r file ]                 # Readable
[ -w file ]                 # Writable
[ -x file ]                 # Executable
[ -s file ]                 # Non-empty

# String tests
[ -z "$var" ]               # Empty string
[ -n "$var" ]               # Non-empty
[ "$a" = "$b" ]             # Equal
[ "$a" != "$b" ]            # Not equal

# Numeric tests
[ $a -eq $b ]               # Equal
[ $a -ne $b ]               # Not equal
[ $a -lt $b ]               # Less than
[ $a -le $b ]               # Less or equal
[ $a -gt $b ]               # Greater than
[ $a -ge $b ]               # Greater or equal
```

### Shell Options

```bash
set -e                      # Exit on error
set -u                      # Error on undefined variables
set -o pipefail             # Pipeline error detection
set -x                      # Trace execution
set -v                      # Verbose mode
```

## Examples

### System Backup Script

```bash
#!/usr/bin/env fortsh

set -euo pipefail

BACKUP_DIR="/backup/$(date +%Y%m%d)"
SOURCE_DIRS=("/home" "/etc" "/var/log")

mkdir -p "$BACKUP_DIR"

for dir in "${SOURCE_DIRS[@]}"; do
    echo "Backing up $dir..."
    tar -czf "$BACKUP_DIR/$(basename $dir).tar.gz" "$dir" 2>/dev/null || {
        echo "Warning: Failed to backup $dir" >&2
    }
done

echo "Backup completed to $BACKUP_DIR"
```

### Log Analysis

```bash
#!/usr/bin/env fortsh

declare -A error_counts
total_lines=0

while IFS= read -r line; do
    ((total_lines++))

    if [[ $line =~ \[(ERROR|WARN|INFO)\] ]]; then
        level=${BASH_REMATCH[1]}
        ((error_counts[$level]++))
    fi
done < /var/log/app.log

echo "Total lines: $total_lines"
for level in ERROR WARN INFO; do
    echo "$level: ${error_counts[$level]:-0}"
done
```

### Parallel Processing

```bash
#!/usr/bin/env fortsh

process_file() {
    local file="$1"
    # Process file
    echo "Processing: $file"
}

export -f process_file

for file in *.txt; do
    process_file "$file" &

    # Limit concurrent jobs to 4
    (($(jobs -r | wc -l) >= 4)) && wait
done

wait  # Wait for all jobs
```

## Environment Variables

```bash
# Shell behavior
FORTSH_DEBUG=1              # Enable debug output
FORTSH_TRACE=1              # Enable execution tracing

# History
HISTSIZE=1000               # Command history size
HISTFILE=~/.fortsh_history  # History file

# Prompts
PS1='[\u@\h \W]\$ '         # Primary prompt
PS2='> '                    # Continuation prompt
```

## Testing

```bash
# Run test suite
./tests/integration_test.sh

# Quick smoke test
make smoke-test

# Full test with memory checking
make check
```

## Project Structure

```
fortsh/
├── src/
│   ├── common/           # Core types, error handling
│   ├── system/           # OS interface, signals
│   ├── parsing/          # Command parser, glob expansion
│   ├── execution/        # Command execution, job control
│   ├── scripting/        # Variables, control flow
│   ├── io/               # I/O, readline
│   └── fortsh.f90        # Main program
└── tests/                # Test suite
```

## Limitations

- Some bash-specific extensions may not be supported
- Complex here-document constructs have limited support
- Coprocess functionality is experimental
- Unicode support depends on system locale

## License

MIT License - see [LICENSE](LICENSE) for details.

## Links

- Repository: https://github.com/FortranGoingOnForty/fortsh
- Issues: https://github.com/FortranGoingOnForty/fortsh/issues
- POSIX Standard: https://pubs.opengroup.org/onlinepubs/9699919799/