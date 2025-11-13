# Advanced POSIX Compliance Test Failures

## Summary
- **Total Tests**: 117
- **Passed**: 78 (66%)
- **Failed**: 39 (34%)

## Categorized Failures

### 1. File Descriptor Operations (4 failures)
- `exec with redirect` - exec builtin with file redirection
- `exec without command` - exec builtin without command (should replace shell)
- `dup stdout to fd3` - Duplicating stdout to fd 3 (`3>&1`)
- `dup stdin from fd` - Duplicating stdin from another fd

### 2. Signal Handling/Traps (5 failures)
- `trap INT signal` - Handle SIGINT trap
- `trap TERM signal` - Handle SIGTERM trap
- `trap HUP signal` - Handle SIGHUP trap
- `trap with number` - Trap using signal number instead of name
- `trap not inherited` - Traps should not be inherited by subshells

### 3. Parameter Expansion (3 failures)
- `length of positional params` - `${#@}` to get count of positional parameters
- `length of <param>` - Parameter length operator `${#var}`
- `length of <param>` - (duplicate entry, likely different test case)

### 4. Process Management (1 failure)
- `wait nonexistent PID` - wait command with non-existent process ID

### 5. IFS Handling (2 failures)
- `empty IFS` - Behavior when IFS is empty string
- `IFS leading delimiters` - Handling of leading delimiters in IFS splitting

### 6. Arithmetic Operations (6 failures)
- `bitwise NOT` - Bitwise NOT operator `~`
- `left shift` - Left shift operator `<<`
- `right shift` - Right shift operator `>>`
- `ternary true` - Ternary conditional operator `? :`
- `ternary false` - Ternary conditional with false condition
- `ternary nested` - Nested ternary operators

### 7. Directory Operations (2 failures)
- `CDPATH usage` - Using CDPATH environment variable
- `cd - uses OLDPWD` - `cd -` should use OLDPWD

### 8. Pattern Matching (5 failures)
- `bracket char class` - Character class in bracket expressions `[[:class:]]`
- `star no dotfiles` - `*` should not match dotfiles
- `for with glob` - for loop with glob pattern expansion
- `case question mark` - `?` pattern in case statement
- `case bracket` - Bracket expression in case pattern

### 9. Functions (1 failure)
- `function recursion` - Recursive function calls

### 10. Redirections (2 failures)
- `multiple redirects` - Multiple redirections on same command
- `redirect compound cmd` - Redirecting compound commands

### 11. Error Handling (2 failures)
- `division by zero` - Arithmetic division by zero error
- `expansion error` - Error in parameter expansion

### 12. Aliases (2 failures)
- `alias definition` - Defining command aliases
- `unalias removes` - unalias command functionality

### 13. Parsing Edge Cases (4 failures)
- `multiple semicolons` - Handling multiple consecutive semicolons
- `semicolon at start` - Semicolon at beginning of command
- `comment alone` - Standalone comment line
- `adjacent quotes` - Adjacent quoted strings

## Priority for Implementation

### High Priority (Core Functionality)
1. **File Descriptor Operations** - Critical for shell scripting
2. **Signal Handling/Traps** - Important for robust scripts
3. **Parameter Expansion** - Frequently used features

### Medium Priority (Important Features)
4. **IFS Handling** - Important for word splitting
5. **Pattern Matching** - Common in scripts
6. **Directory Operations** - CDPATH and cd -
7. **Arithmetic Operations** - Advanced math operators

### Lower Priority (Nice to Have)
8. **Functions** - Recursion edge case
9. **Aliases** - Interactive feature
10. **Parsing Edge Cases** - Corner cases
11. **Error Handling** - Specific error conditions
12. **Process Management** - Edge case
13. **Redirections** - Complex cases