# Fortsh AST-Based Architecture Redesign

## Executive Summary
To achieve true POSIX compliance and overcome current architectural limitations, fortsh needs to transition from its current line-by-line execution model to an Abstract Syntax Tree (AST) based approach. This document outlines the redesign strategy.

## Current Architecture Problems

### 1. Line-by-Line Execution
- Commands are parsed and executed immediately
- No ability to see the "whole picture" before execution
- Loop bodies stored as strings and replayed

### 2. Single Execution Context
- One control stack for everything
- No proper scoping for functions
- Can't handle nested structures properly

### 3. String-Based Command Storage
- Loop bodies are strings
- Functions are arrays of strings
- No structured representation of code

## Proposed AST Architecture

### Core Components

#### 1. Lexer (New Module: `src/ast/lexer.f90`)
```fortran
type :: token_t
  integer :: type           ! TOKEN_WORD, TOKEN_PIPE, TOKEN_AND, etc.
  character(:), allocatable :: value
  integer :: line_number
  integer :: column
end type

type :: token_stream_t
  type(token_t), allocatable :: tokens(:)
  integer :: current_pos
end type
```

#### 2. AST Node Types (New Module: `src/ast/ast_types.f90`)
```fortran
type :: ast_node_t
  integer :: node_type
  ! Common fields
  integer :: line_number
  integer :: column
end type

! Specific node types
type, extends(ast_node_t) :: command_node_t
  character(:), allocatable :: command
  type(ast_node_t), allocatable :: arguments(:)
  type(ast_node_t), allocatable :: redirections(:)
end type

type, extends(ast_node_t) :: pipeline_node_t
  type(ast_node_t), allocatable :: commands(:)
end type

type, extends(ast_node_t) :: for_loop_node_t
  character(:), allocatable :: variable
  type(ast_node_t), allocatable :: items(:)
  type(ast_node_t), allocatable :: body(:)
end type

type, extends(ast_node_t) :: if_node_t
  type(ast_node_t), pointer :: condition
  type(ast_node_t), allocatable :: then_branch(:)
  type(ast_node_t), allocatable :: else_branch(:)
end type

type, extends(ast_node_t) :: while_loop_node_t
  type(ast_node_t), pointer :: condition
  type(ast_node_t), allocatable :: body(:)
end type

type, extends(ast_node_t) :: function_def_node_t
  character(:), allocatable :: name
  type(ast_node_t), allocatable :: body(:)
end type

type, extends(ast_node_t) :: break_node_t
  integer :: levels
end type

type, extends(ast_node_t) :: continue_node_t
  integer :: levels
end type
```

#### 3. Parser (New Module: `src/ast/parser.f90`)
```fortran
! Recursive descent parser
module ast_parser
  use ast_types
  use lexer

contains
  function parse_script(tokens) result(ast)
    type(token_stream_t) :: tokens
    type(ast_node_t), allocatable :: ast(:)
    ! Parse top-level commands
  end function

  function parse_command(tokens) result(node)
    ! Parse single command with arguments and redirections
  end function

  function parse_pipeline(tokens) result(node)
    ! Parse command | command | command
  end function

  function parse_for_loop(tokens) result(node)
    ! Parse for var in items; do commands; done
  end function

  function parse_if_statement(tokens) result(node)
    ! Parse if condition; then commands; else commands; fi
  end function
end module
```

#### 4. Evaluator (New Module: `src/ast/evaluator.f90`)
```fortran
module ast_evaluator
  use ast_types
  use shell_types

  type :: execution_context_t
    type(shell_state_t), pointer :: shell
    type(execution_context_t), pointer :: parent => null()
    type(shell_var_t), allocatable :: local_vars(:)
    logical :: break_requested = .false.
    logical :: continue_requested = .false.
    logical :: return_requested = .false.
    integer :: return_value = 0
  end type

contains
  function eval_node(node, context) result(exit_code)
    class(ast_node_t) :: node
    type(execution_context_t) :: context
    integer :: exit_code

    select type(node)
    type is (command_node_t)
      exit_code = eval_command(node, context)
    type is (for_loop_node_t)
      exit_code = eval_for_loop(node, context)
    type is (if_node_t)
      exit_code = eval_if(node, context)
    type is (break_node_t)
      context%break_requested = .true.
      exit_code = 0
    type is (continue_node_t)
      context%continue_requested = .true.
      exit_code = 0
    end select
  end function

  function eval_for_loop(node, context) result(exit_code)
    type(for_loop_node_t) :: node
    type(execution_context_t) :: context
    integer :: exit_code, i

    do i = 1, size(node%items)
      ! Set loop variable
      call set_variable(context, node%variable, eval_word(node%items(i)))

      ! Execute loop body
      do j = 1, size(node%body)
        exit_code = eval_node(node%body(j), context)

        if (context%break_requested) then
          context%break_requested = .false.
          return
        end if

        if (context%continue_requested) then
          context%continue_requested = .false.
          exit  ! Continue to next iteration
        end if
      end do
    end do
  end function
end module
```

