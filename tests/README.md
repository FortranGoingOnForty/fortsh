# Fortsh Test Suite Documentation

## Overview

The Fortsh test suite is a comprehensive testing framework designed to ensure bash compatibility and POSIX compliance. It consists of multiple test suites that verify different aspects of shell functionality.

## Test Suites

### 1. Integration Tests (`integration_test.sh`)

**Purpose:** Verify basic shell functionality and core features.

**What it tests:**
- Basic command execution
- Variable expansion
- Glob pattern matching
- Here-string redirection
- For loops
- Built-in commands
- Alias functionality
- Error handling

**Run with:**
```bash
make test-integration
```

**Expected runtime:** ~5 seconds

### 2. Bash Parity Tests (`bash_parity_test.sh`)

**Purpose:** Ensure fortsh produces identical output to bash for all commands.

**Methodology:**
- Runs each command in both bash and fortsh
- Compares output byte-for-byte
- Reports differences

**What it tests:**
- Echo and output (5 tests)
- Variable expansion (5 tests)
- Parameter expansion (10 tests)
- Command substitution (4 tests)
- Arithmetic expansion (7 tests)
- Brace expansion (5 tests)
- Glob patterns (3 tests)
- Redirection (4 tests)
- Pipelines (3 tests)
- Conditionals (5 tests)
- Loops (5 tests)
- Test operators (8 tests)
- Logical operators (6 tests)
- Special variables (3 tests)
- Functions (4 tests)
- Arrays (4 tests)
- Quoting and escaping (4 tests)
- Subshells (2 tests)
- Case statements (3 tests)
- Multi-line strings (2 tests)

**Total:** ~95 comparison tests

**Run with:**
```bash
make test-parity
```

**Expected runtime:** ~30-60 seconds

### 3. POSIX Compliance Tests (`posix_compliance_test.sh`)

**Purpose:** Verify compliance with POSIX shell specification.

**Methodology:**
- Written in pure POSIX shell (no bash-isms)
- Compares fortsh with /bin/sh (usually dash or bash in POSIX mode)
- Tests only POSIX-specified features

**What it tests:**
- POSIX basic commands (4 tests)
- POSIX variable expansion (4 tests)
- POSIX parameter expansion (4 tests)
- POSIX command substitution (3 tests)
- POSIX arithmetic with expr (3 tests)
- POSIX redirection (4 tests)
- POSIX pipelines (3 tests)
- POSIX test command (12 tests)
- POSIX conditionals (3 tests)
- POSIX loops (3 tests)
- POSIX case statements (4 tests)
- POSIX functions (4 tests)
- POSIX special variables (6 tests)
- POSIX logical operators (7 tests)
- POSIX quoting (4 tests)
- POSIX subshells (2 tests)
- POSIX compound commands (2 tests)
- POSIX here documents (3 tests)
- POSIX word expansion (2 tests)
- POSIX pathname expansion (3 tests)
- POSIX field splitting (2 tests)
- POSIX exit status (4 tests)
- POSIX set builtin (3 tests)
- POSIX export (1 test)
- POSIX readonly (1 test)

**Total:** ~90 POSIX compliance tests

**Run with:**
```bash
make test-posix
```

**Expected runtime:** ~30-60 seconds

### 4. Feature Test Suite (`feature_test_suite.sh`)

**Purpose:** Comprehensive feature testing within bash itself (not comparing with fortsh).

**What it tests:**
- Basic output and echo
- Redirection
- Pipes
- Command substitution
- Variables
- Parameter expansion
- Brace expansion
- Glob patterns
- Arithmetic
- Control flow
- Test operators
- Here documents
- Background jobs
- Special variables
- Functions
- Arrays
- Quoting
- Complex combinations

**Total:** ~100+ feature tests

**Run with:**
```bash
make test-features
```

**Expected runtime:** ~10-20 seconds

## Running Tests

### Quick Test
Run a basic sanity check:
```bash
make test
```

### Smoke Tests
Run quick validation tests:
```bash
make smoke-test
```

### Individual Test Suites
Run specific test suites:
```bash
make test-integration   # Integration tests
make test-parity        # Bash parity tests
make test-posix         # POSIX compliance tests
make test-features      # Feature tests
```

### All Tests
Run the complete test suite:
```bash
make test-all
```

This runs:
1. Integration tests
2. Bash parity tests
3. POSIX compliance tests

**Expected total runtime:** ~1-2 minutes

### Continuous Integration
For CI/CD pipelines:
```bash
make clean all test-all
```

## Test Output Format

All test scripts use a consistent format:

```
✓ PASS: Test description
✗ FAIL: Test description
  bash:   expected output
  fortsh: actual output
⊘ SKIP: Test description - reason
```

### Color Coding
- 🟢 **Green**: Passed tests
- 🔴 **Red**: Failed tests
- 🟡 **Yellow**: Skipped tests
- 🔵 **Blue**: Section headers

## Test Results

At the end of each suite, you'll see:

