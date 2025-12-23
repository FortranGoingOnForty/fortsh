#!/usr/bin/env python3
"""
Fix exit code tests by running commands in /bin/sh and capturing actual exit codes.
"""

import yaml
import subprocess
import sys
from pathlib import Path


def get_exit_code(command: str) -> int:
    """Run command in /bin/sh and return exit code."""
    try:
        result = subprocess.run(
            ['/bin/sh', '-c', command],
            capture_output=True,
            text=True,
            timeout=5
        )
        return result.returncode
    except Exception as e:
        print(f"  ⚠️  Failed to run: {command[:50]}... - {e}")
        return None


def fix_exit_code_test(test: dict) -> tuple[dict, bool]:
    """
    Fix a single exit code test.
    Returns (updated_test, was_fixed)
    """
    # Check if this is an exit code test that needs review
    if test.get('note') != 'MANUAL REVIEW NEEDED: Check expected exit code':
        return test, False
    
    steps = test.get('steps', [])
    if len(steps) < 2:
        return test, False
    
    # Last step should be: echo "EXIT=$?"
    last_step = steps[-1]
    if not last_step.get('send_line', '').startswith('echo "EXIT=$?"'):
        return test, False
    
    # Expect output should be EXIT=
    if test.get('expect_output') != 'EXIT=':
        return test, False
    
    # Get all commands before the echo
    commands = []
    for step in steps[:-1]:
        cmd = step.get('send_line', '')
        if cmd:
            commands.append(cmd)
    
    # Combine commands with ; and run to get exit code
    full_command = '; '.join(commands)
    exit_code = get_exit_code(full_command)
    
    if exit_code is None:
        return test, False
    
    # Update the test
    test['expect_output'] = f'EXIT={exit_code}'
    test.pop('note', None)  # Remove the manual review note
    
    return test, True


def main():
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <yaml_file>")
        sys.exit(1)
    
    yaml_file = Path(sys.argv[1])
    if not yaml_file.exists():
        print(f"Error: File not found: {yaml_file}")
        sys.exit(1)
    
    # Load YAML
    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)
    
    # Count before
    before_count = sum(1 for t in data['tests'] 
                       if t.get('note') == 'MANUAL REVIEW NEEDED: Check expected exit code')
    
    # Fix tests
    fixed_count = 0
    for i, test in enumerate(data['tests']):
        updated_test, was_fixed = fix_exit_code_test(test)
        data['tests'][i] = updated_test
        if was_fixed:
            fixed_count += 1
            # Print progress
            if fixed_count % 10 == 0:
                print(f"  Fixed {fixed_count} tests...")
    
    # Write back
    with open(yaml_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
    
    print(f"\n✓ Fixed {fixed_count}/{before_count} exit code tests")
    print(f"  File: {yaml_file}")
    
    remaining = before_count - fixed_count
    if remaining > 0:
        print(f"\n⚠️  {remaining} exit code tests still need manual review")


if __name__ == '__main__':
    main()
