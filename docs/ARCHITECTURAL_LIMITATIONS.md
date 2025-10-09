# Fortsh Architectural Limitations

This document describes the fundamental architectural limitations in fortsh that affect certain features, particularly nested control structures.

## Nested Loop Execution Limitation

### The Problem
Nested loops in fortsh do not execute correctly. Inner loops are captured but executed after the outer loop completes, rather than during each iteration of the outer loop.

### Root Cause
The limitation stems from fortsh's single-pass, line-by-line execution model combined with the command buffering approach used for loop implementation:

1. **Single Control Stack**: Fortsh maintains a single control stack for all control flow structures
2. **Command Buffering**: Loop bodies are captured as strings and replayed for each iteration
3. **Capture Mechanism**: When capturing loop body commands, nested loops are stored as text but not parsed as control structures

### Example
```bash
for x in a b
do
    for y in 1 2
    do
        echo "$x$y"
    done
done
```

**Expected Output:**
```
a1
a2
b1
b2
```

**Actual Output:**
```
a
b
11
12
```

### Why This Can't Be Fixed Without Major Refactoring

After attempting to fix this issue, we discovered the fundamental problem:

#### The Core Issue: String-Based Replay Model
Fortsh captures loop bodies as strings and replays them line-by-line. When we tried to make replay recognize control flow commands:

1. **Replay calls execute_single with control flow checking**
   - When the outer loop replays `for y in 1 2`, it correctly recognizes it as a control flow command
   - This starts a new control block and begins capturing

2. **The Capture/Replay Conflict**
   - The inner loop tries to capture its body from the replay stream
   - But the replay stream is controlled by the outer loop's iteration
   - The inner loop can't "pull" commands from the outer loop's stored strings

3. **No Command Flow Control**
   - There's no mechanism to coordinate which commands go to which loop
   - The outer loop's replay and inner loop's capture operate on different assumptions
   - This creates infinite loops or incorrect execution order

#### What We Tried
1. **Making replay check for control flow** - Led to infinite loops as inner loops tried to capture from outer loop's replay
2. **Processing nested loops during replay** - Too complex due to Fortran's loop variable constraints
3. **Recursive execution contexts** - Would require complete refactoring of the execution model

#### The Fundamental Mismatch
The issue isn't just about recognizing control flow during replay. It's that our entire model assumes:
- Commands come from stdin or a file (linear stream)
- Loop bodies are captured once and replayed multiple times
- There's a single execution context at any time

But nested loops require:
- Commands to come from multiple sources (outer loop's stored body)
- Inner loops to be fully executed during each outer loop iteration
- Multiple simultaneous execution contexts

### Potential Solutions

#### Solution 1: AST-Based Execution
Implement an Abstract Syntax Tree (AST) representation:
- Parse the entire script into a tree structure
- Execute by traversing the tree
- **Impact**: Complete rewrite of parser and executor

#### Solution 2: Recursive Executor
Create a recursive execution model:
- Allow executor to call itself for nested structures
- Maintain separate execution contexts
- **Impact**: Major refactoring of executor and control flow modules

#### Solution 3: Multi-Pass Parser
Implement a multi-pass parsing approach:
- First pass: Identify all control structures
- Second pass: Build execution plan
- Third pass: Execute
- **Impact**: Complete redesign of the parsing pipeline

### Recommendation
Given that fortsh is primarily educational and demonstrates shell implementation concepts, the current limitation is acceptable. The workaround is to avoid deeply nested loops or use functions to achieve similar behavior.

## Other Architectural Considerations

### 1. Memory Management
Fortsh uses static arrays in many places, which limits:
- Maximum command length
- Number of tokens per command
- Pipeline depth
- Number of variables

### 2. Signal Handling
The current signal handling is basic and doesn't fully implement:
- Job control signals in all contexts
- Signal masking during critical sections
- Proper signal inheritance in subprocesses

### 3. Unicode Support
Fortsh assumes ASCII/UTF-8 but doesn't fully handle:
- Multi-byte character boundaries in string operations
- Proper display width calculations for prompts
- Unicode normalization

## Break and Continue Limitations

### The Problem
The `break` and `continue` builtins are implemented but don't work correctly due to loop body capture limitations.

### Root Cause
The loop body capture mechanism has a fundamental flaw:
1. When a loop starts (after `do`), it begins capturing commands
2. However, it only captures ONE command before checking for `done`
3. If `done` isn't found, it executes that single command and continues
4. This means only the first command in the loop body is actually captured and replayed

### Example
```bash
for i in 1 2 3
do
    echo "i=$i"      # This gets captured
    [ "$i" = "2" ] && break  # This doesn't get captured
done
```

The `break` command is never part of the loop body - it's executed after the loop completes, making it ineffective.

### Why This Is Hard to Fix
The capture mechanism would need to:
1. Buffer ALL commands between `do` and `done` before execution
2. Handle multi-line constructs properly
3. Deal with nested control structures
4. Manage stdin/file reading differently

This would require rewriting how fortsh reads and buffers commands, essentially requiring a two-pass parser or a completely different execution model.

## Conclusion
These limitations are inherent to fortsh's design philosophy of being a simple, educational shell implementation. Fixing them would require architectural changes that would significantly increase complexity, potentially obscuring the educational value of the codebase.

For production use cases requiring these features, users should use established shells like bash, zsh, or fish.