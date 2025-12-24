"""
Output matching utilities for interactive tests.

Provides flexible matching for verifying shell output, supporting
exact matches, substrings, regex patterns, and structured output.
"""

import re
from typing import Union, List, Optional
from dataclasses import dataclass


@dataclass
class MatchResult:
    """Result of a match operation."""
    matched: bool
    message: str
    actual: str
    expected: str


def match_exact(actual: str, expected: str) -> MatchResult:
    """
    Match output exactly (after stripping whitespace).

    Args:
        actual: Actual output
        expected: Expected output

    Returns:
        MatchResult indicating success/failure
    """
    actual_stripped = actual.strip()
    expected_stripped = expected.strip()

    if actual_stripped == expected_stripped:
        return MatchResult(True, "Exact match", actual_stripped, expected_stripped)

    return MatchResult(
        False,
        f"Exact match failed",
        actual_stripped,
        expected_stripped
    )


def match_contains(actual: str, expected: str) -> MatchResult:
    """
    Check if output contains expected substring.

    Args:
        actual: Actual output
        expected: Expected substring

    Returns:
        MatchResult indicating success/failure
    """
    if expected in actual:
        return MatchResult(True, "Contains match", actual, expected)

    return MatchResult(
        False,
        f"Substring not found",
        actual,
        expected
    )


def match_regex(actual: str, pattern: str, flags: int = 0) -> MatchResult:
    """
    Match output against a regex pattern.

    Args:
        actual: Actual output
        pattern: Regex pattern
        flags: Regex flags (e.g., re.IGNORECASE)

    Returns:
        MatchResult indicating success/failure
    """
    try:
        if re.search(pattern, actual, flags):
            return MatchResult(True, "Regex match", actual, pattern)
        return MatchResult(False, "Regex not matched", actual, pattern)
    except re.error as e:
        return MatchResult(False, f"Invalid regex: {e}", actual, pattern)


def match_lines(actual: str, expected_lines: List[str]) -> MatchResult:
    """
    Match output line by line.

    Args:
        actual: Actual output
        expected_lines: List of expected lines

    Returns:
        MatchResult indicating success/failure
    """
    actual_lines = actual.strip().split('\n')

    if len(actual_lines) != len(expected_lines):
        return MatchResult(
            False,
            f"Line count mismatch: got {len(actual_lines)}, expected {len(expected_lines)}",
            '\n'.join(actual_lines),
            '\n'.join(expected_lines)
        )

    for i, (act, exp) in enumerate(zip(actual_lines, expected_lines)):
        if act.strip() != exp.strip():
            return MatchResult(
                False,
                f"Line {i+1} mismatch",
                act.strip(),
                exp.strip()
            )

    return MatchResult(
        True,
        "All lines match",
        '\n'.join(actual_lines),
        '\n'.join(expected_lines)
    )


def match_startswith(actual: str, prefix: str) -> MatchResult:
    """
    Check if output starts with expected prefix.

    Args:
        actual: Actual output
        prefix: Expected prefix

    Returns:
        MatchResult indicating success/failure
    """
    stripped = actual.strip()
    if stripped.startswith(prefix):
        return MatchResult(True, "Prefix match", stripped, prefix)

    return MatchResult(
        False,
        "Prefix not found",
        stripped[:len(prefix)+20] + "..." if len(stripped) > len(prefix)+20 else stripped,
        prefix
    )


def match_endswith(actual: str, suffix: str) -> MatchResult:
    """
    Check if output ends with expected suffix.

    Args:
        actual: Actual output
        suffix: Expected suffix

    Returns:
        MatchResult indicating success/failure
    """
    stripped = actual.strip()
    if stripped.endswith(suffix):
        return MatchResult(True, "Suffix match", stripped, suffix)

    return MatchResult(
        False,
        "Suffix not found",
        "..." + stripped[-(len(suffix)+20):] if len(stripped) > len(suffix)+20 else stripped,
        suffix
    )


def match_not_contains(actual: str, unwanted: str) -> MatchResult:
    """
    Verify output does NOT contain a substring.

    Args:
        actual: Actual output
        unwanted: Substring that should not be present

    Returns:
        MatchResult indicating success/failure
    """
    if unwanted not in actual:
        return MatchResult(True, "Correctly absent", actual, f"NOT {unwanted}")

    return MatchResult(
        False,
        f"Unwanted substring found",
        actual,
        f"NOT {unwanted}"
    )


