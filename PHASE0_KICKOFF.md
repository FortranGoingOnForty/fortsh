# Phase 0 Kickoff: Parser Rewrite Infrastructure

**Week:** 1 of 7
**Goal:** Set up infrastructure without breaking anything
**Branch:** `parser`

---

## Today's Tasks (Day 1)

### Task 1: Create New Source Files (30 min)

Create skeleton files with proper module structure:

```fortran
! src/parsing/lexer.f90
module lexer
  use iso_fortran_env
  use shell_types
  implicit none
  private
  public :: tokenize, token_t

  ! Token type will be added to types.f90

contains

  ! Stub implementation
  subroutine tokenize(input, tokens, num_tokens)
    character(len=*), intent(in) :: input
    type(token_t), intent(out) :: tokens(:)
    integer, intent(out) :: num_tokens

    ! Placeholder - just return empty for now
    num_tokens = 0
  end subroutine

end module lexer
```

```fortran
! src/parsing/grammar_parser.f90
module grammar_parser
  use iso_fortran_env
  use shell_types
  use lexer
  implicit none
  private
  public :: parse_with_grammar

contains

  ! Stub implementation
  subroutine parse_with_grammar(input, pipeline, shell)
    character(len=*), intent(in) :: input
    type(pipeline_t), intent(out) :: pipeline
    type(shell_state_t), intent(inout) :: shell

    ! Placeholder - delegate to old parser for now
    call parse_pipeline(input, pipeline)
  end subroutine

end module grammar_parser
```

```fortran
! src/parsing/command_tree.f90
module command_tree
  use iso_fortran_env
  use shell_types
  implicit none
  private

  ! Future home of command tree structures

end module command_tree
```

### Task 2: Add Token Type to types.f90 (20 min)

Add after the command_t type definition:

```fortran
! Token types for new parser
integer, parameter :: TOKEN_WORD = 1
integer, parameter :: TOKEN_KEYWORD = 2
integer, parameter :: TOKEN_OPERATOR = 3
integer, parameter :: TOKEN_REDIRECT = 4
integer, parameter :: TOKEN_ASSIGN = 5
integer, parameter :: TOKEN_EOF = 6
integer, parameter :: TOKEN_NEWLINE = 7

type :: token_t
  integer :: token_type           ! TOKEN_* constant
  character(len=MAX_TOKEN_LEN) :: value
  integer :: start_pos
  integer :: end_pos
  logical :: quoted
end type token_t

! Command node types for grammar parser
integer, parameter :: CMD_SIMPLE = 1
integer, parameter :: CMD_PIPELINE = 2
integer, parameter :: CMD_LIST = 3
integer, parameter :: CMD_FOR_LOOP = 4
integer, parameter :: CMD_WHILE_LOOP = 5
integer, parameter :: CMD_UNTIL_LOOP = 6
integer, parameter :: CMD_IF_STATEMENT = 7
integer, parameter :: CMD_CASE_STATEMENT = 8
integer, parameter :: CMD_SUBSHELL = 9
integer, parameter :: CMD_BRACE_GROUP = 10
integer, parameter :: CMD_FUNCTION_DEF = 11

! Will implement command_node_t later
```

### Task 3: Add Feature Flag (15 min)

Add to `shell_state_t` type in types.f90:

```fortran
  ! Parser feature flag
  logical :: use_new_parser = .false.  ! Default to old parser
```

### Task 4: Add Parser Switch in fortsh.f90 (30 min)

Find where `parse_pipeline` is called and add conditional:

```fortran
! Check for environment variable FORTSH_USE_NEW_PARSER
if (shell%use_new_parser) then
  call parse_with_grammar(trim(input_line), pipeline, shell)
else
  call parse_pipeline(trim(input_line), pipeline)
end if
```

Add initialization in main():

```fortran
! Initialize parser selection
call get_environment_variable('FORTSH_USE_NEW_PARSER', env_value)
if (trim(env_value) == '1' .or. trim(env_value) == 'true') then
  shell%use_new_parser = .true.
  if (shell%is_interactive) then
    print *, 'Using new grammar-aware parser (experimental)'
  end if
end if
```

### Task 5: Update Makefile (15 min)

Add new source files to SOURCES:

```makefile
SOURCES_PARSING = \
    src/parsing/glob.f90 \
    src/parsing/parser.f90 \
    src/parsing/lexer.f90 \
    src/parsing/grammar_parser.f90 \
    src/parsing/command_tree.f90
```

### Task 6: Compile and Test (20 min)

```bash
# Clean build
make clean
make

# Test with old parser (default)
./bin/fortsh -c 'echo "Old parser works"'

# Test with new parser (should delegate to old)
FORTSH_USE_NEW_PARSER=1 ./bin/fortsh -c 'echo "New parser works"'

# Run full test suite with old parser
./tests/run_posix_tests.sh

# Verify feature flag works
FORTSH_USE_NEW_PARSER=1 ./tests/run_posix_tests.sh
```

---

## Day 2: Testing Infrastructure

### Task 1: Create Lexer Test File

```fortran
! tests/test_lexer.f90
program test_lexer
  use lexer
  use shell_types
  implicit none

  call test_simple_tokenization()
  call test_quoted_strings()
  call test_operators()
  call test_keywords()

  print *, 'All lexer tests passed!'

contains

  subroutine test_simple_tokenization()
    type(token_t) :: tokens(100)
    integer :: num_tokens

    call tokenize('echo hello', tokens, num_tokens)

    ! Will implement assertions later
    print *, 'test_simple_tokenization: STUB'
  end subroutine

  ! ... more tests

end program test_lexer
```

### Task 2: Create Grammar Parser Test File

Similar structure for grammar parser tests.

### Task 3: Create Integration Test Script

```bash
#!/bin/bash
# tests/test_new_parser.sh

FORTSH_USE_NEW_PARSER=1 \
  ./tests/run_posix_tests.sh > /tmp/new_parser_results.txt 2>&1

# Compare with baseline
# ... comparison logic
```

---

## Day 3: Documentation

### Task 1: Document Feature Flag

Add to README.md or USAGE.md:

```markdown
## Experimental New Parser

fortsh includes an experimental grammar-aware parser that fixes nested control structures.

To enable:
```bash
export FORTSH_USE_NEW_PARSER=1
./bin/fortsh
```

**Status:** Under development, delegates to old parser currently
**ETA:** Full implementation in ~7 weeks
```

### Task 2: Add Developer Notes

Create CONTRIBUTING.md section on parser development.

---

## Success Criteria for Phase 0

✅ All new files compile
✅ Feature flag works
✅ Old parser still works normally
✅ New parser exists but delegates to old
✅ All existing tests pass
✅ Infrastructure for testing in place
✅ Documentation updated

---

## Next Phase Preview

**Phase 1 (Week 2): Basic Lexer**
- Implement actual tokenization
- Token type recognition
- Quote handling
- Operator extraction

**Ready to start?** Let's create those files!
