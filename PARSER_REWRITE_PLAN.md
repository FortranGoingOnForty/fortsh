# Parser Rewrite Plan: Grammar-Aware Architecture

**Branch:** `parser`
**Goal:** Implement proper grammar-aware parsing without breaking existing functionality
**Impact:** Fixes nested control structures, single-line compound commands, and future extensibility

---

## Executive Summary

The current parser uses a **token-splitting approach** that processes input character-by-character and splits on operators (`;`, `&&`, `||`, `|`) without understanding shell grammar. This works for simple cases but fails for nested control structures.

**The Solution:** Implement a **two-phase parser**:
1. **Lexer Phase** - Tokenize input into meaningful units (words, operators, keywords)
2. **Parser Phase** - Build command structures using grammar rules

This matches how bash, dash, and other POSIX shells work.

---

## Part 1: Current Architecture Analysis

### Current Flow (src/parsing/parser.f90)

```
Input: "for i in 1 2; do echo $i; done"
  ↓
Character-by-character scan:
  - Split on ';' → ["for i in 1 2", "do echo $i", "done"]
  - Each becomes a separate command
  ↓
Execute: process_for_statement(), process_do_statement(), process_done_statement()
  ↓
Problem: "do echo $i" is malformed (do without matching for)
```

### Key Problems

1. **No Grammar Awareness**
   - Parser doesn't understand `for...do...done` is ONE compound command
   - Splits on semicolons before understanding structure

2. **Mixed Concerns**
   - Lexical analysis (tokenization) mixed with command splitting
   - No separation between "what are the tokens?" and "what's the grammar?"

3. **State-Based Hacks**
   - Uses depth counters (`case_depth`, `paren_depth`) as band-aids
   - Each new construct requires new state tracking
   - Doesn't scale

4. **Single-Pass Processing**
   - Tries to split and understand in one pass
   - Can't handle lookahead needed for compound commands

### What Works Well

✅ **Token extraction** - `parse_single_command()` does good work
✅ **Operator recognition** - Correctly identifies `&&`, `||`, `|`, etc.
✅ **Quote handling** - Properly tracks quoted sections
✅ **Redirection parsing** - Works correctly
✅ **Variable expansion** - Handled separately and works well

### Files Involved

- `src/parsing/parser.f90` - Main parser (parse_pipeline)
- `src/scripting/control_flow.f90` - Control flow processing
- `src/execution/executor.f90` - Command execution
- `src/common/types.f90` - Type definitions

---

## Part 2: New Architecture Design

### Two-Phase Approach

```
┌─────────────────────────────────────────────────────────────┐
│ INPUT: "for i in 1 2; do echo $i; done"                    │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 1: LEXER (Tokenization)                              │
│ - Break into tokens with types                             │
│ - Preserve structure (don't split compound commands)       │
└─────────────────────────────────────────────────────────────┘
                        ↓
        Tokens: [FOR, WORD("i"), IN, WORD("1"), WORD("2"),
                 SEMI, DO, WORD("echo"), WORD("$i"),
                 SEMI, DONE]
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ PHASE 2: PARSER (Grammar-Aware)                            │
│ - Recognize compound commands                              │
│ - Build command tree                                       │
│ - Apply grammar rules                                      │
└─────────────────────────────────────────────────────────────┘
                        ↓
        Command Tree:
        FOR_LOOP {
          var: "i"
          list: ["1", "2"]
          body: [
            SIMPLE_COMMAND("echo", ["$i"])
          ]
        }
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ EXECUTION                                                   │
└─────────────────────────────────────────────────────────────┘
```

### Phase 1: Enhanced Lexer

**File:** `src/parsing/lexer.f90` (NEW)

**Purpose:** Break input into tokens with semantic meaning

**Token Types:**
```fortran
integer, parameter :: TOKEN_WORD = 1           ! Regular word
integer, parameter :: TOKEN_KEYWORD = 2        ! if, for, while, etc.
integer, parameter :: TOKEN_OPERATOR = 3       ! &&, ||, |, ;
integer, parameter :: TOKEN_REDIRECT = 4       ! >, <, >>, etc.
integer, parameter :: TOKEN_ASSIGN = 5         ! Variable assignment
integer, parameter :: TOKEN_EOF = 6            ! End of input
integer, parameter :: TOKEN_NEWLINE = 7        ! Line break

type :: token_t
  integer :: type                              ! TOKEN_* constant
  character(len=MAX_TOKEN_LEN) :: value        ! Token text
  integer :: start_pos                         ! Position in input
  integer :: end_pos
  logical :: quoted                            ! Was it quoted?
end type
```

