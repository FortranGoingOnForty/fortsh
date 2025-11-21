#!/usr/bin/env python3
"""
Final cleanup pass for converted POSIX tests.

Fixes common issues like escaped variables and cleans up test format.
"""

import yaml
import re
from pathlib import Path
import sys


def unescape_variables(command: str) -> str:
    """
    Remove backslashes before $ signs that were needed in shell scripts
    but not needed in interactive mode.

    \$VAR -> $VAR
    \$# -> $#
    etc.
    """
    # Replace \$ with $ for variable expansion
    command = command.replace(r'\$', '$')
    # Also handle \( \) for command substitution
    command = command.replace(r'\(', '(')
    command = command.replace(r'\)', ')')
    return command


def fix_expected_output_for_variables(test: dict) -> dict:
    """
    Fix tests where the expected output is a literal $VAR but should be the value.
    """
    expected = test.get('expect_output', '')
    command = test.get('steps', [{}])[0].get('send_line', '')

    # If expected output is a literal variable like $VAR, $1, $#, etc.
    # and the command sets that variable, we need to get the actual value
    if expected.startswith('$') and not expected.startswith('$?'):
        # Common patterns we can fix

        # set -- a b c; echo $1 -> expect "a"
        match = re.match(r'set -- ([^;]+); echo \$(\d+)', command)
        if match:
            args, index = match.groups()
            arg_list = args.split()
            idx = int(index) - 1
            if 0 <= idx < len(arg_list):
                test['expect_output'] = arg_list[idx]
                return test

        # set -- a b c; echo $# -> expect "3"
        match = re.match(r'set -- ([^;]+); echo \$#', command)
        if match:
            args = match.group(1)
            test['expect_output'] = str(len(args.split()))
            return test

        # set -- a b c; echo $@ -> expect "a b c"
        match = re.match(r'set -- ([^;]+); echo \$[@\*]', command)
        if match:
            test['expect_output'] = match.group(1)
            return test

        # func() { echo $1 $2; }; func foo bar -> expect "foo bar"
        match = re.match(r'func\(\) \{ echo \$(\d+) \$(\d+); \}; func (\w+) (\w+)', command)
        if match:
            test['expect_output'] = f"{match.group(3)} {match.group(4)}"
            return test

        # true; echo $? -> expect "0"
        if command == 'true; echo $?':
            test['expect_output'] = '0'
            return test

        # false; echo $? -> expect "1"
        if command == 'false; echo $?':
            test['expect_output'] = '1'
            return test

    return test


def fix_exit_code_tests(test: dict) -> dict:
    """
    Simplify exit code tests to just check for the exit code value.
    """
    if 'EXIT=' in test.get('expect_output', ''):
        steps = test.get('steps', [])
        if len(steps) >= 2 and 'echo "EXIT=$?"' in str(steps):
            # Determine expected exit code from command
            first_cmd = steps[0].get('send_line', '')

            # Common patterns
            if 'true' in first_cmd and '&&' not in first_cmd and '||' not in first_cmd:
                test['expect_output'] = 'EXIT=0'
            elif 'false' in first_cmd and '&&' not in first_cmd and '||' not in first_cmd:
                test['expect_output'] = 'EXIT=1'
            elif 'test -f' in first_cmd and 'touch' in first_cmd:
                test['expect_output'] = 'EXIT=0'
            elif 'return' in first_cmd:
                # Extract return value
                match = re.search(r'return (\d+)', first_cmd)
                if match:
                    test['expect_output'] = f'EXIT={match.group(1)}'

            # Remove note if we fixed it
            if test.get('expect_output', '').startswith('EXIT=') and test['expect_output'] != 'EXIT=':
                test.pop('note', None)

    return test


def process_test(test: dict) -> dict:
    """Apply all fixes to a single test."""
    # Fix commands
    for i, step in enumerate(test.get('steps', [])):
        if 'send_line' in step:
            step['send_line'] = unescape_variables(step['send_line'])

    # Fix expected outputs
    test = fix_expected_output_for_variables(test)
    test = fix_exit_code_tests(test)

    # Clean up auto_fixed marker if present
    # (keep it for documentation but it's not needed)

    return test


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <yaml_file>")
        sys.exit(1)

    yaml_file = Path(sys.argv[1])
    if not yaml_file.exists():
        print(f"Error: File not found: {yaml_file}")
        sys.exit(1)

    # Load
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)

    # Count before
    before_manual = sum(1 for t in data['tests']
                       if 'MANUAL_REVIEW' in str(t.get('expect_output', '')) or
                          t.get('expect_output', '') == '$VAR' or
                          t.get('expect_output', '') == '$1')

    # Process
    for i, test in enumerate(data['tests']):
        data['tests'][i] = process_test(test)

    # Count after
    after_manual = sum(1 for t in data['tests']
                      if 'MANUAL_REVIEW' in str(t.get('expect_output', '')) or
                         'note' in t)

    fixed = before_manual - after_manual

    # Write
    with open(yaml_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)

    print(f"✓ Finalized {len(data['tests'])} tests")
    print(f"  Additional fixes applied: {fixed}")
    print(f"  Still needs review: {after_manual}")


if __name__ == '__main__':
    main()
