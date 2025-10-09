# FortSH Development Roadmap

## Implementation Phases

### ✅ Phase 1: Core Shell Foundation
**Status:** Complete
- Basic REPL (Read-Eval-Print Loop)
- Command tokenization and parsing
- External command execution via fork/exec
- Basic built-in commands (cd, pwd, exit)
- Environment variable handling

### ✅ Phase 2: Built-in Commands
**Status:** Complete
- POSIX built-ins (echo, printf, test, export, unset, etc.)
- Variable assignment and expansion
- Positional parameters ($1, $2, $@, $*, $#)
- Special parameters ($$, $?, $!)

### ✅ Phase 3: I/O Redirection
**Status:** Complete
- Input redirection (<)
- Output redirection (>, >>)
- Error redirection (2>, 2>>)
- Here documents (<<, <<-)
- Here strings (<<<)
- File descriptor manipulation

### ✅ Phase 4: Pipelines
**Status:** Complete
- Basic pipe operator (|)
- Multi-stage pipelines
- Proper process group management
- Exit status handling

### ✅ Phase 5: Job Control
**Status:** Complete
- Background processes (&)
- Job listing (jobs)
- Foreground/background control (fg, bg)
- Process groups and terminal control
- Signal handling (SIGINT, SIGTSTP, etc.)

### ✅ Phase 6: Control Structures (Basic)
**Status:** Complete
- if/then/elif/else/fi
- case/esac
- Basic for loops
- while/until loops (structure only)

### ✅ Phase 7: Advanced Expansion
**Status:** Complete
- Command substitution ($(...) and backticks)
- Arithmetic expansion ($((expr)))
- Brace expansion ({a,b,c})
- Tilde expansion (~, ~user)
- Parameter expansion (${var:-default}, ${var##pattern}, etc.)

### ✅ Phase 8: Pattern Matching & Globbing
**Status:** Complete
- Pathname expansion (*, ?, [...])
- Extended globbing patterns
- Case statement patterns

### ✅ Phase 9: Functions & Scripts
**Status:** Complete
- Shell functions
- Function parameters and local variables
- Script sourcing (source, .)
- Shebang support

### ✅ Phase 10: POSIX Compliance
**Status:** Complete
- Shell options (set -e, set -u, set -x, etc.)
- POSIX test operators
- Proper exit status handling
- Field splitting (IFS)
- Quoting and escaping

### ✅ Phase 11: Interactive Features
**Status:** Complete
- Command line editing
- History (arrow keys, history expansion)
- Tab completion
- Prompt customization (PS1, PS2)
- Readline-style keybindings

### ✅ Phase 12: Advanced Features
**Status:** Complete
- Arrays (indexed and associative)
- Coprocesses
- Process substitution
- Advanced redirections (&>, >&2, etc.)
- Multiple redirections

### ✅ Phase 13: Loop Execution
**Status:** Complete (with known limitations)
- Loop body buffering and replay
- For loop iteration (for x in list)
- Arithmetic for loops (for((i=0;i<n;i++)))
- While/until loop execution
- Break and continue statements

**Known Issues:**
- Requires `for((` syntax (no space between for and (())
- Variable scoping issues in sequential arithmetic loops
- Limited support for variable expansion in quoted strings within loops

### ✅ Phase 14: Variable Scoping & Expansion Fixes
**Status:** Complete
- Fixed arithmetic variable persistence across loops
- Fixed loop body cleanup to prevent command replay issues
- Sequential loops now work correctly with proper variable isolation
- Variable expansion in quoted strings works correctly

**Achievements:**
- Loop body commands are properly captured and replayed
- Variables from different loops no longer interfere with each other
- Both basic for loops and arithmetic for loops execute correctly
- Sequential loops maintain proper variable scope

**Known Limitations:**
- Nested loops do not execute correctly (inner loops execute after outer loop completes)
- Requires `for((` syntax without space between 'for' and '(('
- Loop variables persist after loop execution

### 📋 Phase 15: Advanced Loop Features
**Status:** Planned
- Nested loop support
- Loop labels for break/continue
- Select loops
- Proper loop variable scoping

### 📋 Phase 16: Debugging & Tracing
**Status:** Planned
- set -x tracing with PS4
- trap command
- DEBUG trap
- ERR trap
- Execution profiling

### 📋 Phase 17: Performance & Optimization
**Status:** Planned
- Command caching
- Optimized tokenizer
- Memory pool management
- Parallel execution optimization

### 📋 Phase 18: Extended Compatibility
**Status:** Planned
- Bash compatibility mode
- Zsh-style features (optional)
- POSIX strict mode
- Legacy sh compatibility

### 📋 Phase 19: Advanced I/O
**Status:** Planned
- Network redirections (/dev/tcp, /dev/udp)
- Named pipes (FIFOs)
- Advanced coprocess features
- Multiplexed I/O

### 📋 Phase 20: Security & Sandboxing
**Status:** Planned
- Restricted shell mode
- Capability-based security
- Resource limits enforcement
- Audit logging

## Version Milestones

### v1.0 - POSIX Foundation
Phases 1-10: Core POSIX-compliant shell

### v2.0 - Interactive Shell
Phases 11-12: Full interactive shell with advanced features

### v3.0 - Production Ready
Phases 13-16: Complete loop support, debugging, and stability

### v4.0 - Extended Features
Phases 17-20: Performance, compatibility, and advanced features

## Testing Strategy

Each phase includes:
1. Unit tests for new modules
2. Integration tests for feature interactions
3. POSIX compliance tests
4. Performance benchmarks
5. User acceptance testing

## Contributing

See CONTRIBUTING.md for guidelines on:
- Code style and standards
- Testing requirements
- Documentation standards
- Pull request process