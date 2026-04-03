#!/usr/bin/env python3
"""
Interactive test runner for fortsh.

Runs both YAML-based test specifications and pytest test files.
"""

import sys
import os
import argparse
import time
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Tuple, Optional

import gc
import re
import yaml
import pexpect
from colorama import init, Fore, Style

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))

from fortsh_pty import FortshPTY, FortshTestSession
from utils.keys import KEYS, get_key
from utils.matchers import (
    OutputMatcher, match_exact, match_contains, match_regex,
    MatchResult
)

# Initialize colorama for cross-platform colors (strip=False to avoid OSC issues on macOS)
init(strip=False, convert=False)


def strip_control_sequences(text: str) -> str:
    """Remove ANSI and OSC control sequences from text."""
    # Remove OSC sequences (like terminal title)
    text = re.sub(r'\x1b\].*?(?:\x07|\x1b\\)', '', text)
    # Remove CSI sequences
    text = re.sub(r'\x1b\[[\x30-\x3f]*[\x20-\x2f]*[\x40-\x7e]', '', text)
    # Remove other escape sequences
    text = re.sub(r'\x1b[^\[\]].?', '', text)
    return text


class TestResult:
    """Result of a single test."""

    def __init__(self, name: str, passed: bool, error: str = "", duration: float = 0.0):
        self.name = name
        self.passed = passed
        self.error = error
        self.duration = duration
        self.test_id = ""  # e.g., "[history] 5"