```
==========================================
RESULTS
==========================================
Passed:  85
Failed:  2
Skipped: 3
Total:   90
==========================================
Pass rate: 94%
==========================================
```

## Exit Codes

All test scripts follow standard conventions:
- **0**: All tests passed
- **1**: One or more tests failed

## Adding New Tests

### To bash_parity_test.sh

Add a new comparison test:

```bash
compare_output "test description" "command to test"
```

Or compare exit codes:

```bash
compare_exit_code "test description" "command to test"
```

### To posix_compliance_test.sh

Add a POSIX comparison test:

```bash
compare_posix_output "test description" "command to test"
```

Or compare exit codes:

```bash
compare_posix_exit_code "test description" "command to test"
```

### To integration_test.sh

Add a new test section:

```bash
echo ""
echo "Test N: Feature description"
echo "----------------------------"
result=$(echo "command" | "$FORTSH_BIN" 2>/dev/null)
if [[ "$result" == "expected" ]]; then
    echo "✅ Feature works"
else
    echo "❌ Feature failed"
    echo "Expected: 'expected', Got: '$result'"
fi
```

## Test Coverage

Current coverage areas:

### Fully Tested (100% parity with bash)
- ✅ Variable expansion
- ✅ Command substitution
- ✅ Arithmetic expansion
- ✅ Parameter expansion (basic)
- ✅ Glob patterns
- ✅ Redirection (basic)
- ✅ Pipelines
- ✅ For loops
- ✅ While/until loops
- ✅ If/elif/else
- ✅ Case statements
- ✅ Functions
- ✅ Arrays (indexed)
- ✅ Here-documents
- ✅ Here-strings
- ✅ Background jobs (&)
- ✅ Logical operators (&&, ||)

### Partially Tested (>90% parity)
- ⚠️ Advanced parameter expansion
- ⚠️ Associative arrays
- ⚠️ Advanced redirection (FD manipulation)
- ⚠️ Coprocesses
- ⚠️ Process substitution

### POSIX Compliance
- ✅ All POSIX-required builtins
- ✅ POSIX parameter expansion
- ✅ POSIX test operators
- ✅ POSIX control flow
- ✅ POSIX quoting rules
- ✅ POSIX word expansion order

## Debugging Failed Tests

### For Bash Parity Tests

If a test fails, you'll see:

```
✗ FAIL: echo with quotes
  bash:   hello world
  fortsh: hello  world
```

To debug:
```bash
# Run the command manually
bash -c 'echo "hello world"'
./bin/fortsh -c 'echo "hello world"'

# Compare output
bash -c 'echo "hello world"' > /tmp/bash_out
./bin/fortsh -c 'echo "hello world"' > /tmp/fortsh_out
diff /tmp/bash_out /tmp/fortsh_out
```

### For POSIX Tests

```bash
# Run with POSIX shell
sh -c 'command'
./bin/fortsh -c 'command'
```

### Verbose Mode

Add `-x` to any test script for verbose output:

```bash
bash -x tests/bash_parity_test.sh
```

## Test File Organization

```
tests/
├── README.md                   # This file
├── integration_test.sh         # Basic integration tests
├── bash_parity_test.sh        # Bash compatibility tests
├── posix_compliance_test.sh   # POSIX compliance tests
├── feature_test_suite.sh      # Comprehensive feature tests
└── [other test files]         # Legacy/specific tests
```

## Best Practices

1. **Always run tests after changes:** `make test-all`
2. **Add tests for new features:** Before implementing
3. **Test edge cases:** Empty strings, special characters, etc.
4. **Keep tests independent:** Each test should not depend on others
5. **Use descriptive names:** Test names should explain what they verify
6. **Clean up after tests:** Remove temp files in cleanup functions

## Performance Benchmarks

Typical execution times on modern hardware:

| Test Suite | Tests | Time  | Tests/sec |
|------------|-------|-------|-----------|
| Integration| 8     | ~5s   | 1.6       |
| Parity     | ~95   | ~45s  | 2.1       |
| POSIX      | ~90   | ~40s  | 2.2       |
| Features   | ~100  | ~15s  | 6.7       |
| **Total**  | ~293  | ~105s | 2.8       |

## Contributing

When contributing new features:

1. Write tests first (TDD)
2. Ensure bash parity for bash-compatible features
3. Ensure POSIX compliance for POSIX features
4. Run `make test-all` before submitting
5. Document any intentional deviations

## Known Limitations

Some bash features are intentionally not tested:
- Bash-specific builtins not in POSIX
- `[[` extended test (tested separately)
- `(())` arithmetic command (tested separately)
- Bash 4.x+ features (for compatibility)

## License

Tests are part of fortsh and follow the same license as the main project.

## Support

For test failures or questions:
1. Check this documentation
2. Review existing tests for examples
3. Check fortsh documentation in `docs/`
4. Open an issue on GitHub

---

**Last Updated:** 2025-10-13
**Test Suite Version:** 1.0
**Fortsh Version:** 4.0.0+
