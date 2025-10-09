# FortSH AST Migration Task List

## Overview
This document outlines the tasks required to migrate FortSH from its current string-based execution model to a proper AST-based architecture that enables POSIX-compliant shell features.

## Current Status
- ✅ AST type definitions created (`src/ast/ast_types.f90`)
- ✅ Lexer implementation complete (`src/ast/lexer.f90`)
- ✅ Parser skeleton compiles (`src/ast/parser.f90`)
- ⚠️ Parser requires polymorphic array handling fix
- 🔲 Evaluator implementation pending
- 🔲 Integration with main shell pending

## Phase 1: Core AST Infrastructure ✅
- [x] Define AST node types for all shell constructs
- [x] Implement lexer for tokenization
- [x] Create parser skeleton that compiles
- [ ] Fix polymorphic array handling in parser
- [ ] Implement proper node collection in parser
- [ ] Add comprehensive parser tests

## Phase 2: Parser Completion
- [ ] **Polymorphic Array Solution**
  - [ ] Research and implement proper polymorphic assignment pattern
  - [ ] Consider alternative: wrapper types for array elements
  - [ ] Consider alternative: linked list structure
  - [ ] Consider alternative: pointer arrays
- [ ] **Statement Parsing**
  - [ ] Simple commands with arguments
  - [ ] Command pipelines
  - [ ] AND/OR lists (&&, ||)
  - [ ] Command lists (;)
- [ ] **Control Flow Parsing**
  - [ ] For loops (word list)
  - [ ] For loops (arithmetic)
  - [ ] While loops
  - [ ] Until loops
  - [ ] If/then/else/elif/fi
  - [ ] Case statements
  - [ ] Break/continue with levels
- [ ] **Advanced Features**
  - [ ] I/O redirections
  - [ ] Command substitution $(...)
  - [ ] Arithmetic expressions $((...))
  - [ ] Variable assignments
  - [ ] Function definitions
  - [ ] Subshells

## Phase 3: Evaluator Implementation
- [ ] **Execution Context**
  - [ ] Variable scope management
  - [ ] Function scope
  - [ ] Subshell isolation
  - [ ] Loop nesting tracking
- [ ] **Command Execution**
  - [ ] External command execution
  - [ ] Built-in command dispatch
  - [ ] Pipeline creation
  - [ ] Process management
- [ ] **Control Flow Execution**
  - [ ] Loop iteration with proper scoping
  - [ ] Break/continue with multi-level support
  - [ ] Conditional evaluation
  - [ ] Pattern matching for case statements
- [ ] **Variable Expansion**
  - [ ] Simple variable expansion
  - [ ] Parameter expansion (${var:-default}, etc.)
  - [ ] Command substitution
  - [ ] Arithmetic expansion
  - [ ] Tilde expansion
  - [ ] Glob expansion

## Phase 4: Integration Bridge
- [ ] **Dual-Mode Support**
  - [ ] Add --ast-mode flag to fortsh
  - [ ] Create mode detection logic
  - [ ] Implement mode switching
- [ ] **Gradual Migration**
  - [ ] AST evaluator calls legacy built-ins
  - [ ] Legacy expansion module integration
  - [ ] Shared variable storage
  - [ ] Shared history management
- [ ] **Compatibility Layer**
  - [ ] Map legacy command structures to AST
  - [ ] Convert AST results back to legacy format
  - [ ] Maintain backward compatibility

## Phase 5: Feature Migration
- [ ] **Built-in Commands**
  - [ ] Migrate echo to AST-based
  - [ ] Migrate cd to AST-based
  - [ ] Migrate export/set to AST-based
  - [ ] Migrate source to AST-based
  - [ ] Migrate remaining built-ins
- [ ] **Shell Features**
  - [ ] Job control with AST
  - [ ] Signal handling with AST
  - [ ] Alias expansion with AST
  - [ ] History expansion with AST

## Phase 6: Testing & Validation
- [ ] **Parser Tests**
  - [ ] Unit tests for each node type
  - [ ] Complex nested structure tests
  - [ ] Error handling tests
  - [ ] Edge case tests
- [ ] **Evaluator Tests**
  - [ ] Execution correctness tests
  - [ ] Variable scoping tests
  - [ ] Control flow tests
  - [ ] Signal handling tests
- [ ] **Integration Tests**
  - [ ] POSIX compliance test suite
  - [ ] Performance benchmarks
  - [ ] Memory leak detection
  - [ ] Stress tests

## Phase 7: Performance Optimization
- [ ] **Parser Optimization**
  - [ ] Minimize allocations
  - [ ] Optimize tokenization
  - [ ] Cache parsed structures
- [ ] **Evaluator Optimization**
  - [ ] Optimize variable lookup
  - [ ] Minimize process creation
  - [ ] Optimize pipeline setup
- [ ] **Memory Management**
  - [ ] Implement AST node pooling
  - [ ] Optimize string handling
  - [ ] Reduce memory fragmentation

## Phase 8: Documentation & Cleanup
- [ ] **Code Documentation**
  - [ ] Document AST node structures
  - [ ] Document parser algorithm
  - [ ] Document evaluator design
  - [ ] Add inline code comments
- [ ] **User Documentation**
  - [ ] Update README with AST info
  - [ ] Document new features
  - [ ] Migration guide for users
- [ ] **Code Cleanup**
  - [ ] Remove legacy code paths
  - [ ] Consolidate duplicate logic
  - [ ] Final code review

## Known Challenges

### 1. Polymorphic Arrays in Fortran
- **Problem**: Fortran doesn't allow direct assignment to polymorphic array elements
- **Impact**: Cannot easily build arrays of mixed AST node types
- **Potential Solutions**:
  - Use wrapper types with defined assignment
  - Use pointer arrays instead of allocatable
  - Use linked list structure
  - Use separate arrays for each node type

### 2. Recursive Structures
- **Problem**: Fortran has limited support for recursive data structures
- **Impact**: Difficult to represent nested AST nodes naturally
- **Current Solution**: Using allocatable components

### 3. Dynamic Memory Management
- **Problem**: Fortran's memory management is more restrictive than C
- **Impact**: Complex allocation patterns for building AST
- **Mitigation**: Careful design of allocation/deallocation patterns

## Success Metrics
- [ ] All POSIX shell tests pass
- [ ] Performance within 20% of bash for common operations
- [ ] Memory usage comparable to other shells
- [ ] Zero memory leaks in valgrind
- [ ] Clean compilation with all warning flags enabled
- [ ] 90%+ test coverage

## Timeline Estimate
- Phase 1-2: 2-3 weeks (Parser completion)
- Phase 3: 2-3 weeks (Evaluator implementation)
- Phase 4-5: 2 weeks (Integration)
- Phase 6: 1-2 weeks (Testing)
- Phase 7-8: 1 week (Optimization & cleanup)

**Total estimate: 8-11 weeks for full migration**

## Next Immediate Steps
1. Research and implement solution for polymorphic array handling
2. Complete parser node collection for basic commands
3. Write parser tests for simple command parsing
4. Begin evaluator implementation for simple commands
5. Create integration test harness