class YAMLTestRunner:
    """
    Runs tests defined in YAML specification files.

    Uses session reuse to avoid PTY exhaustion - reuses the same
    fortsh session across multiple tests, resetting state between them.
    """

    def __init__(self, fortsh_path: str, verbose: bool = False, tests_per_session: int = 10):
        self.fortsh_path = fortsh_path
        self.verbose = verbose
        self.results: List[TestResult] = []

        # Scale timeouts for slower platforms (ARM64, macOS with flang-new)
        import platform
        machine = platform.machine().lower()
        system = platform.system().lower()
        if machine in ('arm64', 'aarch64'):
            self.pty_timeout = 10.0   # 2x default for ARM64
            self.delay_scale = 1.0
        else:
            self.pty_timeout = 5.0
            self.delay_scale = 1.0
        # macOS: fewer tests per session to reduce state accumulation issues
        # with flang-new I/O buffering and readline mode interactions
        if tests_per_session != 10:
            # Explicit override from caller
            self.tests_per_session = tests_per_session
        elif system == 'darwin':
            # Fresh session per test on macOS: readline cursor tracking
            # gets out of sync across reused sessions with flang-new
            self.tests_per_session = 1
        else:
            self.tests_per_session = tests_per_session
        self._current_session: Optional[FortshPTY] = None
        self._test_count = 0
        self._step_sync_id = 0
        self._use_marker_sync = (system == 'darwin')

    def _get_session(self, env: dict = None, rc_file: str = "/dev/null", fresh: bool = False) -> FortshPTY:
        """
        Get a fortsh session, reusing existing one if possible.

        Args:
            env: Environment variables for the session
            rc_file: RC file path
            fresh: If True, always create a new session

        Returns:
            FortshPTY session
        """
        needs_new = (
            fresh or
            self._current_session is None or
            not self._current_session.is_running or
            self._test_count % self.tests_per_session == 0
        )

        if needs_new:
            if self._current_session is not None:
                try:
                    self._current_session.stop()
                except:
                    pass
                gc.collect()
                time.sleep(0.2 * self.delay_scale)

            self._current_session = FortshPTY(
                fortsh_path=self.fortsh_path,
                timeout=self.pty_timeout,
                env=env or {}
            )
            self._current_session.start(rc_file=rc_file)
        else:
            # Reset session state for reuse
            self._reset_session()

        return self._current_session

    def _reset_session(self) -> None:
        """Reset session state between tests."""
        if self._current_session is None or not self._current_session.is_running:
            return

        try:
            # Exit any special mode the shell might be in:
            # - Ctrl+G cancels search mode (Ctrl+R/Ctrl+S)
            # - Escape exits vi insert→command, or is harmless in emacs mode
            # - Ctrl+C interrupts running commands and clears line
            # - Ctrl+U kills the line
            self._current_session.send_key("C-g")
            time.sleep(0.05)
            self._current_session.send(chr(27))  # Escape
            time.sleep(0.05)
            self._current_session.send_key("C-c")
            time.sleep(0.1)
            self._current_session.send_key("C-c")
            time.sleep(0.1)
            self._current_session.send_key("C-u")
            time.sleep(0.1)

            # Clear buffer before reset command
            self._current_session.clear_buffer()
            time.sleep(0.05)

            # Reset PS1 and editing mode, then echo marker
            marker = f"RESET_{self._test_count}"
            self._current_session.send_line(f"set -o emacs; PS1='> '; echo {marker}")

            # Wait for the marker to ensure we're at a clean state
            try:
                self._current_session.expect(marker, timeout=self.pty_timeout)
            except:
                pass

            # Wait for prompt after marker and clear buffer again
            time.sleep(0.3)
            self._current_session.clear_buffer()
            time.sleep(0.05)
        except:
            pass

    def _cleanup_session(self) -> None:
        """Clean up the current session."""
        if self._current_session is not None:
            try:
                self._current_session.stop()
            except:
                pass
            self._current_session = None
            gc.collect()

    def run_spec_file(self, spec_path: Path) -> List[TestResult]:
        """
        Run all tests in a YAML spec file.

        Args:
            spec_path: Path to the YAML specification file

        Returns:
            List of TestResult objects
        """
        with open(spec_path) as f:
            spec = yaml.safe_load(f)

        category = spec.get('metadata', {}).get('category', spec_path.stem)
        # Use filename stem as prefix: history.yaml -> [history]
        file_prefix = f"[{spec_path.stem}]"
        print(f"\n{Fore.CYAN}=== {category} ==={Style.RESET_ALL}")

        results = []
        test_num = 0
        for test in spec.get('tests', []):
            test_num += 1
            result = self.run_test(test)
            # Store test ID for failed test summary
            result.test_id = f"{file_prefix} {test_num}"
            results.append(result)
            self._test_count += 1

            # Delay between tests for OS cleanup
            time.sleep(0.3 * self.delay_scale)

            if result.passed:
                print(f"  {Fore.GREEN}✓{Style.RESET_ALL} {file_prefix} {test_num}: {result.name}", flush=True)
            else:
                error_msg = strip_control_sequences(result.error)
                print(f"  {Fore.RED}✗{Style.RESET_ALL} {file_prefix} {test_num}: {result.name}: {error_msg}", flush=True)

        # Clean up session at end of spec file
        self._cleanup_session()
        # Reset test count for fresh session at start of next category
        self._test_count = 0

        return results

    def run_test(self, test: Dict[str, Any]) -> TestResult:
        """
        Run a single test from a spec.

        Args:
            test: Test specification dictionary

        Returns:
            TestResult
        """
        name = test.get('name', 'Unnamed test')
        start_time = time.time()

        # Set up environment
        env = test.get('env', {})
        rc_file = test.get('rc_file', '/dev/null')
        fresh_session = test.get('fresh_session', False)

        try:
            # Get session (may be reused or fresh)
            fortsh = self._get_session(env=env, rc_file=rc_file, fresh=fresh_session)

            try:
                # Execute test steps
                steps = test.get('steps', [])
                for i, step in enumerate(steps):
                    is_last = (i == len(steps) - 1)
                    next_step = steps[i + 1] if not is_last else None
                    self._execute_step(fortsh, step, is_last=is_last, next_step=next_step)

                # Get command output
                if 'expect_output' in test:
                    expected = test['expect_output']
                    # Wait for the expected output to appear
                    try:
                        fortsh.expect(expected)
                        # Test passed - we found the expected output
                        duration = time.time() - start_time
                        return TestResult(name, True, "", duration)
                    except pexpect.TIMEOUT:
                        duration = time.time() - start_time
                        # Get cleaned output for error reporting
                        raw_output = fortsh.get_clean_output()
                        output = strip_control_sequences(raw_output)
                        # Truncate for readability
                        if len(output) > 300:
                            output = output[:300] + "..."
                        return TestResult(
                            name, False,
                            f"Expected '{expected}' not found. Got: '{output}'",
                            duration
                        )
                    except Exception as e:
                        duration = time.time() - start_time
                        return TestResult(
                            name, False,
                            f"Error: {str(e)}",
                            duration
                        )
                elif 'expect_not' in test:
                    # Wait for prompt, then check output doesn't contain unwanted
                    output = fortsh.wait_for_prompt()
                    output = strip_control_sequences(output)
                    unwanted = test['expect_not']
                    if unwanted in output:
                        duration = time.time() - start_time
                        return TestResult(
                            name, False,
                            f"Found unwanted output: '{unwanted}'",
                            duration
                        )
                    duration = time.time() - start_time
                    return TestResult(name, True, "", duration)
                else:
                    # No expectation, just run the steps
                    duration = time.time() - start_time
                    return TestResult(name, True, "", duration)

            finally:
                # Don't stop session - it will be reused or cleaned up later
                pass

        except pexpect.TIMEOUT as e:
            duration = time.time() - start_time
            return TestResult(name, False, f"Timeout: {e}", duration)
        except pexpect.EOF as e:
            duration = time.time() - start_time
            return TestResult(name, False, f"Unexpected EOF: {e}", duration)
        except Exception as e:
            duration = time.time() - start_time
            return TestResult(name, False, str(e), duration)

    def _execute_step(self, fortsh: FortshPTY, step: Dict[str, Any], is_last: bool = False,
                       next_step: Optional[Dict[str, Any]] = None) -> None:
        """Execute a single test step."""
        ds = self.delay_scale
        if 'send' in step:
            fortsh.send(step['send'])
            time.sleep(0.02 * ds)
        elif 'send_line' in step:
            # Use marker sync only on macOS AND only when the next step is
            # also a send_line. If next step is send_key/send/wait, the
            # command may be long-running or interactive — the marker echo
            # would queue behind it and interfere.
            next_is_send_line = next_step is not None and 'send_line' in next_step
            if not is_last and self._use_marker_sync and next_is_send_line:
                self._step_sync_id += 1
                marker = f"__STEP_SYNC_{self._step_sync_id}__"
                fortsh.send_line(step['send_line'])
                fortsh.send_line(f"echo {marker}")
                try:
                    fortsh.expect(marker, timeout=self.pty_timeout)
                except pexpect.TIMEOUT:
                    pass
                time.sleep(0.1 * ds)
                fortsh.clear_buffer()
            else:
                fortsh.send_line(step['send_line'])
                if self._use_marker_sync and not is_last:
                    # Check if the command is long-running (next step is 'wait')
                    next_is_wait = (next_step is not None and 'wait' in next_step)
                    if not next_is_wait:
                        # Quick command (e.g. set -o vi) — wait for prompt
                        try:
                            fortsh.wait_for_prompt(timeout=self.pty_timeout)
                        except pexpect.TIMEOUT:
                            pass
                    else:
                        # Long-running command — use fixed delay, test manages timing
                        time.sleep(0.05 * ds)
                else:
                    time.sleep(0.05 * ds)
        elif 'send_key' in step:
            fortsh.send_key(step['send_key'])
            time.sleep(0.02 * ds)
        elif 'send_keys' in step:
            for key in step['send_keys']:
                fortsh.send_key(key)
                time.sleep(0.02 * ds)
        elif 'wait' in step:
            time.sleep(step['wait'] * ds)
        elif 'wait_for_prompt' in step:
            fortsh.wait_for_prompt()
        elif 'expect' in step:
            fortsh.expect(step['expect'])
        elif 'resize' in step:
            rows = step['resize'].get('rows', 24)
            cols = step['resize'].get('cols', 80)
            fortsh.set_terminal_size(rows, cols)


