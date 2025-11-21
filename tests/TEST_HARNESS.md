# Fortsh Test Harness Documentation

## Overview

The fortsh test suite includes comprehensive POSIX compliance tests, memory pool tests, and interactive tests organized into a structured test harness.

## Test Runners

### `run_all_tests.sh` - Comprehensive Test Runner (NEW)

The primary test runner that provides categorized test execution with detailed reporting.

**Usage:**
```bash
./run_all_tests.sh [OPTIONS]
```

**Options:**
- `--posix-only` - Run only POSIX compliance tests (default)
- `--memory-only` - Run only memory pool tests
- `--all` - Run both POSIX and memory pool tests
- `--quick` - Run only fast POSIX tests (skip coverage/untested suites)
- `--verbose` - Show detailed output from each test
- `--stop-on-fail` - Stop running tests after first failure
- `--help` - Show help message

**Examples:**
```bash
# Quick POSIX compliance check (recommended for development, ~30s)
./run_all_tests.sh --quick

# Full POSIX compliance suite (~1-2 minutes)
./run_all_tests.sh --posix-only

# Everything (POSIX + memory pool tests) - SLOW: 5-10 minutes
# WARNING: Memory tests rebuild fortsh from scratch!
./run_all_tests.sh --all

# Verbose mode with stop on first failure
./run_all_tests.sh --verbose --stop-on-fail
```

**Output Features:**
- Color-coded test results
- **Progress indicators** - Shows dots (.) while tests are running so you know it's not hung
- **Duration tracking** - Shows how long each test suite took (if ≥5s)
- **Warnings for slow tests** - Alerts you before running tests that rebuild fortsh
- Individual test counts aggregated across all suites
- Suite-level pass/fail tracking
- Detailed summary with pass rates
- Shows last 20 lines of output on failure (non-verbose mode)

### `run_posix_tests.sh` - POSIX-Only Runner

Simplified runner that executes all 8 POSIX compliance test suites.

**Usage:**
```bash
./run_posix_tests.sh
```

This runner includes all POSIX test suites:
- `posix_compliance_test.sh` - Core POSIX features
- `posix_compliance_extended.sh` - Extended POSIX features
- `posix_compliance_builtins.sh` - Builtin commands
- `posix_compliance_advanced.sh` - Advanced shell features
- `posix_compliance_gaps.sh` - Gap coverage tests
- `posix_compliance_jobcontrol.sh` - Job control features
- `posix_compliance_coverage.sh` - Additional coverage tests
- `posix_compliance_untested.sh` - Previously untested features

## Test Categories

### POSIX Compliance Tests

**Core Tests (Fast):**
- `posix_compliance_test.sh` - Basic POSIX shell features
- `posix_compliance_extended.sh` - Extended command line parsing
- `posix_compliance_builtins.sh` - All builtin commands (52 tests)
- `posix_compliance_advanced.sh` - Advanced features (arithmetic, arrays, etc.)
- `posix_compliance_gaps.sh` - Edge cases and gap coverage (178 tests)
- `posix_compliance_jobcontrol.sh` - Background jobs, fg/bg (33 tests, 7 skipped)

**Extended Tests (Slower):**
- `posix_compliance_coverage.sh` - Comprehensive coverage tests (99 tests)
- `posix_compliance_untested.sh` - Recently added feature tests (45 tests)

### Memory Pool Tests

**⚠️ WARNING:** These tests rebuild fortsh from scratch and are VERY slow (5-10 minutes)!

- `memory_pool_test_bench.sh` - Comprehensive memory pool testing (rebuilds twice)
- `memory_pool_validation.sh` - Memory pool validation (rebuilds)
- `macos_arm64_pool_checks.sh` - macOS ARM64 specific tests (rebuilds)

When you run `--all` or `--memory-only`, you'll get a 5-second warning before these tests start.

### Interactive Tests

These tests require manual interaction and are not run automatically:
- `terminal_integration_tests.sh`
- `terminal_interactive_tests.sh`
- `test_interactive_comprehensive.sh`
- `test_interactive.sh`
- `test_readline_integration.sh`

## Test Results Format

Most test suites output results in this format:

```
==========================================
TEST NAME
==========================================
✓ PASS: test description
✗ FAIL: test description

==========================================
SUMMARY
==========================================
Passed:  X
Failed:  Y
Skipped: Z
Total:   N
==========================================
Pass rate: XX%
```

The test harness parses this output to aggregate statistics across all suites.

## Current Test Status

As of the last run:

**Quick Mode (6 suites):**
- Test Suites: 6/6 passed (100%)
- Individual Tests: 52+ passed

**Full POSIX Mode (8 suites):**
- Test Suites: 6/8 passed (75%)
- Known failures in:
  - `posix_compliance_coverage.sh` - 1 failure out of 99 tests
  - `posix_compliance_untested.sh` - 1 failure out of 45 tests

## Environment Variables

- `FORTSH_BIN` - Path to fortsh binary (auto-detected if not set)
- `VERBOSE` - Set to 1 to enable verbose output in individual test scripts

## Exit Codes

- `0` - All tests passed
- `1` - Some tests failed
- `2` - Invalid arguments (run_all_tests.sh only)

## Development Workflow

**During development:**
```bash
# Quick check after making changes
./run_all_tests.sh --quick

# If quick tests pass, run full suite
./run_all_tests.sh --posix-only
```

**Before committing:**
```bash
# Run full POSIX suite
./run_all_tests.sh --posix-only

# Optionally run memory pool tests if you changed memory-related code
./run_all_tests.sh --all
```

**Debugging failures:**
```bash
# Run with verbose output and stop on first failure
./run_all_tests.sh --verbose --stop-on-fail

# Or run individual test suite directly
./posix_compliance_builtins.sh
```

## Adding New Tests

1. Create a new test script following the naming convention:
   - POSIX: `posix_compliance_*.sh`
   - Memory: `memory_pool_*.sh`
   - Interactive: `test_interactive_*.sh`

2. Ensure your script:
   - Is executable (`chmod +x`)
   - Uses `$FORTSH_BIN` environment variable
   - Outputs summary in the standard format (see above)
   - Exits with 0 on success, non-zero on failure

3. Add the test to appropriate category in `run_all_tests.sh`:
   - `POSIX_CORE_TESTS` for fast POSIX tests
   - `POSIX_SLOW_TESTS` for slower/comprehensive tests
   - `MEMORY_TESTS` for memory pool tests

4. Optionally add to `run_posix_tests.sh` if it's a POSIX compliance test

## Continuous Integration

The test harness is designed for CI integration:

```bash
# In CI pipeline
make clean && make -j8
cd tests
./run_all_tests.sh --quick --stop-on-fail
```

The `--stop-on-fail` flag ensures CI fails fast on first error, saving resources.
