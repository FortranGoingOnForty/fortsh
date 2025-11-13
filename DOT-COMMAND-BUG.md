# Dot Command Segfault Bug - Investigation Notes

## Status: PRE-EXISTING BUG (not introduced by recent changes)

## Failing Tests
- **P2-2.1**: dot command passes arguments to sourced script
- **P2-2.3**: dot command works with absolute paths

## Symptoms

### Segfault when sourcing files with executable commands:
```bash
echo 'echo sourced' > /tmp/test
./bin/fortsh -c '. /tmp/test'
# Result: Segmentation fault
```

### Works when sourcing files with ONLY variable assignments:
```bash
echo 'VAR=value' > /tmp/test
./bin/fortsh -c '. /tmp/test'
# Result: Success (no output, no crash)
```

### Works when there's a command AFTER the dot command:
```bash
echo 'SOURCED_VAR=from_script' > /tmp/test
./bin/fortsh -c '. /tmp/test; echo $SOURCED_VAR'
# Result: from_script (works!)
```

## Root Cause Analysis

The segfault occurs when:
1. Dot command (`. file`) is executed in `-c` mode
2. The sourced file contains executable commands (not just assignments)
3. There is NO subsequent command after the dot command in the `-c` string

### Crash Location
Backtrace consistently shows crash at offset `05f`:
```
#0  0x100ffa103
#1  0x100ff9083
#2  0x194bdc623
#3  0x1005257f7
#4  0x10052b41f
#5  0x10052fbf3
#6  0x100515657
#7  0x10052fc0f
#8  0x10053608b
#9  0x10053717b
#10 0x100537307
#11 0x10059c0e3
#12 0x1005a805f
```

### Code Flow

1. User runs: `fortsh -c '. /tmp/test'`
2. Command parsed → `builtin_source` called (builtins.f90:604)
3. `builtin_source` sets:
   ```fortran
   shell%source_file = filename
   shell%should_source = .true.
   ```
4. Control returns to `-c` handler (fortsh.f90:163-166):
   ```fortran
   if (shell%should_source) then
     call process_source_file(shell)
   end if
   ```
5. `process_source_file` opens file and reads lines
6. For each line, it calls either:
   - `execute_ast(ast_root, shell)` (new parser)
   - `execute_pipeline(pipeline, shell, line)` (old parser)
7. **SEGFAULT occurs during command execution**

### Key Observations

1. **Both old AND new parsers crash** → Not a parser-specific issue
2. **Variable assignments work fine** → Issue is with command execution specifically
3. **Works when dot command isn't the last command** → Related to execution context or cleanup

### Hypothesis

The segfault might be caused by:
1. **Nested execution context issue**: Executing commands from within `process_source_file` while still in the `-c` handler's execution context
2. **State corruption**: Shell state (esp. `positional_params`) not properly initialized when sourcing from `-c` mode
3. **Memory issue**: Some memory structure being accessed after deallocation or before allocation
4. **Exit handling**: The `-c` handler immediately calls `c_exit()` after `process_source_file`, which might interfere with cleanup

## Files Modified (Attempted Fixes)

### src/execution/builtins.f90
Added `positional_params` allocation check in `builtin_source`:
```fortran
if (.not. allocated(shell%positional_params)) then
  allocate(shell%positional_params(50))
end if
```

### src/fortsh.f90
Modified `process_source_file` to use AST parser when `use_new_parser = true`:
```fortran
if (shell%use_new_parser) then
  converted_line = convert_backticks_to_dollar_paren(proc_subst_line)
  ast_root => parse_command_line(converted_line)
  if (associated(ast_root)) then
    exit_code = execute_ast(ast_root, shell)
    shell%last_exit_status = exit_code
    call destroy_command_node(ast_root)
  end if
else
  ! OLD PARSER PATH...
end if
```

## Verification: Bug Existed Before Changes

Tested with commit **485a3c6** (before any dot command modifications):
```bash
git stash
make clean && make -j4
echo 'echo test' > /tmp/test_before
./bin/fortsh -c '. /tmp/test_before'
# Result: SEGFAULT (same behavior)
```

**Conclusion**: This is a **PRE-EXISTING BUG**, not introduced by recent changes.

## Next Steps for Fix

### Option 1: Investigate Memory Corruption
- Use valgrind or AddressSanitizer to identify exact memory issue
- Check if shell state is being corrupted during nested execution

### Option 2: Fix Execution Context
- Ensure `process_source_file` properly saves/restores execution context
- Check if `shell%running` flag or other state needs special handling in `-c` mode

### Option 3: Defer to After Parser Stabilization
- This bug appears to be deep in the execution engine
- May require significant refactoring of how sourcing interacts with `-c` mode
- Consider deferring until after other POSIX compliance work is complete

## Workaround for Testing

For P2-2.2 (which passes):
- Sourced file: `SOURCED_VAR=from_script` (no commands)
- Test command: `. file; echo $SOURCED_VAR` (has command after dot)

For P2-2.1 & P2-2.3 (which fail):
- Need actual command execution in sourced file
- Would need full fix to pass

## Current Status

- **Builtins tests**: 49/52 passing (94.2%)
- **Remaining failures**: 3 (2 dot command + 1 multiple semicolons)
- **Priority**: Fix multiple semicolons (EDGE-4) first, then return to dot command

---

*Document created: 2025-11-10*
*Last updated: 2025-11-10*
