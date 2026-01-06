# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

fortsh is a POSIX-compliant shell written in Fortran 2018. It aims for ~99% bash compatibility while implementing all POSIX required features plus modern conveniences (autosuggestions, syntax highlighting, tab completion).

## Build Commands

```bash
make                    # Build with memory pooling (default)
make release            # Optimized production binary (stripped)
make debug              # Debug build with bounds checking and backtraces
make clean              # Remove build artifacts

# Compiler options
FC=gfortran make        # Force gfortran (Linux, macOS Intel)
FC=flang-new make       # Force LLVM Flang (required for macOS ARM64)
NO_MEMPOOL=1 make       # Disable memory pooling
```

## Testing

```bash
make test               # Basic functionality test
make test-all           # Run integration, parity, and POSIX tests
make test-posix         # POSIX compliance tests
make test-parity        # bash parity tests
make test-integration   # Integration tests
make check              # Comprehensive checks

# Unit tests
make test-memory-pool   # Test string pool
make test-lexer         # Test lexer
make test-bench         # Run all unit bench tests

# Interactive tests (Python/pexpect)
source tests/interactive/.venv/bin/activate
python tests/interactive/run_tests.py
python tests/interactive/run_tests.py --spec line_editing.yaml  # Single spec
```

## Architecture

The codebase follows a modular Fortran architecture with explicit module dependencies:

```
src/
├── fortsh.f90              # Main REPL loop and program entry
├── common/                 # Core types and utilities
│   ├── types.f90           # shell_types module - core data structures
│   ├── string_pool.f90     # Zero-copy string memory pool
│   ├── error_handling.f90  # Error types and handling
│   └── performance.f90     # Performance monitoring
├── system/                 # OS interface layer
│   ├── interface.f90       # system_interface module - POSIX calls via C binding
│   ├── signals.f90         # Signal definitions
│   └── signal_handling.f90 # Signal handler registration
├── parsing/                # Lexing and parsing
│   ├── lexer.f90           # Token generation
│   ├── parser.f90          # Command parsing, glob expansion
│   ├── grammar_parser.f90  # Grammar-aware parser (produces AST)
│   └── command_tree.f90    # AST node types (command_node_t)
├── execution/              # Command execution
│   ├── executor.f90        # Pipeline and command execution
│   ├── ast_executor.f90    # AST-based execution engine
│   ├── builtins.f90        # Built-in command implementations
│   ├── jobs.f90            # Job control (bg, fg, jobs)
│   └── coprocess.f90       # Coprocess support
├── scripting/              # Shell scripting support
│   ├── variables.f90       # Variable storage and expansion
│   ├── expansion.f90       # Parameter expansion (${var#pattern}, etc.)
│   ├── substitution.f90    # Command substitution
│   ├── control_flow.f90    # if/for/while/case/function handling
│   ├── aliases.f90         # Alias management
│   └── shell_options.f90   # set/shopt options
├── io/                     # I/O and terminal
│   ├── readline.f90        # Line editing, history, completion
│   ├── syntax_highlight.f90 # Real-time syntax coloring
│   ├── heredoc.f90         # Here-document handling
│   └── fd_redirection.f90  # File descriptor management
└── c_interop/              # C library bridges
    └── fortsh_c_strings.f90 # C string ops (flang-new workaround)
```

### Key Data Flow

1. **Input**: `readline.f90` handles terminal input with editing, history, completion
2. **Parsing**: `grammar_parser.f90` tokenizes and builds `command_node_t` AST
3. **Expansion**: `expansion.f90` and `substitution.f90` process variables and command substitution
4. **Execution**: `ast_executor.f90` walks AST, calls `executor.f90` for external commands or `builtins.f90` for builtins

### Module Dependencies

The Makefile explicitly declares all module dependencies. When adding new modules:
- Add the `.o` target with its source and all module dependencies it `use`s
- Add to the `OBJECTS` list in dependency order
- Module files (`.mod`) go to `$(BUILDDIR)` via `-J$(BUILDDIR)`

## Platform Notes

### macOS ARM64 (M1/M2/M3)
- **Must use LLVM Flang** (`flang-new`) - gfortran has critical bugs on ARM64
- Command lines limited to 127 characters due to flang-new string buffer limitations
- Install via: `brew install llvm`
- The Makefile auto-detects and uses flang-new on macOS ARM64

### Linux
- Use gfortran (8+)
- No string length limitations

## Code Conventions

- Fortran 2018 standard (`-std=f2018`)
- All modules use `implicit none`
- Fixed-length character buffers in hot paths (avoids allocatable string heap issues on flang)
- Core types defined in `shell_types` module (`src/common/types.f90`)
- C interop via `iso_c_binding` for system calls

## Memory Pool

The string pool (`src/common/string_pool.f90`) provides zero-copy string storage to reduce allocations. Enabled by default; disable with `NO_MEMPOOL=1`.
