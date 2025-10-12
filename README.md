# fortsh

A POSIX-compliant shell implementation written in Fortran 2018. This project demonstrates shell construction techniques and provides a functional command-line interpreter suitable for interactive use and script execution.

## Overview

fortsh implements the core POSIX shell specification with select bash-compatible extensions. The implementation emphasizes standards compliance and code clarity over feature completeness. While functional for daily scripting tasks, it lacks some advanced features present in mature shells.

**Current Status**: Approximately 90% POSIX compliance, 85% bash feature parity for commonly-used constructs.

## Implementation Scope

### Core POSIX Built-in Commands (Complete)

The following POSIX-mandated built-in commands are implemented:

| Command | Function |
|---------|----------|
| `:` | Null command |
| `.` | Source file in current context |
| `break` | Exit from loop |
| `cd` | Change working directory |
| `continue` | Resume loop iteration |
| `echo` | Display arguments |
| `eval` | Evaluate arguments as command |
| `exec` | Replace shell process |
| `exit` | Terminate shell |
| `export` | Mark variables for export |
| `getopts` | Parse command options |
| `hash` | Cache command locations |
| `printf` | Formatted output |
| `pwd` | Print working directory |
| `read` | Read line from input |
| `readonly` | Mark variables immutable |
| `return` | Exit function |
| `set` | Set shell options |
| `shift` | Shift positional parameters |
| `test` / `[` | Evaluate conditions |
| `times` | Display process times |
| `trap` | Set signal handlers |
| `type` | Identify command type |
| `ulimit` | Control resource limits |
| `umask` | Set file creation mask |
| `unset` | Remove variables |
| `wait` | Wait for background jobs |

### Job Control Commands

| Command | Function |
|---------|----------|
| `bg` | Continue job in background |
| `fg` | Continue job in foreground |
| `jobs` | List active jobs |
| `kill` | Send signal to process |

### bash-Compatible Extensions

The following non-POSIX commands are provided for bash compatibility:

| Command | Function |
|---------|----------|
| `[[` | Enhanced conditional evaluation |
| `alias` | Define command aliases |
| `command` | Execute command bypassing functions |
| `declare` | Declare variables with attributes |
| `fc` | History command editor |
| `history` | Command history management |
| `let` | Arithmetic evaluation |
| `local` | Function-local variables |
| `printenv` | Display environment |
| `shopt` | Shell option control |
| `source` | Synonym for `.` |
| `unalias` | Remove aliases |
| `which` | Locate command in PATH |

### fortsh-Specific Commands

| Command | Function |
|---------|----------|
| `config` | Configuration file management |
| `memory` | Display memory usage statistics |
| `perf` | Display performance metrics |

### Feature Coverage

**Implemented**:
- Shell parameter expansion (${var:-default}, ${var#pattern}, etc.)
- Arithmetic expansion $((expr))
- Command substitution $(cmd) and \`cmd\`
- Glob pattern expansion (*, ?, [...])
- Brace expansion {a,b,c}
- Tilde expansion ~user
- I/O redirection (<, >, >>, 2>&1, etc.)
- Here documents (<<EOF)
- Pipeline construction (cmd1 | cmd2)
- Background execution (cmd &)
- Signal handling (trap command)
- Command history with readline
- Function definitions with local scope
- Associative and indexed arrays

**Not Implemented**:
- Process substitution (<(cmd), >(cmd))
- Coprocess support (incomplete)
- Programmable completion
- Extended glob patterns (extglob)
- Advanced regex matching (partial)

## Configuration

fortsh reads configuration files following standard shell conventions:

**Login shells**: `/etc/fortsh/profile`, `~/.fortsh_profile`
**Interactive non-login shells**: `/etc/fortsh/fortshrc`, `~/.fortshrc`
**Logout**: `~/.fortsh_logout`

Legacy `.fshrc` files are also recognized for backward compatibility.

On first execution, fortsh offers to create default configuration files with standard aliases and prompt settings.

## Building

### Prerequisites

- Fortran 2018 compiler (gfortran 8.0+, ifort 19.0+)
- GNU Make
- POSIX system (Linux, BSD, macOS)

### Compilation

```bash
# Clone repository
git clone https://github.com/FortranGoingOnForty/fortsh.git
cd fortsh

# Compile
make

# Optional: Install to system paths
sudo make install          # Installs to /usr/local/bin
make dev-install          # Installs to ~/.local/bin
```

Build artifacts are placed in `bin/fortsh`.

## Usage

### Invocation

```bash
fortsh                    # Interactive mode
fortsh script.sh          # Execute script file
fortsh -c 'command'       # Execute command string
```

### Basic Syntax

Variable assignment and expansion:
```bash
var="value"
echo ${var}              # Standard expansion
echo ${var:-default}     # Default value if unset
echo ${var%pattern}      # Pattern removal
```

Control structures:
```bash
if [ -f "$file" ]; then
    echo "File exists"
fi

for item in list; do
    echo "$item"
done

case "$var" in
    pattern) command ;;
esac
```

Functions:
```bash
func_name() {
    local arg="$1"
    return 0
}
```

Redirection and pipelines:
```bash
command < input > output 2>&1
cmd1 | cmd2 | cmd3
command &                 # Background execution
```

## Testing

```bash
make check               # Run test suite
./tests/integration_test.sh
```

Test coverage includes lexer, parser, executor, and end-to-end integration tests.

## Project Structure

```
fortsh/
├── src/
│   ├── common/          # Type definitions, error handling, performance
│   ├── system/          # OS interface, signals, job control
│   ├── parsing/         # Lexer, parser, glob expansion
│   ├── execution/       # Command executor, built-in dispatcher
│   ├── scripting/       # Variables, control flow, expansion
│   ├── io/              # Readline, redirection, here documents
│   └── fortsh.f90       # Main program loop
├── tests/               # Test scripts and test harness
└── docs/                # Implementation documentation
```

## Known Limitations

- **Process substitution**: Not implemented. Use temporary files as workaround.
- **Coprocess**: Partially implemented but not functional.
- **Regex matching**: `=~` operator has limited support. Use external tools (grep, awk) for complex patterns.
- **Completion**: Only basic filename completion is available.
- **Unicode**: Support depends on system locale; not all locales have been tested.
- **Performance**: Slower than optimized C implementations (bash, dash) for complex scripts.

## Development

fortsh is an educational project and research vehicle for shell implementation techniques. Contributions addressing standards compliance or fixing correctness issues are welcome. Feature requests for bash 4.x+ extensions will be evaluated based on implementation complexity and utility.

## Standards Compliance

Primary reference: POSIX.1-2017 (IEEE Std 1003.1-2017)
Secondary reference: bash 5.x behavior for extensions

Documented deviations from POSIX are tracked in `docs/POSIX_COMPLIANCE_STATUS.md`.

## License

MIT License. See LICENSE file for terms.

## References

- POSIX Shell Command Language: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
- Repository: https://github.com/FortranGoingOnForty/fortsh
- Issue tracker: https://github.com/FortranGoingOnForty/fortsh/issues