**Key Functions:**
- `tokenize(input, tokens)` - Main entry point
- `next_token()` - Get next token
- `peek_token()` - Look ahead without consuming
- `is_keyword(word)` - Check if word is a shell keyword

### Phase 2: Grammar Parser

**File:** `src/parsing/grammar_parser.f90` (NEW)

**Purpose:** Build command structures using grammar rules

**Command Types:**
```fortran
integer, parameter :: CMD_SIMPLE = 1           ! Regular command
integer, parameter :: CMD_PIPELINE = 2         ! cmd1 | cmd2
integer, parameter :: CMD_LIST = 3             ! cmd1; cmd2 or cmd1 && cmd2
integer, parameter :: CMD_FOR_LOOP = 4         ! for...do...done
integer, parameter :: CMD_WHILE_LOOP = 5       ! while...do...done
integer, parameter :: CMD_UNTIL_LOOP = 6       ! until...do...done
integer, parameter :: CMD_IF_STATEMENT = 7     ! if...then...fi
integer, parameter :: CMD_CASE_STATEMENT = 8   ! case...esac
integer, parameter :: CMD_SUBSHELL = 9         ! ( ... )
integer, parameter :: CMD_BRACE_GROUP = 10     ! { ... }
integer, parameter :: CMD_FUNCTION_DEF = 11    ! function or name()

type :: command_node_t
  integer :: cmd_type                          ! CMD_* constant
  type(token_t), allocatable :: tokens(:)      ! Tokens for this command
  type(command_node_t), pointer :: next        ! Next in sequence
  type(command_node_t), pointer :: body        ! Body for compound commands
  type(command_node_t), pointer :: else_part   ! For if/then/else
  ! ... more fields as needed
end type
```

**Grammar Rules (Recursive Descent):**
```fortran
! Grammar (simplified):
! complete_command := list
! list := and_or ((';' | '&' | NEWLINE) and_or)*
! and_or := pipeline (('&&' | '||') pipeline)*
! pipeline := command ('|' command)*
! command := simple_command | compound_command
! compound_command := for_clause | while_clause | if_clause | case_clause | ...
! for_clause := 'for' NAME 'in' word* ';'? 'do' list 'done'
```

**Key Functions:**
- `parse_complete_command()` - Top-level parser
- `parse_compound_command()` - Handle if/for/while/case
- `parse_for_loop()` - Specific to for loops
- `parse_pipeline()` - Handle pipelines
- `parse_simple_command()` - Handle regular commands

---

## Part 3: Phased Implementation

### Phase 0: Preparation (Week 1)

**Goal:** Set up infrastructure without changing behavior

**Tasks:**
1. Create new files with empty structures
   - `src/parsing/lexer.f90`
   - `src/parsing/grammar_parser.f90`
   - `src/parsing/command_tree.f90`

2. Add feature flag to `types.f90`
   ```fortran
   logical :: use_new_parser = .false.  ! Feature flag
   ```

3. Add test harness
   ```fortran
   ! In fortsh.f90, add:
   if (shell%use_new_parser) then
     call new_parse_pipeline(input, pipeline, shell)
   else
     call parse_pipeline(input, pipeline)  ! Existing
   end if
   ```

4. Create parallel test suite
   - Copy existing tests
   - Run with `FORTSH_USE_NEW_PARSER=1`

**Success Criteria:** Compiles, feature flag works, tests pass with old parser

### Phase 1: Basic Lexer (Week 2)

**Goal:** Implement tokenization that matches current behavior

**Tasks:**
1. Implement `token_t` type in `src/common/types.f90`

2. Implement `tokenize()` function
   - Quote handling (preserve from old parser)
   - Operator recognition (`&&`, `||`, `|`, `;`)
   - Word extraction
   - Handle redirections

3. Implement keyword recognition
   ```fortran
   function is_keyword(word) result(is_kw)
     character(len=*), intent(in) :: word
     logical :: is_kw

     select case(trim(word))
     case('if', 'then', 'else', 'elif', 'fi')
       is_kw = .true.
     case('for', 'in', 'do', 'done')
       is_kw = .true.
     case('while', 'until')
       is_kw = .true.
     case('case', 'esac')
       is_kw = .true.
     case default
       is_kw = .false.
     end select
   end function
   ```

4. Add lexer tests
   - Test tokenization of simple commands
   - Test quote preservation
   - Test operator recognition

**Success Criteria:**
- Lexer correctly tokenizes simple commands
- All quote tests pass
- Operator recognition works

### Phase 2: Simple Command Parser (Week 3)

**Goal:** Parse simple commands using new architecture

**Tasks:**
1. Implement `command_node_t` type