## Migration Strategy

### Phase 1: Parallel Implementation
1. Keep existing execution path intact
2. Build AST modules alongside
3. Add a `--ast-mode` flag to fortsh for testing

### Phase 2: Feature Parity
1. Implement basic command execution via AST
2. Add control flow structures
3. Implement redirections and pipelines
4. Add variable expansion

### Phase 3: Advanced Features
1. Proper nested loops
2. Working break/continue
3. Function scoping
4. Command substitution via AST

### Phase 4: Cutover
1. Make AST mode the default
2. Keep legacy mode with `--legacy` flag
3. Eventually remove legacy code

## Benefits of AST Approach

### 1. Proper Nested Structures
- Loops can contain loops naturally
- Functions have proper scope
- Break/continue work at any depth

### 2. Better Error Handling
- Syntax errors caught before execution
- Line numbers in error messages
- Can validate entire script upfront

### 3. Optimization Opportunities
- Can analyze code before execution
- Constant folding
- Dead code elimination
- Command caching

### 4. Debugging Support
- Can implement proper `set -x` tracing
- Step-through debugging possible
- Breakpoints could be added

### 5. POSIX Compliance
- All POSIX shell constructs can be properly represented
- Proper variable scoping
- Correct expansion order

## Implementation Priorities

### Immediate (Week 1-2)
1. Design and implement token types
2. Create basic lexer for tokenization
3. Implement simple AST node types
4. Create proof-of-concept parser for basic commands

### Short Term (Week 3-4)
1. Implement evaluator for basic commands
2. Add pipeline support
3. Implement variable expansion in AST
4. Add if/then/else support

### Medium Term (Week 5-6)
1. Implement for loops properly
2. Add while loops
3. Implement break/continue
4. Add function definitions

### Long Term (Week 7-8)
1. Full POSIX compliance testing
2. Performance optimization
3. Migration of all features
4. Deprecate legacy mode

## Technical Considerations

### Memory Management
- Use Fortran's allocatable arrays for dynamic structures
- Implement proper cleanup for AST nodes
- Consider memory pooling for performance

### Error Recovery
- Parser should recover from errors gracefully
- Provide meaningful error messages
- Support partial execution where safe

### Testing Strategy
- Unit tests for each AST node type
- Integration tests for complex scripts
- POSIX compliance test suite
- Performance benchmarks

## Example: How Nested Loops Would Work

### Input Script
```bash
for i in 1 2 3; do
  echo "Outer: $i"
  for j in a b c; do
    echo "  Inner: $j"
    [ "$j" = "b" ] && break
  done
  echo "Back in outer"
done
```

### AST Representation
```
ForLoopNode {
  variable: "i"
  items: ["1", "2", "3"]
  body: [
    CommandNode { command: "echo", args: ["Outer: $i"] }
    ForLoopNode {
      variable: "j"
      items: ["a", "b", "c"]
      body: [
        CommandNode { command: "echo", args: ["  Inner: $j"] }
        IfNode {
          condition: TestNode { expr: "$j = b" }
          then_branch: [ BreakNode { levels: 1 } ]
        }
      ]
    }
    CommandNode { command: "echo", args: ["Back in outer"] }
  ]
}
```

### Execution
1. Outer loop sets i=1
2. Executes echo "Outer: 1"
3. Inner loop sets j=a
4. Executes echo "  Inner: a"
5. Test fails, continues
6. Inner loop sets j=b
7. Executes echo "  Inner: b"
8. Test succeeds, break is executed
9. Inner loop exits
10. Executes echo "Back in outer"
11. Outer loop continues with i=2...

## Conclusion

Moving to an AST-based architecture is a significant undertaking but will result in a truly POSIX-compliant, maintainable, and extensible shell. The phased approach allows for gradual migration while maintaining stability.