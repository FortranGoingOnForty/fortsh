"""
PTY management for fortsh interactive testing.

Provides a high-level interface to spawn fortsh in a pseudo-terminal
and interact with it programmatically.
"""

import os
import re
import pexpect
from pathlib import Path
from typing import Optional, Union

from utils.keys import KEYS, get_key


class FortshPTY:
    """
    Manages a fortsh process running in a pseudo-terminal.

    This class provides methods to send input, receive output, and verify
    behavior for interactive testing.
    """

    # Default prompt pattern - matches the user's fortsh prompt
    # No anchors for reliability with pexpect's buffering
    DEFAULT_PROMPT_PATTERN = r'> '

    # Unique marker for reliable command output detection
    END_MARKER = "___FORTSH_CMD_END___"

    def __init__(
        self,
        fortsh_path: str = "./bin/fortsh",
        timeout: float = 5.0,
        prompt_pattern: Optional[str] = None,
        env: Optional[dict] = None,
    ):
        """
        Initialize the PTY wrapper.

        Args:
            fortsh_path: Path to fortsh binary
            timeout: Default timeout for expect operations (seconds)
            prompt_pattern: Regex pattern to match the shell prompt
            env: Additional environment variables
        """
        self.fortsh_path = fortsh_path
        self.timeout = timeout
        self.prompt_pattern = prompt_pattern or self.DEFAULT_PROMPT_PATTERN
        self.custom_env = env or {}
        self.child: Optional[pexpect.spawn] = None
        self._output_buffer: str = ""

    def start(self, rc_file: Optional[str] = None) -> None:
        """
        Start fortsh in a PTY.

        Args:
            rc_file: Path to rc file, or None to use default, or "/dev/null" for no rc
        """
        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"

        # Enable test mode for cleaner output (less ANSI redraws)
        # Note: Completion is NOT disabled here - tests can use Tab completion
        env["FORTSH_MINIMAL_ECHO"] = "1"
        env["FORTSH_TEST_MODE"] = "1"

        # Use /dev/null for clean testing unless specified
        if rc_file is not None:
            env["FORTSH_RC_FILE"] = rc_file

        # Apply custom environment
        env.update(self.custom_env)

        self.child = pexpect.spawn(
            self.fortsh_path,
            encoding="utf-8",
            codec_errors="replace",  # Handle raw ANSI/highlight bytes without crashing
            timeout=self.timeout,
            env=env,
            dimensions=(24, 80),  # Standard terminal size
            echo=False,  # Don't echo back input
        )

        # Wait for initial prompt
        self.wait_for_prompt()

    def stop(self) -> int:
        """
        Stop fortsh and return exit code.

        Returns:
            Exit code of the fortsh process
        """
        if self.child is None:
            return -1

        import time
        import signal

        exit_code = 0
        pid = self.child.pid

        try:
            # Try graceful exit first
            self.child.sendline("exit")
            self.child.expect(pexpect.EOF, timeout=1)
            exit_code = self.child.exitstatus or 0
        except (pexpect.TIMEOUT, pexpect.EOF):
            # Send SIGTERM then SIGKILL
            try:
                self.child.kill(signal.SIGTERM)
                time.sleep(0.1)
                if self.child.isalive():
                    self.child.kill(signal.SIGKILL)
                    time.sleep(0.1)
            except:
                pass

        # Close file descriptors explicitly
        try:
            if hasattr(self.child, 'child_fd') and self.child.child_fd is not None:
                try:
                    os.close(self.child.child_fd)
                except OSError:
                    pass
        except:
            pass

        # Close the ptyprocess file object if it exists
        try:
            if hasattr(self.child, 'fileobj') and self.child.fileobj:
                self.child.fileobj.close()
        except:
            pass

        try:
            self.child.close(force=True)
        except:
            pass

        # Wait for process to fully terminate with retries
        for _ in range(5):
            try:
                if pid:
                    result = os.waitpid(pid, os.WNOHANG)
                    if result[0] != 0:
                        break
                    time.sleep(0.05)
            except ChildProcessError:
                break
            except:
                break

        # Ensure any zombie is reaped
        try:
            if pid:
                os.kill(pid, 0)  # Check if still exists
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
        except (ProcessLookupError, ChildProcessError, OSError):
            pass

        self.child = None
        return exit_code

    def clear_buffer(self) -> None:
        """Clear the pexpect buffer to avoid accumulation."""
        if self.child is None:
            return
        # Read any pending output without blocking
        try:
            while True:
                self.child.read_nonblocking(size=1024, timeout=0.01)
        except (pexpect.TIMEOUT, pexpect.EOF):
            pass

    def send(self, text: str) -> None:
        """
        Send text without newline.

        Args:
            text: Text to send to fortsh
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")
        self.child.send(text)

    def send_line(self, text: str) -> None:
        """
        Send text followed by Enter.

        Args:
            text: Text to send to fortsh
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")
        self.child.sendline(text)

    def send_key(self, key_name: str) -> None:
        """
        Send a special key by name.

        Args:
            key_name: Name of the key (e.g., "Up", "C-a", "Enter")
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")
        self.child.send(get_key(key_name))

    def send_keys(self, *key_names: str) -> None:
        """
        Send multiple keys in sequence.

        Args:
            *key_names: Names of keys to send
        """
        for key in key_names:
            self.send_key(key)

    def wait_for_prompt(self, timeout: Optional[float] = None) -> str:
        """
        Wait for the shell prompt to appear.

        Args:
            timeout: Timeout in seconds (uses default if None)

        Returns:
            Output received before the prompt
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")

        self.child.expect(self.prompt_pattern, timeout=timeout or self.timeout)
        output = self.child.before or ""
        self._output_buffer = output
        return output

    def expect(
        self,
        pattern: Union[str, list],
        timeout: Optional[float] = None
    ) -> int:
        """
        Wait for a pattern in the output.

        Args:
            pattern: Regex pattern or list of patterns
            timeout: Timeout in seconds

        Returns:
            Index of matched pattern (if list) or 0

        Raises:
            pexpect.TIMEOUT: If pattern not found within timeout
            pexpect.EOF: If process terminates
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")

        return self.child.expect(pattern, timeout=timeout or self.timeout)

    def expect_exact(self, text: str, timeout: Optional[float] = None) -> None:
        """
        Wait for exact text in output.

        Args:
            text: Exact text to find
            timeout: Timeout in seconds

        Raises:
            pexpect.TIMEOUT: If text not found within timeout
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")

        self.child.expect_exact(text, timeout=timeout or self.timeout)

    def get_output(self) -> str:
        """
        Get output from the last expect operation.

        Returns:
            Output that appeared before the matched pattern
        """
        if self.child is None:
            return ""
        return self.child.before or ""

    def get_clean_output(self) -> str:
        """
        Get cleaned output, filtering out terminal redraw noise.

        Returns:
            Cleaned output with prompts and redraws removed
        """
        if self.child is None:
            return ""

        raw = self.child.before or ""

        # Split into lines and filter
        lines = raw.split('\n')
        clean_lines = []

        for line in lines:
            # Skip lines that are mostly prompt redraws
            if ':: ~' in line and line.count('@') > 1:
                continue
            # Skip lines that look like partial prompts
            if line.strip().endswith('> ') and len(line.strip()) < 10:
                continue
            # Keep the line if it has actual content
            clean_lines.append(line)

        return '\n'.join(clean_lines)

    def get_match(self) -> str:
        """
        Get the text that matched the last expect pattern.

        Returns:
            Matched text
        """
        if self.child is None:
            return ""
        return self.child.after or ""

    def run_command(self, command: str, timeout: Optional[float] = None) -> str:
        """
        Run a command and return its output.

        Uses a unique marker for reliable output detection instead of
        prompt matching, which can be unreliable with terminal redraws.

        Args:
            command: Shell command to run
            timeout: Timeout for the command

        Returns:
            Command output (excluding the prompt and marker)
        """
        # Send command followed by marker echo
        self.send_line(command)
        self.send_line(f"echo {self.END_MARKER}")

        # Wait for the marker to appear
        self.expect(self.END_MARKER, timeout=timeout)
        output = self.get_output()

        # Clean up the output
        # Remove the marker echo command and any prompts
        lines = []
        for line in output.split('\n'):
            # Skip lines containing the marker or prompt patterns
            if self.END_MARKER in line:
                continue
            if line.strip().startswith(('>', '$', '#', '%')):
                continue
            # Skip the echoed command
            if command in line:
                continue
            lines.append(line)

        return '\n'.join(lines).strip()

    def interrupt(self) -> None:
        """Send Ctrl+C to interrupt current operation."""
        self.send_key("C-c")

    def suspend(self) -> None:
        """Send Ctrl+Z to suspend current operation."""
        self.send_key("C-z")

    def eof(self) -> None:
        """Send Ctrl+D (EOF)."""
        self.send_key("C-d")

    @property
    def is_running(self) -> bool:
        """Check if fortsh is still running."""
        if self.child is None:
            return False
        return self.child.isalive()

    def set_terminal_size(self, rows: int, cols: int) -> None:
        """
        Change the terminal dimensions (triggers SIGWINCH).

        Args:
            rows: Number of rows
            cols: Number of columns
        """
        if self.child is None:
            raise RuntimeError("fortsh not started")
        self.child.setwinsize(rows, cols)


class FortshTestSession:
    """
    Context manager for fortsh test sessions.

    Usage:
        with FortshTestSession() as fortsh:
            fortsh.send_line("echo hello")
            output = fortsh.wait_for_prompt()
            assert "hello" in output
    """

    def __init__(self, **kwargs):
        self.kwargs = kwargs
        self.pty: Optional[FortshPTY] = None

    def __enter__(self) -> FortshPTY:
        self.pty = FortshPTY(**self.kwargs)
        self.pty.start()
        return self.pty

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self.pty:
            self.pty.stop()
        return False


# Convenience function for quick testing
def quick_test(command: str, fortsh_path: str = "./bin/fortsh") -> str:
    """
    Run a single command in fortsh and return output.

    Args:
        command: Command to run
        fortsh_path: Path to fortsh binary

    Returns:
        Command output
    """
    with FortshTestSession(fortsh_path=fortsh_path) as fortsh:
        return fortsh.run_command(command)
