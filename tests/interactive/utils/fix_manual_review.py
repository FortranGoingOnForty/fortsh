#!/usr/bin/env python3
"""
Fix MANUAL_REVIEW items in auto-generated YAML test files.

This script applies heuristics to estimate expected outputs for common patterns.
"""

import re
import yaml
from pathlib import Path
import subprocess
import sys


def fix_variable_echo(command: str) -> str:
    """
    Fix: VAR=value; echo $VAR -> expect "value"
    Also handles: VAR=value; echo "$VAR"
    """
    # Pattern: VAR=value; echo $VAR or VAR=value; echo "$VAR"
    match = re.match(r'(\w+)=([^;]+);\s*echo\s+\$\{?\1\}?', command)
    if match:
        var_name, value = match.groups()
        # Remove quotes from value if present
        value = value.strip('\'"')
        return value

    # Pattern with quotes: VAR=value; echo "$VAR"
    match = re.match(r'(\w+)=([^;]+);\s*echo\s+"?\$\1"?', command)
    if match:
        var_name, value = match.groups()
        value = value.strip('\'"')
        return value

    return None


def fix_parameter_expansion(command: str) -> str:
    """
    Fix parameter expansion patterns.
    """
    # ${VAR:-default} when VAR is unset -> expect "default"
    match = re.match(r'echo\s+"\$\{(\w+):-([^}]+)\}"', command)
    if match:
        var_name, default = match.groups()
        if var_name.startswith('UN') or 'UNSET' in var_name:  # Likely unset
            return default

    # ${#VAR} - string length
    match = re.match(r'(\w+)=([^;]+);\s*echo\s+"\$\{#\1\}"', command)
    if match:
        var_name, value = match.groups()
        value = value.strip('\'"')
        return str(len(value))

    # ${VAR#pattern} - remove prefix
    match = re.match(r'(\w+)=([^;]+);\s*echo\s+"\$\{\1#([^}]+)\}"', command)
    if match:
        var_name, value, pattern = match.groups()
        value = value.strip('\'"')
        # Simple pattern matching (this is a heuristic)
        if pattern == '*.':
            # Remove shortest prefix matching *.
            if '.' in value:
                return value.split('.', 1)[1]
        return None  # Complex pattern, keep MANUAL_REVIEW

    return None


def fix_command_substitution(command: str) -> str:
    """
    Fix command substitution patterns.
    """
    # echo $(echo value) -> expect "value"
    match = re.match(r'echo\s+\$\(echo\s+(\w+)\)', command)
    if match:
        return match.group(1)

    # Backtick version: echo `echo value`
    match = re.match(r'echo\s+`echo\s+(\w+)`', command)
    if match:
        return match.group(1)

    return None


def fix_simple_echo(command: str) -> str:
    """
    Fix simple echo commands with unquoted strings.
    """
    # echo hello -> "hello"
    match = re.match(r'echo\s+(\w+)$', command)
    if match:
        return match.group(1)

    # echo one two three -> "one two three"
    match = re.match(r'echo\s+(.+)$', command)
    if match:
        content = match.group(1)
        # If no special characters, return as-is
        if not any(c in content for c in ['$', '`', '(', ')', '{', '}', '\\', '"', "'"]):
            return content

    return None


def try_run_command(command: str, shell: str = '/bin/sh') -> str:
    """
    Actually run the command in a POSIX shell and capture output.
    This is the most reliable way but slower.
    """
    try:
        result = subprocess.run(
            [shell, '-c', command],
            capture_output=True,
            text=True,
            timeout=2
        )
        output = result.stdout.strip()
        # Only use if successful and output is reasonable
        if result.returncode == 0 and len(output) < 100 and '\n' not in output:
            return output
    except:
        pass
    return None


def fix_test(test: dict, use_shell: bool = False) -> dict:
    """
    Fix a single test by estimating expected output.

    Args:
        test: Test dictionary
        use_shell: If True, actually run commands in /bin/sh to get output

    Returns:
        Updated test dictionary
    """
    if test.get('expect_output') != 'MANUAL_REVIEW':
        return test

    # Get the command
    steps = test.get('steps', [])
    if not steps or 'send_line' not in steps[0]:
        return test

    command = steps[0]['send_line']

    # Try different fixing strategies
    expected = None

    # Strategy 1: Pattern matching heuristics (fast)
    expected = fix_variable_echo(command)
    if expected:
        test['expect_output'] = expected
        return test

    expected = fix_parameter_expansion(command)
    if expected:
        test['expect_output'] = expected
        return test

    expected = fix_command_substitution(command)
    if expected:
        test['expect_output'] = expected
        return test

    expected = fix_simple_echo(command)
    if expected:
        test['expect_output'] = expected
        return test

    # Strategy 2: Actually run the command (slower but more reliable)
    if use_shell:
        expected = try_run_command(command)
        if expected:
            test['expect_output'] = expected
            test['auto_fixed'] = 'shell_execution'
            return test

    # Couldn't fix, leave as MANUAL_REVIEW
    return test


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <yaml_file> [--use-shell]")
        print("\nFixes MANUAL_REVIEW items in auto-generated YAML test files.")
        print("--use-shell: Actually run commands in /bin/sh to get expected output (slower)")
        sys.exit(1)

    yaml_file = Path(sys.argv[1])
    use_shell = '--use-shell' in sys.argv

    if not yaml_file.exists():
        print(f"Error: File not found: {yaml_file}")
        sys.exit(1)

    # Load YAML
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)

    # Count before
    before_manual = sum(1 for t in data['tests'] if t.get('expect_output') == 'MANUAL_REVIEW')

    # Fix tests
    for i, test in enumerate(data['tests']):
        data['tests'][i] = fix_test(test, use_shell=use_shell)

    # Count after
    after_manual = sum(1 for t in data['tests'] if t.get('expect_output') == 'MANUAL_REVIEW')
    fixed = before_manual - after_manual

    # Write back
    with open(yaml_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)

    print(f"✓ Fixed {fixed}/{before_manual} MANUAL_REVIEW items")
    print(f"  Remaining: {after_manual}")
    print(f"  Total tests: {len(data['tests'])}")

    if after_manual > 0:
        print(f"\n⚠️  {after_manual} tests still need manual review")
        print("  Consider using --use-shell for better auto-fixing")


if __name__ == '__main__':
    main()