def match_empty(actual: str) -> MatchResult:
    """
    Verify output is empty (after stripping whitespace).

    Args:
        actual: Actual output

    Returns:
        MatchResult indicating success/failure
    """
    stripped = actual.strip()
    if not stripped:
        return MatchResult(True, "Output is empty", stripped, "<empty>")

    return MatchResult(
        False,
        "Output is not empty",
        stripped,
        "<empty>"
    )


def match_not_empty(actual: str) -> MatchResult:
    """
    Verify output is not empty.

    Args:
        actual: Actual output

    Returns:
        MatchResult indicating success/failure
    """
    stripped = actual.strip()
    if stripped:
        return MatchResult(True, "Output is not empty", stripped, "<non-empty>")

    return MatchResult(
        False,
        "Output is unexpectedly empty",
        stripped,
        "<non-empty>"
    )


class OutputMatcher:
    """
    Flexible output matcher supporting multiple match types.

    Usage:
        matcher = OutputMatcher()
        result = matcher.match(output, expected="hello", match_type="contains")

        # Or use the builder pattern:
        result = matcher.contains("hello").match(output)
    """

    def __init__(self):
        self._match_type = "exact"
        self._expected = ""
        self._flags = 0

    def exact(self, expected: str) -> 'OutputMatcher':
        """Set up exact match."""
        self._match_type = "exact"
        self._expected = expected
        return self

    def contains(self, substring: str) -> 'OutputMatcher':
        """Set up contains match."""
        self._match_type = "contains"
        self._expected = substring
        return self

    def regex(self, pattern: str, flags: int = 0) -> 'OutputMatcher':
        """Set up regex match."""
        self._match_type = "regex"
        self._expected = pattern
        self._flags = flags
        return self

    def startswith(self, prefix: str) -> 'OutputMatcher':
        """Set up prefix match."""
        self._match_type = "startswith"
        self._expected = prefix
        return self

    def endswith(self, suffix: str) -> 'OutputMatcher':
        """Set up suffix match."""
        self._match_type = "endswith"
        self._expected = suffix
        return self

    def match(
        self,
        actual: str,
        expected: Optional[str] = None,
        match_type: Optional[str] = None
    ) -> MatchResult:
        """
        Perform the match.

        Args:
            actual: Actual output to match
            expected: Expected value (overrides builder)
            match_type: Match type (overrides builder)

        Returns:
            MatchResult
        """
        exp = expected if expected is not None else self._expected
        mt = match_type if match_type is not None else self._match_type

        if mt == "exact":
            return match_exact(actual, exp)
        elif mt == "contains":
            return match_contains(actual, exp)
        elif mt == "regex":
            return match_regex(actual, exp, self._flags)
        elif mt == "startswith":
            return match_startswith(actual, exp)
        elif mt == "endswith":
            return match_endswith(actual, exp)
        elif mt == "empty":
            return match_empty(actual)
        elif mt == "not_empty":
            return match_not_empty(actual)
        elif mt == "not_contains":
            return match_not_contains(actual, exp)
        elif mt == "lines":
            if isinstance(exp, str):
                exp = exp.split('\n')
            return match_lines(actual, exp)
        else:
            return MatchResult(False, f"Unknown match type: {mt}", actual, exp)


# Convenience functions for pytest-style assertions
def assert_output_equals(actual: str, expected: str, msg: str = "") -> None:
    """Assert output equals expected (pytest-friendly)."""
    result = match_exact(actual, expected)
    if not result.matched:
        raise AssertionError(
            f"{msg}\n{result.message}\n"
            f"Expected: {result.expected}\n"
            f"Actual:   {result.actual}"
        )


def assert_output_contains(actual: str, substring: str, msg: str = "") -> None:
    """Assert output contains substring (pytest-friendly)."""
    result = match_contains(actual, substring)
    if not result.matched:
        raise AssertionError(
            f"{msg}\n{result.message}\n"
            f"Expected to contain: {result.expected}\n"
            f"Actual: {result.actual}"
        )


def assert_output_matches(actual: str, pattern: str, msg: str = "") -> None:
    """Assert output matches regex pattern (pytest-friendly)."""
    result = match_regex(actual, pattern)
    if not result.matched:
        raise AssertionError(
            f"{msg}\n{result.message}\n"
            f"Pattern: {result.expected}\n"
            f"Actual:  {result.actual}"
        )
