"""
Pytest configuration and fixtures for interactive tests.
"""

import os
import pytest
from pathlib import Path

# Add current directory to path for imports
import sys
sys.path.insert(0, str(Path(__file__).parent))

from fortsh_pty import FortshPTY, FortshTestSession


def find_fortsh_binary() -> str:
    """Find the fortsh binary."""
    candidates = [
        "./bin/fortsh",
        "../bin/fortsh",
        "../../bin/fortsh",
        "../fortsh/bin/fortsh",
    ]

    env_path = os.environ.get('FORTSH')
    if env_path:
        candidates.insert(0, env_path)

    for path in candidates:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path

    return "./bin/fortsh"


@pytest.fixture
def fortsh_path():
    """Fixture providing the path to fortsh binary."""
    return find_fortsh_binary()


@pytest.fixture
def fortsh(fortsh_path):
    """
    Fixture providing a running fortsh session.

    The session is automatically started and stopped.

    Usage:
        def test_something(fortsh):
            fortsh.send_line("echo hello")
            output = fortsh.wait_for_prompt()
            assert "hello" in output
    """
    pty = FortshPTY(fortsh_path=fortsh_path)
    pty.start(rc_file="/dev/null")
    yield pty
    pty.stop()


@pytest.fixture
def fortsh_with_rc(fortsh_path):
    """
    Fixture providing a fortsh session with default rc file.

    Uses the user's .fortshrc for testing rc-dependent features.
    """
    pty = FortshPTY(fortsh_path=fortsh_path)
    pty.start()  # Uses default rc
    yield pty
    pty.stop()


@pytest.fixture
def fortsh_factory(fortsh_path):
    """
    Fixture factory for creating multiple fortsh sessions.

    Usage:
        def test_multiple_shells(fortsh_factory):
            shell1 = fortsh_factory()
            shell2 = fortsh_factory()
            # Test interaction between shells
    """
    sessions = []

    def create(**kwargs):
        pty = FortshPTY(fortsh_path=fortsh_path, **kwargs)
        pty.start(rc_file="/dev/null")
        sessions.append(pty)
        return pty

    yield create

    # Cleanup all sessions
    for pty in sessions:
        try:
            pty.stop()
        except:
            pass


# Markers for test categorization
def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "line_editing: tests for line editing features"
    )
    config.addinivalue_line(
        "markers", "history: tests for history features"
    )
    config.addinivalue_line(
        "markers", "completion: tests for tab completion"
    )
    config.addinivalue_line(
        "markers", "signals: tests for signal handling"
    )
    config.addinivalue_line(
        "markers", "job_control: tests for job control"
    )
    config.addinivalue_line(
        "markers", "prompt: tests for prompt features"
    )
    config.addinivalue_line(
        "markers", "slow: marks tests as slow"
    )