2. Implement `parse_simple_command()`
   - Takes token stream
   - Builds command node
   - Handles redirections
   - Handles variable assignments

3. Implement `parse_pipeline()`
   - Handle `|` operator
   - Build pipeline nodes

4. Convert simple command parsing to new system
   - Enable new parser for non-compound commands
   - Run tests

**Success Criteria:**
- Simple commands work: `echo hello`, `ls -la`
- Pipelines work: `echo hello | grep h`
- Redirections work: `echo test > file`
- All basic POSIX tests pass with new parser

### Phase 3: For Loops (Week 4)

**Goal:** Implement `for...do...done` with proper nesting

**Tasks:**
1. Implement `parse_for_loop()`
   ```fortran
   function parse_for_loop(tokens, pos) result(node)
     type(token_t), intent(in) :: tokens(:)
     integer, intent(inout) :: pos
     type(command_node_t) :: node

     ! Grammar: for NAME in WORDS; do LIST; done
     expect_token(tokens, pos, 'for')
     node%loop_var = tokens(pos)%value
     pos = pos + 1
     expect_token(tokens, pos, 'in')
     ! ... collect words until 'do'
     ! ... parse body until 'done'
   end function
   ```

2. Handle nested for loops
   - Recursive parsing of loop body
   - Test: `for i in 1 2; do for j in a b; do echo $i$j; done; done`

3. Handle for loop variations
   - Empty lists
   - Globs in lists
   - Arithmetic for loops

**Success Criteria:**
- Single-line for loops work
- Nested for loops work
- All for loop POSIX tests pass

### Phase 4: If Statements (Week 5)

**Goal:** Implement `if...then...else...fi`

**Tasks:**
1. Implement `parse_if_statement()`
   - Handle if/then/else/elif/fi
   - Parse condition commands
   - Parse then-part and else-part

2. Handle nested if statements
   - Test: `if true; then if false; then echo A; else echo B; fi; fi`

3. Handle if with loops
   - Test: `if true; then for i in 1; do echo $i; done; fi`

**Success Criteria:**
- Single-line if statements work
- Nested if statements work
- Mixed if/loop nesting works

### Phase 5: Other Compound Commands (Week 6)

**Goal:** Implement while, until, case

**Tasks:**
1. Implement `parse_while_loop()`
2. Implement `parse_until_loop()`
3. Implement `parse_case_statement()`
4. Test all combinations

**Success Criteria:**
- All loop types work
- Case statements work
- All can be nested

### Phase 6: Integration & Cleanup (Week 7)

**Goal:** Make new parser the default

**Tasks:**
1. Run full test suite with new parser
2. Fix any regressions
3. Remove old parser code
4. Update documentation
5. Remove feature flag

**Success Criteria:**
- All 389 tests pass
- No regressions
- Code is clean

---

## Part 4: Testing Strategy

### Test Categories

1. **Unit Tests** (per phase)
   - Lexer tests: `tests/test_lexer.f90`
   - Parser tests: `tests/test_grammar_parser.f90`
   - Test each function in isolation

2. **Integration Tests**
   - Use existing POSIX test suites
   - Run with feature flag: `FORTSH_USE_NEW_PARSER=1`

3. **Regression Tests**
   - Keep old tests running with old parser
   - Ensure new parser matches behavior
   - Document intentional differences

4. **Edge Case Tests**
   - Nested structures (the main goal!)
   - Single-line compound commands
   - Mixed nesting
   - Error conditions

### Test Execution

```bash
# Phase-by-phase testing
make test-lexer           # Phase 1
make test-parser-simple   # Phase 2
make test-parser-for      # Phase 3
make test-parser-if       # Phase 4
make test-parser-full     # Phase 5

# Full regression
make test-new-parser      # All tests with new parser
make test-old-parser      # All tests with old parser
make test-both            # Compare results
```

### Success Metrics

- **No Regressions:** All currently passing tests must still pass
- **New Functionality:** Nested structures must work
- **Performance:** Within 10% of old parser speed
- **Code Quality:** Clean, well-documented, maintainable

---

## Part 5: Risk Management

### Risks & Mitigation

1. **Breaking Existing Functionality**
   - **Mitigation:** Feature flag, parallel implementation
   - **Rollback:** Keep old parser until new one fully validated

2. **Performance Degradation**
   - **Mitigation:** Profile early, optimize hot paths
   - **Acceptable:** Small slowdown for correctness

3. **Complexity Explosion**
   - **Mitigation:** Keep grammar simple, document well
   - **Review:** Regular code reviews

4. **Time Overrun**
   - **Mitigation:** Phased approach allows partial deployment
   - **Pivot:** Can stop after critical phases