def find_fortsh_binary() -> str:
    """Find the fortsh binary."""
    # Check common locations
    candidates = [
        "./bin/fortsh",
        "../bin/fortsh",
        "../../bin/fortsh",
        "../fortsh/bin/fortsh",
    ]

    # Also check FORTSH environment variable
    env_path = os.environ.get('FORTSH')
    if env_path:
        candidates.insert(0, env_path)

    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path

    # Default
    return "./bin/fortsh"


def generate_markdown_report(results: List[TestResult], output_path: Path) -> None:
    """
    Generate a markdown report of test results.

    Args:
        results: List of test results
        output_path: Path to write the report
    """
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    total_time = sum(r.duration for r in results)

    with open(output_path, 'w') as f:
        f.write("# Interactive Test Results\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
        f.write(f"## Summary\n\n")
        f.write(f"- **Total:** {len(results)}\n")
        f.write(f"- **Passed:** {passed}\n")
        f.write(f"- **Failed:** {failed}\n")
        f.write(f"- **Duration:** {total_time:.2f}s\n\n")

        if failed > 0:
            f.write("## Failed Tests\n\n")
            for r in results:
                if not r.passed:
                    f.write(f"### {r.name}\n\n")
                    f.write(f"**Error:** {r.error}\n\n")

        f.write("## All Tests\n\n")
        f.write("| Test | Status | Duration |\n")
        f.write("|------|--------|----------|\n")
        for r in results:
            status = "✓ Pass" if r.passed else "✗ Fail"
            f.write(f"| {r.name} | {status} | {r.duration:.3f}s |\n")


def main():
    parser = argparse.ArgumentParser(
        description="Run interactive tests for fortsh"
    )
    parser.add_argument(
        '--fortsh', '-f',
        default=None,
        help='Path to fortsh binary'
    )
    parser.add_argument(
        '--spec', '-s',
        default=None,
        help='Run specific YAML spec file'
    )
    parser.add_argument(
        '--pytest',
        action='store_true',
        help='Run pytest tests instead of YAML specs'
    )
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Verbose output'
    )
    parser.add_argument(
        '--report', '-r',
        default=None,
        help='Generate markdown report at path'
    )

    args = parser.parse_args()

    # Find fortsh binary
    fortsh_path = args.fortsh or find_fortsh_binary()

    if not os.path.isfile(fortsh_path):
        print(f"{Fore.RED}Error: fortsh binary not found at {fortsh_path}{Style.RESET_ALL}")
        print("Build fortsh first or specify path with --fortsh")
        return 1

    print(f"{Fore.CYAN}╔══════════════════════════════════════════════════════════════╗{Style.RESET_ALL}")
    print(f"{Fore.CYAN}║     fortsh Interactive Test Suite                           ║{Style.RESET_ALL}")
    print(f"{Fore.CYAN}╚══════════════════════════════════════════════════════════════╝{Style.RESET_ALL}")
    print(f"\nfortsh binary: {fortsh_path}")

    if args.pytest:
        # Run pytest
        import pytest
        test_dir = Path(__file__).parent
        return pytest.main([str(test_dir), '-v' if args.verbose else '-q'])

    # Run YAML specs
    runner = YAMLTestRunner(fortsh_path, verbose=args.verbose)
    test_dir = Path(__file__).parent / "test_specs"

    if args.spec:
        # Run specific spec
        spec_path = Path(args.spec)
        if not spec_path.exists():
            spec_path = test_dir / args.spec
        if not spec_path.exists():
            print(f"{Fore.RED}Error: Spec file not found: {args.spec}{Style.RESET_ALL}")
            return 1
        results = runner.run_spec_file(spec_path)
    else:
        # Run all specs
        results = []
        for spec_file in sorted(test_dir.glob("*.yaml")):
            results.extend(runner.run_spec_file(spec_file))

    # Print summary
    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed

    print(f"\n{'='*50}")
    print(f"{Fore.CYAN}Test Summary{Style.RESET_ALL}")
    print(f"{'='*50}\n")
    print(f"Total tests run: {len(results)}")
    print(f"{Fore.GREEN}Passed:          {passed}{Style.RESET_ALL}")
    if failed > 0:
        print(f"{Fore.RED}Failed:          {failed}{Style.RESET_ALL}")
    else:
        print(f"Failed:          {failed}")

    if failed == 0:
        print(f"\n{Fore.GREEN}✓ ALL TESTS PASSED!{Style.RESET_ALL}")
    else:
        print(f"\n{Fore.RED}✗ SOME TESTS FAILED{Style.RESET_ALL}")
        # Print failed test summary
        print(f"\n{Fore.RED}Failed tests:{Style.RESET_ALL}")
        for r in results:
            if not r.passed:
                print(f"  {r.test_id}: {r.name}")

    # Generate report if requested
    if args.report:
        report_path = Path(args.report)
        generate_markdown_report(results, report_path)
        print(f"\nReport written to: {report_path}")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
