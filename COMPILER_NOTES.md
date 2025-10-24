# Compiler Notes for fortsh

## TL;DR

- **Linux**: Use `gfortran` (works great)
- **macOS ARM64 (M1/M2/M3)**: Use **LLVM Flang (`flang-new`)** - gfortran has serious bugs
- **macOS x86_64**: Use `gfortran` (should work fine, untested)


Lots of potential bugs uncovered in gfortran ARM64

1. **Stack corruption** - Large stack arrays (600KB+) corrupt memory
2. **Deferred-length allocatable bug** - `character(len=:), allocatable` loses length descriptor
3. **Intent(out) crashes** - Subroutine return epilogue segfaults
4. **Allocatable string assignment corruption** - Assigning to allocatable strings in types corrupts heap
5. **Automatic finalization crashes** - Crashes during automatic cleanup
6. **Substring slice crashes** - `buffer(:length)` operations segfault
7. **Empty string assignment corruption** - `buffer = ''` corrupts heap
8. **flush() in loops corruption** - Frequent stderr flush in tight loops corrupts heap

So we switched to flang-new

```bash
brew install llvm
```

This isntalls the full LLVM toolchain including `flang-new`.

The Makefile auto-detects and uses Flang if available:

```bash
make clean
make
```

You'll see:
```
Using LLVM Flang (flang-new) - recommended for macOS ARM64
```

## Note: Flang limitations

flang is far more stable it seems, but it has **one pretty glaring limitation**: string buffers larger than 128 bytes cause heap corruption when performing certain operations (substring slicing, direct assignment from allocatable strings) on them.

**Impact for fortsh:**
- Command lines are limited to **127 characters** on apple silicon.
- All other features work normally (history, tab completion, syntax highlighting, etc.)
- This is a fundamental limitation we cannot work around without risking heap corruption

**Why? because that seems odd:**
- Allocating strings >128 bytes works fine, obviously
- BUT operating on them (substring ops, assignments) triggers heap corruption
- We attempted a "shadow buffer" pattern (1024-byte storage, 128-byte working buffer)
- Even this approach still limits effective command length to 128 bytes

## Alternative: x86_64 gfortran via Rosetta

If you prefer not to use Flang, you can use x86_64 gfortran through Rosetta, and tell us how it goes:

### other

Force a specific compiler:

```bash
make FC=gfortran clean all    # Force gfortran
make FC=flang-new clean all   # Force LLVM Flang
```
- **gfortran**: Frequent crashes, unusable
- **flang-new**: Works great, but 127-character command limit