### Contingency Plans

- **If Phase 3 fails:** Focus on for loops only, defer if/case
- **If performance bad:** Optimize lexer, consider caching
- **If too complex:** Simplify grammar, accept limitations

---

## Part 6: File Structure

### New Files

```
src/parsing/
  ├── parser.f90              # Existing (keep for now)
  ├── lexer.f90               # NEW - Tokenization
  ├── grammar_parser.f90      # NEW - Grammar-aware parsing
  ├── command_tree.f90        # NEW - Command tree structures
  └── parser_utils.f90        # NEW - Shared utilities

tests/
  ├── test_lexer.f90          # NEW - Lexer unit tests
  ├── test_grammar_parser.f90 # NEW - Parser unit tests
  └── test_nested_commands.sh # NEW - Integration tests
```

### Modified Files

```
src/common/types.f90        # Add token_t, command_node_t
src/fortsh.f90              # Add feature flag logic
src/execution/executor.f90  # Handle new command types
Makefile                    # Add new source files
```

---

## Part 7: Timeline

| Phase | Duration | Description | Deliverable |
|-------|----------|-------------|-------------|
| 0 | 1 week | Infrastructure | Feature flag, parallel testing |
| 1 | 1 week | Lexer | Tokenization works |
| 2 | 1 week | Simple commands | Basic commands work |
| 3 | 1 week | For loops | Nested for loops work |
| 4 | 1 week | If statements | Nested if works |
| 5 | 1 week | Other compounds | while/until/case work |
| 6 | 1 week | Integration | All tests pass, clean up |
| **Total** | **7 weeks** | **Complete rewrite** | **Production-ready** |

### Milestones

- **Week 1:** Compiles, feature flag works
- **Week 3:** Simple commands work with new parser
- **Week 4:** 🎯 **KEY MILESTONE** - Nested for loops work!
- **Week 6:** All compound commands work
- **Week 7:** New parser is default, old parser removed

---

## Part 8: Documentation Requirements

1. **Architecture Document** (this file)
2. **API Documentation** - Document each public function
3. **Grammar Specification** - Formal grammar definition
4. **Migration Guide** - For contributors
5. **Testing Guide** - How to run tests

---

## Part 9: Success Criteria

### Must Have

✅ All 389 current tests pass
✅ Nested for loops work: `for i in 1 2; do for j in a b; do echo $i$j; done; done`
✅ Nested if statements work: `if true; then if false; then echo A; else echo B; fi; fi`
✅ Mixed nesting works: `for i in 1; do if [ $i -eq 1 ]; then echo one; fi; done`
✅ No performance regression > 10%
✅ Code is maintainable and documented

### Nice to Have

- Better error messages with position information
- AST visualization for debugging
- Grammar-based auto-completion
- Support for more POSIX edge cases

---

## Part 10: Next Steps

1. **Review this plan** - Get feedback, adjust timeline
2. **Create Phase 0 branch** - Start infrastructure
3. **Set up CI/CD** - Automated testing
4. **Begin Phase 1** - Lexer implementation
5. **Weekly check-ins** - Track progress, adjust as needed

---

## Appendix A: POSIX Shell Grammar (Simplified)

```
complete_command : list separator_op
                 | list

list             : list separator_op and_or
                 | and_or

and_or           : pipeline
                 | and_or AND_IF pipeline
                 | and_or OR_IF pipeline

pipeline         : pipe_sequence

pipe_sequence    : command
                 | pipe_sequence '|' linebreak command

command          : simple_command
                 | compound_command
                 | compound_command redirect_list

compound_command : brace_group
                 | subshell
                 | for_clause
                 | case_clause
                 | if_clause
                 | while_clause
                 | until_clause

for_clause       : For name linebreak do_group
                 | For name linebreak in wordlist sequential_sep do_group

while_clause     : While compound_list do_group

until_clause     : Until compound_list do_group

if_clause        : If compound_list Then compound_list else_part Fi
                 | If compound_list Then compound_list Fi

case_clause      : Case WORD linebreak in linebreak case_list Esac

do_group         : Do compound_list Done
```

---

## Appendix B: References

- POSIX.1-2017 Shell Command Language: https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html
- Bash Parser Source: https://git.savannah.gnu.org/cgit/bash.git/tree/parse.y
- Dash Parser Source: https://git.kernel.org/pub/scm/utils/dash/dash.git/tree/src/parser.c
- "Parsing Techniques" by Dick Grune and Ceriel J.H. Jacobs

---

**Document Version:** 1.0
**Last Updated:** 2025-11-05
**Author:** Claude Code + Matthew Wolffe
**Status:** 📝 PLANNING
