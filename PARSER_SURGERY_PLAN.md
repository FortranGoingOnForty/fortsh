# Parser Surgery Plan: Fix Single-Line Nested Control Structures

## Problem Statement

The parser currently splits commands on semicolons without tracking control structure depth, causing malformed parsing of single-line nested control structures.

### Example Issue
```bash
# This breaks:
for i in 1 2; do for j in a b; do echo Inner; done; done

# Parser incorrectly splits into:
["for i in 1 2", "do for j in a b", "do echo Inner", "done", "done"]
#                  ^^^^^^^^^^^^^^^^
#                  WRONG - "do" should be with "for"
```

## Root Cause Analysis

**File:** `src/parsing/parser.f90`
**Location:** Lines 284-318 (semicolon splitting logic)

**Current Logic:**
```fortran
else if (working_input(i:i) == ';') then
  ! Only split if NOT inside for(()), braces, parens, or case
  else if (in_for_arith .or. brace_depth > 0 .or. paren_depth > 0 .or. case_depth > 0) then
    ! Skip - we're inside a special construct
  else
    ! SPLIT HERE - this is the problem!
    cmd_count = cmd_count + 1
    ! ... create new command
  end if
end if
```

**What's Missing:**
- No tracking for regular loops (for/while/until...do...done)
- No tracking for conditionals (if...then...fi)

**What Exists:**
- ✅ `case_depth` for case statements (lines 167-230)
- ✅ `in_for_arith` for arithmetic for loops
- ✅ `brace_depth` for function braces
- ✅ `paren_depth` for subshells

## Solution Design

### Phase 1: Add Depth Tracking Variables

**Location:** `src/parsing/parser.f90` line 28

**Current:**
```fortran
integer :: paren_depth, brace_depth, case_depth
```

**New:**
```fortran
integer :: paren_depth, brace_depth, case_depth, loop_depth, if_depth
```

**Initialization:** Add at line 111:
```fortran
loop_depth = 0
if_depth = 0
```

### Phase 2: Track Loop Depth (do/done)

**Location:** After line 231 (after case_depth tracking)

```fortran
! Track loop depth: for/while/until...do...done
! Increment on 'do' keyword (marks start of loop body)
if (i <= len_trim(working_input) - 1) then
  if (working_input(i:i+1) == 'do') then
    ! Verify word boundary before
    if (i == 1 .or. working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';') then
      ! Verify word boundary after
      if (i+2 > len_trim(working_input) .or. &
          working_input(i+2:i+2) == ' ' .or. &
          working_input(i+2:i+2) == ';') then
        loop_depth = loop_depth + 1
      end if
    end if
  end if
end if

! Decrement on 'done' keyword (marks end of loop)
if (i <= len_trim(working_input) - 3) then
  if (working_input(i:i+3) == 'done') then
    ! Verify word boundary before
    if (i == 1 .or. working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';') then
      ! Verify word boundary after
      if (i+4 > len_trim(working_input) .or. &
          working_input(i+4:i+4) == ' ' .or. &
          working_input(i+4:i+4) == ';') then
        loop_depth = loop_depth - 1
        if (loop_depth < 0) loop_depth = 0  ! Prevent negative
      end if
    end if
  end if
end if
```

### Phase 3: Track If Depth (if/then/fi)

**Location:** Immediately after loop_depth tracking

```fortran
! Track if depth: if...then...fi
! Increment on 'if' keyword
if (i <= len_trim(working_input) - 1) then
  if (working_input(i:i+1) == 'if') then
    ! Verify word boundary
    if (i == 1 .or. working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';') then
      if (i+2 > len_trim(working_input) .or. &
          working_input(i+2:i+2) == ' ' .or. &
          working_input(i+2:i+2) == ';') then
        if_depth = if_depth + 1
      end if
    end if
  end if
end if

! Decrement on 'fi' keyword
if (i <= len_trim(working_input) - 1) then
  if (working_input(i:i+1) == 'fi') then
    ! Verify word boundary
    if (i == 1 .or. working_input(i-1:i-1) == ' ' .or. working_input(i-1:i-1) == ';') then
      if (i+2 > len_trim(working_input) .or. &
          working_input(i+2:i+2) == ' ' .or. &
          working_input(i+2:i+2) == ';') then
        if_depth = if_depth - 1
        if (if_depth < 0) if_depth = 0  ! Prevent negative
      end if
    end if
  end if
end if
```

### Phase 4: Update Semicolon Logic

**Location:** Line 303 (current semicolon check)

**Current:**
```fortran
else if (in_for_arith .or. brace_depth > 0 .or. paren_depth > 0 .or. case_depth > 0) then
  ! Skip - inside special construct
```

**New:**
```fortran
else if (in_for_arith .or. brace_depth > 0 .or. paren_depth > 0 .or. &
         case_depth > 0 .or. loop_depth > 0 .or. if_depth > 0) then
  ! Skip - inside special construct (don't split on semicolons)
```

## Test Cases

### Test 1: Nested Loops
```bash
# Should work after fix:
for i in 1 2; do for j in a b; do echo $i$j; done; echo Outer; done

# Expected output:
1a
1b
Outer
2a
2b
Outer
```

### Test 2: Nested If Statements
```bash
# Should work after fix:
if true; then if false; then echo A; else echo B; fi; echo C; fi

# Expected output:
B
C
```

### Test 3: Mixed Nesting
```bash
# Should work after fix:
for i in 1 2; do if [ $i -eq 1 ]; then echo One; else echo Two; fi; done

# Expected output:
One
Two
```

### Test 4: Deep Nesting
```bash
# Should work after fix:
for i in 1; do for j in 2; do for k in 3; do echo $i$j$k; done; done; done

# Expected output:
123
```

## Implementation Steps

1. ✅ Add `loop_depth` and `if_depth` variables
2. ✅ Initialize them to 0
3. ✅ Add keyword tracking for `do`/`done`
4. ✅ Add keyword tracking for `if`/`fi`
5. ✅ Update semicolon split condition
6. ✅ Compile and test
7. ✅ Run full POSIX test suite regression check

## Risks and Mitigation

### Risk 1: False Positives
**Problem:** Keywords in strings or comments might be counted
**Mitigation:** Already handled - tracking only happens when `in_quotes` is false

### Risk 2: Edge Cases
**Problem:** Unusual syntax like `doit` or `iffy` might match
**Mitigation:** Word boundary checks ensure we only match exact keywords

### Risk 3: Regression
**Problem:** Might break currently working tests
**Mitigation:**
- Test incrementally
- Run full test suite after each change
- Keep backup of working code

## Expected Outcome

After implementation:
- ✅ Single-line nested loops work correctly
- ✅ Single-line nested if statements work correctly
- ✅ All 99 Core POSIX tests still pass
- ✅ All 52 Builtin tests still pass
- ✅ No regressions in existing functionality

## Files Modified

1. `src/parsing/parser.f90` - Main parser logic (~100 lines added)

## Timeline

- Analysis: 30 minutes (DONE - this document)
- Implementation: 1-2 hours
- Testing: 30 minutes
- Regression testing: 15 minutes

**Total: ~3 hours**
