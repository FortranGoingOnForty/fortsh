# Heredoc Fix Plan - Path to 100% POSIX Compliance

## Problem Analysis

### Current Behavior
When heredocs are used with `-c` flag:
```bash
./bin/fortsh -c 'cat <<EOF
line1
line2
EOF'
```
The shell hangs waiting for input, never recognizing the EOF delimiter.

### Root Cause
The `-c` flag processing doesn't properly handle multi-line strings containing heredocs. The parser sees the `<<EOF` but doesn't recognize the subsequent lines as heredoc content because:

1. The command string is processed as a single line
2. The newlines in the string are real newlines (char(10)), not escape sequences
3. The parser expects heredoc content to come from subsequent input lines, not from within the same string

### Why It Works Interactively
When typing interactively or piping:
```bash
echo 'cat <<EOF
line1
line2
EOF' | ./bin/fortsh
```
This works because each line is read separately, allowing the heredoc parser to collect lines until it sees the delimiter.

## Solution Approach

### Option 1: Pre-process Multi-line -c Commands (Recommended)
Modify the `-c` flag handler to detect heredocs and handle them specially:

1. **Detect heredoc syntax** in the command string
2. **Extract heredoc content** from the multi-line string
3. **Store heredoc content** before parsing
4. **Inject stored content** when parser expects heredoc input

**Implementation steps:**
1. In fortsh.f90, after getting command_string with `-c`:
   - Scan for heredoc markers (`<<EOF`, `<<'EOF'`, etc.)
   - If found, extract everything between marker and delimiter
   - Store in a temporary heredoc buffer
   - Pass modified command to parser with heredoc pre-loaded

### Option 2: Modify Parser to Handle Embedded Heredocs
Change the parser to recognize that with `-c` flag, heredoc content might be embedded in the same string:

1. Add a flag to parser state indicating `-c` mode
2. When heredoc is detected in `-c` mode, look for content in remaining string
3. Parse embedded newlines as heredoc content, not command separators

**Challenges:**
- More invasive change to parser
- Need to handle mixed content (commands after heredoc)

### Option 3: Convert Newlines to Escape Sequences
Pre-process the `-c` command to convert actual newlines to `\n`:

1. Before parsing, scan command_string
2. Within heredoc sections, convert char(10) to "\n"
3. Let existing parser handle escaped newlines

**Issues:**
- Might break other multi-line constructs
- Need to detect heredoc boundaries accurately

## Recommended Implementation

### Phase 1: Detection (Quick Test)
Add debug output to understand current flow:
```fortran
if (execute_command_string) then
  ! Debug: Check if string contains heredoc
  if (index(command_string, '<<') > 0) then
    write(error_unit, *) 'DEBUG: Heredoc detected in -c command'
    write(error_unit, *) 'Command length:', len_trim(command_string)
    ! Check for actual newlines
    do i = 1, len_trim(command_string)
      if (command_string(i:i) == char(10)) then
        write(error_unit, *) 'Newline at position:', i
      end if
    end do
  end if
```

### Phase 2: Simple Fix (Option 1)
Implement heredoc pre-processing:

1. Create `extract_heredocs_from_command` function
2. Store heredoc content in shell state
3. Modify heredoc reader to check pre-stored content first
4. Test with all three heredoc test cases

### Phase 3: Comprehensive Testing
Test edge cases:
- Multiple heredocs in one command
- Heredoc with command substitution
- Heredoc in subshell
- Heredoc with quoted delimiter

## Success Criteria
All three heredoc tests must pass:
1. Simple heredoc
2. Heredoc with variable expansion
3. Quoted heredoc (no expansion)

## Estimated Effort
- Detection & Analysis: 1 hour
- Implementation: 2-4 hours
- Testing & Refinement: 1-2 hours
- **Total: 4-7 hours**

## Alternative: Disable Heredoc Tests
If heredocs with `-c` prove too complex, we could:
1. Document this as a known limitation
2. Skip these specific tests
3. Focus on the 59 failures in advanced tests

However, fixing heredocs would bring us to **99% on basic POSIX tests**, which is symbolically important.