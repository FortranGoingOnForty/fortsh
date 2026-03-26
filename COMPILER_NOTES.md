# Compiler Notes for fortsh

## TL;DR

- **Linux x86_64**: Use `gfortran` (works great)
- **Linux aarch64**: Use `gfortran` (auto-enables C stat helpers for struct layout differences)
- **macOS ARM64 (M1/M2/M3/M4)**: Use **LLVM Flang (`flang-new`)** — gfortran has serious bugs
- **macOS x86_64**: Use `gfortran` with `-frecursive`

The Makefile auto-detects your platform and selects the right compiler. Just run `make`.

## macOS ARM64: Why flang-new?

gfortran on Apple Silicon has at least 8 confirmed bugs that make it unusable:

1. **Stack corruption** — Large stack arrays (600KB+) corrupt memory
2. **Deferred-length allocatable bug** — `character(len=:), allocatable` loses length descriptor
3. **Intent(out) crashes** — Subroutine return epilogue segfaults
4. **Allocatable string assignment corruption** — Assigning to allocatable strings in types corrupts heap
5. **Automatic finalization crashes** — Crashes during automatic cleanup
6. **Substring slice crashes** — `buffer(:length)` operations segfault
7. **Empty string assignment corruption** — `buffer = ''` corrupts heap
8. **flush() in loops corruption** — Frequent stderr flush in tight loops corrupts heap

Install flang-new:
```bash
brew install flang
```

## flang-new String Buffer Issue (Resolved)

flang-new has a known issue where Fortran string operations (substring slicing, direct assignment) on buffers larger than 128 bytes can cause heap corruption.

**This limitation has been fully worked around** via the C string library (`src/c_interop/fortsh_strings.c`), which routes all critical string operations through C code instead of flang-new's Fortran runtime. The C string library is auto-enabled for all flang-new builds (`USE_C_STRINGS`).

Additionally, a `safe_assign_alloc_str` routine performs char-by-char copies for allocatable strings >16 bytes, and the expansion pipeline uses C-backed growing buffers (`buffer_grow`, `buffer_append_chars`) for all variable and parameter expansion.

The workaround is transparent — no command length limits, no feature restrictions. macOS ARM64 passes the full test suite (3,600+ POSIX tests, 850+ builtin tests, 200+ stress tests) identically to Linux.

## flang-new Fortran I/O Caveat

flang-new's `write(output_unit, ...)` and `write(error_unit, ...)` cache file descriptors at process startup and don't follow `dup2` redirections. This means builtin output written via Fortran I/O bypasses shell redirections like `> /dev/null`.

**Fix**: Key builtins use `write_stdout`/`write_stderr` from `io_helpers.f90`, which call C `write()` directly to fd 1/2. This respects all `dup2` redirections. Files affected: `builtins.f90`, `aliases.f90`, `shell_options.f90`, `better_errors.f90`, `grammar_parser.f90`, `fd_redirection.f90`, `variables.f90`, `ast_executor.f90`.

When adding new builtin output that users might redirect, use `write_stdout`/`write_stderr` instead of `write(output_unit/error_unit, ...)`.

## Linux aarch64: struct stat Layout

glibc on aarch64 uses a different `struct stat` layout than x86_64:
- `st_mode` and `st_nlink` are **swapped** (mode at offset 16 on aarch64, offset 24 on x86_64)
- `st_nlink` is 4 bytes (`unsigned int`) on aarch64, 8 bytes (`unsigned long`) on x86_64
- `st_blksize` is 4 bytes on aarch64, 8 bytes on x86_64
- Total struct size: 128 bytes (aarch64) vs 144 bytes (x86_64)

**Fix**: C stat helper functions in `fd_wrapper.c` (`fortsh_stat_mode`, `fortsh_stat_size`, etc.) use system headers for the correct layout. Enabled via `-DUSE_C_STAT` (auto-set by Makefile when `uname -m` is `aarch64`). x86_64 uses the Fortran `stat_t` struct directly.

## Compiler Selection

Force a specific compiler:
```bash
make FC=gfortran clean all    # Force gfortran
make FC=flang-new clean all   # Force LLVM Flang
```

Build flags:
```bash
make NO_C_STRINGS=1     # Disable C string library (will crash on flang-new)
make NO_MEMPOOL=1       # Disable memory pooling
make MEMPOOL_DEBUG=1    # Enable memory pool debug output
```
