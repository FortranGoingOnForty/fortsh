#!/usr/bin/env python3
"""Quick manual MANUAL_REVIEW fixer - runs commands in /bin/sh to get expected output"""

import yaml
import subprocess
import sys
from pathlib import Path

def run_in_shell(command: str, timeout=5) -> str:
    """Run command in /bin/sh and return output"""
    try:
        result = subprocess.run(
            ['/bin/sh', '-c', command],
            capture_output=True,
            text=True,
            timeout=timeout
        )
        return result.stdout.rstrip('\n')
    except Exception as e:
        return None

def fix_yaml_file(filepath: str):
    """Fix MANUAL_REVIEW items in YAML file"""
    with open(filepath, 'r') as f:
        data = yaml.safe_load(f)

    fixed_count = 0
    total_manual_review = 0

    for test in data.get('tests', []):
        if test.get('expect_output') == 'MANUAL_REVIEW':
            total_manual_review += 1

            # Get the command
            steps = test.get('steps', [])
            if not steps:
                continue

            command = None
            for step in steps:
                if 'send_line' in step:
                    command = step['send_line']
                    break

            if not command:
                continue

            # Run in shell to get expected output
            output = run_in_shell(command)

            if output is not None:
                # Update the expected output
                test['expect_output'] = output if output else ''
                test['match_type'] = 'exact'
                fixed_count += 1
                print(f"✓ Fixed: {test.get('name', 'unnamed')[:60]}")
                print(f"  Command: {command[:60]}")
                print(f"  Output: {repr(output)}")
            else:
                print(f"✗ Failed: {test.get('name', 'unnamed')[:60]}")

    # Write back
    if fixed_count > 0:
        with open(filepath, 'w') as f:
            yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

    print(f"\n{'='*60}")
    print(f"Fixed: {fixed_count}/{total_manual_review} items in {Path(filepath).name}")
    print(f"{'='*60}\n")

    return fixed_count, total_manual_review

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: quick_fix_manual_review.py <yaml_file>")
        sys.exit(1)

    filepath = sys.argv[1]
    fixed, total = fix_yaml_file(filepath)
    sys.exit(0 if fixed == total else 1)
